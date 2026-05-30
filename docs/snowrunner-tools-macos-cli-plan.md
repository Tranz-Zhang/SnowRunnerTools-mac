# SnowRunner Tools macOS CLI Rewrite Plan

## Goal

Build a new native macOS command-line tool that replaces the useful parts of SnowPakTool, using the fixed Windows SnowRunnerTools source and known-good outputs as references.

The first milestone is not feature parity. The first milestone is:

```text
initial.pak -> unpack -> repack in SnowPakTool-compatible layout -> verify -> game-compatible candidate
```

Only after that should the tool support `cache_block` repacking or `pak.load_list` mutation.

## Guiding Principles

- Do not port everything at once.
- Do not depend on a generic ZIP writer for game-ready PAK output.
- Treat the fixed Windows SnowRunnerTools output as the Phase 2 behavioral reference.
- Treat the original game PAK as the format reference, not as the exact layout the first writer must reproduce.
- Use the game launch as the final acceptance test, not the first check.
- Add a verifier before trusting any repacked PAK.
- Separate "content equivalence" from "layout equivalence". The original game PAK and SnowPakTool repack contain the same files, but they do not have the same order or compression methods.

## Reference Fixtures

Create a fixture folder:

```text
fixtures/
  initial.pak
  initial.repacked.pak
  unpacked/
  reports/
```

Generate the reference files with the fixed Windows SnowRunnerTools build:

```bat
snowpaktool pak unpack initial.pak unpacked
snowpaktool pak pack unpacked initial.repacked.pak
```

Also save header reports:

```bat
snowpaktool pak list --local-header VersionNeeded Flags Compression Time Date CompressedSize UncompressedSize ExtraLength initial.pak > reports/original-local.txt
snowpaktool pak list --local-header VersionNeeded Flags Compression Time Date CompressedSize UncompressedSize ExtraLength initial.repacked.pak > reports/repacked-local.txt
```

Keep both PAK files. The original tells us the official game layout. The fixed repacked file tells us one layout we have verified can boot.

Known fixture facts that must shape the verifier:

- `initial.pak` has the same entry names, CRCs, and uncompressed sizes as `initial.repacked.pak`.
- `initial.pak` does not use SnowPakTool's repack compression policy. It contains many stored entries beyond `pak.load_list`.
- `initial.repacked.pak` stores only `pak.load_list`; every other entry is deflated.
- `initial.pak` and `initial.repacked.pak` do not have the same entry order.
- Therefore, `initial.pak` versus `initial.repacked.pak` is a content-equivalence check, not a strict roundtrip check.

## Implementation Language And Toolchain

Use Swift for a native macOS-only command-line tool.

Reason:

- Swift and Xcode are already available in the current macOS development environment.
- The project is macOS-only forever, so Rust's cross-platform advantage is not needed.
- Swift avoids installing an additional global Rust toolchain and keeps the local development environment simpler.
- The hard requirement is a custom deterministic PAK writer, not a specific language runtime.

Build with Swift Package Manager:

```text
Package.swift
Sources/SnowRunnerTool/
  main.swift
  CLI.swift
  Pak/
    PakArchive.swift
    PakEntry.swift
    PakReader.swift
    PakWriter.swift
    PakVerifier.swift
    ZipHeaders.swift
    PakPath.swift
  CacheBlock/
    ...
  LoadList/
    ...
Tests/SnowRunnerToolTests/
  ...
```

Do not create or maintain a hand-written `.xcodeproj` for the CLI. Xcode may be used by opening `Package.swift`, but Swift Package Manager is the project source of truth.

Use system libraries for low-level primitives:

- zlib for raw deflate/inflate
- zlib CRC32 or a small local CRC32 implementation
- Foundation `FileHandle` / `Data` for file IO

ZIP deflate streams are raw deflate streams, not zlib-wrapped streams. If using zlib, call `deflateInit2` / `inflateInit2` with negative window bits. Apple's Compression framework may be used only if a test proves it emits and accepts raw ZIP-compatible deflate bytes.

Do not use high-level ZIP creation APIs for final PAK output. They can inject unsupported metadata, choose incompatible path encoding, add extra fields, or hide local-header details that the game layout depends on.

## CLI Shape

Expose one executable:

```text
snowrunner-tool
  pak inspect <pak>
  pak unpack <pak> <dir>
  pak pack <dir> <pak>
  pak verify-basic <pak>
  pak verify-content-equivalent <reference.pak> <candidate.pak>
  pak verify-snowpak-layout <pak>
```

Future commands:

```text
snowrunner-tool
  cache-block unpack <file> <dir>
  cache-block pack <dir> <file>
  load-list inspect <pak.load_list>
  load-list create-initial <target> <initial> <shared> <shared_sound>
```

## PAK Core Requirements

Implement a custom ZIP/PAK reader and writer.

The reader must support:

- local headers
- central directory
- EOCD
- stored entries
- raw deflate entries
- CRC32 validation
- CP437 filenames
- SnowRunner internal names with backslash separators

The writer must emit:

- `pak.load_list` first
- `pak.load_list` stored
- other entries deflated
- SnowPakTool-compatible case-insensitive name order after `pak.load_list`
- no extra fields
- no data descriptors
- no ZIP64 for current `initial.pak`
- DOS timestamp `1980-01-01 03:00:00`
- version needed `0x14`
- version made by `0x0314`
- Unix external attributes `0100666 << 16`
- backslash paths

## Filesystem Path Mapping

