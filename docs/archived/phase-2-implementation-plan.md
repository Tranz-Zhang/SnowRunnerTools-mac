# Phase 2 PAK Writing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 2 builds `pak unpack` and `pak pack` so `fixtures/initial.pak` can be unpacked, repacked into SnowPakTool-compatible layout, and verified as content-equivalent to the original.

**Architecture:** Reuse the Phase 1 reader and verifier as the oracle, then add a focused unpacker, directory scanner, raw-deflate compressor, and custom ZIP/PAK writer. The writer emits only the SnowPakTool-compatible layout needed for `initial.pak`: `pak.load_list` stored first, `initial.cache_block` second when present, every other entry deflated, no extra fields, no comments, no data descriptors, fixed DOS timestamp, CP437 names, and backslash internal paths.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation `Data` / `FileHandle` / `FileManager`, zlib for raw deflate and CRC32, XCTest.

---

## Phase Goal

Phase 2 proves native PAK writing by unpacking a known PAK directory tree, packing it into a new PAK, and verifying the candidate with Phase 1 content and layout checks.

## Non-Goals

- No `cache_block` unpacking or packing.
- No `pak.load_list` parsing, mutation, or creation.
- No strict byte-for-byte equality with SnowPakTool output.
- No ZIP64 support.
- No data descriptors.
- No directory entries in the archive.
- No UTF-8 ZIP filename flag.
- No high-level ZIP writer APIs.
- No game-launch acceptance test until the verifier accepts the candidate PAK.
- No hand-managed `.xcodeproj`; Swift Package Manager remains the source of truth.

## Inputs And Fixtures

- `fixtures/initial.pak`: required before implementation starts; original game layout and source content for the end-to-end writer test.
- `fixtures/initial.repacked.pak`: required before implementation starts; SnowPakTool-compatible layout reference for writer policy and verifier expectations.
- A generated temporary unpack directory under the XCTest temporary directory: created during tests by `PakUnpacker`; proves path mapping and unpacked bytes without committing a large `fixtures/unpacked/` tree.
- A generated temporary candidate PAK under the XCTest temporary directory: created during tests by `PakWriter`; proves the writer through the existing reader and verifier.
- Optional manual acceptance directory `fixtures/unpacked/`: not required for automated tests; useful for local inspection only.

Fixture facts this phase depends on:

```text
fixtures/initial.pak and fixtures/initial.repacked.pak:
  same entry count
  same internal names
  same CRC32 values
  same uncompressed sizes
  different entry order and compression policy

fixtures/initial.repacked.pak:
  entry 0 is stored pak.load_list
  entry 1 is deflated initial.cache_block
  every other entry is deflated
  no extra fields
  no file comments
  no archive comment
  DOS timestamp is 1980-01-01 03:00:00
  version needed is 0x0014
  version made by is 0x0314
  external attributes are 0x81B60000
```

## Commands To Deliver

```text
snowrunner-tool pak unpack <pak> <dir>
snowrunner-tool pak pack <dir> <pak>
```

Existing Phase 1 commands remain available and are used as acceptance checks:

```text
snowrunner-tool pak verify-basic <pak>
snowrunner-tool pak verify-content-equivalent <reference.pak> <candidate.pak>
snowrunner-tool pak verify-snowpak-layout <pak>
```

## Code Structure

