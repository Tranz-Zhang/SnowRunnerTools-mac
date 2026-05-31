# Phase 3 Cache Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 3 builds cache-block unpacking, cache-block packing, and mixed-cache-block PAK packing so an unpacked `initial.pak` can expose, rebuild, and re-embed `initial.cache_block`.

**Architecture:** Add a focused `CacheBlock` module that owns the cache-block binary format, path conversion, and filesystem extraction. Integrate it into `pak pack --mixed-cache-block` by generating a temporary `initial.cache_block` from mixed source directories, then writing the outer PAK through the existing Phase 2 writer and verifier.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation `Data` / `FileHandle` / `FileManager`, existing CP437 ASCII fast path, existing custom PAK reader/writer, XCTest.

---

## Phase Goal

Phase 3 proves `initial.cache_block` by unpacking it to normal macOS files, packing those files back into a cache-block file, and embedding a regenerated cache block into a SnowPakTool-compatible PAK.

## Non-Goals

- No `pak.load_list` parsing, mutation, or creation.
- No new-file manifest support.
- No high-level ZIP writer APIs.
- No compression inside `cache_block`; payload files are concatenated as raw bytes.
- No non-ASCII cache-block names until full CP437 encode/decode support is needed.
- No ZIP64 or large-cache-block support beyond signed 32-bit entry sizes and signed 64-bit offsets used by SnowPakTool.
- No byte-for-byte guarantee for the outer PAK file because Swift and .NET deflate streams may differ.
- No PAK-entry content-equivalence requirement for mixed-cache-block output because `[strings]` entries intentionally move from loose PAK entries into `initial.cache_block`.

## Inputs And Fixtures

- `fixtures/initial.pak`: required before implementation starts; contains the original `initial.cache_block` as a deflated PAK entry with uncompressed size `14434470`.
- `fixtures/initial.repacked.pak`: required before implementation starts; contains a SnowPakTool-compatible `initial.cache_block` entry with the same uncompressed size `14434470`.
- A generated standalone cache-block file under the XCTest temporary directory: produced by reading `initial.cache_block` from `fixtures/initial.pak`; proves parser and writer behavior without committing another 14 MB fixture.
- A generated pure cache-block unpack directory under the XCTest temporary directory: produced by `CacheBlockUnpacker`; proves internal `<name>` paths map to external `[name]/...` filesystem paths.
- A generated mixed unpack directory under the XCTest temporary directory: produced by `pak unpack`, then `cache-block unpack` into the same root; proves `pak pack --mixed-cache-block`.
- A generated mixed candidate PAK under the XCTest temporary directory: proves the regenerated cache block is accepted by the existing PAK reader and verifier.

Fixture facts this phase depends on:

```text
fixtures/initial.pak:
  initial.cache_block uncompressed size: 14434470
  initial.cache_block compressed size: 810897

fixtures/initial.repacked.pak:
  initial.cache_block uncompressed size: 14434470
  initial.cache_block compressed size: 845337
  initial.cache_block is entry 1 and deflated

standalone initial.cache_block:
  contains `[ps]` and `[ps_common]` entries
  does not prove mixed `[strings]` behavior by itself

mixed generated initial.cache_block:
  contains `[strings]` entries after `cache-block unpack` is mixed into the PAK root and `pak pack --mixed-cache-block` regenerates the cache block
```

The standalone no-edit cache-block pack must preserve every internal name and payload byte. Byte identity with the fixture cache block is not required because the fixture uses an opaque existing entry order that is not recoverable from a plain filesystem tree. The writer emits deterministic sorted order, and game compatibility is proven by the mixed PAK launch acceptance.

## Commands To Deliver

```text
snowrunner-tool cache-block unpack <cache_block> <dir>
snowrunner-tool cache-block pack <dir> <cache_block>
snowrunner-tool cache-block verify-content-equivalent <reference.cache_block> <candidate.cache_block>
snowrunner-tool pak pack --mixed-cache-block <dir> <pak>
```

Existing Phase 1 and Phase 2 commands remain available and are used as acceptance checks:

```text
snowrunner-tool pak unpack <pak> <dir>
snowrunner-tool pak verify-basic <pak>
snowrunner-tool pak verify-snowpak-layout <pak>
```

## Code Structure

