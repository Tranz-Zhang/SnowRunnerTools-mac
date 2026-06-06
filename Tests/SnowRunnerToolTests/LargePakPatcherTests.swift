import Foundation
import XCTest
import zlib
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

    func testPatcherPreservesCentralExtraFieldForNewTextureEntries() throws {
        let base = try makePak(named: "shared_textures.pak", entries: [
            "[textures]\\pct\\existing.pct": Data([1, 2, 3])
        ])
        let output = try temporaryDirectory(named: "large-pak-patcher")
            .appendingPathComponent("shared_textures.merged.pak")
        let uncompressed = Data([4, 5, 6])
        let compressed = rawStoredDeflateBlock(for: uncompressed)
        let crc = uncompressed.withUnsafeBytes { buffer in
            UInt32(zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(uncompressed.count)))
        }
        let textureExtraField = Data([0x02, 0xF0, 0x04, 0x00, 1, 2, 3, 4])
        let compressedPayload = PakCompressedPayload(
            compressionMethod: .deflated,
            data: compressed,
            crc32: crc,
            uncompressedSize: UInt32(uncompressed.count)
        )

        _ = try LargePakPatcher.patchArchive(
            input: base,
            output: output,
            additions: [
                LargePakPatchEntry(
                    name: "[textures]\\pct\\new.pct",
                    data: uncompressed,
                    centralExtraField: textureExtraField,
                    compressedPayload: compressedPayload
                )
            ],
            allowOverwrite: false
        )

        let archive = try PakReader.readArchive(at: output)
        let entry = try XCTUnwrap(archive.entries.first { $0.name == "[textures]\\pct\\new.pct" })
        XCTAssertEqual(entry.localExtraField, Data())
        XCTAssertEqual(entry.centralExtraField, textureExtraField)
        XCTAssertEqual(entry.compressionMethod, .deflated)
        XCTAssertEqual(entry.compressedSize, UInt32(compressed.count))
        XCTAssertEqual(try PakReader.readUncompressedPayload(entry: entry, in: archive), uncompressed)
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

private func rawStoredDeflateBlock(for data: Data) -> Data {
    precondition(data.count <= Int(UInt16.max))
    let length = UInt16(data.count)
    let inverseLength = ~length
    var result = Data([0x01])
    result.append(UInt8(length & 0x00FF))
    result.append(UInt8((length >> 8) & 0x00FF))
    result.append(UInt8(inverseLength & 0x00FF))
    result.append(UInt8((inverseLength >> 8) & 0x00FF))
    result.append(data)
    return result
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
