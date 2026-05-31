import Foundation
import XCTest
@testable import SnowRunnerTool

final class CacheBlockWriterTests: XCTestCase {
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
}