- Modify `Sources/SnowRunnerTool/CLI.swift`: add `pak unpack` and `pak pack` command parsing, usage text, and error reporting.
- Modify `Sources/SnowRunnerTool/Pak/CP437.swift`: add ASCII encode support for writer filenames and keep explicit non-ASCII failure.
- Create `Sources/SnowRunnerTool/Pak/BinaryWriter.swift`: little-endian append helpers for `UInt16`, `UInt32`, and byte arrays.
- Create `Sources/SnowRunnerTool/Pak/PakPath.swift`: convert internal backslash paths to filesystem slash paths, convert filesystem paths back to internal names, and reject ambiguous names.
- Create `Sources/SnowRunnerTool/Pak/PakDeflater.swift`: raw ZIP-compatible deflate using zlib negative window bits.
- Create `Sources/SnowRunnerTool/Pak/PakUnpacker.swift`: read entries with `PakReader`, create directories, and write uncompressed file payloads.
- Create `Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift`: walk an unpacked directory, validate packability, compute internal names, and return file URLs.
- Create `Sources/SnowRunnerTool/Pak/PakWriterError.swift`: shared errors for pack input validation and ZIP32 overflow checks.
- Create `Sources/SnowRunnerTool/Pak/PakWriter.swift`: write local headers, compressed payloads, central directory records, and EOCD.
- Create `Tests/SnowRunnerToolTests/BinaryWriterTests.swift`: little-endian writer tests.
- Create `Tests/SnowRunnerToolTests/PakPathTests.swift`: path mapping and ambiguity tests.
- Create `Tests/SnowRunnerToolTests/PakDeflaterTests.swift`: raw deflate roundtrip tests against `PakInflater`.
- Modify `Tests/SnowRunnerToolTests/TestFixtures.swift`: shared temporary-directory and file-writing helpers for Phase 2 filesystem tests.
- Create `Tests/SnowRunnerToolTests/PakUnpackerTests.swift`: unpack fixture tests and payload equality checks.
- Create `Tests/SnowRunnerToolTests/PakDirectoryScannerTests.swift`: pack input validation and writer order tests.
- Create `Tests/SnowRunnerToolTests/PakWriterTests.swift`: small synthetic archive and full fixture repack tests.
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`: CLI coverage for `pak unpack` and `pak pack`.

## Implementation Contracts

`CP437` adds writer-side encoding for the current ASCII fixture set:

```swift
public enum CP437 {
    public static func decode(_ bytes: [UInt8]) throws -> String
    public static func encode(_ string: String) throws -> [UInt8]
}
```

`PakPath` owns path conversion and rejects names that would produce ambiguous macOS paths:

```swift
public enum PakPath {
    public static func fileSystemRelativePath(forInternalName name: String) throws -> String
    public static func internalName(forFileAt fileURL: URL, rootDirectory: URL) throws -> String
    public static func validatePackInput(internalNames: [String]) throws
}
```

Required path rules:

```text
pak.load_list -> pak.load_list
initial.cache_block -> initial.cache_block
[media]\classes\trucks\hummer_h2.xml -> [media]/classes/trucks/hummer_h2.xml
```

Reject:

```text
internal names ending in \ or /
internal names containing / because PAK names must use \
internal names containing empty components, . components, or .. components
filesystem path components containing literal backslash
duplicate internal names after / -> \ conversion
duplicate internal names under case-insensitive comparison
non-ASCII names until full CP437 table support is added
```

`PakDirectoryScanner` returns entries in writer order, not filesystem traversal order. The order is based on `fixtures/initial.repacked.pak`, because that file is the verified SnowPakTool-compatible behavioral reference for Phase 2.

```swift
public struct PakFileSource: Equatable {
    public let internalName: String
    public let fileURL: URL
}

public enum PakDirectoryScanner {
    public static func scan(rootDirectory: URL) throws -> [PakFileSource]
}
```

Writer order:

```text
1. pak.load_list
2. initial.cache_block, when present
3. [media]\classes entries, sorted case-insensitively by internal name
4. [media]\_dlc entries, sorted case-insensitively by internal name
5. [media]\_templates entries, sorted case-insensitively by internal name
6. [ssl_cache] entries, sorted case-insensitively by internal name
7. [strings] entries, sorted case-insensitively by internal name
8. any remaining entries, sorted case-insensitively by internal name
```

The order rule is chosen because it matches `fixtures/initial.repacked.pak` and the Phase 1 `verify-snowpak-layout` section-order checks. This is the concrete meaning of SnowPakTool-compatible ordering for Phase 2.

`PakWriterError` lives in `Sources/SnowRunnerTool/Pak/PakWriterError.swift` so `PakDirectoryScanner` and `PakWriter` can share the same pack-time error vocabulary:

```swift
public enum PakWriterError: Error, CustomStringConvertible, Equatable {
    case entryCountExceedsZip32(Int)
    case valueExceedsUInt16(field: String, value: Int)
    case valueExceedsUInt32(field: String, value: UInt64)
    case missingPakLoadList

