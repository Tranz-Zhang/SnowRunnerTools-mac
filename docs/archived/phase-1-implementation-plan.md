# Phase 1 Inspect And Verify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 1 builds read-only PAK inspection and verification for `initial.pak` and `initial.repacked.pak`; it does not write PAK files.

**Architecture:** Build a Swift Package Manager CLI with a small manual command parser and a focused PAK module. The PAK module reads local headers, EOCD, central directory records, validates raw deflate payloads with zlib, computes CRC32, and reports verifier failures without mutating archives.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation `Data` / `FileHandle`, zlib for raw inflate and CRC32, XCTest.

---

## Phase Goal

Phase 1 builds read-only PAK inspection and verification; it proves the tool can parse the known PAK fixtures and classify original game layout versus SnowPakTool repack layout.

## Non-Goals

- No `pak pack`.
- No PAK writing of any kind.
- No unpacking files to a directory.
- No `cache_block` unpacking or packing.
- No `pak.load_list` parsing beyond treating it as the first ZIP entry.
- No `pak.load_list` mutation or creation.
- No game-launch acceptance test because Phase 1 emits no candidate PAK.
- No hand-managed `.xcodeproj`; use Swift Package Manager only.

## Inputs And Fixtures

- `fixtures/initial.pak`: original game layout; first entry is stored `pak.load_list`; contains many additional stored entries; should pass `verify-basic`; should fail `verify-snowpak-layout` only for expected layout-policy differences.
- `fixtures/initial.repacked.pak`: SnowPakTool-compatible layout; first entry is stored `pak.load_list`; every other entry is deflated; should pass all Phase 1 verifier commands.

Expected fixture facts:

```text
initial.pak:
  entries: 10308
  stored entries: 8325
  deflated entries: 1983
  first entry: pak.load_list, stored
  initial.cache_block position: 10294
  writer-policy outliers: two deflated entries have 36-byte NTFS extra fields, 2026 DOS timestamps, central version made by 0x001F, and external attributes 0x20

initial.repacked.pak:
  entries: 10308
  stored entries: 1
  deflated entries: 10307
  first entry: pak.load_list, stored
  initial.cache_block position: 1
```

## Commands To Deliver

```text
snowrunner-tool pak inspect <pak>
snowrunner-tool pak verify-basic <pak>
snowrunner-tool pak verify-content-equivalent <reference.pak> <candidate.pak>
snowrunner-tool pak verify-snowpak-layout <pak>
```

Do not implement future commands in this phase.

## Code Structure

- Create `Package.swift`: Swift Package Manager manifest for one library target, one executable target, and one test target.
- Create `Sources/SnowRunnerTool/CLI.swift`: manual command parsing and dispatch for Phase 1 commands.
- Create `Sources/snowrunner-tool/main.swift`: executable process entry point that calls `CLI.run(arguments:)`.
- Create `Sources/SnowRunnerTool/Pak/BinaryReader.swift`: bounds-checked little-endian reads from `Data`.
- Create `Sources/SnowRunnerTool/Pak/ZipHeaders.swift`: ZIP signatures, compression methods, local header, central directory header, and EOCD models.
- Create `Sources/SnowRunnerTool/Pak/CP437.swift`: ASCII fast path for fixture filenames and explicit failure for unsupported non-ASCII bytes.
- Create `Sources/SnowRunnerTool/Pak/PakEntry.swift`: normalized entry metadata from local and central headers.
- Create `Sources/SnowRunnerTool/Pak/PakArchive.swift`: in-memory read-only archive model.
- Create `Sources/SnowRunnerTool/Pak/PakReader.swift`: EOCD discovery, central directory parsing, local header scanning, and metadata consistency checks.
- Create `Sources/SnowRunnerTool/Pak/PakInflater.swift`: raw deflate inflate helper using zlib negative window bits.
- Create `Sources/SnowRunnerTool/Pak/PakVerifier.swift`: `verify-basic`, `verify-content-equivalent`, and `verify-snowpak-layout` checks.
- Create `Sources/SnowRunnerTool/Pak/VerifierIssue.swift`: structured issue severity, code, and message.
- Create `Tests/SnowRunnerToolTests/TestFixtures.swift`: fixture paths and skip helpers.
- Create `Tests/SnowRunnerToolTests/BinaryReaderTests.swift`: little-endian and bounds tests.
- Create `Tests/SnowRunnerToolTests/CP437Tests.swift`: ASCII decode and non-ASCII rejection tests.
- Create `Tests/SnowRunnerToolTests/PakReaderFixtureTests.swift`: fixture parser tests.
- Create `Tests/SnowRunnerToolTests/PakVerifierFixtureTests.swift`: verifier behavior tests against both fixtures.
- Create `Tests/SnowRunnerToolTests/CLITests.swift`: command parser tests using direct `CLI.run(arguments:)` calls.