The PAK internal path separator is `\`. macOS uses `/`.

`pak unpack` must write a normal macOS directory tree:

```text
[media]\classes\trucks\hummer_h2.xml
```

becomes:

```text
out/[media]/classes/trucks/hummer_h2.xml
```

`pak pack` must reverse that mapping and write internal names with backslashes.

The tool must reject ambiguous paths before packing:

- filenames containing literal `\`
- duplicate internal names after converting `/` to `\`
- duplicate internal names under case-insensitive comparison

The fixtures currently contain only ASCII filenames, but the ZIP filename encoding should still be CP437 with no UTF-8 flag, matching SnowPakTool.

Swift filename encoding rule:

- Use an ASCII fast path for current fixtures.
- For future non-ASCII names, use a local CP437 table or CoreFoundation encoding.
- Fail clearly on names that cannot be encoded in CP437.
- Never set the ZIP UTF-8 filename flag.

## Verifier

Implement the verifier before trusting pack output.

`pak verify-basic <pak>` checks:

- readable EOCD
- central directory and local headers agree for every entry
- no ZIP64
- all local and central header general-purpose bit flags are `0`
- no data descriptors
- no extra fields
- no directory entries
- `pak.load_list` exists and is first
- `pak.load_list` is stored
- required namespaces exist: `[media]`, `[strings]`, `[ssl_cache]`
- only stored and deflated entries are present
- all CRCs match decompressed bytes

`pak verify-content-equivalent <reference.pak> <candidate.pak>` checks:

- same entry count
- same names, compared as an unordered set
- same uncompressed sizes
- same CRC32 values

It does not require matching order, compression method, compressed size, offsets, or whole-file hash. This is the correct check for `initial.pak` versus `initial.repacked.pak`.

`pak verify-snowpak-layout <pak>` checks:

- `verify-basic` passes
- `pak.load_list` is entry 0 and stored
- every non-`pak.load_list` entry is deflated
- entry order is `pak.load_list` first, then case-insensitive ordinal sort by internal name
- all local and central headers use DOS timestamp `1980-01-01 03:00:00`
- all local and central header extra-field lengths are zero
- local and central headers use version needed `0x14`
- central headers use version made by `0x0314`
- central headers use Unix external attributes `0100666 << 16`
- no file comments and no archive comment

`pak verify-roundtrip <reference.pak> <candidate.pak>` can be added later as a strict layout comparison. It should be used only when both files are expected to follow the same layout policy. It should not be used for original game PAK versus SnowPakTool repack.

Do not require matching compressed sizes or identical file hash at first. Deflate implementations can produce different valid streams.

Add exact mode later:

```text
pak verify-exact <reference.pak> <candidate.pak>
```

## Phase 1: Inspect And Verify

Build:

```text
pak inspect
pak verify-basic
pak verify-content-equivalent
pak verify-snowpak-layout
```

Success criteria:

- `verify-basic initial.pak` passes.
- `verify-basic initial.repacked.pak` passes.
- `verify-content-equivalent initial.pak initial.repacked.pak` passes.
- `verify-snowpak-layout initial.repacked.pak` passes.
- `verify-snowpak-layout initial.pak` fails only for expected layout-policy differences: order and non-`pak.load_list` stored entries.

## Phase 2: Basic Roundtrip

Build:

```text
pak unpack
pak pack
```

Test:

```bash
snowrunner-tool pak unpack initial.pak out
snowrunner-tool pak pack out candidate.pak
snowrunner-tool pak verify-basic candidate.pak
snowrunner-tool pak verify-content-equivalent initial.pak candidate.pak
snowrunner-tool pak verify-snowpak-layout candidate.pak
```

Success criteria:

- all three verifier commands pass
- candidate has the same names, CRCs, and uncompressed sizes as `initial.pak`
- candidate follows the same layout policy as `initial.repacked.pak`
- candidate size is close to `initial.repacked.pak`, not necessarily close to `initial.pak`
- candidate contains `[strings]`
- game launches with candidate

Optional comparison after Phase 2:

```bash
snowrunner-tool pak verify-content-equivalent initial.repacked.pak candidate.pak
```

This should pass. Exact byte identity is not required because Swift and .NET deflate output may differ.

## Phase 3: Cache Block

Only start this after basic PAK roundtrip succeeds.

Build:

```text
cache-block unpack
cache-block pack
pak pack --mixed-cache-block
```

Success criteria:

- no-edit cache_block unpack/pack roundtrips byte-identically, or all differences are understood.
- mixed-cache-block PAK passes verifier.
- mixed-cache-block PAK follows SnowPakTool layout.
- game launches.

## Phase 4: Load List

Start read-only:

```text
load-list inspect
```

Only after read-only parsing is reliable, add creation support equivalent to SnowPakTool's `load_list create-initial`.

Do not start with ad hoc mutation of one existing `pak.load_list`. The manifest references `initial.pak`, `shared.pak`, and `shared_sound.pak`; correct creation needs the relevant file sets, loader classification, dependency ordering, and phase records.

Before implementing `load-list create-initial`, add later-phase fixtures:

```text
fixtures/
  shared.pak
  shared_sound.pak
```

Success criteria:

- existing `pak.load_list` parses.
- parsed entries match SnowPakTool's `load_list list --compact` output for the fixture.
- `load-list create-initial` can rebuild a manifest from known fixture inputs.
- rebuilt manifest is accepted by `pak pack` and passes verifier.
- adding one controlled file through manifest creation updates the manifest correctly.
- game launches.

## First Implementation Target

Start with:

```text
pak inspect
pak verify-basic
pak verify-content-equivalent
pak verify-snowpak-layout
```

Reason: the verifier gives us a contract before writing the packer and reduces slow game-launch tests.