    public var description: String {
        switch self {
        case let .entryCountExceedsZip32(count):
            return "Archive has too many entries for ZIP32: \(count)"
        case let .valueExceedsUInt16(field, value):
            return "\(field) exceeds UInt16: \(value)"
        case let .valueExceedsUInt32(field, value):
            return "\(field) exceeds UInt32: \(value)"
        case .missingPakLoadList:
            return "Pack input is missing pak.load_list"
        }
    }
}
```

`PakWriter` emits only the Phase 2 layout:

```swift
public enum PakWriter {
    public static func writeArchive(fromDirectory directory: URL, to outputURL: URL) throws -> Int
    public static func writeArchive(fileSources: [PakFileSource], to outputURL: URL) throws -> Int
}
```

`PakUnpacker` returns the number of written files so CLI output and tests can assert the fixture-scale behavior:

```swift
public enum PakUnpacker {
    @discardableResult
    public static func unpack(archiveURL: URL, toDirectory outputDirectory: URL) throws -> Int
}
```

Header constants:

```swift
versionNeeded: UInt16 = 0x0014
versionMadeBy: UInt16 = 0x0314
generalPurposeBitFlag: UInt16 = 0
dosTime: UInt16 = 0x1800
dosDate: UInt16 = 0x0021
externalAttributes: UInt32 = 0x81B60000
localExtraFieldLength: UInt16 = 0
centralExtraFieldLength: UInt16 = 0
centralFileCommentLength: UInt16 = 0
archiveCommentLength: UInt16 = 0
```

Compression policy:

```text
pak.load_list: stored
all other entries: raw deflate
```

Size policy:

```text
Reject archives requiring UInt16 entry counts above 65535.
Reject any file whose compressed size, uncompressed size, data offset, central directory offset, or central directory size exceeds UInt32.max.
```

## Implementation Tasks

### Task 1: Writer Encoding And Little-Endian Output

**Files:**
- Modify `Sources/SnowRunnerTool/Pak/CP437.swift`
- Create `Sources/SnowRunnerTool/Pak/BinaryWriter.swift`
- Create `Tests/SnowRunnerToolTests/BinaryWriterTests.swift`
- Modify `Tests/SnowRunnerToolTests/CP437Tests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that prove ASCII writer encoding and little-endian byte output:

```swift
func testCP437EncodeAcceptsASCII() throws {
    let bytes = try CP437.encode("[media]\\classes\\truck.xml")

    XCTAssertEqual(bytes, Array("[media]\\classes\\truck.xml".utf8))
}

func testCP437EncodeRejectsNonASCII() {
    XCTAssertThrowsError(try CP437.encode("café.xml")) { error in
        XCTAssertTrue(String(describing: error).contains("Unsupported non-ASCII"))
    }
}

func testBinaryWriterAppendsLittleEndianIntegers() {
    var writer = BinaryWriter()

    writer.appendUInt16(0x1234)
    writer.appendUInt32(0x78563412)

    XCTAssertEqual(Array(writer.data), [0x34, 0x12, 0x12, 0x34, 0x56, 0x78])
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter "CP437Tests|BinaryWriterTests"
```

Expected: FAIL because `CP437.encode` and `BinaryWriter` do not exist.

- [ ] **Step 3: Implement encoding and writer helpers**

Add `CP437.encode(_:)`:

```swift
public static func encode(_ string: String) throws -> [UInt8] {
    let bytes = Array(string.utf8)
    for byte in bytes where byte > 0x7F {
        throw CP437Error.nonASCIIByte(byte)
    }
    return bytes
}
```

Add `BinaryWriter`:

```swift
import Foundation

public struct BinaryWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func appendUInt16(_ value: UInt16) {
        data.append(UInt8(value & 0x00FF))
        data.append(UInt8((value >> 8) & 0x00FF))
    }

    public mutating func appendUInt32(_ value: UInt32) {
        data.append(UInt8(value & 0x000000FF))
        data.append(UInt8((value >> 8) & 0x000000FF))
        data.append(UInt8((value >> 16) & 0x000000FF))
        data.append(UInt8((value >> 24) & 0x000000FF))
    }

    public mutating func appendBytes(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    public mutating func appendData(_ payload: Data) {
        data.append(payload)
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run:

```bash
swift test --filter "CP437Tests|BinaryWriterTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/CP437.swift Sources/SnowRunnerTool/Pak/BinaryWriter.swift Tests/SnowRunnerToolTests/CP437Tests.swift Tests/SnowRunnerToolTests/BinaryWriterTests.swift
git commit -m "feat: add pak writer byte encoding helpers"
```

### Task 2: PAK Path Mapping And Pack Input Validation

**Files:**
- Create `Sources/SnowRunnerTool/Pak/PakPath.swift`
- Create `Tests/SnowRunnerToolTests/PakPathTests.swift`

- [ ] **Step 1: Write failing path tests**

```swift
func testInternalNameMapsToFileSystemPath() throws {
    let path = try PakPath.fileSystemRelativePath(forInternalName: "[media]\\classes\\truck.xml")

    XCTAssertEqual(path, "[media]/classes/truck.xml")
}

func testFileSystemPathMapsToInternalName() throws {
    let root = URL(fileURLWithPath: "/tmp/unpacked", isDirectory: true)
    let file = root
        .appendingPathComponent("[media]", isDirectory: true)
        .appendingPathComponent("classes", isDirectory: true)
        .appendingPathComponent("truck.xml")

    let name = try PakPath.internalName(forFileAt: file, rootDirectory: root)

    XCTAssertEqual(name, "[media]\\classes\\truck.xml")
}

