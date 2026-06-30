import Foundation

public struct PakWorkspaceInitResult: Equatable {
    public let initialEntryCount: Int
}

public struct PakWorkspaceAddModsResult: Equatable {
    public let addedMods: [PakWorkspaceMod]
}

public struct PakWorkspaceBuildOutputSummary: Equatable {
    public var initialPak: URL
    public var report: URL
    public var modifiedAt: Date?

    public init(initialPak: URL, report: URL, modifiedAt: Date?) {
        self.initialPak = initialPak
        self.report = report
        self.modifiedAt = modifiedAt
    }
}

public struct PakWorkspaceSummary: Equatable {
    public var workspace: URL
    public var initialSourcePath: String
    public var mods: [PakWorkspaceModSummary]
    public var buildInitialPak: URL
    public var buildReport: URL
    public var buildOutput: PakWorkspaceBuildOutputSummary?

    public init(
        workspace: URL,
        initialSourcePath: String,
        mods: [PakWorkspaceModSummary],
        buildInitialPak: URL,
        buildReport: URL,
        buildOutput: PakWorkspaceBuildOutputSummary? = nil
    ) {
        self.workspace = workspace
        self.initialSourcePath = initialSourcePath
        self.mods = mods
        self.buildInitialPak = buildInitialPak
        self.buildReport = buildReport
        self.buildOutput = buildOutput
    }
}

public struct WorkspaceQuickVerifyResult: Equatable {
    public var conflicts: [WorkspaceModConflict]

    public init(conflicts: [WorkspaceModConflict]) {
        self.conflicts = conflicts
    }

    public var unresolvedConflictCount: Int {
        conflicts.filter { !$0.isResolved }.count
    }

    public var resolvedConflictCount: Int {
        conflicts.filter(\.isResolved).count
    }
}

public struct WorkspaceModConflict: Equatable, Identifiable {
    public var id: String { "\(targetArchive.rawValue):\(internalName)" }
    public var targetArchive: ModMergeTargetArchive
    public var internalName: String
    public var targetPath: String
    public var candidates: [WorkspaceModConflictCandidate]
    public var selectedMod: String?

    public var mods: [String] {
        candidates.map(\.modFolderName).sorted()
    }

    public var isResolved: Bool {
        selectedMod != nil
    }

    public var isByteIdentical: Bool {
        Set(candidates.map(\.sha256)).count <= 1
    }

    public init(
        targetArchive: ModMergeTargetArchive,
        internalName: String,
        targetPath: String,
        candidates: [WorkspaceModConflictCandidate],
        selectedMod: String? = nil
    ) {
        self.targetArchive = targetArchive
        self.internalName = internalName
        self.targetPath = targetPath
        self.candidates = candidates
        self.selectedMod = selectedMod
    }

    public init(targetPath: String, mods: [String]) {
        self.targetArchive = .initial
        self.internalName = targetPath
        self.targetPath = targetPath
        self.candidates = mods.sorted().map {
            WorkspaceModConflictCandidate(
                modFolderName: $0,
                originalName: "",
                byteSize: 0,
                sha256: ""
            )
        }
        self.selectedMod = nil
    }
}

public struct WorkspaceModConflictCandidate: Equatable, Identifiable {
    public var id: String { "\(modFolderName):\(originalName)" }
    public var modFolderName: String
    public var originalName: String
    public var byteSize: Int
    public var sha256: String

