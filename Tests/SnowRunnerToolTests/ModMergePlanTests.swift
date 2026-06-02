import Foundation
import XCTest
@testable import SnowRunnerTool

final class ModMergePlanTests: XCTestCase {
    func testOverlayPreservesBaseRecordsAndAddsModManagedRecords() throws {
        let base = try LoadListBuilder.buildManifest(records: [
            LoadListRecord(
                manifestPath: "<meshes>\\shared_mesh",
                loaderType: "mesh_loader",
                sourcePak: "shared.pak",
                phase: "MESH load"
            )
        ])
        let mapped = [
            ModMappedEntry(
                archiveURL: URL(fileURLWithPath: "main.pak"),
                originalName: "prebuild/meshes/new_mesh",
                internalName: "[meshes]\\new_mesh",
                data: Data([1])
            ),
            ModMappedEntry(
                archiveURL: URL(fileURLWithPath: "pc.pak"),
                originalName: "prebuild/textures/new.pct",
                internalName: "[textures]\\new.pct",
                data: Data([2])
            )
        ]

        let result = try ModLoadListOverlay.overlay(baseManifest: base, mappedEntries: mapped)

        XCTAssertEqual(result.modManagedRecords.map(\.manifestPath), ["<meshes>\\new_mesh"])
        XCTAssertEqual(result.netNewRecordCount, 1)
        XCTAssertTrue(result.sourceOverrides.isEmpty)
        XCTAssertEqual(result.manifest.recordsByPhase["MESH load"]?.map(\.sourcePak).sorted(), ["initial.pak", "shared.pak"])
    }

    func testOverlayReportsSourceOverride() throws {
        let base = try LoadListBuilder.buildManifest(records: [
            LoadListRecord(
                manifestPath: "<meshes>\\same_mesh",
                loaderType: "mesh_loader",
                sourcePak: "shared.pak",
                phase: "MESH load"
            )
        ])
        let mapped = [
            ModMappedEntry(
                archiveURL: URL(fileURLWithPath: "main.pak"),
                originalName: "prebuild/meshes/same_mesh",
                internalName: "[meshes]\\same_mesh",
                data: Data([1])
            )
        ]

        let result = try ModLoadListOverlay.overlay(baseManifest: base, mappedEntries: mapped)

        XCTAssertEqual(result.netNewRecordCount, 0)
        XCTAssertEqual(result.sourceOverrides, [
            ModLoadListSourceOverride(
                manifestPath: "<meshes>\\same_mesh",
                previousSourcePak: "shared.pak",
                newSourcePak: "initial.pak"
            )
        ])
    }
}

