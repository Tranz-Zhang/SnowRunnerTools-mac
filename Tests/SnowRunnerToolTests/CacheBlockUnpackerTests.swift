import Foundation
import XCTest
@testable import SnowRunnerTool

final class CacheBlockUnpackerTests: XCTestCase {
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
}
