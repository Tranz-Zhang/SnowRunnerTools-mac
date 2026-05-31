import Foundation
import XCTest
@testable import SnowRunnerTool

final class CP437Tests: XCTestCase {
    func testDecodesAsciiFixtureName() throws {
        let bytes = Array("pak.load_list".utf8)

        XCTAssertEqual(try CP437.decode(bytes), "pak.load_list")
    }

    func testRejectsNonAsciiUntilFullTableIsNeeded() {
        XCTAssertThrowsError(try CP437.decode([0x80])) { error in
            XCTAssertTrue(String(describing: error).contains("non-ASCII CP437"))
        }
    }

    func testCP437EncodeAcceptsASCII() throws {
        let bytes = try CP437.encode("[media]\\classes\\truck.xml")

        XCTAssertEqual(bytes, Array("[media]\\classes\\truck.xml".utf8))
    }

    func testCP437EncodeRejectsNonASCII() {
        XCTAssertThrowsError(try CP437.encode("café.xml")) { error in
            XCTAssertTrue(String(describing: error).contains("Unsupported non-ASCII"))
        }
    }
}
