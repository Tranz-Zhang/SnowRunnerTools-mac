import Foundation
import XCTest
@testable import SnowRunnerCore

final class BinaryWriterTests: XCTestCase {
    func testBinaryWriterAppendsLittleEndianIntegers() {
        var writer = BinaryWriter()

        writer.appendUInt16(0x1234)
        writer.appendUInt32(0x78563412)

        XCTAssertEqual(Array(writer.data), [0x34, 0x12, 0x12, 0x34, 0x56, 0x78])
    }
}