## Implementation Contracts

These contracts remove ambiguity before coding starts.

`PakEntry` must carry the metadata needed by both parser checks and verifier rules:

```swift
public struct PakEntry: Equatable {
    public let name: String
    public let compressionMethod: ZipCompressionMethod
    public let generalPurposeBitFlag: UInt16
    public let crc32: UInt32
    public let compressedSize: UInt32
    public let uncompressedSize: UInt32
    public let versionNeeded: UInt16
    public let dosTime: UInt16
    public let dosDate: UInt16
    public let localHeaderOffset: UInt32
    public let dataOffset: Int
    public let localExtraFieldLength: UInt16
    public let centralVersionMadeBy: UInt16?
    public let centralExtraFieldLength: UInt16?
    public let centralFileCommentLength: UInt16?
    public let centralExternalAttributes: UInt32?
}
```

`PakArchive` must retain enough archive-level state for CLI output and verifier checks:

```swift
public struct PakArchive {
    public let url: URL
    public let data: Data
    public let entries: [PakEntry]       // central directory order
    public let localEntries: [PakEntry]  // local header order
    public let centralDirectoryOffset: UInt32
    public let centralDirectorySize: UInt32
    public let archiveCommentLength: UInt16
    public let isZip64: Bool
}
```

`VerifierIssue` must be stable enough for tests and CLI output:

```swift
public struct VerifierIssue: Equatable {
    public enum Severity: String {
        case error
        case warning
    }

    public let severity: Severity
    public let code: String
    public let message: String
}
```

Verifier issue codes introduced in Phase 1:

```text
archive-comment
central-local-mismatch
content-crc-mismatch
content-data-mismatch
content-missing-entry
content-size-mismatch
crc-mismatch
data-descriptor
directory-entry
entry-order
external-attributes
extra-field
file-comment
invalid-method
invalid-timestamp
missing-namespace
non-load-list-stored-entry
pak-load-list
unsupported-flag
version-made-by
version-needed
zip64
```

`verifyContentEquivalent(reference:candidate:)` means exact uncompressed content equivalence by internal path. It must ignore compression method, compressed size, local offsets, central directory offsets, and entry order. It must report issues when names differ, uncompressed sizes differ, CRCs differ, or decompressed bytes differ.

SnowPakTool-compatible layout in this phase is defined from `fixtures/initial.repacked.pak`, not from generic ZIP sort order:

- `pak.load_list` is entry `0` and is stored.
- `initial.cache_block` is entry `1` and is deflated.
- Every other entry is deflated.
- Known top-level sections appear in this order when present: `[media]\classes`, `[media]\_dlc`, `[media]\_templates`, `[ssl_cache]`, `[strings]`.
- `verify-snowpak-layout fixtures/initial.pak` must report `entry-order` because `initial.cache_block` appears at position `10294` instead of position `1`; it must also report `non-load-list-stored-entry` for the additional stored entries. It may additionally report `invalid-timestamp`, `extra-field`, `version-made-by`, and `external-attributes` for the two known writer-policy outlier entries.

## Implementation Tasks

### Task 1: Swift Package Skeleton

**Files:**
- Create `Package.swift`
- Create `Sources/SnowRunnerTool/CLI.swift`
- Create `Sources/snowrunner-tool/main.swift`
- Create `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Write the failing CLI smoke tests**

```swift
import Foundation
import XCTest
@testable import SnowRunnerTool

final class CLITests: XCTestCase {
    func testNoArgumentsPrintsUsageAndFails() {
        let result = CLI.run(arguments: [])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool"))
    }

