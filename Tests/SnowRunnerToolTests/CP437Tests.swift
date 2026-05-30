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
}
