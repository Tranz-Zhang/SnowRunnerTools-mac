import Foundation
import Observation
@preconcurrency import SnowRunnerCore

@MainActor
@Observable
public final class WorkspaceViewModel {
    public enum Screen: Equatable {
        case launch
        case workspace
        case conflictDetails
    }

    public enum BusyState: Equatable {
        case idle
        case creatingWorkspace
        case openingWorkspace
        case addingMods
        case updatingMod
        case quickVerifying
        case building
    }

    @ObservationIgnored private let service: WorkspaceAppServicing
    @ObservationIgnored private let recentWorkspaceStore: RecentWorkspaceStoring
    @ObservationIgnored private var quickVerifyTask: Task<Void, Never>?
    @ObservationIgnored private var workspaceAccess: RecentWorkspaceAccess?

    public var screen: Screen = .launch
    public var busyState: BusyState = .idle
    public var summary: PakWorkspaceSummary?
    public var quickVerifyResult: WorkspaceQuickVerifyResult?
    public var errorMessage: String?
    public var buildResult: ModMergeResult?
    public var recentWorkspaces: [URL]

    public init(
        service: WorkspaceAppServicing = WorkspaceAppService(),
        recentWorkspaceStore: RecentWorkspaceStoring = RecentWorkspaceStore()
    ) {
        self.service = service
        self.recentWorkspaceStore = recentWorkspaceStore
        self.recentWorkspaces = recentWorkspaceStore.load()
    }

    public var isBusy: Bool {
        busyState != .idle
    }

    public var hasBuildOutput: Bool {
        summary?.buildOutput != nil
    }

    public var lastBuildOutputDate: Date? {
        summary?.buildOutput?.modifiedAt
    }

    public func createWorkspace(workspace: URL, initialPak: URL) async {
        let access = recentWorkspaceStore.startAccessing(workspace)
        await runWorkspaceMutation(
            .creatingWorkspace,
            recordsRecentWorkspace: true,
            newWorkspaceAccess: access
        ) {
            try await service.createWorkspace(workspace: access.url, initialPak: initialPak)
        }
    }

    public func openWorkspace(_ workspace: URL) async {
        cancelQuickVerify()
        let access = recentWorkspaceStore.startAccessing(workspace)
        busyState = .openingWorkspace
        errorMessage = nil
        quickVerifyResult = nil
        buildResult = nil
        do {
            let loaded = try await service.openWorkspace(access.url)
            summary = loaded
            replaceWorkspaceAccess(with: access)
            recordRecentWorkspace(loaded.workspace)
            screen = .workspace
            busyState = .idle
            startQuickVerify()
        } catch {
            access.stop()
            summary = nil
            quickVerifyResult = nil
            buildResult = nil
            screen = .launch
            busyState = .idle
            errorMessage = String(describing: error)
        }
    }

    public func removeRecentWorkspace(_ workspace: URL) {
        recentWorkspaceStore.remove(workspace)
        recentWorkspaces = recentWorkspaceStore.load()
    }

    public func closeWorkspace() {
        cancelQuickVerify()
        releaseWorkspaceAccess()
        summary = nil
        quickVerifyResult = nil
        buildResult = nil
        errorMessage = nil
        busyState = .idle
        screen = .launch
    }

    public func showWorkspace() {
        guard summary != nil else {
            screen = .launch
            return
        }
        screen = .workspace
    }

    public func showConflictDetails() {
        guard screen == .workspace,
              !(quickVerifyResult?.conflicts.isEmpty ?? true)
        else { return }
        screen = .conflictDetails
    }

    public func addMods(_ modPaks: [URL]) async {
        guard let workspace = summary?.workspace, !modPaks.isEmpty else { return }
        await runWorkspaceMutation(.addingMods) {
            try await service.addModPackages(workspace: workspace, packages: modPaks)
        }
    }

    public func setModEnabled(folderName: String, enabled: Bool) async {
        guard let workspace = summary?.workspace else { return }
        await runWorkspaceMutation(.updatingMod) {
            try await service.setModEnabled(workspace: workspace, folderName: folderName, enabled: enabled)
        }
    }

