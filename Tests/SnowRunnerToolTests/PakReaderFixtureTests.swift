import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakReaderFixtureTests: XCTestCase {
    func testReadsOriginalPakCentralDirectory() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialPak)

        XCTAssertEqual(archive.entries.count, 10_308)
        XCTAssertEqual(archive.entries.first?.name, "pak.load_list")
        XCTAssertEqual(archive.entries.first?.compressionMethod, .stored)
    }

    func testReadsRepackedPakCentralDirectory() throws {
        let archive = try PakReader.readArchive(at: TestFixtures.initialRepackedPak)

        XCTAssertEqual(archive.entries.count, 10_308)
        XCTAssertEqual(archive.entries.first?.name, "pak.load_list")
        XCTAssertEqual(archive.entries.first?.compressionMethod, .stored)
    }
}
