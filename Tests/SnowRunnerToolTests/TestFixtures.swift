import Foundation
@testable import SnowRunnerTool

enum TestFixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let initialPak = root.appendingPathComponent("fixtures/initial.pak")
    static let initialRepackedPak = root.appendingPathComponent("fixtures/initial.repacked.pak")
    static let loadstarJbeModPak = root.appendingPathComponent("fixtures/loadstar_1700_jbe_pc.1/loadstar_1700_jbe.pak")
    static let loadstarJbePcPak = root.appendingPathComponent("fixtures/loadstar_1700_jbe_pc.1/pc.pak")
    static let rootLoadstarJbeModPak = root.appendingPathComponent("fixtures/loadstar_1700_jbe.pak")
    static let rootLoadstarJbePcPak = root.appendingPathComponent("fixtures/loadstar_1700_jbe_pc.pak")
    static let textPak = root.appendingPathComponent("fixtures/text.pak")

    static func extractInitialCacheBlock(from pakURL: URL) throws -> URL {
        let archive = try PakReader.readArchive(at: pakURL)
        guard let entry = archive.entries.first(where: { $0.name == "initial.cache_block" }) else {
            throw CacheBlockError.missingInitialCacheBlock
        }

        let output = try temporaryDirectory(named: "cache-block-fixture")
            .appendingPathComponent("initial.cache_block")
        try PakReader.readUncompressedPayload(entry: entry, in: archive).write(to: output)
        return output
    }

    static func extractPakLoadList(from pakURL: URL) throws -> URL {
        let archive = try PakReader.readArchive(at: pakURL)
        guard let entry = archive.entries.first(where: { $0.name == LoadListConstants.manifestEntryName }) else {
            throw LoadListError.missingManifestEntry
        }
        let output = try temporaryDirectory(named: "load-list-fixture")
            .appendingPathComponent(LoadListConstants.manifestEntryName)
        try PakReader.readUncompressedPayload(entry: entry, in: archive).write(to: output)
        return output
    }

    static func optionalCompactReferenceReport() -> URL? {
        let url = root.appendingPathComponent("fixtures/reports/load-list-compact.txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func optionalSharedPak() -> URL? {
        let url = root.appendingPathComponent("fixtures/shared.pak")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func optionalSharedSoundPak() -> URL? {
        let url = root.appendingPathComponent("fixtures/shared_sound.pak")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func optionalLoadstarJbeModPak() -> URL? {
        if FileManager.default.fileExists(atPath: loadstarJbeModPak.path) {
            return loadstarJbeModPak
        }
        return FileManager.default.fileExists(atPath: rootLoadstarJbeModPak.path) ? rootLoadstarJbeModPak : nil
    }

    static func optionalLoadstarJbePcPak() -> URL? {
        if FileManager.default.fileExists(atPath: loadstarJbePcPak.path) {
            return loadstarJbePcPak
        }
        return FileManager.default.fileExists(atPath: rootLoadstarJbePcPak.path) ? rootLoadstarJbePcPak : nil
    }

    static func optionalTextPak() -> URL? {
        FileManager.default.fileExists(atPath: textPak.path) ? textPak : nil
    }
}

func temporaryDirectory(named name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnowRunnerToolTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
    return base
}

func writeFile(root: URL, relativePath: String, data: Data) throws {
    let fileURL = relativePath
        .split(separator: "/")
        .reduce(root) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try data.write(to: fileURL)
}
