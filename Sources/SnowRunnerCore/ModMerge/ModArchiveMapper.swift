import Foundation
import CryptoKit
import zlib

public enum ModMergeTargetArchive: String, Codable, Equatable, Hashable {
    case initial = "initial.pak"
    case sharedTexturesBase = "shared_textures_base.pak"
    case sharedTextures = "shared_textures.pak"
}

public struct ModMappedEntry: Equatable {
    public let archiveURL: URL
    public let originalName: String
    public let internalName: String
    public let targetArchive: ModMergeTargetArchive
    public let data: Data
    public let localExtraField: Data
    public let centralExtraField: Data
    public let compressedPayload: PakCompressedPayload?

    public init(
        archiveURL: URL,
        originalName: String,
        internalName: String,
        targetArchive: ModMergeTargetArchive = .initial,
        data: Data,
        localExtraField: Data = Data(),
        centralExtraField: Data = Data(),
        compressedPayload: PakCompressedPayload? = nil
    ) {
        self.archiveURL = archiveURL
        self.originalName = originalName
        self.internalName = internalName
        self.targetArchive = targetArchive
        self.data = data
        self.localExtraField = localExtraField
        self.centralExtraField = centralExtraField
        self.compressedPayload = compressedPayload
    }
}

public enum ModArchiveMapper {
    public static func sha256Hex(uncompressedPayload data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func validateMergeCompatiblePackagePaths(_ names: [String], archiveName: String) throws {
        let normalizedNames = names
            .filter { !isDirectoryEntry($0) }
            .map(normalizedPackagePath)
        let role = try role(forPackagePaths: normalizedNames, archiveName: archiveName)
        for name in normalizedNames {
            try validatePackagePath(name, role: role, archiveName: archiveName)
        }
    }

    public static func mapArchive(at url: URL) throws -> [ModMappedEntry] {
        let archive = try PakReader.readArchive(at: url)
        try validateModArchive(archive)

        let archiveName = url.lastPathComponent
        let role = try role(forPackagePaths: archive.entries
            .map(\.name)
            .filter { !isDirectoryEntry($0) }
            .map(normalizedPackagePath), archiveName: archiveName)
        var mapped: [ModMappedEntry] = []
        mapped.reserveCapacity(archive.entries.count)

        for entry in archive.entries {
            if isDirectoryEntry(entry.name) {
                continue
            }
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: archive)
            let compressedPayload = PakCompressedPayload(
                compressionMethod: entry.compressionMethod,
                data: try PakReader.readCompressedPayload(entry: entry, in: archive),
                crc32: entry.crc32,
                uncompressedSize: entry.uncompressedSize
            )
            let destinations = try map(entry.name, role: role, archiveURL: url, payload: payload)
            for destination in destinations {
                mapped.append(ModMappedEntry(
                    archiveURL: url,
                    originalName: entry.name,
                    internalName: destination.internalName,
                    targetArchive: destination.targetArchive,
                    data: destination.data,
                    localExtraField: destination.preserveZipExtraFields ? entry.localExtraField : Data(),
                    centralExtraField: destination.preserveZipExtraFields ? entry.centralExtraField : Data(),
                    compressedPayload: destination.preserveCompressedPayload ? compressedPayload : nil
                ))
            }
        }

        return mapped
    }

