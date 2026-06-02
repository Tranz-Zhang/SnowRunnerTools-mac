import Foundation
import XCTest
@testable import SnowRunnerTool

final class ModMergeCLITests: XCTestCase {
    func testCLIMergeModDryRunReportsPlan() throws {
        let base = try makeSyntheticInitialPak()
        let mod = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/new.xml": Data("<Truck/>".utf8)
        ])
        let output = try temporaryDirectory(named: "cli-merge-output")
            .appendingPathComponent("initial.merged.pak")

        let result = CLI.run(arguments: [
            "pak", "merge-mod", "--dry-run",
            base.path,
            output.path,
            mod.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("merged 1 mod entries"))
        XCTAssertTrue(result.stdout.contains("dry-run: no output written"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCLIMergeModRejectsMissingArguments() {
        let result = CLI.run(arguments: ["pak", "merge-mod"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool pak merge-mod"))
    }
}

func makeSyntheticInitialPak() throws -> URL {
    let manifest = try LoadListBuilder.buildManifest(records: [
        LoadListRecord(
            manifestPath: "<media>\\classes\\trucks\\existing.xml",
            loaderType: "cls_loader",
            sourcePak: "initial.pak",
            phase: "CLASSES load"
        )
    ])
    let manifestData = try LoadListWriter.encodeManifest(manifest)
    let output = try temporaryDirectory(named: "synthetic-initial")
        .appendingPathComponent("initial.pak")
    let sources = try PakDirectoryScanner.sortedPackSources([
        PakFileSource(internalName: LoadListConstants.manifestEntryName, data: manifestData),
        PakFileSource(internalName: "initial.cache_block", data: Data("cache".utf8)),
        PakFileSource(internalName: "[media]\\classes\\trucks\\existing.xml", data: Data("<Truck/>".utf8)),
        PakFileSource(internalName: "[ssl_cache]\\initial_pak", data: Data("ssl".utf8)),
        PakFileSource(internalName: "[strings]\\strings_english.str", data: Data("strings".utf8))
    ])
    try PakWriter.writeArchive(fileSources: sources, to: output)
    return output
}

func makePak(named name: String, entries: [String: Data]) throws -> URL {
    let output = try temporaryDirectory(named: "pak-\(UUID().uuidString)")
        .appendingPathComponent(name)
    let sources = entries.keys.sorted().map { key in
        PakFileSource(internalName: key, data: entries[key]!)
    }
    try PakWriter.writeArchive(fileSources: sources, to: output)
    return output
}