func testRejectsLiteralBackslashInFileSystemComponent() {
    let root = URL(fileURLWithPath: "/tmp/unpacked", isDirectory: true)
    let file = root.appendingPathComponent("bad\\name.xml")

    XCTAssertThrowsError(try PakPath.internalName(forFileAt: file, rootDirectory: root))
}

func testRejectsCaseInsensitiveDuplicateNames() {
    XCTAssertThrowsError(try PakPath.validatePackInput(internalNames: [
        "[media]\\classes\\Truck.xml",
        "[media]\\classes\\truck.xml"
    ]))
}

func testRejectsExactDuplicateNames() {
    XCTAssertThrowsError(try PakPath.validatePackInput(internalNames: [
        "[media]\\classes\\truck.xml",
        "[media]\\classes\\truck.xml"
    ]))
}

func testRejectsUnsafeInternalNames() {
    XCTAssertThrowsError(try PakPath.fileSystemRelativePath(forInternalName: "[media]\\..\\evil.xml"))
    XCTAssertThrowsError(try PakPath.fileSystemRelativePath(forInternalName: "/absolute.xml"))
    XCTAssertThrowsError(try PakPath.fileSystemRelativePath(forInternalName: "[media]/classes/truck.xml"))
    XCTAssertThrowsError(try PakPath.fileSystemRelativePath(forInternalName: "[media]\\\\truck.xml"))
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter PakPathTests
```

Expected: FAIL because `PakPath` does not exist.

- [ ] **Step 3: Implement `PakPath`**

Implement these errors and functions:

```swift
public enum PakPathError: Error, CustomStringConvertible, Equatable {
    case emptyName
    case directoryEntry(String)
    case absolutePath(URL)
    case backslashInFileSystemComponent(String)
    case duplicateInternalName(String)
    case duplicateCaseInsensitiveInternalName(String)

    public var description: String {
        switch self {
        case .emptyName:
            return "PAK entry name is empty"
        case let .directoryEntry(name):
            return "PAK entry is a directory: \(name)"
        case let .absolutePath(url):
            return "Path is not inside pack root: \(url.path)"
        case let .backslashInFileSystemComponent(component):
            return "Filesystem path component contains literal backslash: \(component)"
        case let .duplicateInternalName(name):
            return "Duplicate internal PAK name: \(name)"
        case let .duplicateCaseInsensitiveInternalName(name):
            return "Duplicate case-insensitive internal PAK name: \(name)"
        }
    }
}
```

Use `URL.pathComponents` relative to `rootDirectory.standardizedFileURL`, reject `..` escaping, reject literal `\` in every filesystem component, join filesystem components with `\`, call `CP437.encode(_:)` to reject non-ASCII names, and validate all names with exact and lowercased sets.

- [ ] **Step 4: Verify path tests pass**

Run:

```bash
swift test --filter PakPathTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/PakPath.swift Tests/SnowRunnerToolTests/PakPathTests.swift
git commit -m "feat: add pak path mapping validation"
```

### Task 3: Raw Deflate Compression

**Files:**
- Create `Sources/SnowRunnerTool/Pak/PakDeflater.swift`
- Create `Tests/SnowRunnerToolTests/PakDeflaterTests.swift`

- [ ] **Step 1: Write failing raw-deflate tests**

```swift
func testRawDeflateRoundTripThroughExistingInflater() throws {
    let input = Data(("SnowRunner raw deflate payload\n" + String(repeating: "abc123", count: 512)).utf8)

    let compressed = try PakDeflater.deflateRaw(input)
    let inflated = try PakInflater.inflateRawDeflate(compressed, expectedSize: UInt32(input.count))

    XCTAssertEqual(inflated, input)
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter PakDeflaterTests
```

Expected: FAIL because `PakDeflater` does not exist.

- [ ] **Step 3: Implement raw deflate**

Add `PakDeflater.deflateRaw(_:)` using `deflateInit2` with `windowBits: -MAX_WBITS`. Keep compression policy out of `PakDeflater`; `PakWriter` decides which entries are stored or deflated.

- [ ] **Step 4: Verify deflate tests pass**

Run:

```bash
swift test --filter PakDeflaterTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/PakDeflater.swift Tests/SnowRunnerToolTests/PakDeflaterTests.swift
git commit -m "feat: add raw deflate pak compression"
```

### Task 4: PAK Unpacking

**Files:**
- Create `Sources/SnowRunnerTool/Pak/PakUnpacker.swift`
- Create `Tests/SnowRunnerToolTests/PakUnpackerTests.swift`
- Modify `Tests/SnowRunnerToolTests/TestFixtures.swift`
- Modify `Sources/SnowRunnerTool/CLI.swift`
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Add shared filesystem test helpers**

Modify `Tests/SnowRunnerToolTests/TestFixtures.swift`:

```swift
import Foundation

enum TestFixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let initialPak = root.appendingPathComponent("fixtures/initial.pak")
    static let initialRepackedPak = root.appendingPathComponent("fixtures/initial.repacked.pak")
}

func temporaryDirectory(named name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnowRunnerToolTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
    return base
}

func writeFile(root: URL, relativePath: String, data: Data) throws {
    let fileURL = relativePath
        .split(separator: "/")
        .reduce(root) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try data.write(to: fileURL)
}
```

- [ ] **Step 2: Write failing unpacker tests**

```swift
func testUnpackWritesPakLoadListAndNamespaceDirectories() throws {
    let output = try temporaryDirectory(named: "unpack-repacked")

    try PakUnpacker.unpack(archiveURL: TestFixtures.initialRepackedPak, toDirectory: output)

    XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("pak.load_list").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("[media]").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("[strings]").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("[ssl_cache]").path))
}

