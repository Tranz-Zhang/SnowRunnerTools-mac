import Foundation
import XCTest
@testable import SnowRunnerTool

final class LoadListClassifierTests: XCTestCase {
    func testClassifierRecognizesKnownEntryShapes() throws {
        let cls = try LoadListClassifier.classify(.init(
            internalName: "[media]\\classes\\trucks\\hummer_h2.xml",
            sourcePak: "initial.pak"
        ))
        XCTAssertEqual(cls?.loaderType, "cls_loader")
        XCTAssertEqual(cls?.phase, "CLASSES load")
        XCTAssertEqual(cls?.manifestPath, "<media>\\classes\\trucks\\hummer_h2.xml")
        XCTAssertEqual(cls?.sourcePak, "initial.pak")

        let tpl = try LoadListClassifier.classify(.init(
            internalName: "[media]\\_templates\\trucks.xml",
            sourcePak: "initial.pak"
        ))
        XCTAssertEqual(tpl?.loaderType, "tpl_loader")
        XCTAssertEqual(tpl?.phase, "TEMPLATES load")
        XCTAssertEqual(tpl?.manifestPath, "<media>\\_templates\\trucks.xml")

        let ssl = try LoadListClassifier.classify(.init(
            internalName: "[ssl_cache]\\initial_debug.sslbundle",
            sourcePak: "initial.pak"
        ))
        XCTAssertEqual(ssl?.loaderType, "sslbundle")
        XCTAssertEqual(ssl?.phase, "SSL_INITIAL load")
        XCTAssertEqual(ssl?.manifestPath, "<ssl_cache>\\initial_debug.sslbundle")

        let spdb = try LoadListClassifier.classify(.init(
            internalName: "[ssl_cache]\\initial_debug.spdb",
            sourcePak: "shared_debug.pak"
        ))
        XCTAssertEqual(spdb?.loaderType, "spdb")
        XCTAssertEqual(spdb?.phase, "SSL_INITIAL load")
        XCTAssertEqual(spdb?.sourcePak, "shared_debug.pak")

        let mesh = try LoadListClassifier.classify(.init(
            internalName: "[meshes]\\env_arrow",
            sourcePak: "shared.pak"
        ))
        XCTAssertEqual(mesh?.loaderType, "mesh_loader")
        XCTAssertEqual(mesh?.phase, "MESH load")
        XCTAssertEqual(mesh?.manifestPath, "<meshes>\\env_arrow")

        let sound = try LoadListClassifier.classify(.init(
            internalName: "sound.sound_list",
            sourcePak: "shared_sound.pak"
        ))
        XCTAssertEqual(sound?.loaderType, "sound_loader")
        XCTAssertEqual(sound?.phase, "SOUND load")
        XCTAssertEqual(sound?.manifestPath, "sound.sound_list")
    }

    func testClassifierSkipsManifestAndCacheBlockAndUnknownAuxEntries() throws {
        XCTAssertNil(try LoadListClassifier.classify(.init(
            internalName: "pak.load_list",
            sourcePak: "initial.pak"
        )))
        XCTAssertNil(try LoadListClassifier.classify(.init(
            internalName: "initial.cache_block",
            sourcePak: "initial.pak"
        )))
        XCTAssertNil(try LoadListClassifier.classify(.init(
            internalName: "[strings]\\strings_english.str",
            sourcePak: "initial.pak"
        )))
        XCTAssertNil(try LoadListClassifier.classify(.init(
            internalName: "[ssl_cache]\\initial_pak",
            sourcePak: "initial.pak"
        )))
    }

    func testClassifierThrowsForUnknownEntryShape() {
        XCTAssertThrowsError(try LoadListClassifier.classify(.init(
            internalName: "[media]\\foo\\bar.txt",
            sourcePak: "initial.pak"
        ))) { error in
            guard case LoadListError.invalidManifestPath = error else {
                XCTFail("expected invalidManifestPath, got \(error)")
                return
            }
        }
    }
}