    func testUnknownCommandFails() {
        let result = CLI.run(arguments: ["unknown"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Unknown command"))
    }
}
```

- [ ] **Step 2: Run the test and verify it fails because the package does not exist yet**

Run:

```bash
swift test
```

Expected: FAIL with missing `Package.swift` or missing `CLI`.

- [ ] **Step 3: Create the minimal package and CLI shell**

Create `Package.swift` with one library target, one executable target, and one test target. Link zlib now so later raw inflate and CRC work without package churn.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnowRunnerTool",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "snowrunner-tool", targets: ["snowrunner-tool"]),
        .library(name: "SnowRunnerTool", targets: ["SnowRunnerTool"])
    ],
    targets: [
        .target(
            name: "SnowRunnerTool",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .executableTarget(
            name: "snowrunner-tool",
            dependencies: ["SnowRunnerTool"]
        ),
        .testTarget(
            name: "SnowRunnerToolTests",
            dependencies: ["SnowRunnerTool"]
        )
    ]
)
```

Create `Sources/SnowRunnerTool/CLI.swift`:

```swift
public struct CLIResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum CLI {
    public static func run(arguments: [String]) -> CLIResult {
        guard !arguments.isEmpty else {
            return CLIResult(exitCode: 2, stdout: "", stderr: usage())
        }

        guard arguments.first == "pak" else {
            return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown command: \(arguments[0])\n\n\(usage())")
        }

        return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown pak command\n\n\(usage())")
    }

    private static func usage() -> String {
        """
        Usage: snowrunner-tool pak <command> [arguments]

        Commands:
          pak inspect <pak>
          pak verify-basic <pak>
          pak verify-content-equivalent <reference.pak> <candidate.pak>
          pak verify-snowpak-layout <pak>
        """
    }
}
```

Create `Sources/snowrunner-tool/main.swift`:

```swift
import Foundation
import SnowRunnerTool

let result = CLI.run(arguments: Array(CommandLine.arguments.dropFirst()))

if !result.stdout.isEmpty {
    print(result.stdout, terminator: result.stdout.hasSuffix("\n") ? "" : "\n")
}

if !result.stderr.isEmpty {
    fputs(result.stderr.hasSuffix("\n") ? result.stderr : result.stderr + "\n", stderr)
}

exit(result.exitCode)
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

If the workspace is a git repository:

```bash
git add Package.swift Sources Tests
git commit -m "phase1: scaffold Swift CLI package"
```

If the workspace is not a git repository, record this as the Task 1 checkpoint in the implementation notes.

### Task 2: Binary Reader And ZIP Header Models

**Files:**
- Create `Sources/SnowRunnerTool/Pak/BinaryReader.swift`
- Create `Sources/SnowRunnerTool/Pak/ZipHeaders.swift`
- Create `Tests/SnowRunnerToolTests/BinaryReaderTests.swift`

- [ ] **Step 1: Write failing little-endian and bounds tests**

```swift
import Foundation
import XCTest
@testable import SnowRunnerTool

final class BinaryReaderTests: XCTestCase {
    func testReadsLittleEndianIntegers() throws {
        let data = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])
        var reader = BinaryReader(data: data)

        XCTAssertEqual(try reader.readUInt32(), 0x04034B50)
        XCTAssertEqual(try reader.readUInt16(), 0x0014)
        XCTAssertEqual(reader.offset, 6)
    }

