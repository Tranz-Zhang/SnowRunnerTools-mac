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
