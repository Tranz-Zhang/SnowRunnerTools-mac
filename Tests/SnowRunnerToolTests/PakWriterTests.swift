import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakWriterTests: XCTestCase {
    func testWriterCreatesReadableSnowPakLayoutArchive() throws {
        let root = try temporaryDirectory(named: "writer-small-input")
        let output = root.deletingLastPathComponent().appendingPathComponent("writer-small-output.pak")
        try Data("load\n".utf8).write(to: root.appendingPathComponent("pak.load_list"))
        try Data("cache\n".utf8).write(to: root.appendingPathComponent("initial.cache_block"))
        try writeFile(root: root, relativePath: "[media]/classes/truck.xml", data: Data("<truck/>".utf8))
        try writeFile(root: root, relativePath: "[strings]/strings_english.str", data: Data("English".utf8))
        try writeFile(root: root, relativePath: "[ssl_cache]/initial_pak", data: Data("ssl".utf8))

        try PakWriter.writeArchive(fromDirectory: root, to: output)

        let archive = try PakReader.readArchive(at: output)
        XCTAssertEqual(archive.entries.map(\.name), [
            "pak.load_list",
            "initial.cache_block",
            "[media]\\classes\\truck.xml",
            "[ssl_cache]\\initial_pak",
            "[strings]\\strings_english.str"
        ])
        XCTAssertEqual(archive.entries.first?.compressionMethod, .stored)
        XCTAssertTrue(archive.entries.dropFirst().allSatisfy { $0.compressionMethod == .deflated })
        XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
    }

    func testWriterRepackedInitialPakIsContentEquivalentAndSnowPakLayout() throws {
        let unpacked = try temporaryDirectory(named: "initial-unpacked")
        let candidate = unpacked.deletingLastPathComponent().appendingPathComponent("initial.candidate.pak")

        try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: unpacked)
        try PakWriter.writeArchive(fromDirectory: unpacked, to: candidate)

        let original = try PakReader.readArchive(at: TestFixtures.initialPak)
        let written = try PakReader.readArchive(at: candidate)

        XCTAssertTrue(try PakVerifier.verifyBasic(written).isEmpty)
        XCTAssertTrue(try PakVerifier.verifyContentEquivalent(reference: original, candidate: written).isEmpty)
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(written).isEmpty)
    }
}
