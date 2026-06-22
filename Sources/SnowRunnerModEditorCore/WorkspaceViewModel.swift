import Foundation
import Observation
@preconcurrency import SnowRunnerTool

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
    @ObservationIgnored private var quickVerifyTask: Task<Void, Never>?

    public var screen: Screen = .launch
    public var busyState: BusyState = .idle
    public var summary: PakWorkspaceSummary?
    public var quickVerifyResult: WorkspaceQuickVerifyResult?
    public var errorMessage: String?
    public var buildResult: ModMergeResult?

    public init(service: WorkspaceAppServicing = WorkspaceAppService()) {
        self.service = service
    }

    public var isBusy: Bool {
        busyState != .idle
    }

    public func createWorkspace(workspace: URL, initialPak: URL) async {
        await runWorkspaceMutation(.creatingWorkspace) {
            try await service.createWorkspace(workspace: workspace, initialPak: initialPak)
        }
    }

    public func openWorkspace(_ workspace: URL) async {
        cancelQuickVerify()
        busyState = .openingWorkspace
        errorMessage = nil
        quickVerifyResult = nil
        buildResult = nil
        do {
            let loaded = try await service.openWorkspace(workspace)
            summary = loaded
            screen = .workspace
            busyState = .idle
            startQuickVerify()
        } catch {
            summary = nil
            quickVerifyResult = nil
            buildResult = nil
            screen = .launch
            busyState = .idle
            errorMessage = String(describing: error)
        }
    }

    public func closeWorkspace() {
        cancelQuickVerify()
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
            try await service.addMods(workspace: workspace, modPaks: modPaks)
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

    public func build() async {
        guard let workspace = summary?.workspace else { return }
        busyState = .building
        errorMessage = nil
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
        operation: @MainActor () async throws -> PakWorkspaceSummary
    ) async {
        busyState = state
        errorMessage = nil
        buildResult = nil
        do {
            summary = try await operation()
            screen = .workspace
            busyState = .idle
            startQuickVerify()
        } catch {
            errorMessage = String(describing: error)
            busyState = .idle
        }
    }

    private func startQuickVerify() {
        cancelQuickVerify()
        guard let workspace = summary?.workspace else { return }
        quickVerifyResult = nil
        busyState = .quickVerifying
        quickVerifyTask = Task { [service] in
            do {
                let result = try await service.quickVerify(workspace: workspace)
                guard !Task.isCancelled else { return }
                quickVerifyResult = result
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
}