    public static func mapDirectory(
        at directory: URL,
        archiveName: String,
        sourceCache: URL?,
        sourceEntries: [PakWorkspaceSourceEntry],
        workspaceRoot: URL
    ) throws -> [ModMappedEntry] {
        let sources = try PakModDirectoryScanner.scan(rootDirectory: directory)
        let cacheArchive = try sourceCache.map { try PakReader.readArchive(at: $0) }
        let cacheByName = Dictionary(uniqueKeysWithValues: (cacheArchive?.entries ?? []).map { ($0.name, $0) })
        let sourceHashByName = Dictionary(uniqueKeysWithValues: sourceEntries.map { ($0.sourceEntryName, $0.sha256) })

        var mapped: [ModMappedEntry] = []
        for source in sources {
            let payload = try source.readData()
            let destinations: [(
                internalName: String,
                targetArchive: ModMergeTargetArchive,
                data: Data,
                preserveZipExtraFields: Bool,
                preserveCompressedPayload: Bool
            )]
            do {
                destinations = try mapWorkspaceSource(
                    source.internalName,
                    archiveURL: URL(fileURLWithPath: archiveName),
                    payload: payload
                )
            } catch ModMergeError.unsupportedModPath(let archive, let path) {
                let sourceWorkspacePath = source.fileURL
                    .map { workspaceRelativePath(for: $0, workspaceRoot: workspaceRoot) } ?? source.internalName
                let workspacePath = path == source.internalName ? sourceWorkspacePath : path
                throw ModMergeError.unsupportedModPath(archive: archive, path: workspacePath)
            } catch ModMergeError.invalidModArchive(let archive, let reason) {
                let workspacePath = source.fileURL
                    .map { workspaceRelativePath(for: $0, workspaceRoot: workspaceRoot) } ?? source.internalName
                throw ModMergeError.invalidModArchive(
                    archive: archive,
                    reason: reason.replacingOccurrences(of: source.internalName, with: workspacePath)
                )
            }

            let unchanged = sourceHashByName[source.internalName] == sha256Hex(uncompressedPayload: payload)
            let cachedEntry = cacheByName[source.internalName]
            let compressedPayload: PakCompressedPayload?
            if unchanged, let cacheArchive, let cachedEntry {
                compressedPayload = PakCompressedPayload(
                    compressionMethod: cachedEntry.compressionMethod,
                    data: try PakReader.readCompressedPayload(entry: cachedEntry, in: cacheArchive),
                    crc32: cachedEntry.crc32,
                    uncompressedSize: cachedEntry.uncompressedSize
                )
            } else {
                compressedPayload = nil
            }

            for destination in destinations {
                mapped.append(ModMappedEntry(
                    archiveURL: directory,
                    originalName: source.internalName,
                    internalName: destination.internalName,
                    targetArchive: destination.targetArchive,
                    data: destination.data,
                    localExtraField: destination.preserveZipExtraFields && unchanged ? (cachedEntry?.localExtraField ?? Data()) : Data(),
                    centralExtraField: destination.preserveZipExtraFields && unchanged ? (cachedEntry?.centralExtraField ?? Data()) : Data(),
                    compressedPayload: destination.preserveCompressedPayload && unchanged ? compressedPayload : nil
                ))
            }
        }
        return mapped
    }