    func testThrowsAtEndOfData() {
        var reader = BinaryReader(data: Data([0x01]))

        XCTAssertThrowsError(try reader.readUInt16()) { error in
            XCTAssertTrue(String(describing: error).contains("Unexpected end of data"))
        }
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail because `BinaryReader` is missing**

Run:

```bash
swift test --filter BinaryReaderTests
```

Expected: FAIL with missing `BinaryReader`.

- [ ] **Step 3: Implement `BinaryReader` and ZIP constants**

`BinaryReader` must support `readUInt16`, `readUInt32`, `readBytes(count:)`, `seek(to:)`, and `skip(_:)`, all bounds-checked.

`ZipHeaders.swift` must define:

```swift
enum ZipSignature {
    static let localFileHeader: UInt32 = 0x04034B50
    static let centralDirectoryHeader: UInt32 = 0x02014B50
    static let endOfCentralDirectory: UInt32 = 0x06054B50
    static let zip64EndOfCentralDirectory: UInt32 = 0x06064B50
    static let zip64Locator: UInt32 = 0x07064B50
}

public enum ZipCompressionMethod: UInt16 {
    case stored = 0
    case deflated = 8
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
swift test --filter BinaryReaderTests
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

```bash
git add Sources/SnowRunnerTool/Pak/BinaryReader.swift Sources/SnowRunnerTool/Pak/ZipHeaders.swift Tests/SnowRunnerToolTests/BinaryReaderTests.swift
git commit -m "phase1: add binary reader and zip constants"
```

If no git repository exists, record this as the Task 2 checkpoint.

### Task 3: CP437 Filename Decoder

**Files:**
- Create `Sources/SnowRunnerTool/Pak/CP437.swift`
- Create `Tests/SnowRunnerToolTests/CP437Tests.swift`

- [ ] **Step 1: Write failing CP437 tests**

```swift
import Foundation
import XCTest
@testable import SnowRunnerTool

final class CP437Tests: XCTestCase {
    func testDecodesAsciiFixtureName() throws {
        let bytes = Array("pak.load_list".utf8)

        XCTAssertEqual(try CP437.decode(bytes), "pak.load_list")
    }

    func testRejectsNonAsciiUntilFullTableIsNeeded() {
        XCTAssertThrowsError(try CP437.decode([0x80])) { error in
            XCTAssertTrue(String(describing: error).contains("non-ASCII CP437"))
        }
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail because `CP437` is missing**

Run:

```bash
swift test --filter CP437Tests
```

Expected: FAIL with missing `CP437`.

- [ ] **Step 3: Implement ASCII fast path**

Implement `CP437.decode(_:)` so bytes `0x00...0x7F` decode as ASCII and any byte above `0x7F` throws a clear error. Do not use UTF-8 fallback.

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
swift test --filter CP437Tests
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

```bash
git add Sources/SnowRunnerTool/Pak/CP437.swift Tests/SnowRunnerToolTests/CP437Tests.swift
git commit -m "phase1: add CP437 filename decoder fast path"
```

If no git repository exists, record this as the Task 3 checkpoint.

### Task 4: Read EOCD And Central Directory

**Files:**
- Create `Sources/SnowRunnerTool/Pak/PakEntry.swift`
- Create `Sources/SnowRunnerTool/Pak/PakArchive.swift`
- Create `Sources/SnowRunnerTool/Pak/PakReader.swift`
- Create `Tests/SnowRunnerToolTests/TestFixtures.swift`
- Create `Tests/SnowRunnerToolTests/PakReaderFixtureTests.swift`

- [ ] **Step 1: Write failing fixture tests for EOCD and central directory**

```swift
import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakReaderFixtureTests: XCTestCase {
    func testReadsOriginalPakCentralDirectory() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialPak)

        XCTAssertEqual(archive.entries.count, 10_308)
        XCTAssertEqual(archive.entries.first?.name, "pak.load_list")
        XCTAssertEqual(archive.entries.first?.compressionMethod, .stored)
    }

    func testReadsRepackedPakCentralDirectory() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)

        XCTAssertEqual(archive.entries.count, 10_308)
        XCTAssertEqual(archive.entries.first?.name, "pak.load_list")
        XCTAssertEqual(archive.entries.first?.compressionMethod, .stored)
    }
}
```

`TestFixtures` must resolve fixture paths relative to the package root:

```swift
enum TestFixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let initialPak = root.appendingPathComponent("fixtures/initial.pak")
    static let initialRepackedPak = root.appendingPathComponent("fixtures/initial.repacked.pak")
}
```

- [ ] **Step 2: Run the tests and verify they fail because `PakReader` is missing**

Run:

```bash
swift test --filter PakReaderFixtureTests
```

Expected: FAIL with missing `PakReader`.

- [ ] **Step 3: Implement EOCD and central directory parsing**

Implement:

- EOCD search from the end of the file, supporting no archive comment first.
- EOCD fields: disk numbers, record count, central directory size, central directory offset, comment length.
- ZIP64 rejection when EOCD count, size, or offset uses legacy sentinel values or when ZIP64 signatures are detected near EOCD.
- Central directory header parsing for every entry.
- CP437 name decoding.
- `PakArchive.entries` in central directory order.

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
swift test --filter PakReaderFixtureTests
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

```bash
git add Sources/SnowRunnerTool/Pak/PakEntry.swift Sources/SnowRunnerTool/Pak/PakArchive.swift Sources/SnowRunnerTool/Pak/PakReader.swift Tests/SnowRunnerToolTests/TestFixtures.swift Tests/SnowRunnerToolTests/PakReaderFixtureTests.swift
git commit -m "phase1: parse eocd and central directory"
```

If no git repository exists, record this as the Task 4 checkpoint.

### Task 5: Scan Local Headers And Check Header Consistency

**Files:**
- Modify `Sources/SnowRunnerTool/Pak/PakEntry.swift`
- Modify `Sources/SnowRunnerTool/Pak/PakArchive.swift`
- Modify `Sources/SnowRunnerTool/Pak/PakReader.swift`
- Modify `Tests/SnowRunnerToolTests/PakReaderFixtureTests.swift`

- [ ] **Step 1: Write failing tests for local-header metadata and method counts**

```swift
func testOriginalPakLocalHeaderScanCountsMethods() throws {
    let archive = try PakReader.readArchive(at: TestFixtures.initialPak)

    XCTAssertEqual(archive.localEntries.count, 10_308)
    XCTAssertEqual(archive.localEntries.filter { $0.compressionMethod == .stored }.count, 8_325)
    XCTAssertEqual(archive.localEntries.filter { $0.compressionMethod == .deflated }.count, 1_983)
}

func testRepackedPakLocalHeaderScanCountsMethods() throws {
    let archive = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)

    XCTAssertEqual(archive.localEntries.count, 10_308)
    XCTAssertEqual(archive.localEntries.filter { $0.compressionMethod == .stored }.count, 1)
    XCTAssertEqual(archive.localEntries.filter { $0.compressionMethod == .deflated }.count, 10_307)
}

func testCentralDirectoryAndLocalHeadersAgreeForFirstEntry() throws {
    let archive = try PakReader.readArchive(at: TestFixtures.initialPak)

    let first = try XCTUnwrap(archive.entries.first)
    XCTAssertEqual(first.name, "pak.load_list")
    XCTAssertEqual(first.localHeaderOffset, 0)
    XCTAssertEqual(first.compressionMethod, .stored)
    XCTAssertEqual(first.crc32, 0xE635B186)
    XCTAssertEqual(first.compressedSize, 2_207_322)
    XCTAssertEqual(first.uncompressedSize, 2_207_322)
}
```

- [ ] **Step 2: Run the tests and verify they fail because local header scanning is missing**

Run:

```bash
swift test --filter PakReaderFixtureTests
```

Expected: FAIL for missing `localEntries` or incorrect method counts.

- [ ] **Step 3: Implement local header scanning**

Implement local header scanning from offset `0` until the next signature is not `0x04034B50`.

For each local header:

- read version needed, flags, compression method, DOS time/date, CRC32, compressed size, uncompressed size, name length, extra length
- decode name as CP437
- skip extra bytes
- record data offset
- skip compressed data length

Then cross-check central directory entries against local entries by `localHeaderOffset` and name.

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
swift test --filter PakReaderFixtureTests
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

```bash
git add Sources/SnowRunnerTool/Pak Tests/SnowRunnerToolTests/PakReaderFixtureTests.swift
git commit -m "phase1: scan local headers and compare metadata"
```

If no git repository exists, record this as the Task 5 checkpoint.

### Task 6: Raw Inflate And CRC Validation

**Files:**
- Create `Sources/SnowRunnerTool/Pak/PakInflater.swift`
- Modify `Sources/SnowRunnerTool/Pak/PakReader.swift`
- Modify `Tests/SnowRunnerToolTests/PakReaderFixtureTests.swift`

- [ ] **Step 1: Write failing tests that validate all fixture entry CRCs**

```swift
func testOriginalPakAllEntryCrcsMatchPayloads() throws {
    let archive = try PakReader.readArchive(at: TestFixtures.initialPak)

    try PakReader.validatePayloadCRCs(in: archive)
}

func testRepackedPakAllEntryCrcsMatchPayloads() throws {
    let archive = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)

    try PakReader.validatePayloadCRCs(in: archive)
}
```

- [ ] **Step 2: Run the tests and verify they fail because CRC validation is missing**

Run:

```bash
swift test --filter PakReaderFixtureTests
```

Expected: FAIL with missing `validatePayloadCRCs` or missing inflater.

- [ ] **Step 3: Implement raw inflate and CRC validation**

Implement `PakInflater.inflateRawDeflate(_ compressed: Data, expectedSize: UInt32) throws -> Data` using zlib `inflateInit2` with negative window bits.

Implement `PakReader.readUncompressedPayload(entry:in:)` and `PakReader.validatePayloadCRCs(in:)`:

- for stored entries, read compressed bytes directly as payload
- for deflated entries, raw inflate compressed bytes
- reject unsupported compression methods
- compute CRC32 with zlib `crc32`
- compare against header CRC32
- compare inflated payload size against uncompressed size

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
swift test --filter PakReaderFixtureTests
```

Expected: PASS. This may take longer than earlier tests because both fixtures are fully decompressed.

- [ ] **Step 5: Checkpoint**

```bash
git add Sources/SnowRunnerTool/Pak/PakInflater.swift Sources/SnowRunnerTool/Pak/PakReader.swift Tests/SnowRunnerToolTests/PakReaderFixtureTests.swift
git commit -m "phase1: validate payload crc with raw inflate"
```

If no git repository exists, record this as the Task 6 checkpoint.

### Task 7: Verifier Rules

**Files:**
- Create `Sources/SnowRunnerTool/Pak/VerifierIssue.swift`
- Create `Sources/SnowRunnerTool/Pak/PakVerifier.swift`
- Create `Tests/SnowRunnerToolTests/PakVerifierFixtureTests.swift`

- [ ] **Step 1: Write failing verifier fixture tests**

```swift
import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakVerifierFixtureTests: XCTestCase {
    func testBasicVerifierPassesOriginalPak() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialPak)
        let issues = try PakVerifier.verifyBasic(archive)

        XCTAssertTrue(issues.isEmpty, issues.map(\.message).joined(separator: "\n"))
    }

    func testBasicVerifierPassesRepackedPak() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)
        let issues = try PakVerifier.verifyBasic(archive)

        XCTAssertTrue(issues.isEmpty, issues.map(\.message).joined(separator: "\n"))
    }

