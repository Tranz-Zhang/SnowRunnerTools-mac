import Foundation

public struct PakWorkspaceInitResult: Equatable {
    public let initialEntryCount: Int
}

public struct PakWorkspaceAddModsResult: Equatable {
    public let addedMods: [PakWorkspaceMod]
}

public enum PakWorkspaceManager {
    public static func loadManifest(workspace: URL) throws -> PakWorkspaceManifest {
        let url = PakWorkspacePaths.manifestURL(root: workspace)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PakWorkspaceError.missingManifest(url.path)
        }
        let manifest = try JSONDecoder.pakWorkspace.decode(PakWorkspaceManifest.self, from: Data(contentsOf: url))
        guard manifest.version == 1 else {
            throw PakWorkspaceError.unsupportedManifestVersion(manifest.version)
        }
        return manifest
    }

    public static func initialize(workspace: URL, initialPak: URL) throws -> PakWorkspaceInitResult {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let initialDirectory = PakWorkspacePaths.initialDirectory(root: workspace)
        if try isNonEmptyDirectory(initialDirectory) {
            throw PakWorkspaceError.initialDirectoryAlreadyExists(initialDirectory.path)
        }
        let archive = try PakReader.readArchive(at: initialPak)
        let issues = try PakVerifier.verifyBasic(archive)
        guard issues.isEmpty else {
            throw PakWorkspaceError.verificationFailed(name: "verify-basic", issues: issues)
        }

        let tempInitial = workspace.appendingPathComponent(".initial-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempInitial) }
        let count = try PakUnpacker.unpack(archiveURL: initialPak, toDirectory: tempInitial)
        let manifest = PakWorkspaceManifest(
            version: 1,
            initialSourcePath: initialPak.path,
            mods: [],
            policy: PakWorkspacePolicy(textureMode: "inlineInitial", allowInitialOverwrite: true)
        )
        try commitManifestLast(workspace: workspace, manifest: manifest) {
            if FileManager.default.fileExists(atPath: initialDirectory.path) {
                try FileManager.default.removeItem(at: initialDirectory)
            }
            try FileManager.default.moveItem(at: tempInitial, to: initialDirectory)
        }
        return PakWorkspaceInitResult(initialEntryCount: count)
    }

    public static func addMods(workspace: URL, modPaks: [URL]) throws -> PakWorkspaceAddModsResult {
        var manifest = try loadManifest(workspace: workspace)
        let existingNames = Set(manifest.mods.map(\.folderName))
        let newNames = modPaks.map { folderName(forPak: $0) }
        for name in newNames {
            if existingNames.contains(name) || newNames.filter({ $0 == name }).count > 1 {
                throw PakWorkspaceError.duplicateModFolderName(name)
            }
        }
        for pak in modPaks {
            _ = try ModArchiveMapper.mapArchive(at: pak)
        }

        var staged: [(mod: PakWorkspaceMod, tempMod: URL, finalMod: URL, tempCache: URL, finalCache: URL)] = []
        defer {
            for item in staged {
                try? FileManager.default.removeItem(at: item.tempMod)
                try? FileManager.default.removeItem(at: item.tempCache)
            }
        }

        for pak in modPaks {
            let folderName = folderName(forPak: pak)
            let finalMod = PakWorkspacePaths.modDirectory(root: workspace, folderName: folderName)
            if FileManager.default.fileExists(atPath: finalMod.path) {
                throw PakWorkspaceError.modDirectoryAlreadyExists(finalMod.path)
            }
            let tempMod = workspace.appendingPathComponent(".mod-\(folderName)-\(UUID().uuidString)", isDirectory: true)
            let tempCache = workspace.appendingPathComponent(".source-\(folderName)-\(UUID().uuidString).pak")
            let finalCache = PakWorkspacePaths.sourceCache(root: workspace, folderName: folderName)
            try PakModUnpacker.unpack(archiveURL: pak, toDirectory: tempMod)
            try FileManager.default.createDirectory(at: tempCache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: pak, to: tempCache)
            let entries = try sourceEntries(for: pak, folderName: folderName)
            let mod = PakWorkspaceMod(
                sourcePath: pak.path,
                folderName: folderName,
                archiveName: pak.lastPathComponent,
                sourceCachePath: ".snowrunner/sources/\(folderName).pak",
                entries: entries
            )
            staged.append((mod, tempMod, finalMod, tempCache, finalCache))
        }

        manifest.mods.append(contentsOf: staged.map(\.mod))
        try commitManifestLast(workspace: workspace, manifest: manifest) {
            try FileManager.default.createDirectory(at: PakWorkspacePaths.modsDirectory(root: workspace), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: PakWorkspacePaths.sourcesDirectory(root: workspace), withIntermediateDirectories: true)
            for item in staged {
                try FileManager.default.moveItem(at: item.tempMod, to: item.finalMod)
                try FileManager.default.moveItem(at: item.tempCache, to: item.finalCache)
            }
        }
        return PakWorkspaceAddModsResult(addedMods: staged.map(\.mod))
    }

    private static func folderName(forPak url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? url.lastPathComponent : name
    }

    private static func sourceEntries(for pak: URL, folderName: String) throws -> [PakWorkspaceSourceEntry] {
        let archive = try PakReader.readArchive(at: pak)
        return try archive.entries
            .filter { !$0.name.hasSuffix("/") && !$0.name.hasSuffix("\\") }
            .map { entry in
                let payload = try PakReader.readUncompressedPayload(entry: entry, in: archive)
                let workspacePath = "mods/\(folderName)/" + (try PakModPath.fileSystemRelativePath(forArchiveName: entry.name))
                return PakWorkspaceSourceEntry(
                    sourceEntryName: entry.name,
                    workspacePath: workspacePath,
                    sha256: ModArchiveMapper.sha256Hex(uncompressedPayload: payload)
                )
            }
    }

    private static func commitManifestLast(
        workspace: URL,
        manifest: PakWorkspaceManifest,
        fileMoves: () throws -> Void
    ) throws {
        let manifestURL = PakWorkspacePaths.manifestURL(root: workspace)
        let tempManifest = workspace.appendingPathComponent(".snowrunner-workspace-\(UUID().uuidString).json")
        let data = try JSONEncoder.pakWorkspace.encode(manifest)
        try data.write(to: tempManifest, options: .atomic)
        try fileMoves()
        try replaceItem(at: manifestURL, with: tempManifest)
    }

    private static func isNonEmptyDirectory(_ url: URL) throws -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return try !FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty
    }

    private static func replaceItem(at destination: URL, with source: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: source,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }
}
