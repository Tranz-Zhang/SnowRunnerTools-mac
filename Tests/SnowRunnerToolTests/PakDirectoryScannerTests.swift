import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakDirectoryScannerTests: XCTestCase {
    func testScannerReturnsSnowPakWriterOrder() throws {
        let root = try temporaryDirectory(named: "scan-order")
        try Data("load\n".utf8).write(to: root.appendingPathComponent("pak.load_list"))
        try Data("cache\n".utf8).write(to: root.appendingPathComponent("initial.cache_block"))
        try writeFile(root: root, relativePath: "[strings]/strings_english.str", data: Data("strings".utf8))
        try writeFile(root: root, relativePath: "[media]/_dlc/us_01/file.xml", data: Data("<dlc/>".utf8))
        try writeFile(root: root, relativePath: "[media]/classes/truck.xml", data: Data("<truck/>".utf8))

        let sources = try PakDirectoryScanner.scan(rootDirectory: root)

        XCTAssertEqual(sources.map(\.internalName), [
            "pak.load_list",
            "initial.cache_block",
            "[media]\\classes\\truck.xml",
            "[media]\\_dlc\\us_01\\file.xml",
            "[strings]\\strings_english.str"
        ])
    }

    func testScannerRequiresPakLoadList() throws {
        let root = try temporaryDirectory(named: "scan-missing-load-list")
        try writeFile(root: root, relativePath: "[media]/classes/truck.xml", data: Data())

        XCTAssertThrowsError(try PakDirectoryScanner.scan(rootDirectory: root)) { error in
            XCTAssertTrue(String(describing: error).contains("pak.load_list"))
        }
    }
}