    func testContentEquivalentPassesBetweenOriginalAndRepacked() throws {
        let original = try PakReader.readArchive(at: TestFixtures.initialPak)
        let repacked = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)
        let issues = try PakVerifier.verifyContentEquivalent(reference: original, candidate: repacked)

        XCTAssertTrue(issues.isEmpty, issues.map(\.message).joined(separator: "\n"))
    }

    func testSnowPakLayoutPassesRepackedPak() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)
        let issues = try PakVerifier.verifySnowPakLayout(archive)

        XCTAssertTrue(issues.isEmpty, issues.map(\.message).joined(separator: "\n"))
    }

    func testSnowPakLayoutFailsOriginalPakOnlyForExpectedPolicyReasons() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialPak)
        let issues = try PakVerifier.verifySnowPakLayout(archive)
        let codes = Set(issues.map(\.code))
        let expectedPolicyCodes: Set<String> = [
            "entry-order",
            "non-load-list-stored-entry",
            "invalid-timestamp",
            "extra-field",
            "version-made-by",
            "external-attributes"
        ]

        XCTAssertFalse(issues.isEmpty)
        XCTAssertTrue(codes.isSubset(of: expectedPolicyCodes), issues.map(\.message).joined(separator: "\n"))
        XCTAssertTrue(codes.contains("entry-order"))
        XCTAssertTrue(codes.contains("non-load-list-stored-entry"))
    }

    func testContentEquivalentReportsSizeOrCrcMismatch() throws {
        let original = try PakReader.readArchive(at: TestFixtures.initialPak)
        let first = try XCTUnwrap(original.entries.first)
        let changedFirst = PakEntry(
            name: first.name,
            compressionMethod: first.compressionMethod,
            generalPurposeBitFlag: first.generalPurposeBitFlag,
            crc32: first.crc32 ^ 0xFFFF,
            compressedSize: first.compressedSize,
            uncompressedSize: first.uncompressedSize,
            versionNeeded: first.versionNeeded,
            dosTime: first.dosTime,
            dosDate: first.dosDate,
            localHeaderOffset: first.localHeaderOffset,
            dataOffset: first.dataOffset,
            localExtraFieldLength: first.localExtraFieldLength,
            centralVersionMadeBy: first.centralVersionMadeBy,
            centralExtraFieldLength: first.centralExtraFieldLength,
            centralFileCommentLength: first.centralFileCommentLength,
            centralExternalAttributes: first.centralExternalAttributes
        )
        let candidate = original.replacingEntry(named: first.name, with: changedFirst)

        let issues = try PakVerifier.verifyContentEquivalent(reference: original, candidate: candidate)
        let codes = Set(issues.map(\.code))

        XCTAssertTrue(codes.contains("content-crc-mismatch"), issues.map(\.message).joined(separator: "\n"))
    }
}