- Modify `Sources/SnowRunnerTool/CLI.swift`: add `cache-block` command parsing and `pak pack --mixed-cache-block` option parsing.
- Modify `Sources/SnowRunnerTool/Pak/BinaryReader.swift`: add generic little-endian `Int32` and `Int64` reads needed by cache-block tables.
- Modify `Sources/SnowRunnerTool/Pak/BinaryWriter.swift`: add generic little-endian `Int32`, `Int64`, and `UInt8` writes needed by cache-block tables.
- Modify `Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift`: support excluded top-level directories and additional generated file sources for mixed cache-block packing.
- Modify `Sources/SnowRunnerTool/Pak/PakWriter.swift`: add `mixedCacheBlock` entry point that generates `initial.cache_block`, excludes mixed cache-block directories, and writes the existing SnowPakTool-compatible PAK layout.
- Modify `Sources/SnowRunnerTool/Pak/PakVerifier.swift`: accept mixed-cache-block PAKs where loose `[strings]` entries are absent only when `initial.cache_block` contains `[strings]` cache-block entries.
- Modify `Sources/SnowRunnerTool/Pak/PakWriterError.swift`: add mixed-cache-block validation errors.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockConstants.swift`: signature bytes, fixed markers, initial cache-block filename, and mixed source directory names.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockError.swift`: parser, path, and writer error cases with stable descriptions.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockEntry.swift`: entry metadata with internal name, external filesystem path, relative offset, size, and zero field.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockArchive.swift`: parsed cache-block model holding source data, entries, and payload base offset.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockPath.swift`: conversion between internal `<ps>:file` / `<ps>\dir\file` names and external `[ps]/...` filesystem paths.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockReader.swift`: parse header, names, offsets, sizes, zero table, and payload bounds.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockDirectoryScanner.swift`: scan pure or mixed directories and return sorted cache-block file sources.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockUnpacker.swift`: write cache-block payload files to disk.
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockWriter.swift`: write header, name table, offset table, size table, zero table, and payload bytes.
- Modify `Tests/SnowRunnerToolTests/TestFixtures.swift`: add helper to extract `initial.cache_block` from a fixture PAK into a temporary file.
- Create `Tests/SnowRunnerToolTests/CacheBlockPathTests.swift`: path conversion and validation tests.
- Create `Tests/SnowRunnerToolTests/CacheBlockReaderTests.swift`: synthetic and fixture parser tests.
- Create `Tests/SnowRunnerToolTests/CacheBlockUnpackerTests.swift`: unpack fixture tests.
- Create `Tests/SnowRunnerToolTests/CacheBlockWriterTests.swift`: synthetic writer and no-edit fixture roundtrip tests.
- Create `Tests/SnowRunnerToolTests/MixedCacheBlockPakTests.swift`: mixed directory pack and verifier tests.
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`: CLI coverage for `cache-block unpack`, `cache-block pack`, and `pak pack --mixed-cache-block`.

## Implementation Contracts

The cache-block header is fixed:

```swift
enum CacheBlockConstants {
    static let initialCacheBlockName = "initial.cache_block"
    static let mixedTopLevelDirectories = ["[ps]", "[ps_common]", "[strings]"]
    static let signature: [UInt8] = [
        0x31, 0x53, 0x45, 0x52, 0x63, 0x61, 0x63, 0x68,
        0x65, 0x5F, 0x62, 0x6C, 0x6F, 0x63, 0x6B, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x53, 0x33, 0x44, 0x52,
        0x45, 0x53, 0x4F, 0x55, 0x52, 0x43, 0x45, 0x20,
        0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]
}
```

After the signature, the header is:

```text
Int32 1
UInt8 1
Int32 entryCount
Int32 4
UInt8 1
```

Then the entry tables are:

```text
entryCount x Int32 length + CP437 name bytes
UInt8 1
entryCount x Int64 relative payload offset
UInt8 1
entryCount x Int32 payload size
UInt8 1
entryCount x Int32 zero field, always 0
payload bytes concatenated in entry order
```

`CacheBlockEntry`:

```swift
public struct CacheBlockEntry: Equatable {
    public let internalName: String
    public let externalPath: String
    public let relativeOffset: Int64
    public let size: Int32
    public let zero: Int32
}
```

`CacheBlockArchive`:

```swift
public struct CacheBlockArchive {
    public let url: URL?
    public let data: Data
    public let entries: [CacheBlockEntry]
    public let baseOffset: Int
}
```

`CacheBlockReader`:

```swift
public enum CacheBlockReader {
    public static func readArchive(at url: URL) throws -> CacheBlockArchive
    public static func readArchive(data: Data, url: URL?) throws -> CacheBlockArchive
    public static func readPayload(entry: CacheBlockEntry, in archive: CacheBlockArchive) throws -> Data
}
```

The `data:url:` overload is required so `PakVerifier` can validate a cache-block payload that was read from inside a PAK without first writing it to disk.

`CacheBlockReader` owns cache-block length-prefixed CP437 string parsing. Keep that logic out of `BinaryReader` so the generic little-endian reader does not depend on cache-block-specific errors.

`CacheBlockWriter`:

```swift
public enum CacheBlockWriter {
    @discardableResult
    public static func writeArchive(fromDirectory directory: URL, to outputURL: URL, mixed: Bool = false) throws -> Int

    @discardableResult
    public static func writeArchive(fileSources: [CacheBlockFileSource], to outputURL: URL) throws -> Int
}
```

`CacheBlockDirectoryScanner`:

```swift
public struct CacheBlockFileSource: Equatable {
    public let internalName: String
    public let externalPath: String
    public let fileURL: URL
}

public enum CacheBlockDirectoryScanner {
    public static func scan(rootDirectory: URL, mixed: Bool = false) throws -> [CacheBlockFileSource]
}
```

`PakDirectoryScanner` keeps the existing Phase 2 API and adds one overload for mixed cache-block packing:

```swift
public enum PakDirectoryScanner {
    public static func scan(rootDirectory: URL) throws -> [PakFileSource]

    public static func scan(
        rootDirectory: URL,
        excludingTopLevelDirectories excludedDirectories: Set<String>,
        additionalFileSources: [PakFileSource]
    ) throws -> [PakFileSource]
}
```

The overload must validate duplicates after combining scanned entries and additional generated entries. Mixed cache-block packing passes `["[ps]", "[ps_common]", "[strings]"]` as exclusions and injects one generated `PakFileSource(internalName: "initial.cache_block", fileURL: temporaryCacheBlockURL)`.

