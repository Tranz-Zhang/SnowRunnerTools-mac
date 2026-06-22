import Foundation
import XCTest
@testable import SnowRunnerCore

final class PCTHeaderGeneratorTests: XCTestCase {
    func testGeneratesVariableLengthHeaderFromPCTTableCount() throws {
        let pct = makeSyntheticPCT(tableCount: 11, tail: Data([0xAA, 0xBB]))

        let header = try PCTHeaderGenerator.headerData(for: pct)

        XCTAssertEqual(header.count, 152)
        XCTAssertEqual(header[0..<64], pct[0..<64])
        XCTAssertEqual(header[146], 0x01)
        XCTAssertEqual(header[148], 0x98)
        XCTAssertEqual(header[149], 0x00)
        XCTAssertEqual(header[150], 0x00)
        XCTAssertEqual(header[151], 0x00)
    }

    func testHeaderRuleMatchesLevelPakFixtureWhenAvailable() throws {
        let levelPak = TestFixtures.root.appendingPathComponent("fixtures/level_ru_02_03.pak")
        guard FileManager.default.fileExists(atPath: levelPak.path) else {
            throw XCTSkip("fixtures/level_ru_02_03.pak is not present")
        }

        let archive = try PakReader.readArchive(at: levelPak)
        let pctEntry = try XCTUnwrap(archive.entries.first {
            $0.name == "[textures]\\pct\\level_ru_02_03_blend_map__cmp.pct"
        })
        let headerEntry = try XCTUnwrap(archive.entries.first {
            $0.name == "[textures]\\pct\\level_ru_02_03_blend_map__cmp.pct_header"
        })

        let pct = try PakReader.readUncompressedPayload(entry: pctEntry, in: archive)
        let expectedHeader = try PakReader.readUncompressedPayload(entry: headerEntry, in: archive)

        XCTAssertEqual(try PCTHeaderGenerator.headerData(for: pct), expectedHeader)
    }

    func testRejectsMalformedPCTData() {
        XCTAssertThrowsError(try PCTHeaderGenerator.headerData(for: Data([1, 2, 3])))
    }
}

func makeSyntheticPCT(tableCount: UInt32, tail: Data = Data()) -> Data {
    let headerLength = 64 + Int(tableCount) * 8
    var data = Data(repeating: 0, count: headerLength)
    data[6] = UInt8(ascii: "T")
    data[7] = UInt8(ascii: "C")
    data[8] = UInt8(ascii: "I")
    data[9] = UInt8(ascii: "P")
    data[48] = UInt8(tableCount & 0xFF)
    data[49] = UInt8((tableCount >> 8) & 0xFF)
    data[50] = UInt8((tableCount >> 16) & 0xFF)
    data[51] = UInt8((tableCount >> 24) & 0xFF)
    data[headerLength - 6] = 0xFF
    data[headerLength - 4] = 0xEE
    data[headerLength - 3] = 0xDD
    data[headerLength - 2] = 0xCC
    data[headerLength - 1] = 0xBB
    data.append(tail)
    return data
}
