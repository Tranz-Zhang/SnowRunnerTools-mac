import Foundation
import XCTest
@testable import SnowRunnerCore

final class ModArchiveMapperTests: XCTestCase {
    func testMapperMapsMainModArchiveNamespaces() throws {
        let pak = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8),
            "prebuild/meshes/demo_mesh": Data([1, 2, 3]),
            "ui/textures/demo.png": Data([4, 5, 6]),
            "texts/strings_english.str": Data("Text".utf8)
        ])

        let mapped = try ModArchiveMapper.mapArchive(at: pak)

        XCTAssertEqual(
            Set(mapped.map { "\($0.targetArchive.rawValue):\($0.internalName)" }),
            [
                "initial.pak:[media]\\classes\\trucks\\demo.xml",
                "initial.pak:[meshes]\\demo_mesh",
                "shared_textures_base.pak:[textures]\\demo.png",
                "initial.pak:[strings]\\strings_english.str"
            ]
        )
    }

    func testMapperMapsTexturePakByContentNotFilename() throws {
        let pak = try makePak(named: "colorable_sideboards-flatbeds_pc.pak", entries: [
            "prebuild/textures/pct/demo.pct": makeSyntheticPCT(tableCount: 10)
        ])

        let mapped = try ModArchiveMapper.mapArchive(at: pak)

        XCTAssertEqual(mapped.map(\.internalName), [
            "[textures]\\pct\\demo.pct",
            "[textures]\\pct\\demo.pct_header"
        ])
        XCTAssertEqual(mapped.map(\.targetArchive), [.sharedTextures, .sharedTextures])
    }

    func testMapperMapsExactPcPakByContent() throws {
        let pak = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/demo.pct": makeSyntheticPCT(tableCount: 11)
        ])

        let mapped = try ModArchiveMapper.mapArchive(at: pak)

        XCTAssertEqual(mapped.map(\.internalName), [
            "[textures]\\pct\\demo.pct",
            "[textures]\\pct\\demo.pct_header"
        ])
        XCTAssertEqual(mapped.map(\.targetArchive), [.sharedTextures, .sharedTextures])
    }

    func testMapperRejectsMixedTextureAndMainModArchive() throws {
        let pak = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8),
            "prebuild/textures/pct/demo.pct": makeSyntheticPCT(tableCount: 1)
        ])

        XCTAssertThrowsError(try ModArchiveMapper.mapArchive(at: pak)) { error in
            guard case ModMergeError.unsupportedModPath = error else {
                XCTFail("expected unsupportedModPath, got \(error)")
                return
            }
        }
    }

    func testDirectoryMapperMapsMixedMainAndTextureSourcesByPath() throws {
        let workspace = try temporaryDirectory(named: "mixed-directory-workspace")
        let modRoot = workspace.appendingPathComponent("mods/demo", isDirectory: true)
        let pct = makeSyntheticPCT(tableCount: 2)
        try writeFile(root: modRoot, relativePath: "classes/trucks/demo.xml", data: Data("<Truck/>".utf8))
        try writeFile(root: modRoot, relativePath: "prebuild/textures/pct/demo.pct", data: pct)

        let mapped = try ModArchiveMapper.mapDirectory(
            at: modRoot,
            archiveName: "demo.pak",
            sourceCache: nil,
            sourceEntries: [],
            workspaceRoot: workspace
        )

        XCTAssertEqual(
            Set(mapped.map { "\($0.targetArchive.rawValue):\($0.internalName)" }),
            [
                "initial.pak:[media]\\classes\\trucks\\demo.xml",
                "shared_textures.pak:[textures]\\pct\\demo.pct",
                "shared_textures.pak:[textures]\\pct\\demo.pct_header"
            ]
        )
    }

    func testDirectoryMapperMapsTextOnlySourcesAsMainContent() throws {
        let workspace = try temporaryDirectory(named: "text-directory-workspace")
        let modRoot = workspace.appendingPathComponent("mods/TiresCargo", isDirectory: true)
        try writeFile(root: modRoot, relativePath: "texts/strings_english.str", data: Data("KEY\t\t\"Value\"".utf8))

        let mapped = try ModArchiveMapper.mapDirectory(
            at: modRoot,
            archiveName: "TiresCargo.pak",
            sourceCache: nil,
            sourceEntries: [],
            workspaceRoot: workspace
        )

        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].targetArchive, .initial)
        XCTAssertEqual(mapped[0].internalName, "[strings]\\strings_english.str")
    }

    func testMapperCountsLoadstarFixtureWhenAvailable() throws {
        guard let modPak = TestFixtures.optionalLoadstarJbeModPak(),
              let pcPak = TestFixtures.optionalLoadstarJbePcPak() else {
            throw XCTSkip("Loadstar JBE mod fixture is not present")
        }

        XCTAssertEqual(try ModArchiveMapper.mapArchive(at: modPak).count, 106)
        XCTAssertEqual(try ModArchiveMapper.mapArchive(at: pcPak).count, 84)
    }

    func testMapperMapsTextFixtureAndSkipsDirectoryEntryWhenAvailable() throws {
        guard let textPak = TestFixtures.optionalTextPak() else {
            throw XCTSkip("text.pak fixture is not present")
        }

        let mapped = try ModArchiveMapper.mapArchive(at: textPak)

        XCTAssertEqual(mapped.count, 13)
        XCTAssertTrue(mapped.contains {
            $0.originalName == "texts/strings_english.str"
                && $0.internalName == "[strings]\\strings_english.str"
        })
        XCTAssertFalse(mapped.contains { $0.originalName == "texts/" })
    }
}