    public func removeMod(folderName: String) async {
        guard let workspace = summary?.workspace else { return }
        await runWorkspaceMutation(.updatingMod) {
            try await service.removeMod(workspace: workspace, folderName: folderName)
        }
    }

    public func resolveConflict(
        targetArchive: ModMergeTargetArchive,
        internalName: String,
        selectedMod: String
    ) async {
        guard let workspace = summary?.workspace else { return }
        await runConflictResolutionMutation {
            try await service.resolveConflict(
                workspace: workspace,
                targetArchive: targetArchive,
                internalName: internalName,
                selectedMod: selectedMod
            )
        }
    }

    public func clearConflictResolution(
        targetArchive: ModMergeTargetArchive,
        internalName: String
    ) async {
        guard let workspace = summary?.workspace else { return }
        await runConflictResolutionMutation {
            try await service.clearConflictResolution(
                workspace: workspace,
                targetArchive: targetArchive,
                internalName: internalName
            )
        }
    }

    public func build() async {
        guard let workspace = summary?.workspace else { return }
        busyState = .building
        errorMessage = nil
        buildResult = nil
        do {
            buildResult = try await service.build(workspace: workspace)
            summary = try await service.openWorkspace(workspace)
        } catch {
            errorMessage = String(describing: error)
        }
        busyState = .idle
    }

    private func runWorkspaceMutation(
        _ state: BusyState,
        recordsRecentWorkspace: Bool = false,
        newWorkspaceAccess: RecentWorkspaceAccess? = nil,
        operation: @MainActor () async throws -> PakWorkspaceSummary
    ) async {
        busyState = state
        errorMessage = nil
        buildResult = nil
        do {
            let loaded = try await operation()
            summary = loaded
            if let newWorkspaceAccess {
                replaceWorkspaceAccess(with: newWorkspaceAccess)
            }
            if recordsRecentWorkspace {
                recordRecentWorkspace(loaded.workspace)
            }
            screen = .workspace
            busyState = .idle
            startQuickVerify()
        } catch {
            newWorkspaceAccess?.stop()
            errorMessage = String(describing: error)
            busyState = .idle
        }
    }

    private func runConflictResolutionMutation(
        operation: @MainActor () async throws -> PakWorkspaceSummary
    ) async {
        busyState = .updatingMod
        errorMessage = nil
        buildResult = nil
        do {
            summary = try await operation()
            screen = .conflictDetails
            busyState = .idle
            startQuickVerify(preservingCurrentResult: true)
        } catch {
            errorMessage = String(describing: error)
            busyState = .idle
        }
    }

    private func startQuickVerify(preservingCurrentResult: Bool = false) {
        cancelQuickVerify()
        guard let workspace = summary?.workspace else { return }
        if !preservingCurrentResult {
            quickVerifyResult = nil
        }
        busyState = .quickVerifying
        quickVerifyTask = Task { [service] in
            do {
                let result = try await service.quickVerify(workspace: workspace)
                guard !Task.isCancelled else { return }
                quickVerifyResult = Self.appVisibleQuickVerifyResult(from: result)
                if busyState == .quickVerifying {
                    busyState = .idle
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = String(describing: error)
                if busyState == .quickVerifying {
                    busyState = .idle
                }
            }
        }
    }

    private func cancelQuickVerify() {
        quickVerifyTask?.cancel()
        quickVerifyTask = nil
    }

    private func replaceWorkspaceAccess(with access: RecentWorkspaceAccess) {
        workspaceAccess?.stop()
        workspaceAccess = access
    }

    private func releaseWorkspaceAccess() {
        workspaceAccess?.stop()
        workspaceAccess = nil
    }

    private func recordRecentWorkspace(_ workspace: URL) {
        recentWorkspaceStore.record(workspace)
        recentWorkspaces = recentWorkspaceStore.load()
    }

    private static func appVisibleQuickVerifyResult(from result: WorkspaceQuickVerifyResult) -> WorkspaceQuickVerifyResult {
        WorkspaceQuickVerifyResult(conflicts: result.conflicts.filter { !$0.isByteIdentical })
    }
}
