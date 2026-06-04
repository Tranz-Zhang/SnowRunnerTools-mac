import Foundation
import zlib

public enum ModMergeTargetArchive: String, Equatable {
    case initial = "initial.pak"
    case sharedTextures = "shared_textures_base.pak"
}

public struct ModMappedEntry: Equatable {
    public let archiveURL: URL
    public let originalName: String
    public let internalName: String
    public let targetArchive: ModMergeTargetArchive
    public let data: Data

    public init(
        archiveURL: URL,
        originalName: String,
        internalName: String,
        targetArchive: ModMergeTargetArchive = .initial,
        data: Data
    ) {
        self.archiveURL = archiveURL
        self.originalName = originalName
        self.internalName = internalName
        self.targetArchive = targetArchive
        self.data = data
    }
}

public enum ModArchiveMapper {
    public static func mapArchive(at url: URL) throws -> [ModMappedEntry] {
        let archive = try PakReader.readArchive(at: url)
        try validateModArchive(archive)

        let role = try role(for: archive)
        var mapped: [ModMappedEntry] = []
        mapped.reserveCapacity(archive.entries.count)

        for entry in archive.entries {
            if isDirectoryEntry(entry.name) {
                continue
            }
            let destination = try map(entry.name, role: role, archiveURL: url)
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: archive)
            mapped.append(ModMappedEntry(
                archiveURL: url,
                originalName: entry.name,
                internalName: destination.internalName,
                targetArchive: destination.targetArchive,
                data: payload
            ))
        }

        return mapped
    }

    private enum Role {
        case mainMod
        case texture
    }

    private static func role(for archive: PakArchive) throws -> Role {
        let fileNames = archive.entries
            .map(\.name)
            .filter { !isDirectoryEntry($0) }
            .map(normalizedPackagePath)

        let texturePrefix = "prebuild/textures/"
        let textureNames = fileNames.filter { $0.hasPrefix(texturePrefix) }
        if !textureNames.isEmpty {
            guard textureNames.count == fileNames.count else {
                let mixedPath = fileNames.first { !$0.hasPrefix(texturePrefix) } ?? textureNames[0]
                throw ModMergeError.unsupportedModPath(
                    archive: archive.url.lastPathComponent,
                    path: mixedPath
                )
            }
            return .texture
        }

        return .mainMod
    }

    private static func validateModArchive(_ archive: PakArchive) throws {
        if archive.isZip64 {
            throw ModMergeError.invalidModArchive(archive: archive.url.lastPathComponent, reason: "ZIP64 archives are not supported")
        }

        for entry in archive.entries {
            if entry.generalPurposeBitFlag != 0 {
                throw ModMergeError.invalidModArchive(
                    archive: archive.url.lastPathComponent,
                    reason: "\(entry.name) has general-purpose bit flag \(entry.generalPurposeBitFlag)"
                )
            }
            if isDirectoryEntry(entry.name) {
                continue
            }

            let payload = try PakReader.readUncompressedPayload(entry: entry, in: archive)
            let actual = crc32(payload)
            guard actual == entry.crc32 else {
                throw ModMergeError.invalidModArchive(
                    archive: archive.url.lastPathComponent,
                    reason: "\(entry.name) CRC mismatch"
                )
            }
        }
    }

    private static func map(
        _ name: String,
        role: Role,
        archiveURL: URL
    ) throws -> (internalName: String, targetArchive: ModMergeTargetArchive) {
        let path = normalizedPackagePath(name)
        let archiveName = archiveURL.lastPathComponent

        switch role {
        case .texture:
            guard let rest = consumePrefix("prebuild/textures/", from: path), !rest.isEmpty else {
                throw ModMergeError.unsupportedModPath(archive: archiveName, path: name)
            }
            guard rest.hasSuffix(".pct") else {
                throw ModMergeError.unsupportedModPath(archive: archiveName, path: name)
            }
            let mappedRest = String(rest.dropLast(".pct".count)) + ".pct_base"
            return (
                "[textures]\\" + mappedRest.replacingOccurrences(of: "/", with: "\\"),
                .sharedTextures
            )

        case .mainMod:
            if let rest = consumePrefix("classes/", from: path), !rest.isEmpty {
                return ("[media]\\classes\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial)
            }
            if let rest = consumePrefix("prebuild/meshes/", from: path), !rest.isEmpty {
                return ("[meshes]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial)
            }
            if let rest = consumePrefix("ui/textures/", from: path), !rest.isEmpty {
                return ("[textures]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .sharedTextures)
            }
            if let rest = consumePrefix("texts/", from: path), !rest.isEmpty, rest.hasSuffix(".str") {
                return ("[strings]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial)
            }
            throw ModMergeError.unsupportedModPath(archive: archiveName, path: name)
        }
    }

    private static func isDirectoryEntry(_ name: String) -> Bool {
        name.hasSuffix("/") || name.hasSuffix("\\")
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            UInt32(zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)))
        }
    }

    private static func normalizedPackagePath(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/")
    }

    private static func consumePrefix(_ prefix: String, from path: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}