Path conversion rules:

```text
<ps>:foo.xml -> [ps]/foo.xml
<ps>\ui\foo.xml -> [ps]/ui/foo.xml
[ps]/foo.xml -> <ps>:foo.xml
[ps]/ui/foo.xml -> <ps>\ui\foo.xml
```

Reject:

```text
empty names
rooted filesystem paths
internal names not matching ^<[^>]+>(?:(\\.+\\)|:)[^\\]+$
external names without a top-level [name] directory
external names with empty, ., or .. components
filesystem path components containing literal backslash
duplicate exact internal names
duplicate case-insensitive internal names
non-ASCII names until full CP437 table support is added
```

`CacheBlockError` must include these cases so tests and CLI errors are not forced to borrow PAK writer errors:

```swift
public enum CacheBlockError: Error, CustomStringConvertible, Equatable {
    case invalidHeader
    case invalidMarker(field: String, expected: String, actual: String)
    case invalidEntryCount(Int32)
    case invalidStringLength(Int32)
    case invalidInternalName(String)
    case invalidExternalPath(String)
    case duplicateInternalName(String)
    case duplicateCaseInsensitiveInternalName(String)
    case valueExceedsInt32(field: String, value: UInt64)
    case negativeOffset(entry: String, offset: Int64)
    case negativeSize(entry: String, size: Int32)
    case payloadOutOfBounds(entry: String)
    case rootFileNotAllowed(String)
    case missingInitialCacheBlock
    case outputAlreadyExists(String)
}
```

Pure cache-block packing scans every regular file below the source directory and rejects files directly in the root. Mixed cache-block packing scans only:

```text
[ps]/
[ps_common]/
[strings]/
```

Mixed PAK packing must:

```text
1. Build a temporary initial.cache_block from [ps], [ps_common], and [strings].
2. Ignore any stale root initial.cache_block file in the mixed source directory.
3. Exclude [ps], [ps_common], and [strings] from loose PAK entries.
4. Add the generated initial.cache_block as the PAK entry named initial.cache_block.
5. Preserve existing PAK writer order: pak.load_list first, initial.cache_block second, then existing section order.
```

`PakVerifier.verifyBasic` must continue to require `[media]` and `[ssl_cache]`. It must require either loose `[strings]` PAK entries or a parseable `initial.cache_block` containing at least one cache-block entry whose external path starts with `[strings]/`.

## Implementation Tasks

### Task 1: Cache-Block Binary Primitives

**Files:**
- Modify `Sources/SnowRunnerTool/Pak/BinaryReader.swift`
- Modify `Sources/SnowRunnerTool/Pak/BinaryWriter.swift`
- Create `Tests/SnowRunnerToolTests/CacheBlockReaderTests.swift`

- [ ] **Step 1: Write failing primitive tests**

```swift
func testBinaryReaderReadsSignedCacheBlockIntegers() throws {
    let data = Data([0xFE, 0xFF, 0xFF, 0xFF, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
    var reader = BinaryReader(data: data)

    XCTAssertEqual(try reader.readInt32(), -2)
    XCTAssertEqual(try reader.readInt64(), 0x0102030405060708)
}

func testBinaryWriterWritesSignedCacheBlockIntegers() {
    var writer = BinaryWriter()

    writer.appendInt32(-2)
    writer.appendInt64(0x0102030405060708)
    writer.appendUInt8(1)

    XCTAssertEqual(Array(writer.data), [
        0xFE, 0xFF, 0xFF, 0xFF,
        0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
        0x01
    ])
}

```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockReaderTests
```

Expected: FAIL because `readInt32`, `readInt64`, `appendInt32`, `appendInt64`, and `appendUInt8` do not exist.

- [ ] **Step 3: Add minimal primitive support**

Implement these methods by reusing the existing little-endian byte style:

```swift
public mutating func readInt32() throws -> Int32 {
    Int32(bitPattern: try readUInt32())
}

public mutating func readInt64() throws -> Int64 {
    let bytes = try readBytes(count: 8)
    let value = UInt64(bytes[0])
        | (UInt64(bytes[1]) << 8)
        | (UInt64(bytes[2]) << 16)
        | (UInt64(bytes[3]) << 24)
        | (UInt64(bytes[4]) << 32)
        | (UInt64(bytes[5]) << 40)
        | (UInt64(bytes[6]) << 48)
        | (UInt64(bytes[7]) << 56)
    return Int64(bitPattern: value)
}

public mutating func appendUInt8(_ value: UInt8) {
    data.append(value)
}

public mutating func appendInt32(_ value: Int32) {
    appendUInt32(UInt32(bitPattern: value))
}

public mutating func appendInt64(_ value: Int64) {
    let raw = UInt64(bitPattern: value)
    data.append(UInt8(raw & 0x00000000000000FF))
    data.append(UInt8((raw >> 8) & 0x00000000000000FF))
    data.append(UInt8((raw >> 16) & 0x00000000000000FF))
    data.append(UInt8((raw >> 24) & 0x00000000000000FF))
    data.append(UInt8((raw >> 32) & 0x00000000000000FF))
    data.append(UInt8((raw >> 40) & 0x00000000000000FF))
    data.append(UInt8((raw >> 48) & 0x00000000000000FF))
    data.append(UInt8((raw >> 56) & 0x00000000000000FF))
}

