import Foundation
import zlib

public struct ModMappedEntry: Equatable {
    public let archiveURL: URL
    public let originalName: String
    public let internalName: String
    public let data: Data

    public init(archiveURL: URL, originalName: String, internalName: String, data: Data) {
        self.archiveURL = archiveURL
        self.originalName = originalName
        self.internalName = internalName
        self.data = data
    }
}

public enum ModArchiveMapper {
    public static func mapArchive(at url: URL) throws -> [ModMappedEntry] {
        let archive = try PakReader.readArchive(at: url)
        try validateModArchive(archive)

        let role = role(for: url)
        var mapped: [ModMappedEntry] = []
        mapped.reserveCapacity(archive.entries.count)

        for entry in archive.entries {
            if isDirectoryEntry(entry.name) {
                continue
            }
            let mappedName = try map(entry.name, role: role, archiveURL: url)
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: archive)
            mapped.append(ModMappedEntry(
                archiveURL: url,
                originalName: entry.name,
                internalName: mappedName,
                data: payload
            ))
        }

        return mapped
    }

    private enum Role {
        case mainMod
        case pc
    }

    private static func role(for url: URL) -> Role {
        url.lastPathComponent.lowercased() == "pc.pak" ? .pc : .mainMod
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

    private static func map(_ name: String, role: Role, archiveURL: URL) throws -> String {
        let path = normalizedPackagePath(name)
        let archiveName = archiveURL.lastPathComponent

        switch role {
        case .pc:
            guard let rest = consumePrefix("prebuild/textures/", from: path), !rest.isEmpty else {
                throw ModMergeError.unsupportedModPath(archive: archiveName, path: name)
            }
            return "[textures]\\" + rest.replacingOccurrences(of: "/", with: "\\")

        case .mainMod:
            if let rest = consumePrefix("classes/", from: path), !rest.isEmpty {
                return "[media]\\classes\\" + rest.replacingOccurrences(of: "/", with: "\\")
            }
            if let rest = consumePrefix("prebuild/meshes/", from: path), !rest.isEmpty {
                return "[meshes]\\" + rest.replacingOccurrences(of: "/", with: "\\")
            }
            if let rest = consumePrefix("ui/textures/", from: path), !rest.isEmpty {
                return "[textures]\\" + rest.replacingOccurrences(of: "/", with: "\\")
            }
            if let rest = consumePrefix("texts/", from: path), !rest.isEmpty, rest.hasSuffix(".str") {
                return "[strings]\\" + rest.replacingOccurrences(of: "/", with: "\\")
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
