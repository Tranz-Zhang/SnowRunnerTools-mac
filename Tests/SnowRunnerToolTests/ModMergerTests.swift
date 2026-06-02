import Foundation
import XCTest
@testable import SnowRunnerTool

final class ModMergerTests: XCTestCase {
    func testMergerRequiresOverwriteForBaseCollision() throws {
        let base = try makeSyntheticInitialPak()
        let mod = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/existing.xml": Data("<Truck mod=\"true\"/>".utf8)
        ])
        let output = try temporaryDirectory(named: "merge-output")
            .appendingPathComponent("initial.merged.pak")

        XCTAssertThrowsError(try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            modPaks: [mod],
            options: ModMergeOptions(allowOverwrite: false)
        )) { error in
            guard case ModMergeError.overwriteRequired = error else {
                XCTFail("expected overwriteRequired, got \(error)")
                return
            }
        }
    }

    func testMergerWritesVerifiedMergedPak() throws {
        let base = try makeSyntheticInitialPak()
        let mod = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/existing.xml": Data("<Truck mod=\"true\"/>".utf8),
            "prebuild/meshes/new_mesh": Data([1, 2, 3]),
            "ui/textures/icon.png": Data([4, 5, 6]),
            "texts/strings_english.str": Data("Merged strings".utf8)
        ])
        let pc = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/new_texture.pct": Data([7, 8, 9])
        ])
        let output = try temporaryDirectory(named: "merge-output")
            .appendingPathComponent("initial.merged.pak")

        let result = try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            modPaks: [mod, pc],
            options: ModMergeOptions(allowOverwrite: true)
        )

        XCTAssertEqual(result.plan.mappedModEntryCount, 5)
        XCTAssertEqual(result.plan.collisions, [
            "[media]\\classes\\trucks\\existing.xml",
            "[strings]\\strings_english.str"
        ])
        XCTAssertEqual(result.plan.netNewOuterPakEntryCount, 3)
        XCTAssertEqual(result.plan.loadListCandidateRecords.count, 2)
        XCTAssertEqual(result.plan.netNewLoadListRecordCount, 1)

        let archive = try PakReader.readArchive(at: output)
        XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
        XCTAssertTrue(archive.entries.contains { $0.name == "[meshes]\\new_mesh" })
        XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct" })
        XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\icon.png" })
        XCTAssertTrue(archive.entries.contains { $0.name == "[strings]\\strings_english.str" })

        let manifestEntry = try XCTUnwrap(archive.entries.first { $0.name == LoadListConstants.manifestEntryName })
        let manifestData = try PakReader.readUncompressedPayload(entry: manifestEntry, in: archive)
        let manifest = try LoadListReader.readManifest(data: manifestData)
        let meshRecords = manifest.recordsByPhase["MESH load"] ?? []
        XCTAssertTrue(meshRecords.contains {
            $0.manifestPath == "<meshes>\\new_mesh"
                && $0.loaderType == "mesh_loader"
                && $0.sourcePak == "initial.pak"
        })
        let textureRecords = manifest.phaseOrder.flatMap { manifest.recordsByPhase[$0] ?? [] }
            .filter { $0.manifestPath.contains("<textures>") || $0.manifestPath.contains("<ui>") || $0.manifestPath.contains("<strings>") }
        XCTAssertTrue(textureRecords.isEmpty)
    }
}