    private static func mapWorkspaceSource(
        _ name: String,
        archiveURL: URL,
        payload: Data
    ) throws -> [(
        internalName: String,
        targetArchive: ModMergeTargetArchive,
        data: Data,
        preserveZipExtraFields: Bool,
        preserveCompressedPayload: Bool
    )] {
        let path = normalizedPackagePath(name)
        let archiveName = archiveURL.lastPathComponent

        if let rest = consumePrefix("classes/", from: path), !rest.isEmpty {
            return [("[media]\\classes\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial, payload, false, false)]
        }
        if let rest = consumePrefix("prebuild/meshes/", from: path), !rest.isEmpty {
            return [("[meshes]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial, payload, false, false)]
        }
        if let rest = consumePrefix("ui/textures/", from: path), !rest.isEmpty {
            return [("[textures]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .sharedTexturesBase, payload, false, false)]
        }
        if let rest = consumePrefix("texts/", from: path), !rest.isEmpty, !rest.contains("/"), rest.hasSuffix(".str") {
            return [("[strings]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial, payload, false, false)]
        }
        if let rest = consumePrefix("prebuild/textures/", from: path), !rest.isEmpty, rest.hasSuffix(".pct") {
            let pctName = "[textures]\\" + rest.replacingOccurrences(of: "/", with: "\\")
            let headerData: Data
            do {
                headerData = try PCTHeaderGenerator.headerData(for: payload)
            } catch {
                throw ModMergeError.invalidModArchive(
                    archive: archiveName,
                    reason: "\(name) invalid PCT texture: \(error)"
                )
            }
            return [
                (pctName, .sharedTextures, payload, true, true),
                (pctName + "_header", .sharedTextures, headerData, false, false)
            ]
        }

        throw ModMergeError.unsupportedModPath(archive: archiveName, path: name)
    }

    private enum Role {
        case mainMod
        case texture
    }

    private static func role(forPackagePaths fileNames: [String], archiveName: String) throws -> Role {
        let texturePrefix = "prebuild/textures/"
        let textureNames = fileNames.filter { $0.hasPrefix(texturePrefix) }
        if !textureNames.isEmpty {
            guard textureNames.count == fileNames.count else {
                let mixedPath = fileNames.first { !$0.hasPrefix(texturePrefix) } ?? textureNames[0]
                throw ModMergeError.unsupportedModPath(
                    archive: archiveName,
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
        archiveURL: URL,
        payload: Data
    ) throws -> [(
        internalName: String,
        targetArchive: ModMergeTargetArchive,
        data: Data,
        preserveZipExtraFields: Bool,
        preserveCompressedPayload: Bool
    )] {
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
            let pctName = "[textures]\\" + rest.replacingOccurrences(of: "/", with: "\\")
            let headerData: Data
            do {
                headerData = try PCTHeaderGenerator.headerData(for: payload)
            } catch {
                throw ModMergeError.invalidModArchive(
                    archive: archiveName,
                    reason: "\(name) invalid PCT texture: \(error)"
                )
            }
            return [
                (pctName, .sharedTextures, payload, true, true),
                (pctName + "_header", .sharedTextures, headerData, false, false)
            ]

        case .mainMod:
            if let rest = consumePrefix("classes/", from: path), !rest.isEmpty {
                return [("[media]\\classes\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial, payload, false, false)]
            }
            if let rest = consumePrefix("prebuild/meshes/", from: path), !rest.isEmpty {
                return [("[meshes]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial, payload, false, false)]
            }
            if let rest = consumePrefix("ui/textures/", from: path), !rest.isEmpty {
                return [("[textures]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .sharedTexturesBase, payload, false, false)]
            }
            if let rest = consumePrefix("texts/", from: path), !rest.isEmpty, rest.hasSuffix(".str") {
                return [("[strings]\\" + rest.replacingOccurrences(of: "/", with: "\\"), .initial, payload, false, false)]
            }
            throw ModMergeError.unsupportedModPath(archive: archiveName, path: name)
        }
    }

    private static func validatePackagePath(_ path: String, role: Role, archiveName: String) throws {
        switch role {
        case .texture:
            guard let rest = consumePrefix("prebuild/textures/", from: path), !rest.isEmpty else {
                throw ModMergeError.unsupportedModPath(archive: archiveName, path: path)
            }
            guard rest.hasSuffix(".pct") else {
                throw ModMergeError.unsupportedModPath(archive: archiveName, path: path)
            }
        case .mainMod:
            if let rest = consumePrefix("classes/", from: path), !rest.isEmpty {
                return
            }
            if let rest = consumePrefix("prebuild/meshes/", from: path), !rest.isEmpty {
                return
            }
            if let rest = consumePrefix("ui/textures/", from: path), !rest.isEmpty {
                return
            }
            if let rest = consumePrefix("texts/", from: path), !rest.isEmpty, rest.hasSuffix(".str") {
                return
            }
            throw ModMergeError.unsupportedModPath(archive: archiveName, path: path)
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

    private static func workspaceRelativePath(for fileURL: URL, workspaceRoot: URL) -> String {
        let rootPath = workspaceRoot.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
