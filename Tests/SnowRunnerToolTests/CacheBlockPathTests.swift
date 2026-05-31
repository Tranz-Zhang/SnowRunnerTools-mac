import XCTest
@testable import SnowRunnerTool

final class CacheBlockPathTests: XCTestCase {
    func testInternalNamesMapToExternalPaths() throws {
        XCTAssertEqual(try CacheBlockPath.externalPath(forInternalName: "<ps>:hud.xml"), "[ps]/hud.xml")
        XCTAssertEqual(try CacheBlockPath.externalPath(forInternalName: "<strings>\\ui\\menu.str"), "[strings]/ui/menu.str")
    }

    func testExternalPathsMapToInternalNames() throws {
        XCTAssertEqual(try CacheBlockPath.internalName(forExternalPath: "[ps]/hud.xml"), "<ps>:hud.xml")
        XCTAssertEqual(try CacheBlockPath.internalName(forExternalPath: "[strings]/ui/menu.str"), "<strings>\\ui\\menu.str")
    }

    func testRejectsUnsafeCacheBlockNames() {
        XCTAssertThrowsError(try CacheBlockPath.externalPath(forInternalName: "ps:hud.xml"))
        XCTAssertThrowsError(try CacheBlockPath.externalPath(forInternalName: "<ps>\\..\\hud.xml"))
        XCTAssertThrowsError(try CacheBlockPath.internalName(forExternalPath: "/[ps]/hud.xml"))
        XCTAssertThrowsError(try CacheBlockPath.internalName(forExternalPath: "[ps]/../hud.xml"))
    }
}
