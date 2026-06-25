import Foundation
@preconcurrency import SnowRunnerCore

@MainActor
public protocol WorkspaceAppServicing {
    func createWorkspace(workspace: URL, initialPak: URL) async throws -> PakWorkspaceSummary
    func openWorkspace(_ workspace: URL) async throws -> PakWorkspaceSummary
    func addModPackages(workspace: URL, packages: [URL]) async throws -> PakWorkspaceSummary
    func setModEnabled(workspace: URL, folderName: String, enabled: Bool) async throws -> PakWorkspaceSummary
    func removeMod(workspace: URL, folderName: String) async throws -> PakWorkspaceSummary
    func resolveConflict(
        workspace: URL,
        targetArchive: ModMergeTargetArchive,
        internalName: String,
        selectedMod: String
    ) async throws -> PakWorkspaceSummary
    func clearConflictResolution(
        workspace: URL,
        targetArchive: ModMergeTargetArchive,
        internalName: String
    ) async throws -> PakWorkspaceSummary
    func quickVerify(workspace: URL) async throws -> WorkspaceQuickVerifyResult
    func build(workspace: URL) async throws -> ModMergeResult
}

public struct WorkspaceAppService: WorkspaceAppServicing {
    public init() {}

    public func createWorkspace(workspace: URL, initialPak: URL) async throws -> PakWorkspaceSummary {
        try await detachedValue(priority: .userInitiated) {
            _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: initialPak)
            return try PakWorkspaceManager.summary(workspace: workspace)
        }
    }

    public func openWorkspace(_ workspace: URL) async throws -> PakWorkspaceSummary {
        try await detachedValue(priority: .userInitiated) {
            try PakWorkspaceManager.summary(workspace: workspace)
        }
    }

    public func addModPackages(workspace: URL, packages: [URL]) async throws -> PakWorkspaceSummary {
        try await detachedValue(priority: .userInitiated) {
            _ = try PakWorkspaceManager.addModPackages(workspace: workspace, packages: packages)
            return try PakWorkspaceManager.summary(workspace: workspace)
        }
    }

    public func setModEnabled(workspace: URL, folderName: String, enabled: Bool) async throws -> PakWorkspaceSummary {
        try await detachedValue(priority: .userInitiated) {
            try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: folderName, enabled: enabled)
            return try PakWorkspaceManager.summary(workspace: workspace)
        }
    }

    public func removeMod(workspace: URL, folderName: String) async throws -> PakWorkspaceSummary {
        try await detachedValue(priority: .userInitiated) {
            try PakWorkspaceManager.removeMod(workspace: workspace, folderName: folderName)
            return try PakWorkspaceManager.summary(workspace: workspace)
        }
    }

    public func resolveConflict(
        workspace: URL,
        targetArchive: ModMergeTargetArchive,
        internalName: String,
        selectedMod: String
    ) async throws -> PakWorkspaceSummary {
        let targetArchiveRawValue = targetArchive.rawValue
        return try await detachedValue(priority: .userInitiated) {
            let targetArchive = ModMergeTargetArchive(rawValue: targetArchiveRawValue)!
            try PakWorkspaceManager.resolveConflict(
                workspace: workspace,
                targetArchive: targetArchive,
                internalName: internalName,
                selectedMod: selectedMod
            )
            return try PakWorkspaceManager.summary(workspace: workspace)
        }
    }

    public func clearConflictResolution(
        workspace: URL,
        targetArchive: ModMergeTargetArchive,
        internalName: String
    ) async throws -> PakWorkspaceSummary {
        let targetArchiveRawValue = targetArchive.rawValue
        return try await detachedValue(priority: .userInitiated) {
            let targetArchive = ModMergeTargetArchive(rawValue: targetArchiveRawValue)!
            try PakWorkspaceManager.clearConflictResolution(
                workspace: workspace,
                targetArchive: targetArchive,
                internalName: internalName
            )
            return try PakWorkspaceManager.summary(workspace: workspace)
        }
    }

    public func quickVerify(workspace: URL) async throws -> WorkspaceQuickVerifyResult {
        try await detachedValue(priority: .utility) {
            try PakWorkspaceManager.quickVerify(workspace: workspace)
        }
    }

    public func build(workspace: URL) async throws -> ModMergeResult {
        try await detachedValue(priority: .userInitiated) {
            try PakWorkspaceManager.build(workspace: workspace)
        }
    }
}

@MainActor
private func detachedValue<Value>(
    priority: TaskPriority,
    operation: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try await Task.detached(priority: priority) {
        UncheckedSendableBox(try operation())
    }.value.value
}

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
