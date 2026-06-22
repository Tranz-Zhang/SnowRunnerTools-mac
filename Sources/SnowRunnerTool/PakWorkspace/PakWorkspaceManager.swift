import Foundation

public struct PakWorkspaceInitResult: Equatable {
    public let initialEntryCount: Int
}

public struct PakWorkspaceAddModsResult: Equatable {
    public let addedMods: [PakWorkspaceMod]
}

public struct PakWorkspaceSummary: Equatable {
    public var workspace: URL
    public var initialSourcePath: String
    public var mods: [PakWorkspaceModSummary]
    public var buildInitialPak: URL
    public var buildReport: URL

    public init(
        workspace: URL,
        initialSourcePath: String,
        mods: [PakWorkspaceModSummary],
        buildInitialPak: URL,
        buildReport: URL
    ) {
        self.workspace = workspace
        self.initialSourcePath = initialSourcePath
        self.mods = mods
        self.buildInitialPak = buildInitialPak
        self.buildReport = buildReport
    }
}

public struct WorkspaceQuickVerifyResult: Equatable {
    public var conflicts: [WorkspaceModConflict]

    public init(conflicts: [WorkspaceModConflict]) {
        self.conflicts = conflicts
    }
}

public struct WorkspaceModConflict: Equatable, Identifiable {
    public var id: String { targetPath }
    public var targetPath: String
    public var mods: [String]

    public init(targetPath: String, mods: [String]) {
        self.targetPath = targetPath
        self.mods = mods
    }
}

public struct PakWorkspaceModSummary: Equatable, Identifiable {
    public var id: String { folderName }
    public var folderName: String
    public var archiveName: String
    public var sourcePath: String
    public var modDirectory: URL
    public var sourceCache: URL
    public var enabled: Bool

    public init(
        folderName: String,
        archiveName: String,
        sourcePath: String,
        modDirectory: URL,
        sourceCache: URL,
        enabled: Bool
    ) {
        self.folderName = folderName
        self.archiveName = archiveName
        self.sourcePath = sourcePath
        self.modDirectory = modDirectory
        self.sourceCache = sourceCache
        self.enabled = enabled
    }
}

public enum PakWorkspaceManager {
    nonisolated(unsafe) static var afterInitialBuildPakPublishHook: (() throws -> Void)?

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

    public static func summary(workspace: URL) throws -> PakWorkspaceSummary {
        let manifest = try loadManifest(workspace: workspace)
        return PakWorkspaceSummary(
            workspace: workspace,
            initialSourcePath: manifest.initialSourcePath,
            mods: manifest.mods.map { mod in
                PakWorkspaceModSummary(
                    folderName: mod.folderName,
                    archiveName: mod.archiveName,
                    sourcePath: mod.sourcePath,
                    modDirectory: PakWorkspacePaths.modDirectory(root: workspace, folderName: mod.folderName),
                    sourceCache: workspace.appendingPathComponent(mod.sourceCachePath),
                    enabled: mod.enabled
                )
            },
            buildInitialPak: PakWorkspacePaths.buildInitialPak(root: workspace),
            buildReport: PakWorkspacePaths.buildReport(root: workspace)
        )
    }

    public static func setModEnabled(workspace: URL, folderName: String, enabled: Bool) throws {
        var manifest = try loadManifest(workspace: workspace)
        guard let index = manifest.mods.firstIndex(where: { $0.folderName == folderName }) else {
            throw PakWorkspaceError.modNotFound(folderName)
        }
        if enabled {
            let mod = manifest.mods[index]
            let modDirectory = PakWorkspacePaths.modDirectory(root: workspace, folderName: mod.folderName)
            let cache = workspace.appendingPathComponent(mod.sourceCachePath)
            guard FileManager.default.fileExists(atPath: modDirectory.path) else {
                throw PakWorkspaceError.missingModDirectory(modDirectory.path)
            }
            guard FileManager.default.fileExists(atPath: cache.path) else {
                throw PakWorkspaceError.missingSourceCache(cache.path)
            }
        }
        manifest.mods[index].enabled = enabled
        try commitManifestOnly(workspace: workspace, manifest: manifest)
    }

