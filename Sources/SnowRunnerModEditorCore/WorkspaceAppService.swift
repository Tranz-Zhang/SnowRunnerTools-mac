import Foundation
@preconcurrency import SnowRunnerTool

@MainActor
public protocol WorkspaceAppServicing {
    func createWorkspace(workspace: URL, initialPak: URL) async throws -> PakWorkspaceSummary
    func openWorkspace(_ workspace: URL) async throws -> PakWorkspaceSummary
    func addMods(workspace: URL, modPaks: [URL]) async throws -> PakWorkspaceSummary
    func setModEnabled(workspace: URL, folderName: String, enabled: Bool) async throws -> PakWorkspaceSummary
    func removeMod(workspace: URL, folderName: String) async throws -> PakWorkspaceSummary
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

    public func addMods(workspace: URL, modPaks: [URL]) async throws -> PakWorkspaceSummary {
        try await detachedValue(priority: .userInitiated) {
            _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: modPaks)
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