func testUnpackedPayloadMatchesReaderPayloadForSampleEntries() throws {
    let output = try temporaryDirectory(named: "unpack-sample")
    let archive = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)

    try PakUnpacker.unpack(archiveURL: TestFixtures.initialRepackedPak, toDirectory: output)

    for entry in archive.entries.prefix(25) {
        let relativePath = try PakPath.fileSystemRelativePath(forInternalName: entry.name)
        let fileData = try Data(contentsOf: output.appendingPathComponent(relativePath))
        let readerData = try PakReader.readUncompressedPayload(entry: entry, in: archive)
        XCTAssertEqual(fileData, readerData, entry.name)
    }
}

func testCLIUnpackReturnsPass() throws {
    let output = try temporaryDirectory(named: "cli-unpack")

    let result = CLI.run(arguments: ["pak", "unpack", TestFixtures.initialRepackedPak.path, output.path])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains("unpacked 10308 entries"))
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test --filter "PakUnpackerTests|CLITests"
```

Expected: FAIL because `PakUnpacker` and CLI command dispatch do not exist.

- [ ] **Step 4: Implement unpacking**

`PakUnpacker.unpack(archiveURL:toDirectory:)` must:

```text
read the archive with PakReader
create the output directory if needed
for each entry, convert the internal name through PakPath.fileSystemRelativePath
create parent directories
write PakReader.readUncompressedPayload(entry:in:) bytes atomically to disk
fail if an entry maps outside the destination directory
```

Update CLI usage to include:

```text
pak unpack <pak> <dir>
pak pack <dir> <pak>
```

Add CLI handling:

```swift
case "unpack":
    guard arguments.count == 3 else {
        return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool pak unpack <pak> <dir>\n")
    }
    let count = try PakUnpacker.unpack(
        archiveURL: URL(fileURLWithPath: arguments[1]),
        toDirectory: URL(fileURLWithPath: arguments[2], isDirectory: true)
    )
    return CLIResult(exitCode: 0, stdout: "unpacked \(count) entries\n", stderr: "")
```

- [ ] **Step 5: Verify unpack tests pass**

Run:

```bash
swift test --filter "PakUnpackerTests|CLITests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/PakUnpacker.swift Sources/SnowRunnerTool/CLI.swift Tests/SnowRunnerToolTests/TestFixtures.swift Tests/SnowRunnerToolTests/PakUnpackerTests.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "feat: add pak unpack command"
```

### Task 5: Directory Scanner And Writer Order

**Files:**
- Create `Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift`
- Create `Sources/SnowRunnerTool/Pak/PakWriterError.swift`
- Create `Tests/SnowRunnerToolTests/PakDirectoryScannerTests.swift`

- [ ] **Step 1: Write failing scanner tests**

```swift
func testScannerReturnsSnowPakWriterOrder() throws {
    let root = try temporaryDirectory(named: "scan-order")
    try Data("load\n".utf8).write(to: root.appendingPathComponent("pak.load_list"))
    try Data("cache\n".utf8).write(to: root.appendingPathComponent("initial.cache_block"))
    try writeFile(root: root, relativePath: "[strings]/strings_english.str", data: Data("strings".utf8))
    try writeFile(root: root, relativePath: "[media]/_dlc/us_01/file.xml", data: Data("<dlc/>".utf8))
    try writeFile(root: root, relativePath: "[media]/classes/truck.xml", data: Data("<truck/>".utf8))

    let sources = try PakDirectoryScanner.scan(rootDirectory: root)

    XCTAssertEqual(sources.map(\.internalName), [
        "pak.load_list",
        "initial.cache_block",
        "[media]\\classes\\truck.xml",
        "[media]\\_dlc\\us_01\\file.xml",
        "[strings]\\strings_english.str"
    ])
}

