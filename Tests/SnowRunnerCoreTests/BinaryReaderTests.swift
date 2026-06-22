import Foundation
import XCTest
@testable import SnowRunnerCore

final class BinaryReaderTests: XCTestCase {
    func testReadsLittleEndianIntegers() throws {
        let data = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])
        var reader = BinaryReader(data: data)

        XCTAssertEqual(try reader.readUInt32(), 0x04034B50)
        XCTAssertEqual(try reader.readUInt16(), 0x0014)
        XCTAssertEqual(reader.offset, 6)
    }

    func testThrowsAtEndOfData() {
        var reader = BinaryReader(data: Data([0x01]))

        XCTAssertThrowsError(try reader.readUInt16()) { error in
            XCTAssertTrue(String(describing: error).contains("Unexpected end of data"))
        }
    }
}
