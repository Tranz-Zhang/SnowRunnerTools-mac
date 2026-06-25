import Foundation
import XCTest
@testable import SnowRunnerCore

final class ModRegistryXMLMergeTests: XCTestCase {
    func testWheelRegistryMergePreservesBaseTiresAndAddsModEntries() throws {
        let base = Data("""
        <TruckWheels>
            <TruckTires>
                <TruckTire Name="highway_1" Mesh="base_highway_1" />
                <TruckTire Name="highway_2" Mesh="base_highway_2" />
            </TruckTires>
            <TruckRims>
                <TruckRim Name="rim_2" Mesh="base_rim_2" />
            </TruckRims>
        </TruckWheels>
        """.utf8)
        let mod = Data("""
        <TruckWheels>
            <TruckTires>
                <TruckTire Name="offroad_1" Mesh="mod_offroad_1" />
            </TruckTires>
            <TruckRims>
                <TruckRim Name="rim_9" Mesh="mod_rim_9" />
            </TruckRims>
        </TruckWheels>
        """.utf8)

        let merged = try ModRegistryXMLMerge.merge(
            baseData: base,
            modData: mod,
            path: "[media]\\classes\\wheels\\wheels_medium_double.xml"
        )
        let text = decodedUTF8(merged)

        XCTAssertTrue(text.contains("Name=\"highway_1\""))
        XCTAssertTrue(text.contains("Name=\"highway_2\""))
        XCTAssertTrue(text.contains("Name=\"rim_2\""))
        XCTAssertTrue(text.contains("Name=\"offroad_1\""))
        XCTAssertTrue(text.contains("Name=\"rim_9\""))
    }

    func testWheelRegistryMergeReplacesMatchingModKeys() throws {
        let base = Data("""
        <TruckWheels>
            <TruckTires>
                <TruckTire Name="offroad_1" Mesh="base" />
            </TruckTires>
            <TruckRims />
        </TruckWheels>
        """.utf8)
        let mod = Data("""
        <TruckWheels>
            <TruckTires>
                <TruckTire Name="offroad_1" Mesh="mod" />
            </TruckTires>
            <TruckRims />
        </TruckWheels>
        """.utf8)

        let merged = try ModRegistryXMLMerge.merge(
            baseData: base,
            modData: mod,
            path: "[media]\\classes\\wheels\\wheels_medium_double.xml"
        )
        let text = decodedUTF8(merged)

        XCTAssertTrue(text.contains("Mesh=\"mod\""))
        XCTAssertFalse(text.contains("Mesh=\"base\""))
    }

    func testEngineRegistryMergePreservesLeadingTemplates() throws {
        let base = Data("""
        <_templates>
            <Engine><TemplateEngine /></Engine>
        </_templates>
        <EngineVariants>
            <Engine Name="engine_base" Torque="100" />
        </EngineVariants>
        """.utf8)
        let mod = Data("""
        <EngineVariants>
            <Engine Name="engine_mod" Torque="200" />
        </EngineVariants>
        """.utf8)

        let merged = try ModRegistryXMLMerge.merge(
            baseData: base,
            modData: mod,
            path: "[media]\\classes\\engines\\e_us_truck_old.xml"
        )
        let text = decodedUTF8(merged)

        XCTAssertTrue(text.contains("<_templates>"))
        XCTAssertTrue(text.contains("Name=\"engine_base\""))
        XCTAssertTrue(text.contains("Name=\"engine_mod\""))
    }

    func testWinchUiDrawIsNotRegistryMergePath() {
        XCTAssertFalse(ModRegistryXMLMerge.isSupportedRegistryPath("[media]\\classes\\winches\\winch_ui_draw.xml"))
        XCTAssertTrue(ModRegistryXMLMerge.isSupportedRegistryPath("[media]\\classes\\winches\\winches_medium_trucks.xml"))
    }
}
