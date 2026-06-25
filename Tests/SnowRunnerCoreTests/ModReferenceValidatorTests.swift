import Foundation
@testable import SnowRunnerCore
import XCTest

final class ModReferenceValidatorTests: XCTestCase {
    func testMissingTireFailsWithPreciseIssue() throws {
        let issues = try validationIssues(for: [
            source("[media]\\classes\\wheels\\wheels_medium_double.xml", wheelRegistry(tires: ["highway_2"], rims: ["rim_2"])),
            source("[media]\\classes\\trucks\\western_star_49x.xml", truckWheels(defaultTire: "highway_1", defaultRim: "rim_2"))
        ])

        XCTAssertTrue(issues.contains {
            $0.sourcePath == "[media]\\classes\\trucks\\western_star_49x.xml"
                && $0.referencedCategory == "tire"
                && $0.missingValue == "highway_1"
                && $0.explanation.contains("wheels_medium_double")
        })
    }

    func testMissingRimFailsWithPreciseIssue() throws {
        let issues = try validationIssues(for: [
            source("[media]\\classes\\wheels\\wheels_medium_double.xml", wheelRegistry(tires: ["highway_1"], rims: ["rim_1"])),
            source("[media]\\classes\\trucks\\western_star_49x.xml", truckWheels(defaultTire: "highway_1", defaultRim: "rim_2"))
        ])

        XCTAssertTrue(issues.contains {
            $0.sourcePath == "[media]\\classes\\trucks\\western_star_49x.xml"
                && $0.referencedCategory == "rim"
                && $0.missingValue == "rim_2"
                && $0.explanation.contains("wheels_medium_double")
        })
    }

    func testWheelRegistryParentResolvesInheritedTires() throws {
        try ModReferenceValidator.validateInitialSources([
            source("[media]\\classes\\wheels\\wheels_superheavy_single.xml", wheelRegistry(tires: ["mudtires_cat745"], rims: ["rim_cat745"])),
            source(
                "[media]\\classes\\wheels\\wheels_superheavy_cat745_single.xml",
                """
                <_parent File="wheels_superheavy_single" />
                <TruckWheels>
                    <TruckRims>
                        <TruckRim Name="rim_cat745" />
                    </TruckRims>
                </TruckWheels>
                """
            ),
            source(
                "[media]\\classes\\trucks\\cat_745c.xml",
                """
                <Truck>
                    <TruckData>
                        <Wheels DefaultWheelType="wheels_superheavy_cat745_single" DefaultTire="mudtires_cat745" DefaultRim="rim_cat745" />
                    </TruckData>
                </Truck>
                """
            )
        ])
    }

    func testMissingEngineDefaultFailsWithPreciseIssue() throws {
        let issues = try validationIssues(for: [
            source("[media]\\classes\\engines\\e_us_truck_old.xml", engineRegistry(names: ["engine_available"])),
            source("[media]\\classes\\trucks\\western_star_49x.xml", socketTruck(socketName: "EngineSocket", type: "e_us_truck_old", defaultValue: "engine_missing"))
        ])

        XCTAssertIssue(issues, category: "engine", missingValue: "engine_missing")
    }

    func testMissingGearboxDefaultFailsWithPreciseIssue() throws {
        let issues = try validationIssues(for: [
            source("[media]\\classes\\gearboxes\\gearboxes_trucks.xml", gearboxRegistry(names: ["g_truck_default"])),
            source("[media]\\classes\\trucks\\western_star_49x.xml", socketTruck(socketName: "GearboxSocket", type: "gearboxes_trucks", defaultValue: "g_truck_missing"))
        ])

        XCTAssertIssue(issues, category: "gearbox", missingValue: "g_truck_missing")
    }

    func testMissingSuspensionDefaultFailsWithPreciseIssue() throws {
        let issues = try validationIssues(for: [
            source("[media]\\classes\\suspensions\\s_western_star_49x.xml", suspensionRegistry(names: ["suspension_default"])),
            source("[media]\\classes\\trucks\\western_star_49x.xml", socketTruck(socketName: "SuspensionSocket", type: "s_western_star_49x", defaultValue: "suspension_missing"))
        ])

        XCTAssertIssue(issues, category: "suspension", missingValue: "suspension_missing")
    }

    func testMissingWinchDefaultFailsWithPreciseIssue() throws {
        let issues = try validationIssues(for: [
            source("[media]\\classes\\winches\\winches_medium_trucks.xml", winchRegistry(names: ["w_medium_trucks_default"])),
            source("[media]\\classes\\trucks\\western_star_49x.xml", socketTruck(socketName: "WinchUpgradeSocket", type: "winches_medium_trucks", defaultValue: "w_medium_trucks_missing"))
        ])

        XCTAssertIssue(issues, category: "winch", missingValue: "w_medium_trucks_missing")
    }

