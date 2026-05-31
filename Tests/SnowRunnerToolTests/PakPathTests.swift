import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakPathTests: XCTestCase {
    func testInternalNameMapsToFileSystemPath() throws {
        let path = try PakPath.fileSystemRelativePath(forInternalName: "[media]\\classes\\truck.xml")

        XCTAssertEqual(path, "[media]/classes/truck.xml")
    }

    func testFileSystemPathMapsToInternalName() throws {
        let root = URL(fileURLWithPath: "/tmp/unpacked", isDirectory: true)
        let file = root
            .appendingPathComponent("[media]", isDirectory: true)
            .appendingPathComponent("classes", isDirectory: true)
            .appendingPathComponent("truck.xml")

        let name = try PakPath.internalName(forFileAt: file, rootDirectory: root)

        XCTAssertEqual(name, "[media]\\classes\\truck.xml")
    }

    func testRejectsLiteralBackslashInFileSystemComponent() {
        let root = URL(fileURLWithPath: "/tmp/unpacked", isDirectory: true)
        let file = root.appendingPathComponent("bad\\name.xml")

        XCTAssertThrowsError(try PakPath.internalName(forFileAt: file, rootDirectory: root))
    }

    func testRejectsCaseInsensitiveDuplicateNames() {
        XCTAssertThrowsError(try PakPath.validatePackInput(internalNames: [
            "[media]\\classes\\Truck.xml",
            "[media]\\classes\\truck.xml"
        ]))
    }

    func testRejectsExactDuplicateNames() {
        XCTAssertThrowsError(try PakPath.validatePackInput(internalNames: [
            "[media]\\classes\\truck.xml",
            "[media]\\classes\\truck.xml"
        ]))
    }

    func testRejectsUnsafeInternalNames() {
        XCTAssertThrowsError(try PakPath.fileSystemRelativePath(forInternalName: "[media]\\..\\evil.xml"))
        XCTAssertThrowsError(try PakPath.fileSystemRelativePath(forInternalName: "/absolute.xml"))
        XCTAssertThrowsError(try PakPath.fileSystemRelativePath(forInternalName: "[media]/classes/truck.xml"))
        XCTAssertThrowsError(try PakPath.fileSystemRelativePath(forInternalName: "[media]\\\\truck.xml"))
    }
}
