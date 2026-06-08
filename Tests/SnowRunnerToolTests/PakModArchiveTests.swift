import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakModArchiveTests: XCTestCase {
    func testUnpackWritesModPackageDirectories() throws {
        let pak = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8),
            "prebuild/meshes/demo_mesh": Data([1, 2, 3]),
            "ui/textures/demo.png": Data([4, 5, 6]),
            "texts/strings_english.str": Data("Text".utf8)
        ])
        let output = try temporaryDirectory(named: "mod-unpack")

        let count = try PakModUnpacker.unpack(archiveURL: pak, toDirectory: output)

        XCTAssertEqual(count, 4)
        XCTAssertEqual(
            try Data(contentsOf: output.appendingPathComponent("classes/trucks/demo.xml")),
            Data("<Truck/>".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: output.appendingPathComponent("prebuild/meshes/demo_mesh")),
            Data([1, 2, 3])
        )
    }

    func testUnpackedPayloadMatchesReaderPayloadForFixtureWhenAvailable() throws {
        guard let modPak = TestFixtures.optionalLoadstarJbeModPak() else {
            throw XCTSkip("Loadstar JBE mod fixture is not present")
        }
        let output = try temporaryDirectory(named: "loadstar-mod-unpack")
        let archive = try PakReader.readArchive(at: modPak)

        let count = try PakModUnpacker.unpack(archiveURL: modPak, toDirectory: output)

        XCTAssertEqual(count, 106)
        for entry in archive.entries.prefix(25) {
            let relativePath = try PakModPath.fileSystemRelativePath(forArchiveName: entry.name)
            let fileData = try Data(contentsOf: output.appendingPathComponent(relativePath))
            let readerData = try PakReader.readUncompressedPayload(entry: entry, in: archive)
            XCTAssertEqual(fileData, readerData, entry.name)
        }
    }

    func testPackWritesMergeCompatibleForwardSlashArchive() throws {
        let root = try temporaryDirectory(named: "mod-pack")
        let output = root.deletingLastPathComponent().appendingPathComponent("mod-output.pak")
        try writeFile(root: root, relativePath: "classes/trucks/demo.xml", data: Data("<Truck/>".utf8))
        try writeFile(root: root, relativePath: "prebuild/meshes/demo_mesh", data: Data([1, 2, 3]))
        try writeFile(root: root, relativePath: "ui/textures/demo.png", data: Data([4, 5, 6]))
        try writeFile(root: root, relativePath: "texts/strings_english.str", data: Data("Text".utf8))

        let count = try PakModWriter.writeArchive(fromDirectory: root, to: output)

        XCTAssertEqual(count, 4)
        let archive = try PakReader.readArchive(at: output)
        XCTAssertEqual(archive.entries.map(\.name), [
            "classes/trucks/demo.xml",
            "prebuild/meshes/demo_mesh",
            "texts/strings_english.str",
            "ui/textures/demo.png"
        ])
        XCTAssertEqual(try ModArchiveMapper.mapArchive(at: output).count, 4)
    }

    func testPackRejectsUnsupportedRootsBeforeWritingOutput() throws {
        let root = try temporaryDirectory(named: "mod-pack-unsupported")
        let output = root.deletingLastPathComponent().appendingPathComponent("unsupported-output.pak")
        try writeFile(root: root, relativePath: "unknown/demo.xml", data: Data("<Truck/>".utf8))

        XCTAssertThrowsError(try PakModWriter.writeArchive(fromDirectory: root, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testPackRejectsMixedMainAndTextureArchiveBeforeWritingOutput() throws {
        let root = try temporaryDirectory(named: "mod-pack-mixed")
        let output = root.deletingLastPathComponent().appendingPathComponent("mixed-output.pak")
        try writeFile(root: root, relativePath: "classes/trucks/demo.xml", data: Data("<Truck/>".utf8))
        try writeFile(root: root, relativePath: "prebuild/textures/pct/demo.pct", data: makeSyntheticPCT(tableCount: 1))

        XCTAssertThrowsError(try PakModWriter.writeArchive(fromDirectory: root, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