    func testUnresolvedParentFileFails() throws {
        let issues = try validationIssues(for: [
            source("[media]\\classes\\trucks\\addons\\child_addon.xml", #"<_parent File="missing_parent" />"#)
        ])

        XCTAssertIssue(issues, category: "parent class", missingValue: "missing_parent")
    }

    func testUnresolvedDefaultAddonFails() throws {
        let issues = try validationIssues(for: [
            source("[media]\\classes\\trucks\\western_star_49x.xml", #"<Truck><GameData><AddonSockets DefaultAddon="missing_addon" /></GameData></Truck>"#)
        ])

        XCTAssertIssue(issues, category: "default addon", missingValue: "missing_addon")
    }

    func testParsesEachXMLSourceNoMoreThanOnce() throws {
        let sources = [
            source("[media]\\classes\\wheels\\wheels_medium_double.xml", wheelRegistry(tires: ["highway_1"], rims: ["rim_2"])),
            source(
                "[media]\\classes\\trucks\\western_star_49x.xml",
                """
                <Truck>
                    <TruckData>
                        <Wheels DefaultWheelType="wheels_medium_double" DefaultTire="highway_1" DefaultRim="rim_2" />
                        <ExtraWheels WheelType="wheels_medium_double" Tire="highway_1" Rim="rim_2" />
                        <ExtraWheels WheelType="wheels_medium_double" Tire="highway_1" Rim="rim_2" />
                    </TruckData>
                </Truck>
                """
            )
        ]
        var parseCounts: [String: Int] = [:]

        try ModReferenceValidator.validateInitialSources(sources) { data, path in
            parseCounts[path, default: 0] += 1
            return try XMLDocument(data: data, options: [])
        }

        XCTAssertEqual(parseCounts["[media]\\classes\\wheels\\wheels_medium_double.xml"], 1)
        XCTAssertEqual(parseCounts["[media]\\classes\\trucks\\western_star_49x.xml"], 1)
    }

    private func validationIssues(for sources: [PakFileSource]) throws -> [ModReferenceIssue] {
        do {
            try ModReferenceValidator.validateInitialSources(sources)
            XCTFail("Expected broken reference validation to fail")
            return []
        } catch let ModMergeError.brokenMergedReferences(issues) {
            return issues
        }
    }

    private func XCTAssertIssue(
        _ issues: [ModReferenceIssue],
        category: String,
        missingValue: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            issues.contains {
                ($0.sourcePath == "[media]\\classes\\trucks\\western_star_49x.xml"
                    || $0.sourcePath == "[media]\\classes\\trucks\\addons\\child_addon.xml")
                    && $0.referencedCategory == category
                    && $0.missingValue == missingValue
            },
            "Missing issue \(category): \(missingValue) in \(issues)",
            file: file,
            line: line
        )
    }

    private func source(_ internalName: String, _ xml: String) -> PakFileSource {
        PakFileSource(internalName: internalName, data: Data(xml.utf8))
    }

    private func wheelRegistry(tires: [String], rims: [String]) -> String {
        """
        <TruckWheels>
            <TruckTires>
                \(tires.map { #"<TruckTire Name="\#($0)" />"# }.joined(separator: "\n"))
            </TruckTires>
            <TruckRims>
                \(rims.map { #"<TruckRim Name="\#($0)" />"# }.joined(separator: "\n"))
            </TruckRims>
        </TruckWheels>
        """
    }

    private func truckWheels(defaultTire: String, defaultRim: String) -> String {
        """
        <Truck>
            <TruckData>
                <Wheels DefaultWheelType="wheels_medium_double" DefaultTire="\(defaultTire)" DefaultRim="\(defaultRim)" />
            </TruckData>
        </Truck>
        """
    }

    private func socketTruck(socketName: String, type: String, defaultValue: String) -> String {
        """
        <Truck>
            <TruckData>
                <\(socketName) Type="\(type)" Default="\(defaultValue)" />
            </TruckData>
        </Truck>
        """
    }

    private func engineRegistry(names: [String]) -> String {
        "<EngineVariants>\(names.map { #"<Engine Name="\#($0)" />"# }.joined())</EngineVariants>"
    }

    private func gearboxRegistry(names: [String]) -> String {
        "<GearboxVariants>\(names.map { #"<Gearbox Name="\#($0)" />"# }.joined())</GearboxVariants>"
    }

    private func suspensionRegistry(names: [String]) -> String {
        "<SuspensionSetVariants>\(names.map { #"<SuspensionSet Name="\#($0)" />"# }.joined())</SuspensionSetVariants>"
    }

    private func winchRegistry(names: [String]) -> String {
        "<WinchVariants>\(names.map { #"<Winch Name="\#($0)" />"# }.joined())</WinchVariants>"
    }
}