```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockReaderTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/BinaryReader.swift Sources/SnowRunnerTool/Pak/BinaryWriter.swift Tests/SnowRunnerToolTests/CacheBlockReaderTests.swift
git commit -m "feat: add cache-block binary primitives"
```

### Task 2: Cache-Block Path Conversion

**Files:**
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockError.swift`
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockPath.swift`
- Create `Tests/SnowRunnerToolTests/CacheBlockPathTests.swift`

- [ ] **Step 1: Write failing path tests**

```swift
func testInternalNamesMapToExternalPaths() throws {
    XCTAssertEqual(try CacheBlockPath.externalPath(forInternalName: "<ps>:hud.xml"), "[ps]/hud.xml")
    XCTAssertEqual(try CacheBlockPath.externalPath(forInternalName: "<strings>\\ui\\menu.str"), "[strings]/ui/menu.str")
}

func testExternalPathsMapToInternalNames() throws {
    XCTAssertEqual(try CacheBlockPath.internalName(forExternalPath: "[ps]/hud.xml"), "<ps>:hud.xml")
    XCTAssertEqual(try CacheBlockPath.internalName(forExternalPath: "[strings]/ui/menu.str"), "<strings>\\ui\\menu.str")
}

func testRejectsUnsafeCacheBlockNames() {
    XCTAssertThrowsError(try CacheBlockPath.externalPath(forInternalName: "ps:hud.xml"))
    XCTAssertThrowsError(try CacheBlockPath.externalPath(forInternalName: "<ps>\\..\\hud.xml"))
    XCTAssertThrowsError(try CacheBlockPath.internalName(forExternalPath: "/[ps]/hud.xml"))
    XCTAssertThrowsError(try CacheBlockPath.internalName(forExternalPath: "[ps]/../hud.xml"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockPathTests
```

Expected: FAIL because the cache-block path types do not exist.

- [ ] **Step 3: Implement minimal path support**

Implement `CacheBlockError` with the complete enum from `Implementation Contracts`. Implement `CacheBlockPath` using exact string parsing, not regular expressions hidden in tests:

```swift
public enum CacheBlockPath {
    public static func externalPath(forInternalName name: String) throws -> String
    public static func internalName(forExternalPath path: String) throws -> String
    public static func internalName(forFileAt fileURL: URL, rootDirectory: URL) throws -> String
    public static func validateInternalNames(_ names: [String]) throws
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockPathTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CacheBlock/CacheBlockError.swift Sources/SnowRunnerTool/CacheBlock/CacheBlockPath.swift Tests/SnowRunnerToolTests/CacheBlockPathTests.swift
git commit -m "feat: add cache-block path mapping"
```

### Task 3: Cache-Block Reader

**Files:**
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockConstants.swift`
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockEntry.swift`
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockArchive.swift`
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockReader.swift`
- Modify `Tests/SnowRunnerToolTests/CacheBlockReaderTests.swift`
- Modify `Tests/SnowRunnerToolTests/TestFixtures.swift`

- [ ] **Step 1: Write failing reader tests**

```swift
func testReaderParsesSyntheticCacheBlock() throws {
    let file = try temporaryDirectory(named: "cache-reader")
        .appendingPathComponent("synthetic.cache_block")
    try makeSyntheticCacheBlock(entries: [
        ("<ps>:hud.xml", Data("HUD".utf8)),
        ("<strings>\\ui\\menu.str", Data("MENU".utf8))
    ]).write(to: file)

    let archive = try CacheBlockReader.readArchive(at: file)

    XCTAssertEqual(archive.entries.map(\.internalName), ["<ps>:hud.xml", "<strings>\\ui\\menu.str"])
    XCTAssertEqual(archive.entries.map(\.externalPath), ["[ps]/hud.xml", "[strings]/ui/menu.str"])
    XCTAssertEqual(archive.entries.map(\.relativeOffset), [0, 3])
    XCTAssertEqual(archive.entries.map(\.size), [3, 4])
}

func testReaderParsesInitialCacheBlockFromFixturePak() throws {
    let cacheBlock = try TestFixtures.extractInitialCacheBlock(from: TestFixtures.initialPak)
    let archive = try CacheBlockReader.readArchive(at: cacheBlock)

    XCTAssertGreaterThan(archive.entries.count, 0)
    XCTAssertTrue(archive.entries.contains { $0.externalPath.hasPrefix("[ps]/") })
    XCTAssertTrue(archive.entries.contains { $0.externalPath.hasPrefix("[ps_common]/") })
    XCTAssertTrue(archive.entries.allSatisfy { $0.zero == 0 })
}

private func makeSyntheticCacheBlock(entries: [(String, Data)]) throws -> Data {
    var writer = BinaryWriter()
    writer.appendBytes(CacheBlockConstants.signature)
    writer.appendInt32(1)
    writer.appendUInt8(1)
    writer.appendInt32(Int32(entries.count))
    writer.appendInt32(4)
    writer.appendUInt8(1)

    for entry in entries {
        let nameBytes = try CP437.encode(entry.0)
        writer.appendInt32(Int32(nameBytes.count))
        writer.appendBytes(nameBytes)
    }

    writer.appendUInt8(1)

    var relativeOffset: Int64 = 0
    for entry in entries {
        writer.appendInt64(relativeOffset)
        relativeOffset += Int64(entry.1.count)
    }

    writer.appendUInt8(1)

    for entry in entries {
        writer.appendInt32(Int32(entry.1.count))
    }

    writer.appendUInt8(1)

    for _ in entries {
        writer.appendInt32(0)
    }

    for entry in entries {
        writer.appendData(entry.1)
    }

    return writer.data
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockReaderTests
```

