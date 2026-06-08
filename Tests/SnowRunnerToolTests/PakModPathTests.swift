import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakModPathTests: XCTestCase {
    func testArchiveNameMapsToFileSystemPath() throws {
        let path = try PakModPath.fileSystemRelativePath(forArchiveName: "classes\\trucks\\demo.xml")

        XCTAssertEqual(path, "classes/trucks/demo.xml")
    }

    func testFileSystemPathMapsToArchiveName() throws {
        let root = URL(fileURLWithPath: "/tmp/mod", isDirectory: true)
        let file = root
            .appendingPathComponent("classes", isDirectory: true)
            .appendingPathComponent("trucks", isDirectory: true)
            .appendingPathComponent("demo.xml")

        let name = try PakModPath.archiveName(forFileAt: file, rootDirectory: root)

        XCTAssertEqual(name, "classes/trucks/demo.xml")
    }

    func testRejectsUnsafeArchiveNames() {
        XCTAssertThrowsError(try PakModPath.fileSystemRelativePath(forArchiveName: "/absolute.xml"))
        XCTAssertThrowsError(try PakModPath.fileSystemRelativePath(forArchiveName: "classes/../evil.xml"))
        XCTAssertThrowsError(try PakModPath.fileSystemRelativePath(forArchiveName: "classes//bad.xml"))
        XCTAssertThrowsError(try PakModPath.fileSystemRelativePath(forArchiveName: ""))
    }

    func testRejectsCaseInsensitiveDuplicateNames() {
        XCTAssertThrowsError(try PakModPath.validatePackInput(archiveNames: [
            "classes/trucks/Demo.xml",
            "classes/trucks/demo.xml"
        ]))
    }
}
