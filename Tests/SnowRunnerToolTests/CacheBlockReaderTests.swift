import Foundation
import XCTest
@testable import SnowRunnerTool

final class CacheBlockReaderTests: XCTestCase {
    func testBinaryReaderReadsSignedCacheBlockIntegers() throws {
        let data = Data([0xFE, 0xFF, 0xFF, 0xFF, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
        var reader = BinaryReader(data: data)

        XCTAssertEqual(try reader.readInt32(), -2)
        XCTAssertEqual(try reader.readInt64(), 0x0102030405060708)
    }

    func testBinaryWriterWritesSignedCacheBlockIntegers() {
        var writer = BinaryWriter()

        writer.appendInt32(-2)
        writer.appendInt64(0x0102030405060708)
        writer.appendUInt8(1)

        XCTAssertEqual(Array(writer.data), [
            0xFE, 0xFF, 0xFF, 0xFF,
            0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
            0x01
        ])
    }

    func testReaderParsesSyntheticCacheBlock() throws {
        let file = try temporaryDirectory(named: "cache-reader")
            .appendingPathComponent("synthetic.cache_block")
        try makeSyntheticCacheBlock(entries: [
            ("<ps>:hud.xml", Data("HUD".utf8)),
            ("<strings>\\ui\\menu.str", Data("MENU".utf8))
        ]).write(to: file)

        let archive = try CacheBlockReader.readArchive(at: file)

        XCTAssertEqual(archive.entries.map(\.internalName), ["<ps>:hud.xml", "<strings>\\ui\\menu.str"])
        XCTAssertEqual(archive.entries.map(\.externalPath), ["[ps]/hud.xml", "[strings]/ui/menu.str"])
        XCTAssertEqual(archive.entries.map(\.relativeOffset), [0, 3])
        XCTAssertEqual(archive.entries.map(\.size), [3, 4])
    }

    func testReaderParsesInitialCacheBlockFromFixturePak() throws {
        let cacheBlock = try TestFixtures.extractInitialCacheBlock(from: TestFixtures.initialPak)
        let archive = try CacheBlockReader.readArchive(at: cacheBlock)

        XCTAssertGreaterThan(archive.entries.count, 0)
        XCTAssertTrue(archive.entries.contains { $0.externalPath.hasPrefix("[ps]/") })
        XCTAssertTrue(archive.entries.contains { $0.externalPath.hasPrefix("[ps_common]/") })
        XCTAssertTrue(archive.entries.allSatisfy { $0.zero == 0 })
    }

    private func makeSyntheticCacheBlock(entries: [(String, Data)]) throws -> Data {
        var writer = BinaryWriter()
        writer.appendBytes(CacheBlockConstants.signature)
        writer.appendInt32(1)
        writer.appendUInt8(1)
        writer.appendInt32(Int32(entries.count))
        writer.appendInt32(4)
        writer.appendUInt8(1)

        for entry in entries {
            let nameBytes = try CP437.encode(entry.0)
            writer.appendInt32(Int32(nameBytes.count))
            writer.appendBytes(nameBytes)
        }

        writer.appendUInt8(1)

        var relativeOffset: Int64 = 0
        for entry in entries {
            writer.appendInt64(relativeOffset)
            relativeOffset += Int64(entry.1.count)
        }

        writer.appendUInt8(1)

        for entry in entries {
            writer.appendInt32(Int32(entry.1.count))
        }

        writer.appendUInt8(1)

        for _ in entries {
            writer.appendInt32(0)
        }

        for entry in entries {
            writer.appendData(entry.1)
        }

        return writer.data
    }
}
