import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakDeflaterTests: XCTestCase {
    func testRawDeflateRoundTripThroughExistingInflater() throws {
        let input = Data(("SnowRunner raw deflate payload\n" + String(repeating: "abc123", count: 512)).utf8)

        let compressed = try PakDeflater.deflateRaw(input)
        let inflated = try PakInflater.inflateRawDeflate(compressed, expectedSize: UInt32(input.count))

        XCTAssertEqual(inflated, input)
    }
}
