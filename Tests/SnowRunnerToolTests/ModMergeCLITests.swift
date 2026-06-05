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
            "--input-initial",
            base.path,
            "--output-initial",
            output.path,
            "--mods",
            mod.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("merged 1 mod entries"))
        XCTAssertTrue(result.stdout.contains("dry-run initial: no output written"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCLIMergeModRejectsMissingArguments() {
        let result = CLI.run(arguments: ["pak", "merge-mod"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool pak merge-mod"))
    }

    func testCLIMergeModWritesInitialAndTextureOutputsWithNamedSyntax() throws {
        let base = try makeSyntheticInitialPak()
        let baseTextures = try makeSyntheticSharedTexturesPak(entries: [:])
        let baseSharedTextures = try makeSyntheticHighSharedTexturesPak(entries: [:])
        let mod = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/new.xml": Data("<Truck/>".utf8),
            "ui/textures/icon.png": Data([4, 5, 6])
        ])
        let pc = try makePak(named: "colorable_sideboards-flatbeds_pc.pak", entries: [
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 11)
        ])
        let output = try temporaryDirectory(named: "cli-merge-output")
            .appendingPathComponent("initial.merged.pak")
        let outputTextures = try temporaryDirectory(named: "cli-merge-textures-output")
            .appendingPathComponent("shared_textures_base.merged.pak")
        let outputSharedTextures = try temporaryDirectory(named: "cli-merge-shared-textures-output")
            .appendingPathComponent("shared_textures.merged.pak")

        let result = CLI.run(arguments: [
            "pak", "merge-mod",
            "--input-initial", base.path,
            "--output-initial", output.path,
            "--input-textures", baseTextures.path,
            "--output-textures", outputTextures.path,
            "--input-shared-textures", baseSharedTextures.path,
            "--output-shared-textures", outputSharedTextures.path,
            "--mods", mod.path, pc.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputTextures.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputSharedTextures.path))
        XCTAssertTrue(result.stdout.contains("written initial: \(output.path)"))
        XCTAssertTrue(result.stdout.contains("written textures: \(outputTextures.path)"))
        XCTAssertTrue(result.stdout.contains("written shared textures: \(outputSharedTextures.path)"))
    }

    func testCLIMergeModPCTTextureMergeRequiresSharedTextureArguments() throws {
        let base = try makeSyntheticInitialPak()
        let pc = try makePak(named: "renamed_texture_archive.pak", entries: [
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 10)
        ])
        let output = try temporaryDirectory(named: "cli-merge-output")
            .appendingPathComponent("initial.merged.pak")

        let result = CLI.run(arguments: [
            "pak", "merge-mod",
            "--input-initial", base.path,
            "--output-initial", output.path,
            "--mods", pc.path
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("PCT texture merge requires --input-shared-textures and --output-shared-textures"))
    }

    func testCLIMergeModRejectsOldPositionalSyntax() throws {
        let base = try makeSyntheticInitialPak()
        let mod = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/new.xml": Data("<Truck/>".utf8)
        ])
        let output = try temporaryDirectory(named: "cli-merge-output")
            .appendingPathComponent("initial.merged.pak")

        let result = CLI.run(arguments: [
            "pak", "merge-mod",
            base.path,
            output.path,
            mod.path
        ])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--input-initial"))
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

func makeSyntheticSharedTexturesPak(entries: [String: Data]) throws -> URL {
    let output = try temporaryDirectory(named: "synthetic-shared-textures")
        .appendingPathComponent("shared_textures_base.pak")
    let sources = try PakDirectoryScanner.sortedPackSources(
        entries.keys.sorted().map { key in
            PakFileSource(internalName: key, data: entries[key]!)
        },
        requirePakLoadList: false
    )
    try PakWriter.writeArchive(fileSources: sources, to: output)
    return output
}

func makeSyntheticHighSharedTexturesPak(entries: [String: Data]) throws -> URL {
    let output = try temporaryDirectory(named: "synthetic-high-shared-textures")
        .appendingPathComponent("shared_textures.pak")
    let sources = try PakDirectoryScanner.sortedPackSources(
        entries.keys.sorted().map { key in
            PakFileSource(internalName: key, data: entries[key]!)
        },
        requirePakLoadList: false
    )
    try PakWriter.writeArchive(fileSources: sources, to: output)
    return output
}
