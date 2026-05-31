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
}
