import Foundation
import XCTest
@testable import SnowRunnerTool

final class ModArchiveMapperTests: XCTestCase {
    func testMapperMapsMainModArchiveNamespaces() throws {
        let pak = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8),
            "prebuild/meshes/demo_mesh": Data([1, 2, 3]),
            "ui/textures/demo.png": Data([4, 5, 6])
        ])

        let mapped = try ModArchiveMapper.mapArchive(at: pak)

        XCTAssertEqual(Set(mapped.map(\.internalName)), [
            "[media]\\classes\\trucks\\demo.xml",
            "[meshes]\\demo_mesh",
            "[textures]\\demo.png"
        ])
    }

    func testMapperMapsPcPakTexturesOnly() throws {
        let pak = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/demo.pct": Data([7, 8, 9])
        ])

        let mapped = try ModArchiveMapper.mapArchive(at: pak)

        XCTAssertEqual(mapped.map(\.internalName), ["[textures]\\pct\\demo.pct"])
    }

    func testMapperRejectsTextureRootOutsidePcPak() throws {
        let pak = try makePak(named: "main-mod.pak", entries: [
            "prebuild/textures/pct/demo.pct": Data([1])
        ])

        XCTAssertThrowsError(try ModArchiveMapper.mapArchive(at: pak)) { error in
            guard case ModMergeError.unsupportedModPath = error else {
                XCTFail("expected unsupportedModPath, got \(error)")
                return
            }
        }
    }

    func testMapperRejectsNonTexturePathInsidePcPak() throws {
        let pak = try makePak(named: "pc.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])

        XCTAssertThrowsError(try ModArchiveMapper.mapArchive(at: pak)) { error in
            guard case ModMergeError.unsupportedModPath = error else {
                XCTFail("expected unsupportedModPath, got \(error)")
                return
            }
        }
    }

    func testMapperCountsLoadstarFixtureWhenAvailable() throws {
        guard let modPak = TestFixtures.optionalLoadstarJbeModPak(),
              let pcPak = TestFixtures.optionalLoadstarJbePcPak() else {
            throw XCTSkip("Loadstar JBE mod fixture is not present")
        }

        XCTAssertEqual(try ModArchiveMapper.mapArchive(at: modPak).count, 109)
        XCTAssertEqual(try ModArchiveMapper.mapArchive(at: pcPak).count, 42)
    }
}
