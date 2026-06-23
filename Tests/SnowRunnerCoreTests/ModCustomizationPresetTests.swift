import Foundation
import XCTest
@testable import SnowRunnerCore

final class ModCustomizationPresetTests: XCTestCase {
    func testMergeAppendsNewModTruckAndPreservesBaseTrucks() throws {
        let base = customizationPresetData([
            truckXML(name: "base_a", marker: "base-a"),
            truckXML(name: "base_b", marker: "base-b")
        ])
        let mod = customizationPresetData([
            truckXML(name: "mod_c", marker: "mod-c")
        ])

        let merged = try ModCustomizationPreset.merge(
            baseData: base,
            modData: mod,
            path: "[media]\\classes\\customization_presets\\customization_preset.xml"
        )
        let text = decodedUTF8(merged)

        XCTAssertTrue(text.contains("Name=\"base_a\""))
        XCTAssertTrue(text.contains("Name=\"base_b\""))
        XCTAssertTrue(text.contains("Name=\"mod_c\""))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "Name=\"base_a\"")?.lowerBound),
                          try XCTUnwrap(text.range(of: "Name=\"base_b\"")?.lowerBound))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "Name=\"base_b\"")?.lowerBound),
                          try XCTUnwrap(text.range(of: "Name=\"mod_c\"")?.lowerBound))
    }

    func testMergeReplacesExistingTruckBlockByName() throws {
        let base = customizationPresetData([
            truckXML(name: "base_a", marker: "base-a"),
            truckXML(name: "base_b", marker: "old")
        ])
        let mod = customizationPresetData([
            truckXML(name: "base_b", marker: "new")
        ])

        let merged = try ModCustomizationPreset.merge(
            baseData: base,
            modData: mod,
            path: "[media]\\classes\\customization_presets\\customization_preset.xml"
        )
        let text = decodedUTF8(merged)

        XCTAssertTrue(text.contains("Name=\"base_a\""))
        XCTAssertTrue(text.contains("Marker=\"new\""))
        XCTAssertFalse(text.contains("Marker=\"old\""))
    }

    func testMergeCombinesMultipleModCustomizationFiles() throws {
        let first = customizationPresetData([
            truckXML(name: "mod_a", marker: "a")
        ])
        let second = customizationPresetData([
            truckXML(name: "mod_b", marker: "b")
        ])

        let mergedMods = try ModCustomizationPreset.merge(
            baseData: first,
            modData: second,
            path: "[media]\\classes\\customization_presets\\customization_preset.xml"
        )
        let merged = try ModCustomizationPreset.merge(
            baseData: customizationPresetData([truckXML(name: "base", marker: "base")]),
            modData: mergedMods,
            path: "[media]\\classes\\customization_presets\\customization_preset.xml"
        )
        let text = decodedUTF8(merged)

        XCTAssertTrue(text.contains("Name=\"base\""))
        XCTAssertTrue(text.contains("Name=\"mod_a\""))
        XCTAssertTrue(text.contains("Name=\"mod_b\""))
    }

    func testMergeUsesLaterTruckWhenMultipleModsDefineSameName() throws {
        let first = customizationPresetData([
            truckXML(name: "same", marker: "first")
        ])
        let second = customizationPresetData([
            truckXML(name: "same", marker: "second")
        ])

        let merged = try ModCustomizationPreset.merge(
            baseData: first,
            modData: second,
            path: "[media]\\classes\\customization_presets\\customization_preset.xml"
        )
        let text = decodedUTF8(merged)

        XCTAssertTrue(text.contains("Marker=\"second\""))
        XCTAssertFalse(text.contains("Marker=\"first\""))
    }

    func testMergeRepairsDuplicateTintColorAttributesInCustomizationPresets() throws {
        let mod = Data("""
        <TruckSet>
            <Truck Name="bad_tint">
                <CustomizationPreset
                    Id="40"
                    TintColor1="g(45; 45; 45)"
                    TintColor1="g(205; 178; 21)"
                    TintColor1="g(205; 178; 21)"
                    MaterialOverrideName="skin_00"
                />
                <CustomizationPreset
                    Id="42"
                    TintColor1="g(67; 93; 151)"
                    TintColor1="g(200; 200; 200)"
                    TintColor3="g(209; 204; 199)"
                    MaterialOverrideName="skin_00"
                />
            </Truck>
        </TruckSet>
        """.utf8)

        let merged = try ModCustomizationPreset.merge(
            baseData: Data("<TruckSet/>".utf8),
            modData: mod,
            path: "[media]\\classes\\customization_presets\\customization_preset.xml"
        )
        let text = decodedUTF8(merged)

        XCTAssertTrue(text.contains("TintColor1=\"g(45; 45; 45)\""))
        XCTAssertTrue(text.contains("TintColor2=\"g(205; 178; 21)\""))
        XCTAssertTrue(text.contains("TintColor3=\"g(205; 178; 21)\""))
        XCTAssertTrue(text.contains("TintColor1=\"g(67; 93; 151)\""))
        XCTAssertTrue(text.contains("TintColor2=\"g(200; 200; 200)\""))
        XCTAssertTrue(text.contains("TintColor3=\"g(209; 204; 199)\""))
    }

    func testMergeRejectsInvalidRoot() throws {
        XCTAssertThrowsError(try ModCustomizationPreset.merge(
            baseData: Data("<Invalid/>".utf8),
            modData: customizationPresetData([truckXML(name: "mod", marker: "mod")]),
            path: "[media]\\classes\\customization_presets\\customization_preset.xml"
        )) { error in
            guard case let ModMergeError.invalidCustomizationPreset(path, reason) = error else {
                XCTFail("expected invalidCustomizationPreset, got \(error)")
                return
            }
            XCTAssertEqual(path, "[media]\\classes\\customization_presets\\customization_preset.xml")
            XCTAssertTrue(reason.contains("TruckSet"))
        }
    }

    func testMergeRejectsTruckWithoutName() throws {
        XCTAssertThrowsError(try ModCustomizationPreset.merge(
            baseData: customizationPresetData([truckXML(name: "base", marker: "base")]),
            modData: Data("<TruckSet><Truck /></TruckSet>".utf8),
            path: "[media]\\classes\\customization_presets\\customization_preset.xml"
        )) { error in
            guard case let ModMergeError.invalidCustomizationPreset(path, reason) = error else {
                XCTFail("expected invalidCustomizationPreset, got \(error)")
                return
            }
            XCTAssertEqual(path, "[media]\\classes\\customization_presets\\customization_preset.xml")
            XCTAssertTrue(reason.contains("Name"))
        }
    }
}

func customizationPresetData(_ trucks: [String]) -> Data {
    Data(("<TruckSet>\n" + trucks.joined(separator: "\n") + "\n</TruckSet>\n").utf8)
}

func truckXML(name: String, marker: String) -> String {
    """
    <Truck Name="\(name)">
        <CustomizationPreset Id="0" Marker="\(marker)" />
    </Truck>
    """
}

func decodedUTF8(_ data: Data) -> String {
    String(data: data, encoding: .utf8)!
}