Expected: FAIL because `CacheBlockConstants`, `CacheBlockReader`, and `TestFixtures.extractInitialCacheBlock` do not exist.

- [ ] **Step 3: Implement reader and fixture extraction**

`TestFixtures.extractInitialCacheBlock(from:)` should use `PakReader` so the test proves the real PAK path:

```swift
static func extractInitialCacheBlock(from pakURL: URL) throws -> URL {
    let archive = try PakReader.readArchive(at: pakURL)
    guard let entry = archive.entries.first(where: { $0.name == "initial.cache_block" }) else {
        throw CacheBlockError.missingInitialCacheBlock
    }
    let output = try temporaryDirectory(named: "cache-block-fixture")
        .appendingPathComponent("initial.cache_block")
    try PakReader.readUncompressedPayload(entry: entry, in: archive).write(to: output)
    return output
}
```

`CacheBlockReader` must validate every marker, every zero field, and every payload range before returning.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockReaderTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CacheBlock Tests/SnowRunnerToolTests/CacheBlockReaderTests.swift Tests/SnowRunnerToolTests/TestFixtures.swift
git commit -m "feat: read cache-block archives"
```

### Task 4: Cache-Block Unpacker

**Files:**
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockUnpacker.swift`
- Create `Tests/SnowRunnerToolTests/CacheBlockUnpackerTests.swift`

- [ ] **Step 1: Write failing unpacker tests**

```swift
func testUnpackerWritesFixtureEntriesToExternalPaths() throws {
    let cacheBlock = try TestFixtures.extractInitialCacheBlock(from: TestFixtures.initialPak)
    let output = try temporaryDirectory(named: "cache-unpack")

    let count = try CacheBlockUnpacker.unpack(cacheBlockURL: cacheBlock, toDirectory: output)

    XCTAssertGreaterThan(count, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("[ps]").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("[ps_common]").path))
}

func testUnpackedPayloadMatchesReaderForSampleEntries() throws {
    let cacheBlock = try TestFixtures.extractInitialCacheBlock(from: TestFixtures.initialPak)
    let output = try temporaryDirectory(named: "cache-unpack-sample")
    let archive = try CacheBlockReader.readArchive(at: cacheBlock)

    try CacheBlockUnpacker.unpack(cacheBlockURL: cacheBlock, toDirectory: output)

    for entry in archive.entries.prefix(25) {
        let written = try Data(contentsOf: output.appendingPathComponent(entry.externalPath))
        let payload = try CacheBlockReader.readPayload(entry: entry, in: archive)
        XCTAssertEqual(written, payload, entry.internalName)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockUnpackerTests
```

Expected: FAIL because `CacheBlockUnpacker` does not exist.

- [ ] **Step 3: Implement unpacker**

The unpacker must create directories with `withIntermediateDirectories: true` and write files with `.withoutOverwriting` semantics. If a target file already exists, throw a `CacheBlockError.outputAlreadyExists` error instead of silently replacing user edits.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockUnpackerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CacheBlock/CacheBlockUnpacker.swift Tests/SnowRunnerToolTests/CacheBlockUnpackerTests.swift
git commit -m "feat: unpack cache-block files"
```

### Task 5: Cache-Block Writer

**Files:**
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockDirectoryScanner.swift`
- Create `Sources/SnowRunnerTool/CacheBlock/CacheBlockWriter.swift`
- Create `Tests/SnowRunnerToolTests/CacheBlockWriterTests.swift`

- [ ] **Step 1: Write failing writer tests**

```swift
func testWriterCreatesReadableSyntheticCacheBlock() throws {
    let root = try temporaryDirectory(named: "cache-writer-input")
    let output = root.deletingLastPathComponent().appendingPathComponent("written.cache_block")
    try writeFile(root: root, relativePath: "[ps]/hud.xml", data: Data("HUD".utf8))
    try writeFile(root: root, relativePath: "[strings]/ui/menu.str", data: Data("MENU".utf8))

    let count = try CacheBlockWriter.writeArchive(fromDirectory: root, to: output)
    let archive = try CacheBlockReader.readArchive(at: output)

    XCTAssertEqual(count, 2)
    XCTAssertEqual(archive.entries.map(\.internalName), ["<ps>:hud.xml", "<strings>\\ui\\menu.str"])
}

func testNoEditFixtureCacheBlockRoundTripsAllEntriesAndPayloads() throws {
    let source = try TestFixtures.extractInitialCacheBlock(from: TestFixtures.initialPak)
    let unpacked = try temporaryDirectory(named: "cache-roundtrip")
    let rebuilt = unpacked.deletingLastPathComponent().appendingPathComponent("rebuilt.cache_block")

    try CacheBlockUnpacker.unpack(cacheBlockURL: source, toDirectory: unpacked)
    try CacheBlockWriter.writeArchive(fromDirectory: unpacked, to: rebuilt)

    let sourceArchive = try CacheBlockReader.readArchive(at: source)
    let rebuiltArchive = try CacheBlockReader.readArchive(at: rebuilt)
    let sourceByName = Dictionary(uniqueKeysWithValues: sourceArchive.entries.map { ($0.internalName, $0) })
    let rebuiltByName = Dictionary(uniqueKeysWithValues: rebuiltArchive.entries.map { ($0.internalName, $0) })

    XCTAssertEqual(Set(sourceByName.keys), Set(rebuiltByName.keys))
    for name in sourceByName.keys {
        let sourceEntry = try XCTUnwrap(sourceByName[name])
        let rebuiltEntry = try XCTUnwrap(rebuiltByName[name])
        XCTAssertEqual(
            try CacheBlockReader.readPayload(entry: rebuiltEntry, in: rebuiltArchive),
            try CacheBlockReader.readPayload(entry: sourceEntry, in: sourceArchive),
            name
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockWriterTests
```