private extension PakArchive {
    func replacingEntry(named name: String, with replacement: PakEntry) -> PakArchive {
        PakArchive(
            url: url,
            data: data,
            entries: entries.map { $0.name == name ? replacement : $0 },
            localEntries: localEntries.map { $0.name == name ? replacement : $0 },
            centralDirectoryOffset: centralDirectoryOffset,
            centralDirectorySize: centralDirectorySize,
            archiveCommentLength: archiveCommentLength,
            isZip64: isZip64
        )
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail because `PakVerifier` is missing**

Run:

```bash
swift test --filter PakVerifierFixtureTests
```

Expected: FAIL with missing `PakVerifier`.

- [ ] **Step 3: Implement verifier checks**

Implement:

- `verifyBasic(_:) throws -> [VerifierIssue]`
- `verifyContentEquivalent(reference:candidate:) throws -> [VerifierIssue]`
- `verifySnowPakLayout(_:) throws -> [VerifierIssue]`

`verifyBasic` must check:

- readable EOCD and central directory already parsed
- central directory and local headers agree
- no ZIP64
- all local and central header general-purpose bit flags are `0`
- no data descriptors
- no directory entries
- `pak.load_list` exists and is first
- `pak.load_list` is stored
- required namespaces exist: `[media]`, `[strings]`, `[ssl_cache]`
- only stored and deflated entries are present
- all CRCs match decompressed bytes

`verifyContentEquivalent` must check:

- reference and candidate have the same internal path set
- matching entries have the same uncompressed size
- matching entries have the same CRC32
- matching entries decompress to identical bytes
- compression method, compressed size, offsets, and order do not affect equivalence

`verifySnowPakLayout` must additionally check:

- every non-`pak.load_list` entry is deflated
- entry order follows the SnowPakTool-compatible fixture layout defined in `Implementation Contracts`: `pak.load_list` first, `initial.cache_block` second, then the known section order `[media]\classes`, `[media]\_dlc`, `[media]\_templates`, `[ssl_cache]`, `[strings]`
- DOS timestamp is `1980-01-01 03:00:00`
- extra-field lengths are zero
- version needed is `0x14`
- central version made by is `0x0314`
- central external attributes are `0x81B60000`
- no file comments and no archive comment

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
swift test --filter PakVerifierFixtureTests
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

```bash
git add Sources/SnowRunnerTool/Pak/VerifierIssue.swift Sources/SnowRunnerTool/Pak/PakVerifier.swift Tests/SnowRunnerToolTests/PakVerifierFixtureTests.swift
git commit -m "phase1: add pak verifier rules"
```

If no git repository exists, record this as the Task 7 checkpoint.

### Task 8: Inspect And Verify CLI Commands

**Files:**
- Modify `Sources/SnowRunnerTool/CLI.swift`
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Write failing CLI command tests**

```swift
func testInspectCommandReportsEntryCounts() {
    let result = CLI.run(arguments: ["pak", "inspect", TestFixtures.initialPak.path])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains("entries: 10308"))
    XCTAssertTrue(result.stdout.contains("stored: 8325"))
    XCTAssertTrue(result.stdout.contains("deflated: 1983"))
}

func testVerifyBasicCommandPassesFixture() {
    let result = CLI.run(arguments: ["pak", "verify-basic", TestFixtures.initialPak.path])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains("PASS"))
}

func testVerifySnowPakLayoutCommandReturnsFailureForOriginalPak() {
    let result = CLI.run(arguments: ["pak", "verify-snowpak-layout", TestFixtures.initialPak.path])

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.stdout.contains("entry-order") || result.stdout.contains("non-load-list-stored-entry"))
}
```

- [ ] **Step 2: Run the tests and verify they fail because commands are not wired**

Run:

```bash
swift test --filter CLITests
```

Expected: FAIL with unknown pak command or missing output.

- [ ] **Step 3: Implement Phase 1 command dispatch**

Implement:

- `pak inspect <pak>`: prints entry count, stored count, deflated count, first entry name, first entry method, central directory offset, central directory size
- `pak verify-basic <pak>`: prints `PASS verify-basic` on no issues, otherwise prints issues and exits `1`
- `pak verify-content-equivalent <reference.pak> <candidate.pak>`: prints `PASS verify-content-equivalent` on no issues, otherwise prints issues and exits `1`
- `pak verify-snowpak-layout <pak>`: prints `PASS verify-snowpak-layout` on no issues, otherwise prints issues and exits `1`

Command parse errors must exit `2`.

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
swift test --filter CLITests
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

```bash
git add Sources/SnowRunnerTool/CLI.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "phase1: wire inspect and verify commands"
```

If no git repository exists, record this as the Task 8 checkpoint.

### Task 9: End-To-End Acceptance

**Files:**
- Modify documentation only if acceptance exposes a mismatch in the plan.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Run Phase 1 acceptance commands**

Run:

```bash
swift run snowrunner-tool pak inspect fixtures/initial.pak
swift run snowrunner-tool pak verify-basic fixtures/initial.pak
swift run snowrunner-tool pak verify-basic fixtures/initial.repacked.pak
swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak fixtures/initial.repacked.pak
swift run snowrunner-tool pak verify-snowpak-layout fixtures/initial.repacked.pak
```

Expected: all commands exit `0`.

- [ ] **Step 3: Run the expected layout-policy failure**

Run:

```bash
swift run snowrunner-tool pak verify-snowpak-layout fixtures/initial.pak
```

Expected: command exits `1`, and reported issue codes are limited to:

```text
entry-order
non-load-list-stored-entry
invalid-timestamp
extra-field
version-made-by
external-attributes
```

- [ ] **Step 4: Checkpoint**

```bash
git add .
git commit -m "phase1: complete inspect and verify milestone"
```

If no git repository exists, record this as the Phase 1 completion checkpoint.

## Test Strategy

- Unit tests prove little-endian parsing, bounds checks, and CP437 ASCII fixture decoding.
- Fixture tests prove EOCD, central directory, local headers, method counts, and metadata consistency for both PAK files.
- Payload tests prove raw deflate compatibility and CRC32 validation for every entry in both fixtures.
- Verifier tests prove the expected difference between original game layout and SnowPakTool repack layout.
- CLI tests prove command routing, exit codes, and important output.
- No game-launch test is required because Phase 1 emits no candidate PAK.

## Acceptance Criteria

These commands must pass:

```bash
swift test
swift run snowrunner-tool pak inspect fixtures/initial.pak
swift run snowrunner-tool pak verify-basic fixtures/initial.pak
swift run snowrunner-tool pak verify-basic fixtures/initial.repacked.pak
swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak fixtures/initial.repacked.pak
swift run snowrunner-tool pak verify-snowpak-layout fixtures/initial.repacked.pak
```

This command must fail only for expected layout-policy differences:

```bash
swift run snowrunner-tool pak verify-snowpak-layout fixtures/initial.pak
```

Expected issue codes:

```text
entry-order
non-load-list-stored-entry
invalid-timestamp
extra-field
version-made-by
external-attributes
```

Phase 1 is not complete until these acceptance results are fresh and verified.

## Risks

- Raw deflate compatibility: contain the risk by inflating every deflated fixture entry and matching CRC32 in Phase 1.
- zlib Swift interop: contain the risk by linking zlib in Task 1 and proving raw inflate in Task 6 before CLI acceptance.
- CP437 filenames: current fixtures are ASCII; implement ASCII fast path and explicit non-ASCII failure so the tool does not silently misdecode names.
- Header consistency: compare central directory records against local headers for every entry before trusting verifier output.
- Large fixture runtime: full CRC validation decompresses both PAKs; keep fast unit tests separate from fixture-heavy tests by using XCTest filters during development.
- Git checkpoint churn: the workspace is a git repository, so each task has a commit point; keep commits scoped to the files named by the task.

## Stop Rule

Stop Phase 1 when all acceptance commands pass exactly as described.

Do not begin Phase 2 until Phase 1 can parse both fixtures, validate CRCs, pass `verify-basic`, pass `verify-content-equivalent`, pass SnowPakTool layout on `initial.repacked.pak`, and fail SnowPakTool layout on `initial.pak` only for expected policy differences.
