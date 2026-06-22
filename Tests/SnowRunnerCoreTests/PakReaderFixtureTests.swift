import Foundation
import XCTest
@testable import SnowRunnerCore

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

    func testOriginalPakAllEntryCrcsMatchPayloads() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialPak)

        try PakReader.validatePayloadCRCs(in: archive)
    }

    func testRepackedPakAllEntryCrcsMatchPayloads() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)

        try PakReader.validatePayloadCRCs(in: archive)
    }
}