Expected: FAIL because `CacheBlockWriter` and scanner do not exist.

- [ ] **Step 3: Implement scanner and writer**

`CacheBlockDirectoryScanner.scan(rootDirectory:mixed:)` returns sources sorted by internal name:

```swift
public struct CacheBlockFileSource: Equatable {
    public let internalName: String
    public let externalPath: String
    public let fileURL: URL
}
```

Writer order must be the sorted scanner order. The implementation does not need real seeking: build the header, name table, offset table, size table, and zero table in memory, then append payload data in the same order. Offsets are the cumulative payload byte counts before each file.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CacheBlockWriterTests
```

Expected: PASS. The fixture cache block does not need to rebuild byte-identically because the original entry ordering is not recoverable from the filesystem tree; the required invariant is exact internal-name and payload equivalence.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CacheBlock/CacheBlockDirectoryScanner.swift Sources/SnowRunnerTool/CacheBlock/CacheBlockWriter.swift Tests/SnowRunnerToolTests/CacheBlockWriterTests.swift
git commit -m "feat: write cache-block archives"
```

### Task 6: Cache-Block CLI

**Files:**
- Modify `Sources/SnowRunnerTool/CLI.swift`
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Write failing CLI tests**

```swift
func testCLICacheBlockUnpackAndPackRoundTrip() throws {
    let cacheBlock = try TestFixtures.extractInitialCacheBlock(from: TestFixtures.initialPak)
    let unpacked = try temporaryDirectory(named: "cli-cache-unpack")
    let rebuilt = unpacked.deletingLastPathComponent().appendingPathComponent("cli.cache_block")

    let unpackResult = CLI.run(arguments: ["cache-block", "unpack", cacheBlock.path, unpacked.path])
    XCTAssertEqual(unpackResult.exitCode, 0)
    XCTAssertTrue(unpackResult.stdout.contains("unpacked"))

    let packResult = CLI.run(arguments: ["cache-block", "pack", unpacked.path, rebuilt.path])
    XCTAssertEqual(packResult.exitCode, 0)
    XCTAssertTrue(packResult.stdout.contains("packed"))
    XCTAssertEqual(try Data(contentsOf: rebuilt), try Data(contentsOf: cacheBlock))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLICacheBlockUnpackAndPackRoundTrip
```

Expected: FAIL because `cache-block` is unknown.

- [ ] **Step 3: Add CLI parsing**

Usage must include:

```text
snowrunner-tool cache-block unpack <cache_block> <dir>
snowrunner-tool cache-block pack <dir> <cache_block>
```

Successful output:

```text
unpacked N cache-block entries
packed N cache-block entries
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLICacheBlockUnpackAndPackRoundTrip
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CLI.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "feat: add cache-block cli commands"
```

### Task 7: Mixed Cache-Block PAK Packing

**Files:**
- Modify `Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift`
- Modify `Sources/SnowRunnerTool/Pak/PakWriter.swift`
- Modify `Sources/SnowRunnerTool/Pak/PakWriterError.swift`
- Create `Tests/SnowRunnerToolTests/MixedCacheBlockPakTests.swift`

- [ ] **Step 1: Write failing mixed PAK tests**

```swift
func testMixedCacheBlockPakPacksGeneratedInitialCacheBlock() throws {
    let mixedRoot = try temporaryDirectory(named: "mixed-pak-root")
    let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("mixed.pak")

    try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: mixedRoot)
    try CacheBlockUnpacker.unpack(
        cacheBlockURL: mixedRoot.appendingPathComponent("initial.cache_block"),
        toDirectory: mixedRoot
    )

    try PakWriter.writeArchive(fromDirectory: mixedRoot, to: candidate, mixedCacheBlock: true)

    let archive = try PakReader.readArchive(at: candidate)
    XCTAssertEqual(archive.entries[0].name, "pak.load_list")
    XCTAssertEqual(archive.entries[1].name, "initial.cache_block")
    XCTAssertFalse(archive.entries.contains { $0.name.hasPrefix("[ps]\\") })
    XCTAssertFalse(archive.entries.contains { $0.name.hasPrefix("[ps_common]\\") })
    XCTAssertFalse(archive.entries.contains { $0.name.hasPrefix("[strings]\\") })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter MixedCacheBlockPakTests
```

Expected: FAIL because mixed PAK packing is not implemented.

