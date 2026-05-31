import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakUnpackerTests: XCTestCase {
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
}