    public init(modFolderName: String, originalName: String, byteSize: Int, sha256: String) {
        self.modFolderName = modFolderName
        self.originalName = originalName
        self.byteSize = byteSize
        self.sha256 = sha256
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
        let buildInitialPak = PakWorkspacePaths.buildInitialPak(root: workspace)
        let buildReport = PakWorkspacePaths.buildReport(root: workspace)
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
            buildInitialPak: buildInitialPak,
            buildReport: buildReport,
            buildOutput: buildOutputSummary(initialPak: buildInitialPak, report: buildReport)
        )
    }

    private static func buildOutputSummary(initialPak: URL, report: URL) -> PakWorkspaceBuildOutputSummary? {
        guard FileManager.default.fileExists(atPath: initialPak.path) else { return nil }
        let modifiedAt = try? FileManager.default
            .attributesOfItem(atPath: initialPak.path)[.modificationDate] as? Date
        return PakWorkspaceBuildOutputSummary(
            initialPak: initialPak,
            report: report,
            modifiedAt: modifiedAt
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

    public static func resolveConflict(
        workspace: URL,
        targetArchive: ModMergeTargetArchive,
        internalName: String,
        selectedMod: String
    ) throws {
        var manifest = try loadManifest(workspace: workspace)
        let resolution = PakWorkspaceConflictResolution(
            targetArchive: targetArchive,
            internalName: internalName,
            selectedMod: selectedMod
        )
        manifest.conflictResolutions.removeAll {
            $0.targetArchive == targetArchive && $0.internalName == internalName
        }
        manifest.conflictResolutions.append(resolution)
        manifest.conflictResolutions.sort {
            if $0.targetArchive.rawValue != $1.targetArchive.rawValue {
                return $0.targetArchive.rawValue < $1.targetArchive.rawValue
            }
            return $0.internalName < $1.internalName
        }
        try commitManifestOnly(workspace: workspace, manifest: manifest)
    }

    public static func clearConflictResolution(
        workspace: URL,
        targetArchive: ModMergeTargetArchive,
        internalName: String
    ) throws {
        var manifest = try loadManifest(workspace: workspace)
        manifest.conflictResolutions.removeAll {
            $0.targetArchive == targetArchive && $0.internalName == internalName
        }
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

    public static func addModPackages(workspace: URL, packages: [URL]) throws -> PakWorkspaceAddModsResult {
        if packages.allSatisfy({ $0.pathExtension.lowercased() == "pak" }) {
            return try addMods(workspace: workspace, modPaks: packages)
        }

        var manifest = try loadManifest(workspace: workspace)
        var staged: [StagedModPackage] = []
        defer {
            for item in staged {
                try? FileManager.default.removeItem(at: item.tempMod)
                try? FileManager.default.removeItem(at: item.tempCache)
                for temporaryDirectory in item.temporaryDirectories {
                    try? FileManager.default.removeItem(at: temporaryDirectory)
                }
            }
        }

        for package in packages {
            switch package.pathExtension.lowercased() {
            case "pak":
                staged.append(try stagePakModPackage(workspace: workspace, pak: package))
            case "zip":
                staged.append(try stageZipModPackage(workspace: workspace, package: package))
            default:
                throw PakWorkspaceError.invalidCommand("Unsupported mod package extension: \(package.lastPathComponent)")
            }
        }

        let existingNames = Set(manifest.mods.map(\.folderName))
        let newNames = staged.map { $0.mod.folderName }
        for name in newNames {
            if existingNames.contains(name) || newNames.filter({ $0 == name }).count > 1 {
                throw PakWorkspaceError.duplicateModFolderName(name)
            }
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
        var manifest = try loadManifest(workspace: workspace)
        let mappedMods = try mappedEntriesForEnabledMods(workspace: workspace, manifest: manifest)
        let grouped = groupedMappedCandidates(mappedMods)
        let resolutionResult = try pruneConflictResolutionsIfNeeded(
            workspace: workspace,
            manifest: &manifest,
            grouped: grouped
        )

        let conflicts = grouped.values
            .filter { $0.count > 1 }
            .filter { !isAutomaticallyMergedTarget($0[0].key) }
            .map { candidates in
                makeWorkspaceConflict(
                    candidates: candidates,
                    selectedMod: resolutionResult[candidates[0].key]
                )
            }
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

    private struct StagedModPackage {
        var mod: PakWorkspaceMod
        var tempMod: URL
        var finalMod: URL
        var tempCache: URL
        var finalCache: URL
        var temporaryDirectories: [URL]
    }

    private struct InnerPakMember {
        enum Role {
            case main
            case textureCompanion
        }

        var archiveName: String
        var archive: PakArchive
        var role: Role
    }

    private struct CombinedSourceEntry {
        var sourceEntry: PakWorkspaceSourceEntry
        var cacheSource: PakFileSource
        var sha256: String
    }

    private static func stagePakModPackage(workspace: URL, pak: URL) throws -> StagedModPackage {
        _ = try ModArchiveMapper.mapArchive(at: pak)
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
        return StagedModPackage(
            mod: mod,
            tempMod: tempMod,
            finalMod: finalMod,
            tempCache: tempCache,
            finalCache: finalCache,
            temporaryDirectories: []
        )
    }

    private static func stageZipModPackage(workspace: URL, package: URL) throws -> StagedModPackage {
        let packageTemp = workspace.appendingPathComponent(".package-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: packageTemp, withIntermediateDirectories: true)
        do {
            let members = try discoverInnerPakMembers(package: package, temporaryDirectory: packageTemp)
            let mainMembers = members.filter { $0.role == .main }
            guard mainMembers.count == 1, let main = mainMembers.first else {
                throw PakWorkspaceError.invalidCommand(
                    "Expected exactly one main PAK in \(package.lastPathComponent); found \(mainMembers.count)"
                )
            }

            let folderName = folderName(forPak: URL(fileURLWithPath: main.archiveName))
            let finalMod = PakWorkspacePaths.modDirectory(root: workspace, folderName: folderName)
            let tempMod = workspace.appendingPathComponent(".mod-\(folderName)-\(UUID().uuidString)", isDirectory: true)
            let tempCache = workspace.appendingPathComponent(".source-\(folderName)-\(UUID().uuidString).pak")
            let finalCache = PakWorkspacePaths.sourceCache(root: workspace, folderName: folderName)
            let combined = try combineInnerPakMembers(
                members,
                folderName: folderName,
                outputDirectory: tempMod
            )
            let cacheSources = combined
                .map(\.cacheSource)
                .sorted { $0.internalName < $1.internalName }
            try PakWriter.writeArchive(fileSources: cacheSources, to: tempCache)
            let sourceEntries = combined
                .map(\.sourceEntry)
                .sorted { $0.sourceEntryName < $1.sourceEntryName }
            let mod = PakWorkspaceMod(
                sourcePath: package.path,
                folderName: folderName,
                archiveName: main.archiveName,
                sourceCachePath: ".snowrunner/sources/\(folderName).pak",
                entries: sourceEntries
            )
            return StagedModPackage(
                mod: mod,
                tempMod: tempMod,
                finalMod: finalMod,
                tempCache: tempCache,
                finalCache: finalCache,
                temporaryDirectories: [packageTemp]
            )
        } catch {
            try? FileManager.default.removeItem(at: packageTemp)
            throw error
        }
    }

    private static func discoverInnerPakMembers(package: URL, temporaryDirectory: URL) throws -> [InnerPakMember] {
        let outer = try PakReader.readArchive(at: package)
        var members: [InnerPakMember] = []
        for (index, entry) in outer.entries.enumerated() {
            if PakModPath.isDirectoryEntry(entry.name) || isIgnoredPackageMetadata(entry.name) {
                continue
            }

            let normalizedName = entry.name.replacingOccurrences(of: "\\", with: "/")
            guard normalizedName.lowercased().hasSuffix(".pak") else {
                throw PakWorkspaceError.invalidCommand(
                    "Unsupported loose file in \(package.lastPathComponent): \(entry.name)"
                )
            }
            if entry.uncompressedSize == 0 {
                continue
            }

            let archiveName = URL(fileURLWithPath: normalizedName).lastPathComponent
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: outer)
            let innerURL = temporaryDirectory.appendingPathComponent("\(index)-\(archiveName)")
            try payload.write(to: innerURL, options: .atomic)
            let archive: PakArchive
            do {
                archive = try PakReader.readArchive(at: innerURL)
            } catch {
                throw PakWorkspaceError.invalidCommand(
                    "Invalid inner PAK in \(package.lastPathComponent): \(entry.name)"
                )
            }
            let role = try classifyInnerPak(archive, archiveName: archiveName)
            members.append(InnerPakMember(
                archiveName: archiveName,
                archive: archive,
                role: role
            ))
        }

        guard !members.isEmpty else {
            throw PakWorkspaceError.invalidCommand("No supported inner PAKs found in \(package.lastPathComponent)")
        }
        return members
    }

    private static func classifyInnerPak(_ archive: PakArchive, archiveName: String) throws -> InnerPakMember.Role {
        let fileNames = archive.entries
            .map(\.name)
            .filter { !PakModPath.isDirectoryEntry($0) }
            .map { $0.replacingOccurrences(of: "\\", with: "/") }

        guard !fileNames.isEmpty else {
            throw PakWorkspaceError.invalidCommand("Unsupported empty PAK in mod package: \(archiveName)")
        }

        var hasMainSource = false
        var hasTextureSource = false
        for name in fileNames {
            if isSupportedMainSourcePath(name) {
                hasMainSource = true
            } else if isSupportedTextureCompanionPath(name) {
                hasTextureSource = true
            } else {
                throw ModMergeError.unsupportedModPath(archive: archiveName, path: name)
            }
        }

        if hasMainSource {
            return .main
        }
        if hasTextureSource {
            return .textureCompanion
        }
        throw PakWorkspaceError.invalidCommand("Unsupported empty PAK in mod package: \(archiveName)")
    }

    private static func combineInnerPakMembers(
        _ members: [InnerPakMember],
        folderName: String,
        outputDirectory: URL
    ) throws -> [CombinedSourceEntry] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var combinedByName: [String: CombinedSourceEntry] = [:]

        for member in members {
            for entry in member.archive.entries {
                if PakModPath.isDirectoryEntry(entry.name) {
                    continue
                }
                let sourceEntryName = try PakModPath.fileSystemRelativePath(forArchiveName: entry.name)
                let payload = try PakReader.readUncompressedPayload(entry: entry, in: member.archive)
                let sha = ModArchiveMapper.sha256Hex(uncompressedPayload: payload)
                if let existing = combinedByName[sourceEntryName] {
                    guard existing.sha256 == sha else {
                        throw PakWorkspaceError.invalidCommand(
                            "Duplicate mod package path has different contents: \(sourceEntryName)"
                        )
                    }
                    continue
                }

                let outputURL = outputDirectory.appendingPathComponent(sourceEntryName).standardizedFileURL
                guard outputURL.path.hasPrefix(outputDirectory.standardizedFileURL.path + "/") else {
                    throw PakModPathError.absolutePath(outputURL)
                }
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try payload.write(to: outputURL, options: .atomic)

                let compressedPayload = PakCompressedPayload(
                    compressionMethod: entry.compressionMethod,
                    data: try PakReader.readCompressedPayload(entry: entry, in: member.archive),
                    crc32: entry.crc32,
                    uncompressedSize: entry.uncompressedSize
                )
                let sourceEntry = PakWorkspaceSourceEntry(
                    sourceEntryName: sourceEntryName,
                    workspacePath: "mods/\(folderName)/\(sourceEntryName)",
                    sha256: sha
                )
                combinedByName[sourceEntryName] = CombinedSourceEntry(
                    sourceEntry: sourceEntry,
                    cacheSource: PakFileSource(
                        internalName: sourceEntryName,
                        compressedPayload: compressedPayload,
                        localExtraField: entry.localExtraField,
                        centralExtraField: entry.centralExtraField
                    ),
                    sha256: sha
                )
            }
        }

        return combinedByName.values.sorted { $0.sourceEntry.sourceEntryName < $1.sourceEntry.sourceEntryName }
    }

    private static func isIgnoredPackageMetadata(_ name: String) -> Bool {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        let last = URL(fileURLWithPath: normalized).lastPathComponent
        return normalized.hasPrefix("__MACOSX/") || last == ".DS_Store"
    }

    private static func isSupportedMainSourcePath(_ name: String) -> Bool {
        if let rest = consumePrefix("classes/", from: name), !rest.isEmpty {
            return true
        }
        if let rest = consumePrefix("prebuild/meshes/", from: name), !rest.isEmpty {
            return true
        }
        if let rest = consumePrefix("ui/textures/", from: name), !rest.isEmpty {
            return true
        }
        if let rest = consumePrefix("texts/", from: name),
           !rest.isEmpty,
           !rest.contains("/"),
           rest.hasSuffix(".str")
        {
            return true
        }
        return false
    }

    private static func isSupportedTextureCompanionPath(_ name: String) -> Bool {
        guard let rest = consumePrefix("prebuild/textures/", from: name), !rest.isEmpty else {
            return false
        }
        return rest.hasSuffix(".pct")
    }

    private static func consumePrefix(_ prefix: String, from path: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
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
        let mappedMods = try mappedEntriesForEnabledMods(workspace: workspace, manifest: manifest)
        let mapped = try resolutionAwareMappedEntries(workspace: workspace, manifest: manifest, mappedMods: mappedMods)
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

    private static func resolutionAwareMappedEntries(
        workspace: URL,
        manifest: PakWorkspaceManifest,
        mappedMods: [(mod: PakWorkspaceMod, entries: [ModMappedEntry])]
    ) throws -> [ModMappedEntry] {
        var mutableManifest = manifest
        let grouped = groupedMappedCandidates(mappedMods)
        let selectedByKey = try pruneConflictResolutionsIfNeeded(
            workspace: workspace,
            manifest: &mutableManifest,
            grouped: grouped
        )

        var filtered: [ModMappedEntry] = []
        for mappedMod in mappedMods {
            for entry in mappedMod.entries {
                let key = MappedTargetKey(targetArchive: entry.targetArchive, internalName: entry.internalName)
                if let selectedMod = selectedByKey[key] {
                    if mappedMod.mod.folderName == selectedMod {
                        filtered.append(entry)
                    }
                } else {
                    filtered.append(entry)
                }
            }
        }
        return filtered
    }

    private struct MappedConflictCandidate {
        var key: MappedTargetKey
        var mod: PakWorkspaceMod
        var entry: ModMappedEntry

        var candidate: WorkspaceModConflictCandidate {
            WorkspaceModConflictCandidate(
                modFolderName: mod.folderName,
                originalName: entry.originalName,
                byteSize: entry.data.count,
                sha256: ModArchiveMapper.sha256Hex(uncompressedPayload: entry.data)
            )
        }
    }

    private static func groupedMappedCandidates(
        _ mappedMods: [(mod: PakWorkspaceMod, entries: [ModMappedEntry])]
    ) -> [MappedTargetKey: [MappedConflictCandidate]] {
        var grouped: [MappedTargetKey: [MappedConflictCandidate]] = [:]
        for mappedMod in mappedMods {
            for entry in mappedMod.entries {
                let key = MappedTargetKey(targetArchive: entry.targetArchive, internalName: entry.internalName)
                grouped[key, default: []].append(MappedConflictCandidate(key: key, mod: mappedMod.mod, entry: entry))
            }
        }
        return grouped
    }

    private static func makeWorkspaceConflict(
        candidates: [MappedConflictCandidate],
        selectedMod: String?
    ) -> WorkspaceModConflict {
        let sortedCandidates = candidates.sorted {
            if $0.mod.folderName != $1.mod.folderName {
                return $0.mod.folderName < $1.mod.folderName
            }
            return $0.entry.originalName < $1.entry.originalName
        }
        let key = sortedCandidates[0].key
        return WorkspaceModConflict(
            targetArchive: key.targetArchive,
            internalName: key.internalName,
            targetPath: key.internalName,
            candidates: sortedCandidates.map(\.candidate),
            selectedMod: selectedMod
        )
    }

    private static func isAutomaticallyMergedTarget(_ key: MappedTargetKey) -> Bool {
        guard key.targetArchive == .initial else {
            return false
        }
        return key.internalName == ModCustomizationPreset.internalName
            || (key.internalName.hasPrefix("[strings]\\") && key.internalName.hasSuffix(".str"))
    }

    private static func pruneConflictResolutionsIfNeeded(
        workspace: URL,
        manifest: inout PakWorkspaceManifest,
        grouped: [MappedTargetKey: [MappedConflictCandidate]]
    ) throws -> [MappedTargetKey: String] {
        var validSelections: [MappedTargetKey: String] = [:]
        var pruned = false
        var kept: [PakWorkspaceConflictResolution] = []

        for resolution in manifest.conflictResolutions {
            let key = MappedTargetKey(targetArchive: resolution.targetArchive, internalName: resolution.internalName)
            guard !isAutomaticallyMergedTarget(key),
                  let candidates = grouped[key],
                  candidates.count > 1,
                  candidates.contains(where: { $0.mod.folderName == resolution.selectedMod })
            else {
                pruned = true
                continue
            }
            kept.append(resolution)
            validSelections[key] = resolution.selectedMod
        }

        if pruned {
            manifest.conflictResolutions = kept
            try commitManifestOnly(workspace: workspace, manifest: manifest)
        }

        return validSelections
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
        let tempManifest = workspace.appendingPathComponent("snowrunner-workspace-\(UUID().uuidString).json")
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