- [ ] **Step 3: Implement mixed pack path**

Add:

```swift
@discardableResult
public static func writeArchive(fromDirectory directory: URL, to outputURL: URL, mixedCacheBlock: Bool) throws -> Int
```

For `mixedCacheBlock == false`, call the existing implementation. For `true`, create a temporary cache-block file under `FileManager.default.temporaryDirectory`, write it with `CacheBlockWriter.writeArchive(fromDirectory:mixed:true)`, scan the PAK directory while excluding `[ps]`, `[ps_common]`, `[strings]`, ignore a stale root `initial.cache_block`, and inject the temporary file as `initial.cache_block`.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter MixedCacheBlockPakTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift Sources/SnowRunnerTool/Pak/PakWriter.swift Sources/SnowRunnerTool/Pak/PakWriterError.swift Tests/SnowRunnerToolTests/MixedCacheBlockPakTests.swift
git commit -m "feat: pack mixed cache-block pak"
```

### Task 8: Mixed Layout Verifier Support

**Files:**
- Modify `Sources/SnowRunnerTool/Pak/PakVerifier.swift`
- Modify `Tests/SnowRunnerToolTests/MixedCacheBlockPakTests.swift`
- Modify `Tests/SnowRunnerToolTests/PakVerifierFixtureTests.swift`

- [ ] **Step 1: Write failing verifier tests**

```swift
func testMixedCacheBlockPakPassesExistingPakVerifiers() throws {
    let mixedRoot = try temporaryDirectory(named: "mixed-verifier-root")
    let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("mixed-verifier.pak")

    try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: mixedRoot)
    try CacheBlockUnpacker.unpack(
        cacheBlockURL: mixedRoot.appendingPathComponent("initial.cache_block"),
        toDirectory: mixedRoot
    )
    try PakWriter.writeArchive(fromDirectory: mixedRoot, to: candidate, mixedCacheBlock: true)

    let archive = try PakReader.readArchive(at: candidate)
    XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
    XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter MixedCacheBlockPakTests/testMixedCacheBlockPakPassesExistingPakVerifiers
```

Expected: FAIL with `missing-namespace` for `[strings]`.

- [ ] **Step 3: Update verifier**

When loose `[strings]` entries are absent, read the uncompressed `initial.cache_block` payload from the PAK, parse it with `CacheBlockReader.readArchive(data:url:)`, and accept `[strings]` only if at least one parsed cache-block entry has external path prefix `[strings]/`. If parsing fails, report `missing-namespace` with a message that the cache block could not prove `[strings]`.

- [ ] **Step 4: Run verifier tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter MixedCacheBlockPakTests
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakVerifierFixtureTests
```