    public static func removeMod(workspace: URL, folderName: String) throws {
        var manifest = try loadManifest(workspace: workspace)
        guard let index = manifest.mods.firstIndex(where: { $0.folderName == folderName }) else {
            throw PakWorkspaceError.modNotFound(folderName)
        }
        let mod = manifest.mods.remove(at: index)

        let modDirectory = PakWorkspacePaths.modDirectory(root: workspace, folderName: mod.folderName)
        let sourceCache = workspace.appendingPathComponent(mod.sourceCachePath)
        let modBackup = workspace.appendingPathComponent(".remove-mod-\(mod.folderName)-\(UUID().uuidString)", isDirectory: true)
        let cacheBackup = workspace.appendingPathComponent(".remove-source-\(mod.folderName)-\(UUID().uuidString).pak")
        var movedModDirectory = false
        var movedSourceCache = false

        do {
            if FileManager.default.fileExists(atPath: modDirectory.path) {
                try FileManager.default.moveItem(at: modDirectory, to: modBackup)
                movedModDirectory = true
            }
            if FileManager.default.fileExists(atPath: sourceCache.path) {
                try FileManager.default.moveItem(at: sourceCache, to: cacheBackup)
                movedSourceCache = true
            }

            try commitManifestOnly(workspace: workspace, manifest: manifest)
        } catch {
            restoreBackup(from: modBackup, to: modDirectory, didMove: movedModDirectory)
            restoreBackup(from: cacheBackup, to: sourceCache, didMove: movedSourceCache)
            throw error
        }

        if movedModDirectory {
            try? FileManager.default.removeItem(at: modBackup)
        }
        if movedSourceCache {
            try? FileManager.default.removeItem(at: cacheBackup)
        }
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
        } rollback: {
            try? FileManager.default.removeItem(at: initialDirectory)
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
                try? FileManager.default.removeItem(at: item.finalMod)
                try? FileManager.default.removeItem(at: item.finalCache)
                try FileManager.default.moveItem(at: item.tempMod, to: item.finalMod)
                try FileManager.default.moveItem(at: item.tempCache, to: item.finalCache)
            }
        } rollback: {
            for item in staged {
                try? FileManager.default.removeItem(at: item.finalMod)
                try? FileManager.default.removeItem(at: item.finalCache)
            }
        }
        return PakWorkspaceAddModsResult(addedMods: staged.map(\.mod))
    }

    public static func verify(workspace: URL) throws -> ModMergeResult {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SnowRunnerWorkspaceVerify-\(UUID().uuidString).pak")
        defer { try? FileManager.default.removeItem(at: temp) }
        return try buildCandidate(workspace: workspace, output: temp, reportURL: nil)
    }

    public static func quickVerify(workspace: URL) throws -> WorkspaceQuickVerifyResult {
        let manifest = try loadManifest(workspace: workspace)
        let mappedMods = try mappedEntriesForEnabledMods(workspace: workspace, manifest: manifest)
        var modsByTarget: [MappedTargetKey: Set<String>] = [:]

        for mappedMod in mappedMods {
            for entry in mappedMod.entries {
                let key = MappedTargetKey(targetArchive: entry.targetArchive, internalName: entry.internalName)
                modsByTarget[key, default: []].insert(mappedMod.mod.folderName)
            }
        }

        let conflicts = modsByTarget
            .filter { $0.value.count > 1 }
            .map { WorkspaceModConflict(targetPath: targetPathDisplay(for: $0.key), mods: $0.value.sorted()) }
            .sorted { $0.targetPath < $1.targetPath }

        return WorkspaceQuickVerifyResult(conflicts: conflicts)
    }

    public static func build(workspace: URL) throws -> ModMergeResult {
        let buildDirectory = PakWorkspacePaths.buildDirectory(root: workspace)
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        let tempPak = workspace.appendingPathComponent(".build-initial-\(UUID().uuidString).pak")
        let tempReport = workspace.appendingPathComponent(".build-report-\(UUID().uuidString).md")
        defer {
            try? FileManager.default.removeItem(at: tempPak)
            try? FileManager.default.removeItem(at: tempReport)
        }
        let result = try buildCandidate(workspace: workspace, output: tempPak, reportURL: tempReport)
        try publishBuildOutputs(
            initialPak: tempPak,
            report: tempReport,
            outputInitialPak: PakWorkspacePaths.buildInitialPak(root: workspace),
            outputReport: PakWorkspacePaths.buildReport(root: workspace)
        )
        return ModMergeResult(
            plan: result.plan,
            outputURL: PakWorkspacePaths.buildInitialPak(root: workspace),
            outputTexturesURL: nil,
            outputSharedTexturesURL: nil,
            writtenEntryCount: result.writtenEntryCount,
            writtenTextureEntryCount: nil,
            writtenSharedTextureEntryCount: nil
        )
    }

    private static func folderName(forPak url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? url.lastPathComponent : name
    }

    private static func buildCandidate(workspace: URL, output: URL, reportURL: URL?) throws -> ModMergeResult {
        let manifest = try loadManifest(workspace: workspace)
        let initialDirectory = PakWorkspacePaths.initialDirectory(root: workspace)
        guard FileManager.default.fileExists(atPath: initialDirectory.path) else {
            throw PakWorkspaceError.missingInitialDirectory(initialDirectory.path)
        }
        let baseManifest = try LoadListReader.readManifest(
            from: initialDirectory.appendingPathComponent(LoadListConstants.manifestEntryName)
        )
        let records = try WorkspaceInitialLoadListBuilder.records(fromInitialDirectory: initialDirectory, preservingFrom: baseManifest)
        let rebuiltManifest = try LoadListBuilder.buildManifest(records: records)
        let mapped = try mappedEntriesForEnabledMods(workspace: workspace, manifest: manifest).flatMap(\.entries)
        let result = try ModMerger.mergeWorkspaceInitial(
            initialDirectory: initialDirectory,
            baseManifest: rebuiltManifest,
            mappedEntries: mapped,
            outputInitialPak: output,
            reportURL: nil,
            verifyOutput: true
        )
        if let reportURL {
            try PakWorkspaceReporter.markdown(result: result).write(to: reportURL, atomically: true, encoding: .utf8)
        }
        return result
    }

    private static func mappedEntriesForEnabledMods(
        workspace: URL,
        manifest: PakWorkspaceManifest
    ) throws -> [(mod: PakWorkspaceMod, entries: [ModMappedEntry])] {
        try manifest.mods.filter(\.enabled).map { mod in
            let modDirectory = PakWorkspacePaths.modDirectory(root: workspace, folderName: mod.folderName)
            let cache = workspace.appendingPathComponent(mod.sourceCachePath)
            guard FileManager.default.fileExists(atPath: modDirectory.path) else {
                throw PakWorkspaceError.missingModDirectory(modDirectory.path)
            }
            guard FileManager.default.fileExists(atPath: cache.path) else {
                throw PakWorkspaceError.missingSourceCache(cache.path)
            }
            let entries = try ModArchiveMapper.mapDirectory(
                at: modDirectory,
                archiveName: mod.archiveName,
                sourceCache: cache,
                sourceEntries: mod.entries,
                workspaceRoot: workspace
            )
            return (mod: mod, entries: entries)
        }
    }

    private struct MappedTargetKey: Hashable {
        var targetArchive: ModMergeTargetArchive
        var internalName: String

        static func == (lhs: MappedTargetKey, rhs: MappedTargetKey) -> Bool {
            lhs.targetArchive == rhs.targetArchive && lhs.internalName == rhs.internalName
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(targetArchive.rawValue)
            hasher.combine(internalName)
        }
    }

    private static func targetPathDisplay(for key: MappedTargetKey) -> String {
        switch key.targetArchive {
        case .initial:
            return key.internalName
        case .sharedTexturesBase, .sharedTextures:
            return "\(key.targetArchive.rawValue):\(key.internalName)"
        }
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
        fileMoves: () throws -> Void,
        rollback: () -> Void
    ) throws {
        let manifestURL = PakWorkspacePaths.manifestURL(root: workspace)
        let tempManifest = workspace.appendingPathComponent(".snowrunner-workspace-\(UUID().uuidString).json")
        let data = try JSONEncoder.pakWorkspace.encode(manifest)
        try data.write(to: tempManifest, options: .atomic)
        do {
            try fileMoves()
            try replaceItem(at: manifestURL, with: tempManifest)
        } catch {
            rollback()
            try? FileManager.default.removeItem(at: tempManifest)
            throw error
        }
    }

    private static func commitManifestOnly(workspace: URL, manifest: PakWorkspaceManifest) throws {
        try commitManifestLast(workspace: workspace, manifest: manifest) {
        } rollback: {
        }
    }

    private static func publishBuildOutputs(
        initialPak: URL,
        report: URL,
        outputInitialPak: URL,
        outputReport: URL
    ) throws {
        let transactionID = UUID().uuidString
        let pakBackup = outputInitialPak.deletingLastPathComponent()
            .appendingPathComponent(".\(outputInitialPak.lastPathComponent).backup-\(transactionID)")
        let reportBackup = outputReport.deletingLastPathComponent()
            .appendingPathComponent(".\(outputReport.lastPathComponent).backup-\(transactionID)")
        var movedPakBackup = false
        var movedReportBackup = false
        var publishedPak = false
        var publishedReport = false

        do {
            movedPakBackup = try moveExistingItemForRollback(at: outputInitialPak, to: pakBackup)
            movedReportBackup = try moveExistingItemForRollback(at: outputReport, to: reportBackup)
            try FileManager.default.moveItem(at: initialPak, to: outputInitialPak)
            publishedPak = true
            try afterInitialBuildPakPublishHook?()
            try FileManager.default.moveItem(at: report, to: outputReport)
            publishedReport = true
        } catch {
            removePublishedItem(at: outputReport, didPublish: publishedReport)
            removePublishedItem(at: outputInitialPak, didPublish: publishedPak)
            restoreBackup(from: reportBackup, to: outputReport, didMove: movedReportBackup)
            restoreBackup(from: pakBackup, to: outputInitialPak, didMove: movedPakBackup)
            throw error
        }

        if movedPakBackup {
            try? FileManager.default.removeItem(at: pakBackup)
        }
        if movedReportBackup {
            try? FileManager.default.removeItem(at: reportBackup)
        }
    }

    private static func moveExistingItemForRollback(at original: URL, to backup: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: original.path) else {
            return false
        }
        try FileManager.default.moveItem(at: original, to: backup)
        return true
    }

    private static func removePublishedItem(at url: URL, didPublish: Bool) {
        guard didPublish else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func restoreBackup(from backup: URL, to original: URL, didMove: Bool) {
        guard didMove,
              FileManager.default.fileExists(atPath: backup.path),
              !FileManager.default.fileExists(atPath: original.path)
        else {
            return
        }
        try? FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: backup, to: original)
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