func testScannerRequiresPakLoadList() throws {
    let root = try temporaryDirectory(named: "scan-missing-load-list")
    try writeFile(root: root, relativePath: "[media]/classes/truck.xml", data: Data())

    XCTAssertThrowsError(try PakDirectoryScanner.scan(rootDirectory: root)) { error in
        XCTAssertTrue(String(describing: error).contains("pak.load_list"))
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter PakDirectoryScannerTests
```

Expected: FAIL because `PakDirectoryScanner` does not exist.

- [ ] **Step 3: Implement scanner**

Create `Sources/SnowRunnerTool/Pak/PakWriterError.swift` using the `PakWriterError` definition from the Implementation Contracts section.

Use `FileManager.enumerator(at:includingPropertiesForKeys:options:)`, include regular files only, compute internal names with `PakPath.internalName`, validate duplicate rules with `PakPath.validatePackInput`, throw `PakWriterError.missingPakLoadList` when `pak.load_list` is absent, and return sorted sources:

```swift
private static func writerSortKey(_ name: String) -> (Int, String) {
    if name == "pak.load_list" {
        return (0, "")
    }
    if name == "initial.cache_block" {
        return (1, "")
    }
    if name.hasPrefix("[media]\\classes") {
        return (2, name.lowercased())
    }
    if name.hasPrefix("[media]\\_dlc") {
        return (3, name.lowercased())
    }
    if name.hasPrefix("[media]\\_templates") {
        return (4, name.lowercased())
    }
    if name.hasPrefix("[ssl_cache]") {
        return (5, name.lowercased())
    }
    if name.hasPrefix("[strings]") {
        return (6, name.lowercased())
    }
    return (7, name.lowercased())
}
```

Use a comparator that breaks lowercased ties with the original name so the order is deterministic even when names differ only by case. The duplicate validator still rejects case-insensitive duplicates before sorting.

- [ ] **Step 4: Verify scanner tests pass**

Run:

```bash
swift test --filter PakDirectoryScannerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift Sources/SnowRunnerTool/Pak/PakWriterError.swift Tests/SnowRunnerToolTests/PakDirectoryScannerTests.swift
git commit -m "feat: scan pak input directories"
```

### Task 6: Custom PAK Writer

**Files:**
- Create `Sources/SnowRunnerTool/Pak/PakWriter.swift`
- Create `Tests/SnowRunnerToolTests/PakWriterTests.swift`

- [ ] **Step 1: Write failing synthetic archive tests**

```swift
func testWriterCreatesReadableSnowPakLayoutArchive() throws {
    let root = try temporaryDirectory(named: "writer-small-input")
    let output = root.deletingLastPathComponent().appendingPathComponent("writer-small-output.pak")
    try Data("load\n".utf8).write(to: root.appendingPathComponent("pak.load_list"))
    try Data("cache\n".utf8).write(to: root.appendingPathComponent("initial.cache_block"))
    try writeFile(root: root, relativePath: "[media]/classes/truck.xml", data: Data("<truck/>".utf8))
    try writeFile(root: root, relativePath: "[strings]/strings_english.str", data: Data("English".utf8))
    try writeFile(root: root, relativePath: "[ssl_cache]/initial_pak", data: Data("ssl".utf8))

    try PakWriter.writeArchive(fromDirectory: root, to: output)

    let archive = try PakReader.readArchive(at: output)
    XCTAssertEqual(archive.entries.map(\.name), [
        "pak.load_list",
        "initial.cache_block",
        "[media]\\classes\\truck.xml",
        "[ssl_cache]\\initial_pak",
        "[strings]\\strings_english.str"
    ])
    XCTAssertEqual(archive.entries.first?.compressionMethod, .stored)
    XCTAssertTrue(archive.entries.dropFirst().allSatisfy { $0.compressionMethod == .deflated })
    XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
    XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter PakWriterTests
```

Expected: FAIL because `PakWriter` does not exist.

- [ ] **Step 3: Implement local header and payload writing**

For each `PakFileSource`:

```text
read uncompressed bytes
compute CRC32 over uncompressed bytes with zlib crc32
choose .stored for pak.load_list, .deflated for every other entry
compress deflated entries with PakDeflater.deflateRaw
record local header offset
write local file header
write CP437 filename bytes
write payload bytes
```

Local header layout:

```text
0x04034B50 signature
0x0014 version needed
0x0000 general-purpose bit flag
compression method
0x1800 DOS time
0x0021 DOS date
crc32
compressed size
uncompressed size
filename length
0 extra-field length
filename bytes
payload bytes
```

- [ ] **Step 4: Implement central directory and EOCD writing**

After payloads, write one central directory record per entry in the same order:

```text
0x02014B50 signature
0x0314 version made by
0x0014 version needed
0x0000 general-purpose bit flag
compression method
0x1800 DOS time
0x0021 DOS date
crc32
compressed size
uncompressed size
filename length
0 extra-field length
0 file-comment length
0 disk number start
0 internal file attributes
0x81B60000 external file attributes
local header offset
filename bytes
```

Write EOCD:

```text
0x06054B50 signature
0 disk number
0 central directory start disk
entry count on disk
total entry count
central directory size
central directory offset
0 archive comment length
```

Before writing each UInt16 or UInt32 field, validate the value fits. Throw a descriptive `PakWriterError` when the archive would require ZIP64.

- [ ] **Step 5: Verify synthetic writer test passes**

Run:

```bash
swift test --filter PakWriterTests.testWriterCreatesReadableSnowPakLayoutArchive
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnowRunnerTool/Pak/PakWriter.swift Tests/SnowRunnerToolTests/PakWriterTests.swift
git commit -m "feat: write custom snowpak archives"
```

### Task 7: Full Fixture Repack And CLI Pack

**Files:**
- Modify `Sources/SnowRunnerTool/CLI.swift`
- Modify `Tests/SnowRunnerToolTests/PakWriterTests.swift`
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Write failing full fixture writer test**

```swift
func testWriterRepackedInitialPakIsContentEquivalentAndSnowPakLayout() throws {
    let unpacked = try temporaryDirectory(named: "initial-unpacked")
    let candidate = unpacked.deletingLastPathComponent().appendingPathComponent("initial.candidate.pak")

    try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: unpacked)
    try PakWriter.writeArchive(fromDirectory: unpacked, to: candidate)

    let original = try PakReader.readArchive(at: TestFixtures.initialPak)
    let written = try PakReader.readArchive(at: candidate)

    XCTAssertTrue(try PakVerifier.verifyBasic(written).isEmpty)
    XCTAssertTrue(try PakVerifier.verifyContentEquivalent(reference: original, candidate: written).isEmpty)
    XCTAssertTrue(try PakVerifier.verifySnowPakLayout(written).isEmpty)
}
```

- [ ] **Step 2: Write failing CLI pack test**

```swift
func testCLIPackWritesVerifiableArchive() throws {
    let unpacked = try temporaryDirectory(named: "cli-pack-input")
    let candidate = unpacked.deletingLastPathComponent().appendingPathComponent("cli-pack-output.pak")

    XCTAssertEqual(CLI.run(arguments: ["pak", "unpack", TestFixtures.initialPak.path, unpacked.path]).exitCode, 0)
    let packResult = CLI.run(arguments: ["pak", "pack", unpacked.path, candidate.path])

    XCTAssertEqual(packResult.exitCode, 0)
    XCTAssertTrue(packResult.stdout.contains("packed 10308 entries"))
    XCTAssertEqual(CLI.run(arguments: ["pak", "verify-content-equivalent", TestFixtures.initialPak.path, candidate.path]).exitCode, 0)
    XCTAssertEqual(CLI.run(arguments: ["pak", "verify-snowpak-layout", candidate.path]).exitCode, 0)
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test --filter "PakWriterTests.testWriterRepackedInitialPakIsContentEquivalentAndSnowPakLayout|CLITests.testCLIPackWritesVerifiableArchive"
```

Expected: FAIL because CLI `pak pack` does not exist or the writer has fixture-scale bugs.

- [ ] **Step 4: Implement CLI pack**

Add CLI handling:

```swift
case "pack":
    guard arguments.count == 3 else {
        return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool pak pack <dir> <pak>\n")
    }
    let sources = try PakWriter.writeArchive(
        fromDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true),
        to: URL(fileURLWithPath: arguments[2])
    )
    return CLIResult(exitCode: 0, stdout: "packed \(sources) entries\n", stderr: "")
```

Make `PakWriter.writeArchive(fromDirectory:to:)` return the number of written entries so CLI output can be tested directly.

- [ ] **Step 5: Verify full fixture and CLI tests pass**

Run:

```bash
swift test --filter "PakWriterTests|CLITests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnowRunnerTool/CLI.swift Sources/SnowRunnerTool/Pak/PakWriter.swift Tests/SnowRunnerToolTests/PakWriterTests.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "feat: add pak pack command"
```

### Task 8: Phase 2 Acceptance Run

**Files:**
- No code files unless acceptance exposes a defect.

- [ ] **Step 1: Run all tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Run manual acceptance commands**

Use fresh temporary paths that do not already exist. The example below uses fixed names for readability; if either path exists, choose new names instead of deleting unrelated contents.

Run:

```bash
swift run snowrunner-tool pak verify-basic fixtures/initial.pak
swift run snowrunner-tool pak verify-basic fixtures/initial.repacked.pak
swift run snowrunner-tool pak unpack fixtures/initial.pak /tmp/snowrunner-phase2-unpacked-example
swift run snowrunner-tool pak pack /tmp/snowrunner-phase2-unpacked-example /tmp/snowrunner-phase2-candidate-example.pak
swift run snowrunner-tool pak verify-basic /tmp/snowrunner-phase2-candidate-example.pak
swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak /tmp/snowrunner-phase2-candidate-example.pak
swift run snowrunner-tool pak verify-snowpak-layout /tmp/snowrunner-phase2-candidate-example.pak
```

Expected:

```text
verify-basic fixtures/initial.pak: PASS
verify-basic fixtures/initial.repacked.pak: PASS
unpack: exits 0 and reports 10308 entries
pack: exits 0 and reports 10308 entries
verify-basic candidate: PASS
verify-content-equivalent original versus candidate: PASS
verify-snowpak-layout candidate: PASS
```

- [ ] **Step 3: Confirm original game PAK still fails SnowPak layout only for expected reasons**

Run:

```bash
swift run snowrunner-tool pak verify-snowpak-layout fixtures/initial.pak
```

Expected: FAIL only with known Phase 1 layout-policy issue codes:

```text
entry-order
non-load-list-stored-entry
invalid-timestamp
extra-field
version-made-by
external-attributes
```

- [ ] **Step 4: Commit acceptance fixes if any were needed**

If code changed during acceptance:

```bash
git add Sources Tests
git commit -m "fix: satisfy phase 2 pak writer acceptance"
```

If no code changed, do not create an empty commit.

## Test Strategy

- Unit tests for `BinaryWriter`, `CP437.encode`, `PakPath`, and `PakDeflater`.
- Negative tests for non-ASCII names, literal backslash filesystem components, missing `pak.load_list`, duplicate exact internal names, and duplicate case-insensitive internal names.
- Fixture tests for unpacking `fixtures/initial.repacked.pak` and comparing written files against `PakReader.readUncompressedPayload`.
- Writer tests for a small synthetic archive that exercises required namespaces without requiring the large fixture.
- Full fixture test for `fixtures/initial.pak -> unpack temp dir -> pack candidate -> verify`.
- CLI tests for `pak unpack` and `pak pack` exit codes and important output.
- No game-launch test in Phase 2; game launch belongs after verifier-backed candidate generation succeeds.

## Acceptance Criteria

All of these commands must pass:

```bash
swift test
swift run snowrunner-tool pak verify-basic fixtures/initial.pak
swift run snowrunner-tool pak verify-basic fixtures/initial.repacked.pak
swift run snowrunner-tool pak unpack fixtures/initial.pak /tmp/snowrunner-phase2-unpacked-example
swift run snowrunner-tool pak pack /tmp/snowrunner-phase2-unpacked-example /tmp/snowrunner-phase2-candidate-example.pak
swift run snowrunner-tool pak verify-basic /tmp/snowrunner-phase2-candidate-example.pak
swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak /tmp/snowrunner-phase2-candidate-example.pak
swift run snowrunner-tool pak verify-snowpak-layout /tmp/snowrunner-phase2-candidate-example.pak
```

This command must fail only for known original-layout policy differences:

```bash
swift run snowrunner-tool pak verify-snowpak-layout fixtures/initial.pak
```

Allowed issue codes for that failure:

```text
entry-order
non-load-list-stored-entry
invalid-timestamp
extra-field
version-made-by
external-attributes
```

Phase 2 is not complete if the candidate PAK only passes `verify-content-equivalent`; it must also pass `verify-snowpak-layout`.

## Risks

- Raw deflate compatibility: contained by roundtripping through the existing raw inflater and validating fixture CRCs after writing.
- Writer metadata drift: contained by `verify-snowpak-layout`, which checks timestamps, versions, attributes, comments, extra fields, methods, and order.
- Path ambiguity on macOS: contained by explicit duplicate and literal-backslash validation before writing.
- Filename encoding: current fixtures are ASCII; Phase 2 implements ASCII CP437 encode and fails clearly on non-ASCII names instead of setting the UTF-8 ZIP flag.
- ZIP64 overflow: contained by explicit UInt16 and UInt32 fit checks before header emission.
- Fixture-scale performance: contained by full `initial.pak` repack tests; optimize only if the acceptance commands are too slow to use regularly.

## Stop Rule

Phase 2 is complete only when every acceptance command passes and the generated candidate PAK passes both content equivalence and SnowPak layout verification.

If acceptance exposes a format misunderstanding, update this plan before continuing implementation. Do not start Phase 3 until Phase 2 acceptance is clean.
