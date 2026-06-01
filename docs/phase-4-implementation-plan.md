# Phase 4 Load List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 4 builds `pak.load_list` parsing first, then manifest creation from base-game fixtures, so a `pak.load_list` extracted from `fixtures/initial.pak` can be inspected, regenerated from `initial.pak`, `shared.pak`, and `shared_sound.pak`, and embedded into a SnowPakTool-compatible PAK that the game accepts.

**Architecture:** Add a focused `LoadList` module that owns the binary manifest format, loader-type classification, source-pak attribution, and phase-record layout. Reading is implemented before writing, and writing is driven by a deterministic builder that walks fixture PAKs, classifies each entry, assigns it to a phase, and emits the same byte-level structure used by the original game manifest. Integrate creation into `pak pack --rebuild-load-list` so a candidate `initial.pak` can be packed end-to-end with a freshly built manifest; reuse the existing Phase 2 writer and verifier for the outer PAK.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation `Data` / `FileHandle` / `FileManager`, existing CP437 ASCII fast path, existing custom PAK reader/writer, existing cache-block module, XCTest.

---

## Phase Goal

Phase 4 proves `pak.load_list` by parsing the existing manifest, regenerating an equivalent manifest from `initial.pak`, `shared.pak`, and `shared_sound.pak`, and producing a candidate `initial.pak` whose rebuilt manifest is accepted by the game.

## Non-Goals

- No ad hoc mutation of an existing `pak.load_list` (e.g. inserting one record into a parsed manifest and re-serializing it). The phase only supports full rebuilds from fixture PAKs.
- No high-level ZIP writer APIs.
- No new outer-PAK layout policies; the outer PAK still follows Phase 2 SnowPakTool-compatible layout.
- No `cache_block` format changes; the cache-block writer from Phase 3 is reused unchanged.
- No non-ASCII manifest strings. Path, loader-type, and source-pak strings are CP437 ASCII for current fixtures; non-ASCII bytes must fail clearly.
- No byte-for-byte equality with SnowPakTool `load_list create-initial` output. The acceptance bar is structural and behavioral equivalence: same phases, same loader-type classification, same source-pak attribution, same per-record flag bytes for known patterns, and game-launch acceptance.
- No game-launch acceptance for read-only `load-list inspect` because that command emits no candidate PAK.

## Inputs And Fixtures

- `fixtures/initial.pak`: required before implementation starts; contains the original `pak.load_list` as the first stored PAK entry and the reference content set for `[media]`, `[ssl_cache]`, `[strings]`, and `initial.cache_block`.
- `fixtures/initial.repacked.pak`: required before implementation starts; contains the same `pak.load_list` bytes; used as a second parser-input fixture and as the Phase 2 layout reference for the outer PAK.
- `fixtures/shared.pak`: required before `load-list create-initial` implementation starts; provides the content set classified into the `cls_loader` and `mesh_loader` records that point at `shared.pak`. Required only for the rebuild and CLI tasks; read-only `load-list inspect` does not depend on it.
- `fixtures/shared_sound.pak`: required before `load-list create-initial` implementation starts; provides the content set for `sound_loader` records that point at `shared_sound.pak`. Required only for the rebuild and CLI tasks.
- `fixtures/shared_debug.pak`: conditionally required. The reference manifest's source-pak table includes `shared_debug.pak`, so the parser will recognize it. Whether the rebuilder must walk it is decided by Task 7's parity test: if any reference record cannot be matched without `shared_debug.pak` content, this fixture becomes required and `LoadListBuilderInputs` is extended with a `sharedDebugPak: URL` field. Until Task 7 confirms the need, the rebuilder treats `shared_debug.pak` as a known source-pak label that no built record is attributed to.
- `fixtures/reports/load-list-compact.txt`: required before the parser-equivalence task starts; produced by SnowPakTool on Windows with `snowpaktool load_list list --compact`. Treated as the read-only oracle for parser output.
- A generated standalone `pak.load_list` file under the XCTest temporary directory: produced by reading the manifest entry from `fixtures/initial.pak` so the parser can read a real manifest without committing another fixture file.
- A generated rebuilt `pak.load_list` file under the XCTest temporary directory: produced by `LoadListBuilder` from the three fixture PAKs.
- A generated rebuilt-manifest mixed candidate PAK under the XCTest temporary directory: proves the outer PAK writer accepts the rebuilt manifest and the existing verifier still passes.

