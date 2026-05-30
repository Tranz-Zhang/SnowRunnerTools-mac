import Foundation
import XCTest
@testable import SnowRunnerTool

final class CLITests: XCTestCase {
    func testNoArgumentsPrintsUsageAndFails() {
        let result = CLI.run(arguments: [])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool"))
    }

    func testUnknownCommandFails() {
        let result = CLI.run(arguments: ["unknown"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Unknown command"))
    }
}
