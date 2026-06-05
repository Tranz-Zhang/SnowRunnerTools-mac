import Foundation
import XCTest
@testable import SnowRunnerTool

final class LargePakPatcherTests: XCTestCase {
    func testPatcherCopiesExistingEntriesAndAddsNewStoredEntries() throws {
        let base = try makePak(named: "shared_textures.pak", entries: [
            "[textures]\\pct\\existing.pct": Data([1, 2, 3])
        ])
        let output = try temporaryDirectory(named: "large-pak-patcher")
            .appendingPathComponent("shared_textures.merged.pak")

        let written = try LargePakPatcher.patchArchive(
            input: base,
            output: output,
            additions: [
                LargePakPatchEntry(name: "[textures]\\pct\\new.pct", data: Data([4, 5, 6])),
                LargePakPatchEntry(name: "[textures]\\pct\\new.pct_header", data: Data([7, 8]))
            ],
            allowOverwrite: false
        )

        XCTAssertEqual(written, 3)
        let archive = try PakReader.readArchive(at: output)
        XCTAssertEqual(Set(archive.entries.map(\.name)), [
            "[textures]\\pct\\existing.pct",
            "[textures]\\pct\\new.pct",
            "[textures]\\pct\\new.pct_header"
        ])
    }

    func testPatcherRejectsCollisionWithoutOverwrite() throws {
        let base = try makePak(named: "shared_textures.pak", entries: [
            "[textures]\\pct\\existing.pct": Data([1, 2, 3])
        ])
        let output = try temporaryDirectory(named: "large-pak-patcher")
            .appendingPathComponent("shared_textures.merged.pak")

        XCTAssertThrowsError(try LargePakPatcher.patchArchive(
            input: base,
            output: output,
            additions: [
                LargePakPatchEntry(name: "[textures]\\pct\\existing.pct", data: Data([4, 5, 6]))
            ],
            allowOverwrite: false
        ))
    }

    func testPatcherCanEmitZip64EndRecordsForLargeArchivePath() throws {
        let base = try makePak(named: "shared_textures.pak", entries: [
            "[textures]\\pct\\existing.pct": Data([1, 2, 3])
        ])
        let output = try temporaryDirectory(named: "large-pak-patcher")
            .appendingPathComponent("shared_textures.zip64.pak")

        _ = try LargePakPatcher.patchArchive(
            input: base,
            output: output,
            additions: [
                LargePakPatchEntry(name: "[textures]\\pct\\new.pct", data: Data([4, 5, 6]))
            ],
            allowOverwrite: false,
            forceZip64EndRecords: true
        )

        let bytes = try Data(contentsOf: output)
        XCTAssertTrue(bytes.containsLittleEndianUInt32(ZipSignature.zip64EndOfCentralDirectory))
        XCTAssertTrue(bytes.containsLittleEndianUInt32(ZipSignature.zip64Locator))
    }
}

private extension Data {
    func containsLittleEndianUInt32(_ value: UInt32) -> Bool {
        guard count >= 4 else { return false }
        for offset in 0...(count - 4) {
            let actual = UInt32(self[offset])
                | (UInt32(self[offset + 1]) << 8)
                | (UInt32(self[offset + 2]) << 16)
                | (UInt32(self[offset + 3]) << 24)
            if actual == value {
                return true
            }
        }
        return false
    }
}