Fixture facts this phase depends on (verified by inspecting `fixtures/initial.pak`'s `pak.load_list` bytes directly):

```text
fixtures/initial.pak / fixtures/initial.repacked.pak:
  pak.load_list uncompressed size: 2207322
  pak.load_list crc32: 0xE635B186
  pak.load_list is the first PAK entry and stored

manifest header (first 13 bytes):
  offset 0..3:  version u32 = 0x00000001
  offset 4:     marker u8   = 0x01
  offset 5..8:  total_record_count u32 = 0x000045FD = 17917
  offset 9..12: header_tail u32 (observed value 0x00000003; semantics undecided —
                  may be source-pak count or something else; the parser captures
                  it verbatim and the writer emits it back unchanged)

manifest body layout (preliminary, confirmed by scanning the fixture):
  offset 13: a per-record byte table of length total_record_count (17917 bytes).
             Observed values are 0x01, 0x02, 0x05; meaning is captured verbatim
             on `LoadListRecord.flags`, not interpreted by the writer.
  offset 13 + 17917 = 17930: a second per-record table whose entry size is
             still being established (5 bytes per entry has been ruled out; needs
             further byte-level verification).
  records and phase tags then follow. Phase tags are written as length-prefixed
  CP437 strings ending with the literal token " load". Each phase tag is followed
  by per-phase footer bytes the parser captures verbatim.

phase set actually present in the fixture (in write order discovered by scanning):
  RES3_INIT load
  SSL_SOURCES_PARSE load
  SSL_INITIAL load
  TEMPLATES load
  CLASSES load
  TEXTURE_PREPARE load
  TEXTURE load
  MESH load
  SOUND load
  RES3_PROJECT load
  PROJECT load
  DEFAULT load
  DESC_BLOCK load

(13 phases — the format-doc §12.2 list of 8 phases is incomplete. The parser
locks the actual 13-phase list as the canonical source of truth.)

source-pak names referenced by the manifest (in observed first-appearance order):
  shared_debug.pak  (first occurrence at offset 250901)
  initial.pak       (first occurrence at offset 251140)
  shared.pak        (first occurrence at offset 1433847)
  shared_sound.pak  (first occurrence at offset 2207151)

source-pak occurrence counts (length-prefixed CP437 strings; counted across the
whole manifest body):
  shared_debug.pak: 3      (matches sslbundle count)
  initial.pak:      10292  (≈ 10284 cls + 5 tpl + a few other initial.pak
                            classifications observed in mid-file phases)
  shared.pak:       7606   (matches mesh_loader count)
  shared_sound.pak: 1      (matches sound_loader count)
  total:            17902  (matches the 17902 records flagged 0x02 in the
                            byte-table; the other 15 records — 14 with flag 0x01
                            and 1 with flag 0x05 — do not embed a source-pak
                            string and live in the early/late phases)

Source-pak attribution is INLINE: each record carries its source-pak as a
length-prefixed CP437 string. The manifest header does NOT contain a separate
source-pak table; the four-name set above is observed by the parser, not read
from a fixed table. Records flagged 0x01 or 0x05 in the byte-table are
phase-control or terminator records and do not carry a source-pak string.

reference loader-type counts (approximate; the exact counts come from the
parsed reference manifest and the parser-equivalence test must match them):
  cls_loader:   10284
  tpl_loader:   5
  sslbundle:    3 (the literal token "sslbundle" also appears 6 times because
                  it is the suffix of 3 manifest paths; the parser must count
                  loader-type fields, not raw string occurrences)
  mesh_loader:  7606
  sound_loader: 1
```

The reference byte counts above are the fingerprint, not the contract. The per-record table layout starting at offset 17930, the source-pak attribution mode (table index vs inline string), the exact encoding of record flags, and the per-phase footer bytes are part of the implementation contract that the parser must establish by reading the fixture and the rebuilder must reproduce. All of these must be derived from the parsed bytes of `fixtures/initial.pak`'s manifest, not invented.

## Commands To Deliver

```text
snowrunner-tool load-list inspect <pak.load_list>
snowrunner-tool load-list create-initial <target.load_list> <initial.pak> <shared.pak> <shared_sound.pak>
snowrunner-tool pak pack --rebuild-load-list <dir> <pak> <shared.pak> <shared_sound.pak>
```

Existing Phase 1, Phase 2, and Phase 3 commands remain available and are used as acceptance checks:

```text
snowrunner-tool pak unpack <pak> <dir>
snowrunner-tool pak pack <dir> <pak>
snowrunner-tool pak pack --mixed-cache-block <dir> <pak>
snowrunner-tool pak verify-basic <pak>
snowrunner-tool pak verify-snowpak-layout <pak>
snowrunner-tool pak verify-content-equivalent <reference.pak> <candidate.pak>
```

`pak pack --rebuild-load-list` accepts an optional `--mixed-cache-block` switch in either order, so the full command shape is:

```text
snowrunner-tool pak pack --rebuild-load-list [--mixed-cache-block] <dir> <pak> <shared.pak> <shared_sound.pak>
```

## Code Structure

- Modify `Sources/SnowRunnerTool/CLI.swift`: add `load-list inspect`, `load-list create-initial`, and `pak pack --rebuild-load-list` parsing, usage text, and error reporting.
- Modify `Sources/SnowRunnerTool/Pak/BinaryReader.swift`: add length-prefixed CP437 string read used by manifest fields, only if the existing helpers do not already cover it; otherwise leave unchanged.
- Modify `Sources/SnowRunnerTool/Pak/BinaryWriter.swift`: add length-prefixed CP437 string append, only if not already present; otherwise leave unchanged.
- Modify `Sources/SnowRunnerTool/Pak/PakWriter.swift`: add `rebuildLoadList` entry point that takes the unpacked directory, optional mixed-cache-block flag, and the two shared PAK URLs; generates `pak.load_list` from the three PAK fixtures, replaces any stale `pak.load_list` in the directory, and delegates to the existing writer paths.
- Modify `Sources/SnowRunnerTool/Pak/PakWriterError.swift`: add rebuild-specific errors (`missingSharedPak`, `missingSharedSoundPak`, `loadListBuildFailed`).
- Modify `Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift`: only if the rebuild path needs to inject a generated `pak.load_list` file source the same way mixed-cache-block injects `initial.cache_block`. Otherwise leave unchanged.
- Create `Sources/SnowRunnerTool/LoadList/LoadListConstants.swift`: marker bytes, phase tag strings, fixed manifest filename, and known loader-type strings.
- Create `Sources/SnowRunnerTool/LoadList/LoadListError.swift`: parser, classifier, and writer error cases with stable descriptions.
- Create `Sources/SnowRunnerTool/LoadList/LoadListPhase.swift`: enum of the eight observed phase tags in canonical write order.
- Create `Sources/SnowRunnerTool/LoadList/LoadListLoaderType.swift`: enum of known loader-type strings with classification helpers.
- Create `Sources/SnowRunnerTool/LoadList/LoadListRecord.swift`: parsed record metadata (manifest path, loader type, source pak, flag byte, owning phase).
- Create `Sources/SnowRunnerTool/LoadList/LoadListManifest.swift`: parsed manifest model (version tag, source-pak table, records grouped by phase, terminator).
- Create `Sources/SnowRunnerTool/LoadList/LoadListReader.swift`: parse manifest from `Data` or file URL, validating every marker, length, and phase footer before returning.
- Create `Sources/SnowRunnerTool/LoadList/LoadListClassifier.swift`: classify a `(internalName, sourcePak)` pair into a `LoadListRecord` using path patterns, loader-type rules, and phase assignment derived from the reference fixture.
- Create `Sources/SnowRunnerTool/LoadList/LoadListBuilder.swift`: deterministic builder that walks `initial.pak`, `shared.pak`, and `shared_sound.pak`, classifies entries, sorts records inside each phase, and produces a `LoadListManifest`.
- Create `Sources/SnowRunnerTool/LoadList/LoadListWriter.swift`: serialize a `LoadListManifest` to deterministic bytes that round-trip through `LoadListReader` and match the reference manifest's structure.
- Create `Sources/SnowRunnerTool/LoadList/LoadListInspector.swift`: format a parsed `LoadListManifest` as the same compact line layout SnowPakTool emits with `load_list list --compact`.
- Modify `Tests/SnowRunnerToolTests/TestFixtures.swift`: add helpers to extract `pak.load_list` from a PAK fixture, locate `fixtures/shared.pak` and `fixtures/shared_sound.pak` with skip behavior when absent, and load the SnowPakTool compact reference report.
- Create `Tests/SnowRunnerToolTests/LoadListReaderTests.swift`: synthetic-manifest and fixture parser tests.
- Create `Tests/SnowRunnerToolTests/LoadListInspectorTests.swift`: compact-format equivalence test against the SnowPakTool reference report.
- Create `Tests/SnowRunnerToolTests/LoadListClassifierTests.swift`: classifier rule tests for `cls_loader`, `tpl_loader`, `sslbundle`, `mesh_loader`, and `sound_loader`.
- Create `Tests/SnowRunnerToolTests/LoadListBuilderTests.swift`: rebuild-from-fixture-PAKs tests, including phase-by-phase record-count parity with the parsed reference manifest.
- Create `Tests/SnowRunnerToolTests/LoadListWriterTests.swift`: synthetic and parser-roundtrip tests, including byte-stable round-trips of every parsed reference manifest.
- Create `Tests/SnowRunnerToolTests/RebuildLoadListPakTests.swift`: end-to-end tests that build a rebuilt-manifest PAK and check verifier acceptance.
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`: CLI coverage for `load-list inspect`, `load-list create-initial`, and `pak pack --rebuild-load-list`.

## Implementation Contracts

The manifest is a binary, length-prefixed structure. Establish the contract by parsing the reference manifest first, then encode it in code as fixed constants. The builder must never re-derive these constants at runtime.

```swift
enum LoadListConstants {
    static let manifestEntryName = "pak.load_list"
    static let versionTag: UInt32 = 0x00000001
    static let marker: UInt8 = 0x01
    static let phasesInWriteOrder: [String] = [
        "RES3_INIT load",
        "SSL_SOURCES_PARSE load",
        "SSL_INITIAL load",
        "TEMPLATES load",
        "CLASSES load",
        "TEXTURE_PREPARE load",
        "TEXTURE load",
        "MESH load",
        "SOUND load",
        "RES3_PROJECT load",
        "PROJECT load",
        "DEFAULT load",
        "DESC_BLOCK load"
    ]
    static let knownSourcePaks: [String] = [
        "initial.pak",
        "shared_debug.pak",
        "shared.pak",
        "shared_sound.pak"
    ]
    static let knownLoaderTypes: [String] = [
        "cls_loader",
        "tpl_loader",
        "sslbundle",
        "mesh_loader",
        "sound_loader"
    ]
}
```

`LoadListRecord`:

```swift
public struct LoadListRecord: Equatable {
    public let manifestPath: String       // e.g. "<media>\\classes\\trucks\\hummer_h2.xml"
    public let loaderType: String         // e.g. "cls_loader"
    public let sourcePak: String          // e.g. "initial.pak"; resolved through the source-pak table when the manifest stores an index
    public let flags: UInt8               // single per-record flag byte from the flag/category table; preserved verbatim by the parser
    public let phase: String              // owning phase tag, e.g. "DESC_BLOCK load"
}
```

The per-record flag byte may live in a separate table near the top of the manifest (see format-doc §12.6) rather than inline with each record. The parser is responsible for binding flag-table bytes to records by index; the writer must emit them back in the same place. `LoadListRecord.flags` exposes the bound value to the rest of the system.

`LoadListManifest`:

```swift
public struct LoadListManifest: Equatable {
    public let versionTag: UInt32
    public let sourcePakTable: [String]
    public let recordsByPhase: [String: [LoadListRecord]]
    public let phaseOrder: [String]
}
```

`LoadListReader`:

```swift
public enum LoadListReader {
    public static func readManifest(from url: URL) throws -> LoadListManifest
    public static func readManifest(data: Data) throws -> LoadListManifest
}
```

`LoadListReader` owns length-prefixed CP437 string parsing for manifest fields. Keep that logic out of `BinaryReader` if cache-block parsing already carries the same separation; reuse helpers only when the encoding rule is exactly the same.

`LoadListWriter`:

```swift
public enum LoadListWriter {
    @discardableResult
    public static func writeManifest(_ manifest: LoadListManifest, to url: URL) throws -> Int
    public static func encodeManifest(_ manifest: LoadListManifest) throws -> Data
}
```

`LoadListClassifier`:

```swift
public struct LoadListClassificationInput: Equatable {
    public let internalName: String       // PAK internal name, e.g. "[media]\\classes\\trucks\\hummer_h2.xml"
    public let sourcePak: String          // owning fixture PAK filename
}

public enum LoadListClassifier {
    public static func classify(_ input: LoadListClassificationInput) throws -> LoadListRecord?
}
```

The classifier returns `nil` for entries that intentionally do not appear in `pak.load_list` (e.g. `pak.load_list` itself, `initial.cache_block`, and any namespace not consumed by the manifest). Classification rules are derived from the reference manifest, not invented.

Path conversion rule for the manifest:

```text
[media]\classes\trucks\hummer_h2.xml -> <media>\classes\trucks\hummer_h2.xml
[ssl_cache]\initial_debug.sslbundle  -> <ssl_cache>\initial_debug.sslbundle
[strings]\strings_english.str        -> <strings>\strings_english.str
```

Reject ambiguous inputs the same way Phases 2 and 3 do:

```text
empty paths
paths containing forward slash
paths whose first component is not a [name] namespace
internal names that map to a different namespace than the one observed in the reference manifest
duplicate exact records inside a phase
duplicate case-insensitive records inside a phase
```

`LoadListBuilder`:

```swift
public struct LoadListBuilderInputs {
    public let initialPak: URL
    public let sharedPak: URL
    public let sharedSoundPak: URL
}

public enum LoadListBuilder {
    public static func buildManifest(inputs: LoadListBuilderInputs) throws -> LoadListManifest
}
```

Builder behavior:

```text
1. Read each fixture PAK with PakReader.
2. For initial.pak, also extract initial.cache_block payloads with CacheBlockReader; classify cache-block entries against initial.pak as their source.
3. Skip pak.load_list and initial.cache_block as PAK entries; do not classify them.
4. Run LoadListClassifier on every remaining entry with sourcePak set to the owning fixture filename.
5. Sort records inside each phase using a deterministic key derived from the parsed reference manifest:
   - case-insensitive ordinal sort by manifestPath, with original path as tiebreaker.
6. Build the source-pak table by collecting every distinct sourcePak in classifier output, in the order they first appear, restricted to LoadListConstants.knownSourcePaks.
7. Construct a LoadListManifest with phaseOrder = LoadListConstants.phasesInWriteOrder.
```

`LoadListInspector`:

```swift
public enum LoadListInspector {
    public static func compactReport(_ manifest: LoadListManifest) -> String
}
```

The compact report must produce one line per record in phase order:

```text
<phase>\t<sourcePak>\t<loaderType>\t<manifestPath>
```

The returned string ends with exactly one trailing `\n`; downstream consumers (CLI stdout, the inspector test) compare against it verbatim. If SnowPakTool's `load_list list --compact` uses a different separator on the host where the report was generated, the test must normalize both files identically before comparison.

`LoadListError` must include:

```swift
public enum LoadListError: Error, CustomStringConvertible, Equatable {
    case invalidVersionTag(UInt32)
    case invalidMarker(field: String, expected: UInt8, actual: UInt8)
    case invalidStringLength(Int32)
    case invalidPhaseTag(String)
    case invalidLoaderType(String)
    case invalidSourcePakIndex(Int32)
    case invalidManifestPath(String)
    case duplicateRecord(phase: String, path: String)
    case duplicateCaseInsensitiveRecord(phase: String, path: String)
    case missingSharedPak
    case missingSharedSoundPak
    case mismatchedRecordCount(phase: String, headerCount: Int, parsedCount: Int)
    case unsupportedNonASCIIString(String)
    case truncatedManifest
}
```

Outer-PAK rebuild behavior in `PakWriter`:

```text
1. Resolve unpacked directory contents the same way Phase 2 (or Phase 3 mixed mode) does.
2. Generate pak.load_list bytes via LoadListBuilder + LoadListWriter using the supplied shared.pak and shared_sound.pak URLs.
3. Write the generated manifest to a temporary file under FileManager.default.temporaryDirectory.
4. Inject that temporary file as the pak.load_list PakFileSource, ignoring any stale pak.load_list inside the unpacked directory.
5. Delegate to the existing writer path; if --mixed-cache-block is also requested, the cache-block injection from Phase 3 still applies.
```

`PakVerifier` is not modified. The rebuild path must produce a manifest that satisfies the existing `verify-basic` and `verify-snowpak-layout` checks unchanged. If a verifier change is required, that is a Phase 1 / Phase 2 contract change and must be raised before continuing this phase.

## Implementation Tasks

### Task 1: Reference Manifest Fixture And Parser Skeleton

**Files:**
- Create `Sources/SnowRunnerTool/LoadList/LoadListConstants.swift`
- Create `Sources/SnowRunnerTool/LoadList/LoadListError.swift`
- Create `Sources/SnowRunnerTool/LoadList/LoadListRecord.swift`
- Create `Sources/SnowRunnerTool/LoadList/LoadListManifest.swift`
- Create `Sources/SnowRunnerTool/LoadList/LoadListReader.swift` (skeleton only; full record parsing is added in Task 2)
- Modify `Tests/SnowRunnerToolTests/TestFixtures.swift`
- Create `Tests/SnowRunnerToolTests/LoadListReaderTests.swift`

- [ ] **Step 1: Add manifest extraction helper**

Add to `TestFixtures`:

```swift
static func extractPakLoadList(from pakURL: URL) throws -> URL {
    let archive = try PakReader.readArchive(at: pakURL)
    guard let entry = archive.entries.first(where: { $0.name == "pak.load_list" }) else {
        throw LoadListError.truncatedManifest
    }
    let output = try temporaryDirectory(named: "load-list-fixture")
        .appendingPathComponent("pak.load_list")
    try PakReader.readUncompressedPayload(entry: entry, in: archive).write(to: output)
    return output
}
```

- [ ] **Step 2: Write failing manifest-skeleton tests**

```swift
func testReaderRecognizesReferenceManifestVersionTagAndPhaseSet() throws {
    let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
    let manifest = try LoadListReader.readManifest(from: url)

    XCTAssertEqual(manifest.versionTag, LoadListConstants.versionTag)
    XCTAssertEqual(manifest.phaseOrder, LoadListConstants.phasesInWriteOrder)
    XCTAssertEqual(manifest.recordFlags.count, 17917)
    XCTAssertEqual(manifest.headerTail, 0x00000003)
}
```

- [ ] **Step 3: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListReaderTests
```

Expected: FAIL because none of the load-list types exist.

- [ ] **Step 4: Implement minimum types and the version-tag, source-pak-table, and phase-tag scan**

Implement only enough of `LoadListReader` to read the version tag, marker, source-pak table, and the eight phase tag strings in order. Do not parse records yet; treat each phase as opaque bytes the reader skips by length until the manifest terminator.

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListReaderTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnowRunnerTool/LoadList Tests/SnowRunnerToolTests/TestFixtures.swift Tests/SnowRunnerToolTests/LoadListReaderTests.swift
git commit -m "feat: parse load-list header and phase set"
```

### Task 2: Full Record Parser And Per-Phase Counts

**Files:**
- Modify `Sources/SnowRunnerTool/LoadList/LoadListReader.swift`
- Modify `Tests/SnowRunnerToolTests/LoadListReaderTests.swift`

- [ ] **Step 1: Write failing record-parser tests**

```swift
func testReaderParsesEveryRecordInReferenceManifest() throws {
    let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
    let manifest = try LoadListReader.readManifest(from: url)

    let total = manifest.phaseOrder.reduce(0) { partial, phase in
        partial + (manifest.recordsByPhase[phase]?.count ?? 0)
    }
    XCTAssertGreaterThan(total, 17000)

    let descBlock = manifest.recordsByPhase["DESC_BLOCK load", default: []]
    XCTAssertTrue(descBlock.contains { $0.loaderType == "cls_loader" && $0.manifestPath.hasPrefix("<media>\\classes\\trucks") })

    let initialPakRecords = descBlock.filter { $0.sourcePak == "initial.pak" }
    XCTAssertGreaterThan(initialPakRecords.count, 0)
}

func testReaderRejectsTruncatedManifest() {
    let bytes = Data([0x01, 0x00, 0x00, 0x00])
    XCTAssertThrowsError(try LoadListReader.readManifest(data: bytes))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListReaderTests
```

Expected: FAIL because the reader still treats phases as opaque bytes.

- [ ] **Step 3: Implement full record parsing**

The reader must parse the structures in the order documented under "Fixture facts": signature/version, total record count, source-pak table, per-record flag/category table (a contiguous run of one byte per record), then each phase as:

```text
phase tag length-prefixed CP437 string
record_count u32
record_count records:
  manifestPath length-prefixed CP437 string
  loaderType length-prefixed CP437 string
  sourcePak attribution: either an Int32 source-pak table index or a
    length-prefixed CP437 string; the parser observes the fixture and
    locks the mode for both reads and writes
phase footer (the per-phase trailing bytes observed in the reference fixture;
  pin the exact bytes once read from the fixture)
```

Bind the per-record flag-table bytes to records by global record index (across all phases, in write order) and store the result on `LoadListRecord.flags`. Parsers must not invent a flag-byte location; if the actual layout differs from the format-doc fingerprint, update Task 1's "Fixture facts" before proceeding.

Validate every length, every marker, and the manifest terminator. Reject non-ASCII bytes via `CP437.decode`. Verify that the sum of per-phase record counts equals the manifest-level total record count and the flag-table length; mismatches must throw `LoadListError.mismatchedRecordCount`.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListReaderTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/LoadList/LoadListReader.swift Tests/SnowRunnerToolTests/LoadListReaderTests.swift
git commit -m "feat: parse load-list records"
```

### Task 3: Compact Inspector And SnowPakTool Equivalence

**Files:**
- Create `Sources/SnowRunnerTool/LoadList/LoadListInspector.swift`
- Modify `Tests/SnowRunnerToolTests/TestFixtures.swift`
- Create `Tests/SnowRunnerToolTests/LoadListInspectorTests.swift`
- Add `fixtures/reports/load-list-compact.txt` (generated externally, committed as a test oracle)

- [ ] **Step 1: Generate the SnowPakTool reference report**

On a Windows host with the fixed SnowPakTool build, run:

```bat
snowpaktool load_list list --compact initial.pak\pak.load_list > load-list-compact.txt
```

Commit the resulting file as `fixtures/reports/load-list-compact.txt`. If the column separator is not tab, document the actual separator in the file's first line and reuse that separator below.

- [ ] **Step 2: Write failing inspector test**

```swift
func testInspectorMatchesSnowPakToolCompactReport() throws {
    let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
    let manifest = try LoadListReader.readManifest(from: url)

    let actual = LoadListInspector.compactReport(manifest)
    let expected = try TestFixtures.loadCompactReferenceReport()

    XCTAssertEqual(actual.normalizedLines(), expected.normalizedLines())
}
```

`normalizedLines()` is a small helper inside the test target that splits on `\n`, trims trailing whitespace, and drops trailing empty lines.

- [ ] **Step 3: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListInspectorTests
```

Expected: FAIL because `LoadListInspector` and the reference loader do not exist.

- [ ] **Step 4: Implement compact inspector**

Output one line per record in phase order:

```text
<phase>\t<sourcePak>\t<loaderType>\t<manifestPath>
```

If the SnowPakTool reference uses a different layout, match it exactly; do not silently change the inspector format to make the test pass against a malformed oracle. If the oracle and the parser disagree, fix whichever is wrong before continuing.

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListInspectorTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnowRunnerTool/LoadList/LoadListInspector.swift fixtures/reports/load-list-compact.txt Tests/SnowRunnerToolTests/TestFixtures.swift Tests/SnowRunnerToolTests/LoadListInspectorTests.swift
git commit -m "feat: format load-list as compact report"
```

### Task 4: Read-Only `load-list inspect` CLI

**Files:**
- Modify `Sources/SnowRunnerTool/CLI.swift`
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Write failing CLI test**

```swift
func testCLILoadListInspectMatchesInspectorOutput() throws {
    let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)

    let result = CLI.run(arguments: ["load-list", "inspect", url.path])

    XCTAssertEqual(result.exitCode, 0)
    let manifest = try LoadListReader.readManifest(from: url)
    XCTAssertEqual(result.stdout, LoadListInspector.compactReport(manifest))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLILoadListInspectMatchesInspectorOutput
```

Expected: FAIL because `load-list inspect` is unknown.

- [ ] **Step 3: Add CLI parsing**

Usage must include:

```text
snowrunner-tool load-list inspect <pak.load_list>
```

Successful behavior:

```text
exit code: 0
stdout: LoadListInspector.compactReport(manifest)
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLILoadListInspectMatchesInspectorOutput
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CLI.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "feat: add load-list inspect cli"
```

### Task 5: Manifest Writer And Round-Trip

**Files:**
- Create `Sources/SnowRunnerTool/LoadList/LoadListWriter.swift`
- Create `Tests/SnowRunnerToolTests/LoadListWriterTests.swift`

- [ ] **Step 1: Write failing writer tests**

```swift
func testWriterRoundTripsParsedReferenceManifestByteForByte() throws {
    let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
    let original = try Data(contentsOf: url)
    let manifest = try LoadListReader.readManifest(data: original)

    let written = try LoadListWriter.encodeManifest(manifest)

    XCTAssertEqual(written, original)
}

func testWriterRejectsManifestWithUnknownPhase() {
    let manifest = LoadListManifest(
        versionTag: LoadListConstants.versionTag,
        sourcePakTable: ["initial.pak"],
        recordsByPhase: ["UNKNOWN load": []],
        phaseOrder: ["UNKNOWN load"]
    )

    XCTAssertThrowsError(try LoadListWriter.encodeManifest(manifest))
}
```

The byte-for-byte round-trip is required because the parser and writer must agree on every byte, including per-phase footers and the manifest terminator. If the round-trip fails, the parser is incomplete and Task 2 must be revisited before continuing.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListWriterTests
```

Expected: FAIL because `LoadListWriter` does not exist.

- [ ] **Step 3: Implement writer**

Serialize in `phaseOrder`. Each record uses the same source-pak attribution mode the reader observed (table index vs inline string). Emit phase footers and the manifest terminator using the constants captured from the reference fixture.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListWriterTests
```

Expected: PASS, including byte-for-byte equality with the reference fixture.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/LoadList/LoadListWriter.swift Tests/SnowRunnerToolTests/LoadListWriterTests.swift
git commit -m "feat: write load-list manifests"
```

### Task 6: Classifier From Reference Manifest

**Files:**
- Create `Sources/SnowRunnerTool/LoadList/LoadListClassifier.swift`
- Create `Tests/SnowRunnerToolTests/LoadListClassifierTests.swift`

- [ ] **Step 1: Write failing classifier tests**

```swift
func testClassifierRecognizesKnownEntryShapes() throws {
    let cls = try LoadListClassifier.classify(.init(
        internalName: "[media]\\classes\\trucks\\hummer_h2.xml",
        sourcePak: "initial.pak"
    ))
    XCTAssertEqual(cls?.loaderType, "cls_loader")
    XCTAssertEqual(cls?.phase, "DESC_BLOCK load")
    XCTAssertEqual(cls?.manifestPath, "<media>\\classes\\trucks\\hummer_h2.xml")

    let tpl = try LoadListClassifier.classify(.init(
        internalName: "[media]\\_templates\\trucks.xml",
        sourcePak: "initial.pak"
    ))
    XCTAssertEqual(tpl?.loaderType, "tpl_loader")
    XCTAssertEqual(tpl?.phase, "TEMPLATES load")

    let ssl = try LoadListClassifier.classify(.init(
        internalName: "[ssl_cache]\\initial_debug.sslbundle",
        sourcePak: "initial.pak"
    ))
    XCTAssertEqual(ssl?.loaderType, "sslbundle")
    XCTAssertEqual(ssl?.phase, "SSL_INITIAL load")
}

func testClassifierSkipsManifestAndCacheBlock() throws {
    XCTAssertNil(try LoadListClassifier.classify(.init(
        internalName: "pak.load_list",
        sourcePak: "initial.pak"
    )))
    XCTAssertNil(try LoadListClassifier.classify(.init(
        internalName: "initial.cache_block",
        sourcePak: "initial.pak"
    )))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListClassifierTests
```

Expected: FAIL because `LoadListClassifier` does not exist.

- [ ] **Step 3: Implement classifier**

Implement classification rules derived from the parsed reference manifest:

```text
[media]\_templates\<file>.xml         -> tpl_loader, phase TEMPLATES load
[ssl_cache]\<file>.sslbundle          -> sslbundle, phase SSL_INITIAL load
[media]\classes\...\<file>.xml        -> cls_loader, phase DESC_BLOCK load
shared.pak meshes (path pattern derived from reference) -> mesh_loader, phase derived from reference
shared_sound.pak audio                -> sound_loader, phase derived from reference
[strings] entries                      -> phase observed in reference (record may not be a cls_loader)
pak.load_list, initial.cache_block     -> nil
```

If a path matches none of these rules, throw `LoadListError.invalidManifestPath`. The classifier is the single place that decides which entries are recorded; the builder must not second-guess it.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListClassifierTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/LoadList/LoadListClassifier.swift Tests/SnowRunnerToolTests/LoadListClassifierTests.swift
git commit -m "feat: classify load-list entries"
```

### Task 7: Builder And Phase-By-Phase Parity With Reference

**Files:**
- Create `Sources/SnowRunnerTool/LoadList/LoadListBuilder.swift`
- Create `Tests/SnowRunnerToolTests/LoadListBuilderTests.swift`

- [ ] **Step 1: Write failing builder tests**

```swift
func testBuilderProducesSameRecordCountsAsReferenceManifest() throws {
    let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
    let reference = try LoadListReader.readManifest(from: url)

    let manifest = try LoadListBuilder.buildManifestFromPaks(inputs: .init(
        initialPak: TestFixtures.initialPak,
        sharedPak: try TestFixtures.requireSharedPak(),
        sharedSoundPak: try TestFixtures.requireSharedSoundPak()
    ))

    for phase in LoadListConstants.phasesInWriteOrder {
        XCTAssertEqual(
            manifest.recordsByPhase[phase, default: []].count,
            reference.recordsByPhase[phase, default: []].count,
            phase
        )
    }
}

func testBuilderRecordSetMatchesReferenceManifest() throws {
    let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
    let reference = try LoadListReader.readManifest(from: url)

    let manifest = try LoadListBuilder.buildManifestFromPaks(inputs: .init(
        initialPak: TestFixtures.initialPak,
        sharedPak: try TestFixtures.requireSharedPak(),
        sharedSoundPak: try TestFixtures.requireSharedSoundPak()
    ))

    for phase in LoadListConstants.phasesInWriteOrder {
        let referenceKeys = Set((reference.recordsByPhase[phase] ?? []).map(\.manifestPath))
        let builtKeys = Set((manifest.recordsByPhase[phase] ?? []).map(\.manifestPath))
        XCTAssertEqual(builtKeys, referenceKeys, phase)
    }
}
```

`TestFixtures.requireSharedPak()` and `requireSharedSoundPak()` must `throw XCTSkip` when the fixture is absent so the suite stays green on machines without the optional fixtures.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListBuilderTests
```

Expected: FAIL because the builder does not exist.

- [ ] **Step 3: Implement builder**

Walk each fixture PAK with `PakReader`. For `initial.pak`, also walk its `initial.cache_block`. Pass each entry through `LoadListClassifier`, drop `nil` results, and group by phase. Sort each phase by `(manifestPath.lowercased(), manifestPath)`. Build the source-pak table from observed `sourcePak` values restricted to `LoadListConstants.knownSourcePaks`, preserving first-seen order.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter LoadListBuilderTests
```

Expected: PASS for each phase. If a phase mismatches, do not loosen the test; instead fix the classifier or builder until the record sets match. A mismatch is the canonical signal that classifier rules need to be refined against the reference.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/LoadList/LoadListBuilder.swift Tests/SnowRunnerToolTests/LoadListBuilderTests.swift
git commit -m "feat: build load-list manifests from fixture paks"
```

### Task 8: `load-list create-initial` CLI

**Files:**
- Modify `Sources/SnowRunnerTool/CLI.swift`
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Write failing CLI test**

```swift
func testCLILoadListCreateInitialWritesParseableManifest() throws {
    let target = try temporaryDirectory(named: "cli-load-list")
        .appendingPathComponent("pak.load_list")

    let result = CLI.run(arguments: [
        "load-list", "create-initial",
        target.path,
        TestFixtures.initialPak.path,
        try TestFixtures.requireSharedPak().path,
        try TestFixtures.requireSharedSoundPak().path
    ])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains("created"))

    let manifest = try LoadListReader.readManifest(from: target)
    XCTAssertEqual(manifest.phaseOrder, LoadListConstants.phasesInWriteOrder)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLILoadListCreateInitialWritesParseableManifest
```

Expected: FAIL because `load-list create-initial` is unknown.

- [ ] **Step 3: Add CLI parsing**

Usage must include:

```text
snowrunner-tool load-list create-initial <target.load_list> <initial.pak> <shared.pak> <shared_sound.pak>
```

Implementation: parse the four positional arguments, call `LoadListBuilder.buildManifestFromPaks`, and write the result with `LoadListWriter.writeManifest`. Wire under the `runLoadListCommand` dispatcher added in Task 4.

Successful output:

```text
created load-list with N records across M phases
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLILoadListCreateInitialWritesParseableManifest
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CLI.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "feat: add load-list create-initial cli"
```

### Task 9: Outer-PAK Rebuild Path

**Files:**
- Modify `Sources/SnowRunnerTool/Pak/PakWriter.swift`
- Modify `Sources/SnowRunnerTool/Pak/PakWriterError.swift`
- Modify `Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift` (only if needed)
- Create `Tests/SnowRunnerToolTests/RebuildLoadListPakTests.swift`

- [ ] **Step 1: Write failing rebuild tests**

```swift
func testRebuildLoadListPakPassesExistingPakVerifiers() throws {
    let mixedRoot = try temporaryDirectory(named: "rebuild-root")
    let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("rebuild.pak")

    try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: mixedRoot)
    try CacheBlockUnpacker.unpack(
        cacheBlockURL: mixedRoot.appendingPathComponent("initial.cache_block"),
        toDirectory: mixedRoot
    )

    try PakWriter.writeArchive(
        fromDirectory: mixedRoot,
        to: candidate,
        rebuildLoadList: true,
        mixedCacheBlock: true,
        sharedPak: try TestFixtures.requireSharedPak(),
        sharedSoundPak: try TestFixtures.requireSharedSoundPak()
    )

    let archive = try PakReader.readArchive(at: candidate)
    XCTAssertEqual(archive.entries[0].name, "pak.load_list")
    XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
    XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)

    let manifestData = try PakReader.readUncompressedPayload(entry: archive.entries[0], in: archive)
    let manifest = try LoadListReader.readManifest(data: manifestData)
    XCTAssertEqual(manifest.phaseOrder, LoadListConstants.phasesInWriteOrder)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter RebuildLoadListPakTests
```

Expected: FAIL because the rebuild entry point does not exist.

- [ ] **Step 3: Implement rebuild path**

Add:

```swift
@discardableResult
public static func writeArchive(
    fromDirectory directory: URL,
    to outputURL: URL,
    rebuildLoadList: Bool,
    mixedCacheBlock: Bool,
    sharedPak: URL?,
    sharedSoundPak: URL?
) throws -> Int
```

When `rebuildLoadList == true`, `sharedPak` and `sharedSoundPak` are required; if either is missing, throw `PakWriterError.missingSharedPak` or `missingSharedSoundPak`. Generate the manifest into a temporary file via `LoadListBuilder` + `LoadListWriter`, then inject it as the `pak.load_list` source overriding any stale file in `directory`. When `mixedCacheBlock == true`, reuse the Phase 3 injection unchanged.

Keep existing entry points intact:

```swift
public static func writeArchive(fromDirectory directory: URL, to outputURL: URL) throws -> Int
public static func writeArchive(fromDirectory directory: URL, to outputURL: URL, mixedCacheBlock: Bool) throws -> Int
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter RebuildLoadListPakTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/PakWriter.swift Sources/SnowRunnerTool/Pak/PakWriterError.swift Tests/SnowRunnerToolTests/RebuildLoadListPakTests.swift
git commit -m "feat: rebuild load-list during pak pack"
```

### Task 10: `pak pack --rebuild-load-list` CLI

**Files:**
- Modify `Sources/SnowRunnerTool/CLI.swift`
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Write failing CLI test**

```swift
func testCLIPakPackRebuildLoadListProducesVerifiableArchive() throws {
    let mixedRoot = try temporaryDirectory(named: "cli-rebuild-root")
    let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("cli-rebuild.pak")

    XCTAssertEqual(CLI.run(arguments: ["pak", "unpack", TestFixtures.initialPak.path, mixedRoot.path]).exitCode, 0)
    XCTAssertEqual(CLI.run(arguments: [
        "cache-block", "unpack",
        mixedRoot.appendingPathComponent("initial.cache_block").path,
        mixedRoot.path
    ]).exitCode, 0)

    let result = CLI.run(arguments: [
        "pak", "pack",
        "--rebuild-load-list", "--mixed-cache-block",
        mixedRoot.path, candidate.path,
        try TestFixtures.requireSharedPak().path,
        try TestFixtures.requireSharedSoundPak().path
    ])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains("packed"))
    XCTAssertEqual(CLI.run(arguments: ["pak", "verify-basic", candidate.path]).exitCode, 0)
    XCTAssertEqual(CLI.run(arguments: ["pak", "verify-snowpak-layout", candidate.path]).exitCode, 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLIPakPackRebuildLoadListProducesVerifiableArchive
```

Expected: FAIL because `--rebuild-load-list` is not parsed.

- [ ] **Step 3: Add CLI option parsing**

Accept these shapes:

```text
snowrunner-tool pak pack --rebuild-load-list <dir> <pak> <shared.pak> <shared_sound.pak>
snowrunner-tool pak pack --rebuild-load-list --mixed-cache-block <dir> <pak> <shared.pak> <shared_sound.pak>
snowrunner-tool pak pack --mixed-cache-block --rebuild-load-list <dir> <pak> <shared.pak> <shared_sound.pak>
```

Parsing rule, applied to the arguments passed to the `pack` case (i.e. arguments after `pak pack`):

```text
1. Drop the leading "pack" token.
2. Collect the contiguous prefix of tokens that start with "--" into a flag set; stop at the first non-flag token.
3. Reject unknown flags. Reject duplicate flags.
4. Determine the expected positional count from the flag set:
     {}                                            -> 2 positionals (dir, pak)
     {--mixed-cache-block}                         -> 2 positionals (dir, pak)
     {--rebuild-load-list}                         -> 4 positionals (dir, pak, shared, shared_sound)
     {--rebuild-load-list, --mixed-cache-block}    -> 4 positionals (dir, pak, shared, shared_sound)
5. If the remaining positional count does not match exactly, emit usage and exit 2.
```

Keep existing Phase 2 and Phase 3 shapes unchanged. Do not silently accept `--rebuild-load-list` without the two trailing fixture arguments.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLIPakPackRebuildLoadListProducesVerifiableArchive
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CLI.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "feat: expose pak pack --rebuild-load-list"
```

### Task 11: Add-One-Controlled-File Acceptance

**Files:**
- Modify `Tests/SnowRunnerToolTests/RebuildLoadListPakTests.swift`

- [ ] **Step 1: Write failing single-record-addition test**

```swift
func testRebuildAddsControlledClsLoaderRecord() throws {
    let mixedRoot = try temporaryDirectory(named: "rebuild-add-one")
    let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("rebuild-add-one.pak")
    try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: mixedRoot)
    try CacheBlockUnpacker.unpack(
        cacheBlockURL: mixedRoot.appendingPathComponent("initial.cache_block"),
        toDirectory: mixedRoot
    )

    let extraFile = mixedRoot.appendingPathComponent("[media]")
        .appendingPathComponent("classes")
        .appendingPathComponent("trucks")
        .appendingPathComponent("phase4_probe.xml")
    try FileManager.default.createDirectory(
        at: extraFile.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("<truck phase4_probe=\"1\"/>".utf8).write(to: extraFile)

    try PakWriter.writeArchive(
        fromDirectory: mixedRoot,
        to: candidate,
        rebuildLoadList: true,
        mixedCacheBlock: true,
        sharedPak: try TestFixtures.requireSharedPak(),
        sharedSoundPak: try TestFixtures.requireSharedSoundPak()
    )

    let archive = try PakReader.readArchive(at: candidate)
    let manifestData = try PakReader.readUncompressedPayload(entry: archive.entries[0], in: archive)
    let manifest = try LoadListReader.readManifest(data: manifestData)
    let descBlock = manifest.recordsByPhase["DESC_BLOCK load", default: []]

    XCTAssertTrue(descBlock.contains { record in
        record.manifestPath == "<media>\\classes\\trucks\\phase4_probe.xml"
            && record.loaderType == "cls_loader"
            && record.sourcePak == "initial.pak"
    })
}
```

- [ ] **Step 2: Run test and inspect**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter RebuildLoadListPakTests/testRebuildAddsControlledClsLoaderRecord
```

If the test fails, the classifier or builder is not picking up new files in already-known patterns. Fix the relevant module rather than weakening the test.

- [ ] **Step 3: Commit**

```bash
git add Tests/SnowRunnerToolTests/RebuildLoadListPakTests.swift
git commit -m "test: rebuild adds controlled cls_loader record"
```

### Task 12: Full Phase Acceptance

**Files:**
- Modify only files needed to fix failures exposed by full acceptance.

- [ ] **Step 1: Run the complete automated test suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
```

Expected: PASS.

- [ ] **Step 2: Run manual CLI acceptance**

Run:

```bash
PHASE4_DIR="$(mktemp -d /tmp/snowrunner-tools-phase4.XXXXXX)"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak unpack fixtures/initial.pak "$PHASE4_DIR/initial"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block unpack "$PHASE4_DIR/initial/initial.cache_block" "$PHASE4_DIR/initial"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list inspect "$PHASE4_DIR/initial/pak.load_list" > "$PHASE4_DIR/inspect.txt"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list create-initial "$PHASE4_DIR/created.load_list" fixtures/initial.pak fixtures/shared.pak fixtures/shared_sound.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak pack --rebuild-load-list --mixed-cache-block "$PHASE4_DIR/initial" "$PHASE4_DIR/initial.rebuild.pak" fixtures/shared.pak fixtures/shared_sound.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-basic "$PHASE4_DIR/initial.rebuild.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-snowpak-layout "$PHASE4_DIR/initial.rebuild.pak"
```

Expected:

```text
load-list inspect exits 0 and matches fixtures/reports/load-list-compact.txt under the same normalization the test uses
load-list create-initial exits 0 and writes a parseable manifest
pak pack --rebuild-load-list --mixed-cache-block exits 0
verify-basic exits 0
verify-snowpak-layout exits 0
```

- [ ] **Step 3: Confirm expected non-goal behavior**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak "$PHASE4_DIR/initial.rebuild.pak"
```

Expected: FAIL only for the same reasons Phase 3 documents (loose `[strings]` moved into `initial.cache_block`, plus a different `pak.load_list` byte set when the rebuilder produces deterministic output that differs from the original record order). Do not block Phase 4 on byte equality with the original manifest; block only on game launch.

- [ ] **Step 4: Manual game-launch acceptance**

Replace a backed-up game `initial.pak` with `$PHASE4_DIR/initial.rebuild.pak` and launch the game.

Expected:

```text
The game reaches the main menu with the rebuilt-manifest candidate.
```

- [ ] **Step 5: Commit**

```bash
git add Sources Tests docs/phase-4-implementation-plan.md
git commit -m "test: complete phase 4 load-list acceptance"
```

## Test Strategy

- Unit tests for length-prefixed CP437 reads, marker validation, and per-phase footers.
- Synthetic manifest tests for hand-built minimal manifests to exercise edge cases (empty phase, single record, missing terminator).
- Fixture parser tests against `pak.load_list` extracted from `fixtures/initial.pak` and `fixtures/initial.repacked.pak`.
- Inspector equivalence test against the SnowPakTool `load_list list --compact` reference report.
- Writer byte-for-byte round-trip test against the parsed reference manifest. This is the only safe way to confirm the parser does not lose information.
- Classifier rule tests for every loader type observed in the reference fixture.
- Builder phase-by-phase parity test against the parsed reference manifest, gated on optional `shared.pak` and `shared_sound.pak` fixtures via `XCTSkip`.
- Outer-PAK rebuild test that proves the existing PAK verifiers still pass after the rebuilt manifest replaces the original.
- Single-record-addition test that proves the rebuilder picks up new files in known patterns without weakening the verifier.
- CLI tests for `load-list inspect`, `load-list create-initial`, and `pak pack --rebuild-load-list`.
- Game-launch test is required because Phase 4 emits a candidate game PAK with a regenerated manifest.

## Acceptance Criteria

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
```

Must pass.

```bash
PHASE4_DIR="$(mktemp -d /tmp/snowrunner-tools-phase4.XXXXXX)"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak unpack fixtures/initial.pak "$PHASE4_DIR/initial"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block unpack "$PHASE4_DIR/initial/initial.cache_block" "$PHASE4_DIR/initial"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list inspect "$PHASE4_DIR/initial/pak.load_list"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list create-initial "$PHASE4_DIR/created.load_list" fixtures/initial.pak fixtures/shared.pak fixtures/shared_sound.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak pack --rebuild-load-list --mixed-cache-block "$PHASE4_DIR/initial" "$PHASE4_DIR/initial.rebuild.pak" fixtures/shared.pak fixtures/shared_sound.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-basic "$PHASE4_DIR/initial.rebuild.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-snowpak-layout "$PHASE4_DIR/initial.rebuild.pak"
```

Must pass.

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak "$PHASE4_DIR/initial.rebuild.pak"
```

Must fail only for expected reasons documented in Phase 3 plus regenerated `pak.load_list` bytes that no longer match the original record ordering.

Manual game-launch acceptance must pass with `$PHASE4_DIR/initial.rebuild.pak`.

## Risks

- Manifest byte layout: the per-record flag-table location, the per-phase footer bytes, source-pak attribution mode (table index vs inline string), and the manifest terminator are not fully documented. The format doc (§12.6) only fingerprints them. The parser establishes the contract, the writer round-trips it byte-for-byte (Task 5), and the builder reproduces the same bytes for a rebuilt-from-fixtures manifest. Any drift between parser and writer is caught by Task 5; if Task 5 fails, the parser's flag-table or footer model is wrong and must be revised before Task 6.
- Classifier completeness: the rules cover the loader types observed in the reference fixture. New entry shapes that match no rule must throw rather than silently dropping records. Builder parity tests in Task 7 enforce this.
- `shared_debug.pak` attribution: the manifest references `shared_debug.pak` in its source-pak table. Whether any actual records are attributed to it is only knowable after Task 2 parses the fixture and Task 7 cross-checks against `shared.pak` + `shared_sound.pak`. If Task 7 surfaces records that cannot be classified without `shared_debug.pak` content, promote `fixtures/shared_debug.pak` from optional to required and extend both `LoadListBuilderPakInputs` and `LoadListBuilderDirectoryInputs` with a `sharedDebugPak: URL` field. Update this plan in place before continuing.
- Optional fixtures: `fixtures/shared.pak` and `fixtures/shared_sound.pak` are large and may be absent on some machines. Tests that require them must skip via `XCTSkip` rather than fail. Manual acceptance and game-launch acceptance still require both files (and possibly `shared_debug.pak`).
- CP437 support is still ASCII-only. Manifest strings in current fixtures are ASCII; non-ASCII paths must fail clearly rather than guessing an encoding.
- Game compatibility is not proven by parser equivalence alone. Phase 4 emits a candidate PAK with a regenerated manifest, so manual launch remains part of acceptance.
- Determinism: rebuilt manifest bytes can change if the classifier sort key, source-pak first-seen order, or per-phase footer constants change. Pin all three in code constants (or fixture-derived constants) and cover them in Task 5's round-trip and Task 7's parity tests.
- Stale manifest on disk: when rebuilding, the unpacked tree contains the original `pak.load_list`. The rebuild path must inject the regenerated manifest and confirm the on-disk one is ignored. The current `PakDirectoryScanner` already skips disk files whose names appear in `additionalFileSources`; a regression test is required to keep that behavior pinned.

## Stop Rule

Phase 4 is complete only when all automated tests pass, the writer round-trips the reference manifest byte-for-byte, the builder produces phase-by-phase record parity with the parsed reference manifest, the rebuilt-manifest candidate PAK passes `verify-basic` and `verify-snowpak-layout`, the single-record-addition test passes, and the rebuilt-manifest candidate launches the game.

Do not start any later phase because load-list parsing "looks close." If round-trip, parity, or game launch fails, update this phase plan with the actual format finding before continuing.
