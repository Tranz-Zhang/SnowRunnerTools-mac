import Foundation
@preconcurrency @testable import SnowRunnerTool
@testable import SnowRunnerModEditorCore
import XCTest

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
    func testOpenWorkspaceEntersWorkspaceScreenAndRunsQuickVerify() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let model = WorkspaceViewModel(service: service)

        await model.openWorkspace(workspace)
        await waitForQuickVerify()

        XCTAssertEqual(model.screen, .workspace)
        XCTAssertEqual(model.summary?.workspace, workspace)
        XCTAssertEqual(model.quickVerifyResult, WorkspaceQuickVerifyResult(conflicts: []))
        XCTAssertEqual(service.quickVerifyCalls, 1)
    }

    func testOpenInvalidWorkspaceStaysOnLaunchScreen() async {
        let service = FakeWorkspaceService()
        service.openWorkspaceError = PakWorkspaceError.missingManifest("/tmp/bad/.snowrunner-workspace.json")
        let model = WorkspaceViewModel(service: service)

        await model.openWorkspace(URL(fileURLWithPath: "/tmp/bad", isDirectory: true))

        XCTAssertEqual(model.screen, .launch)
        XCTAssertNil(model.summary)
        XCTAssertNotNil(model.errorMessage)
    }

    func testOldQuickVerifyCannotUpdateStateAfterFailedOpen() async {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
            WorkspaceModConflict(targetPath: "classes/trucks/stale.xml", mods: ["old"])
        ])
        service.quickVerifyDelayNanoseconds = 50_000_000
        let model = WorkspaceViewModel(service: service)

        await model.openWorkspace(workspace)
        service.openWorkspaceError = PakWorkspaceError.missingManifest("/tmp/bad/.snowrunner-workspace.json")
        await model.openWorkspace(URL(fileURLWithPath: "/tmp/bad", isDirectory: true))

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.screen, .launch)
        XCTAssertNil(model.summary)
        XCTAssertNil(model.quickVerifyResult)
        XCTAssertNil(model.buildResult)
        XCTAssertNotNil(model.errorMessage)
    }

    func testAddModsRefreshesSummaryAndRunsQuickVerify() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(workspace)
        await waitForQuickVerify()

        service.summary = summary(workspace: workspace, mods: [
            PakWorkspaceModSummary(
                folderName: "demo",
                archiveName: "demo.pak",
                sourcePath: "/mods/demo.pak",
                modDirectory: workspace.appendingPathComponent("mods/demo", isDirectory: true),
                sourceCache: workspace.appendingPathComponent(".snowrunner/sources/demo.pak"),
                enabled: true
            )
        ])
        await model.addMods([URL(fileURLWithPath: "/mods/demo.pak")])
        await waitForQuickVerify()

        XCTAssertEqual(model.summary?.mods.map(\.folderName), ["demo"])
        XCTAssertEqual(service.quickVerifyCalls, 2)
    }

    func testAddModsClearsPreviousBuildResult() async {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        service.buildResult = makeBuildResult()
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(workspace)
        await waitForQuickVerify()
        await model.build()
        XCTAssertNotNil(model.buildResult)

        service.summary = summary(workspace: workspace, mods: [
            PakWorkspaceModSummary(
                folderName: "demo",
                archiveName: "demo.pak",
                sourcePath: "/mods/demo.pak",
                modDirectory: workspace.appendingPathComponent("mods/demo", isDirectory: true),
                sourceCache: workspace.appendingPathComponent(".snowrunner/sources/demo.pak"),
                enabled: true
            )
        ])
        await model.addMods([URL(fileURLWithPath: "/mods/demo.pak")])

        XCTAssertNil(model.buildResult)
    }

    private func summary(workspace: URL, mods: [PakWorkspaceModSummary]) -> PakWorkspaceSummary {
        PakWorkspaceSummary(
            workspace: workspace,
            initialSourcePath: "/game/initial.pak",
            mods: mods,
            buildInitialPak: workspace.appendingPathComponent("build/initial.pak"),
            buildReport: workspace.appendingPathComponent("build/workspace-build-report.md")
        )
    }

    private func waitForQuickVerify() async {
        await Task.yield()
        await Task.yield()
    }

    private func makeBuildResult() -> ModMergeResult {
        ModMergeResult(
            plan: ModMergePlan(
                baseEntryCount: 0,
                mappedModEntryCount: 0,
                netNewOuterPakEntryCount: 0,
                collisions: [],
                textureBaseEntryCount: 0,
                netNewTexturePakEntryCount: 0,
                textureCollisions: [],
                sharedTextureEntryCount: 0,
                netNewSharedTexturePakEntryCount: 0,
                sharedTextureCollisions: [],
                stringMergeEntryCount: 0,
                customizationPresetMergeEntryCount: 0,
                duplicateIdenticalMappedNames: [],
                loadListSourceOverrides: [],
                loadListCandidateRecords: [],
                netNewLoadListRecordCount: 0,
                texturesInInitial: true
            ),
            outputURL: URL(fileURLWithPath: "/tmp/workspace/build/initial.pak"),
            outputTexturesURL: nil,
            outputSharedTexturesURL: nil,
            writtenEntryCount: 0,
            writtenTextureEntryCount: nil,
            writtenSharedTextureEntryCount: nil
        )
    }
}

private final class FakeWorkspaceService: WorkspaceAppServicing {
    var summary = PakWorkspaceSummary(
        workspace: URL(fileURLWithPath: "/tmp/workspace", isDirectory: true),
        initialSourcePath: "/game/initial.pak",
        mods: [],
        buildInitialPak: URL(fileURLWithPath: "/tmp/workspace/build/initial.pak"),
        buildReport: URL(fileURLWithPath: "/tmp/workspace/build/workspace-build-report.md")
    )
    var quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
    var buildResult: ModMergeResult?
    var error: Error?
    var openWorkspaceError: Error?
    var quickVerifyCalls = 0
    var quickVerifyDelayNanoseconds: UInt64 = 0

    func createWorkspace(workspace: URL, initialPak: URL) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        return summary
    }

    func openWorkspace(_ workspace: URL) async throws -> PakWorkspaceSummary {
        if let openWorkspaceError { throw openWorkspaceError }
        if let error { throw error }
        return summary
    }

    func addMods(workspace: URL, modPaks: [URL]) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        return summary
    }

    func setModEnabled(workspace: URL, folderName: String, enabled: Bool) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        return summary
    }

    func removeMod(workspace: URL, folderName: String) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        return summary
    }

    func quickVerify(workspace: URL) async throws -> WorkspaceQuickVerifyResult {
        quickVerifyCalls += 1
        if quickVerifyDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: quickVerifyDelayNanoseconds)
        }
        if let error { throw error }
        return quickVerifyResult
    }

    func build(workspace: URL) async throws -> ModMergeResult {
        if let error { throw error }
        if let buildResult { return buildResult }
        throw FakeWorkspaceError.unimplementedBuild
    }
}

private enum FakeWorkspaceError: Error {
    case unimplementedBuild
}