Expected: PASS. Existing original and repacked PAK verifier behavior must not change.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/PakVerifier.swift Tests/SnowRunnerToolTests/MixedCacheBlockPakTests.swift Tests/SnowRunnerToolTests/PakVerifierFixtureTests.swift
git commit -m "feat: verify mixed cache-block pak layout"
```

### Task 9: Mixed Cache-Block CLI

**Files:**
- Modify `Sources/SnowRunnerTool/CLI.swift`
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Write failing CLI test**

```swift
func testCLIPackMixedCacheBlockWritesVerifiableArchive() throws {
    let mixedRoot = try temporaryDirectory(named: "cli-mixed-root")
    let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("cli-mixed.pak")

    XCTAssertEqual(CLI.run(arguments: ["pak", "unpack", TestFixtures.initialPak.path, mixedRoot.path]).exitCode, 0)
    XCTAssertEqual(CLI.run(arguments: [
        "cache-block", "unpack",
        mixedRoot.appendingPathComponent("initial.cache_block").path,
        mixedRoot.path
    ]).exitCode, 0)

    let packResult = CLI.run(arguments: ["pak", "pack", "--mixed-cache-block", mixedRoot.path, candidate.path])

    XCTAssertEqual(packResult.exitCode, 0)
    XCTAssertTrue(packResult.stdout.contains("packed"))
    XCTAssertEqual(CLI.run(arguments: ["pak", "verify-basic", candidate.path]).exitCode, 0)
    XCTAssertEqual(CLI.run(arguments: ["pak", "verify-snowpak-layout", candidate.path]).exitCode, 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLIPackMixedCacheBlockWritesVerifiableArchive
```

Expected: FAIL because `pak pack --mixed-cache-block` is not parsed.

- [ ] **Step 3: Add CLI option parsing**

Accept only this shape:

```text
snowrunner-tool pak pack --mixed-cache-block <dir> <pak>
```

Keep existing Phase 2 shape unchanged:

```text
snowrunner-tool pak pack <dir> <pak>
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testCLIPackMixedCacheBlockWritesVerifiableArchive
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CLI.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "feat: expose mixed cache-block packing"
```

### Task 10: Full Phase Acceptance

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
PHASE3_DIR="$(mktemp -d /tmp/snowrunner-tools-phase3.XXXXXX)"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak unpack fixtures/initial.pak "$PHASE3_DIR/initial"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block unpack "$PHASE3_DIR/initial/initial.cache_block" "$PHASE3_DIR/cache"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block pack "$PHASE3_DIR/cache" "$PHASE3_DIR/rebuilt.cache_block"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block verify-content-equivalent "$PHASE3_DIR/initial/initial.cache_block" "$PHASE3_DIR/rebuilt.cache_block"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block unpack "$PHASE3_DIR/initial/initial.cache_block" "$PHASE3_DIR/initial"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak pack --mixed-cache-block "$PHASE3_DIR/initial" "$PHASE3_DIR/initial.mixed-cache-block.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-basic "$PHASE3_DIR/initial.mixed-cache-block.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-snowpak-layout "$PHASE3_DIR/initial.mixed-cache-block.pak"
```

Expected:

```text
pak unpack exits 0
cache-block unpack exits 0
cache-block pack exits 0
cache-block verify-content-equivalent exits 0
pak pack --mixed-cache-block exits 0
verify-basic exits 0
verify-snowpak-layout exits 0
```

- [ ] **Step 3: Confirm expected non-goal behavior**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak "$PHASE3_DIR/initial.mixed-cache-block.pak"
```

Expected: FAIL with `content-missing-entry` for moved loose `[strings]` entries and `content-size-mismatch` for `initial.cache_block`. This failure is expected and must not block Phase 3, because mixed cache-block packing moves those strings into a regenerated, larger cache block.

- [ ] **Step 4: Manual game-launch acceptance**

Replace a backed-up game `initial.pak` with `$PHASE3_DIR/initial.mixed-cache-block.pak` and launch the game.

Expected:

```text
The game reaches the main menu with the mixed-cache-block candidate.
```

- [ ] **Step 5: Commit**

```bash
git add Sources Tests docs/phase-3-implementation-plan.md
git commit -m "test: complete phase 3 cache-block acceptance"
```

## Test Strategy

- Unit tests for cache-block binary primitives and marker validation.
- Unit tests for cache-block internal/external path conversion.
- Synthetic cache-block tests for small hand-built archives.
- Fixture tests that parse `initial.cache_block` extracted from `fixtures/initial.pak`.
- No-edit cache-block unpack/pack internal-name and payload-equivalence test.
- CLI tests for `cache-block unpack`, `cache-block pack`, and `pak pack --mixed-cache-block`.
- Mixed PAK tests that prove loose `[ps]`, `[ps_common]`, and `[strings]` entries are excluded and regenerated into `initial.cache_block`.
- Existing PAK verifier tests must keep passing for `fixtures/initial.pak` and `fixtures/initial.repacked.pak`.
- Game-launch test is required because Phase 3 emits a candidate game PAK with a changed cache-block layout.

## Acceptance Criteria

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
```

Must pass.

```bash
PHASE3_DIR="$(mktemp -d /tmp/snowrunner-tools-phase3.XXXXXX)"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak unpack fixtures/initial.pak "$PHASE3_DIR/initial"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block unpack "$PHASE3_DIR/initial/initial.cache_block" "$PHASE3_DIR/cache"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block pack "$PHASE3_DIR/cache" "$PHASE3_DIR/rebuilt.cache_block"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block verify-content-equivalent "$PHASE3_DIR/initial/initial.cache_block" "$PHASE3_DIR/rebuilt.cache_block"
```

Must pass.

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block unpack "$PHASE3_DIR/initial/initial.cache_block" "$PHASE3_DIR/initial"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak pack --mixed-cache-block "$PHASE3_DIR/initial" "$PHASE3_DIR/initial.mixed-cache-block.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-basic "$PHASE3_DIR/initial.mixed-cache-block.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-snowpak-layout "$PHASE3_DIR/initial.mixed-cache-block.pak"
```

Must pass.

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak "$PHASE3_DIR/initial.mixed-cache-block.pak"
```

Must fail only for expected PAK-entry movement caused by mixed cache-block packing: loose `[strings]` entries are missing from the outer PAK, and `initial.cache_block` has a different size because those strings moved into it.

Manual game-launch acceptance must pass with `$PHASE3_DIR/initial.mixed-cache-block.pak`.

## Risks

- Cache-block byte identity depends on entry ordering, and the fixture order is not recoverable from a plain filesystem tree. This phase proves internal-name and payload equivalence, then relies on mixed PAK verifier checks plus game launch for compatibility.
- `[strings]` has two meanings in mixed mode: a loose PAK namespace in Phase 2, and a cache-block source directory in Phase 3. The verifier must prove `[strings]` exists in one of those places instead of blindly requiring loose PAK entries.
- Existing `initial.cache_block` in a mixed root can be stale after users edit unpacked cache-block files. Mixed PAK packing ignores the stale root file and regenerates `initial.cache_block` from source directories.
- CP437 support is still ASCII-only. Current fixtures are ASCII; non-ASCII names must fail clearly rather than setting the ZIP UTF-8 flag or guessing an encoding.
- Cache-block offsets are signed 64-bit in the reference implementation, while sizes are signed 32-bit. Writer tests must reject values outside these ranges before writing invalid files.
- Game compatibility is not proven by parser success alone. Phase 3 emits a candidate PAK, so manual launch remains part of acceptance.

## Stop Rule

Phase 3 is complete only when all automated tests pass, all CLI acceptance commands produce the expected result, the no-edit cache-block roundtrip is content-equivalent by internal name and payload bytes, and the mixed-cache-block candidate launches the game.

Do not start Phase 4 because cache-block parsing "looks close." If no-edit content equivalence or mixed game launch fails, update this phase plan with the actual format finding before continuing.
