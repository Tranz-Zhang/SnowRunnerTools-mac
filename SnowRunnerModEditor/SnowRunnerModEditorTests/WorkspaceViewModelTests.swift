import Foundation
@preconcurrency @testable import SnowRunnerCore
@testable import SnowRunnerModEditor
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

    func testOpenWorkspaceExposesPreviousBuildOutputWithoutBuildResult() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let modifiedAt = Date(timeIntervalSince1970: 1_803_897_600)
        let service = FakeWorkspaceService()
        service.summary = summary(
            workspace: workspace,
            mods: [],
            buildOutput: PakWorkspaceBuildOutputSummary(
                initialPak: workspace.appendingPathComponent("build/initial.pak"),
                report: workspace.appendingPathComponent("build/workspace-build-report.md"),
                modifiedAt: modifiedAt
            )
        )
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let model = WorkspaceViewModel(service: service)

        await model.openWorkspace(workspace)
        await waitForQuickVerify()

        XCTAssertNil(model.buildResult)
        XCTAssertTrue(model.hasBuildOutput)
        XCTAssertEqual(model.lastBuildOutputDate, modifiedAt)
    }

    func testOpenInvalidWorkspaceStaysOnLaunchScreen() async {
        let service = FakeWorkspaceService()
        service.openWorkspaceError = PakWorkspaceError.missingManifest("/tmp/bad/snowrunner-workspace.json")
        let model = WorkspaceViewModel(service: service)

        await model.openWorkspace(URL(fileURLWithPath: "/tmp/bad", isDirectory: true))

        XCTAssertEqual(model.screen, .launch)
        XCTAssertNil(model.summary)
        XCTAssertNotNil(model.errorMessage)
    }

    func testOpenWorkspaceRecordsRecentWorkspaceAfterSuccessfulOpen() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let store = makeRecentWorkspaceStore()
        let model = WorkspaceViewModel(service: service, recentWorkspaceStore: store)

        await model.openWorkspace(workspace)

        XCTAssertEqual(model.recentWorkspaces, [workspace])
        XCTAssertEqual(store.load(), [workspace])
    }

    func testOpenWorkspaceUsesRecentWorkspaceStoreAccessWhileOpening() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let store = makeRecentWorkspaceStore()
        service.onOpenWorkspace = { _ in
            XCTAssertTrue(store.isAccessingWorkspace)
        }
        let model = WorkspaceViewModel(service: service, recentWorkspaceStore: store)

        await model.openWorkspace(workspace)

        XCTAssertEqual(store.accessedWorkspaces, [workspace])
        XCTAssertTrue(store.isAccessingWorkspace)
        model.closeWorkspace()
        XCTAssertFalse(store.isAccessingWorkspace)
    }

    func testOpenInvalidWorkspaceDoesNotRecordRecentWorkspace() async {
        let workspace = URL(fileURLWithPath: "/tmp/bad", isDirectory: true)
        let service = FakeWorkspaceService()
        service.openWorkspaceError = PakWorkspaceError.missingManifest("/tmp/bad/snowrunner-workspace.json")
        let store = makeRecentWorkspaceStore()
        let model = WorkspaceViewModel(service: service, recentWorkspaceStore: store)

        await model.openWorkspace(workspace)

        XCTAssertEqual(model.recentWorkspaces, [])
        XCTAssertEqual(store.load(), [])
    }

    func testCreateWorkspaceRecordsRecentWorkspaceAfterSuccessfulCreate() async {
        let workspace = URL(fileURLWithPath: "/tmp/created-workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let store = makeRecentWorkspaceStore()
        let model = WorkspaceViewModel(service: service, recentWorkspaceStore: store)

        await model.createWorkspace(
            workspace: workspace,
            initialPak: URL(fileURLWithPath: "/tmp/initial.pak")
        )

        XCTAssertEqual(model.recentWorkspaces, [workspace])
        XCTAssertEqual(store.load(), [workspace])
    }

    func testRemoveRecentWorkspaceUpdatesModelAndStore() {
        let first = URL(fileURLWithPath: "/tmp/first", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/second", isDirectory: true)
        let store = makeRecentWorkspaceStore()
        store.record(first)
        store.record(second)
        let model = WorkspaceViewModel(service: FakeWorkspaceService(), recentWorkspaceStore: store)

        model.removeRecentWorkspace(second)

        XCTAssertEqual(model.recentWorkspaces, [first])
        XCTAssertEqual(store.load(), [first])
    }

    func testConflictDetailsScreenRequiresConflictsAndCanReturnToWorkspace() async {
        let service = FakeWorkspaceService()
        let model = WorkspaceViewModel(service: service)

        model.showConflictDetails()
        XCTAssertEqual(model.screen, .launch)

        model.summary = summary(workspace: URL(fileURLWithPath: "/tmp/workspace", isDirectory: true), mods: [])
        model.screen = .workspace
        model.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        model.showConflictDetails()
        XCTAssertEqual(model.screen, .workspace)

        model.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
            WorkspaceModConflict(targetPath: "classes/trucks/demo.xml", mods: ["first", "second"])
        ])
        model.showConflictDetails()
        XCTAssertEqual(model.screen, .conflictDetails)

        model.showWorkspace()
        XCTAssertEqual(model.screen, .workspace)
    }

    func testQuickVerifyFiltersByteIdenticalConflictsFromAppModel() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
            byteIdenticalConflict()
        ])
        let model = WorkspaceViewModel(service: service)

        await model.openWorkspace(workspace)
        await waitForQuickVerify()

        XCTAssertEqual(model.quickVerifyResult?.conflicts, [])
        XCTAssertEqual(model.quickVerifyResult?.unresolvedConflictCount, 0)
        model.showConflictDetails()
        XCTAssertEqual(model.screen, .workspace)
    }

    func testQuickVerifyKeepsOnlyDifferentByteConflictsInAppModel() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
            byteIdenticalConflict(),
            differentByteConflict()
        ])
        let model = WorkspaceViewModel(service: service)

        await model.openWorkspace(workspace)
        await waitForQuickVerify()

        XCTAssertEqual(model.quickVerifyResult?.conflicts, [differentByteConflict()])
        XCTAssertEqual(model.quickVerifyResult?.unresolvedConflictCount, 1)
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
        service.openWorkspaceError = PakWorkspaceError.missingManifest("/tmp/bad/snowrunner-workspace.json")
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
        XCTAssertEqual(service.addedPackages, [URL(fileURLWithPath: "/mods/demo.pak")])
        XCTAssertEqual(service.quickVerifyCalls, 2)
    }

    func testModsSortedByNameUsesCaseInsensitiveLocalizedOrder() {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let model = WorkspaceViewModel(service: FakeWorkspaceService())
        model.summary = summary(workspace: workspace, mods: [
            modSummary(folderName: "zebra-pack", archiveName: "zebra.pak", workspace: workspace),
            modSummary(folderName: "Alpha-Pack", archiveName: "alpha.pak", workspace: workspace),
            modSummary(folderName: "beta-pack", archiveName: "beta.pak", workspace: workspace)
        ])

        XCTAssertEqual(model.modsSortedByName.map(\.folderName), [
            "Alpha-Pack",
            "beta-pack",
            "zebra-pack"
        ])
    }

    func testAddModsMarksOnlyNewlyAddedFolderNames() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [
            modSummary(folderName: "existing", archiveName: "existing.pak", workspace: workspace)
        ])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(workspace)
        await waitForQuickVerify()

        service.summary = summary(workspace: workspace, mods: [
            modSummary(folderName: "existing", archiveName: "existing.pak", workspace: workspace),
            modSummary(folderName: "new-alpha", archiveName: "new-alpha.pak", workspace: workspace),
            modSummary(folderName: "new-beta", archiveName: "new-beta.pak", workspace: workspace)
        ])
        await model.addMods([
            URL(fileURLWithPath: "/mods/new-alpha.pak"),
            URL(fileURLWithPath: "/mods/new-beta.pak")
        ])
        await waitForQuickVerify()

        XCTAssertFalse(model.isNewMod(folderName: "existing"))
        XCTAssertTrue(model.isNewMod(folderName: "new-alpha"))
        XCTAssertTrue(model.isNewMod(folderName: "new-beta"))
    }

    func testOpeningAndClosingWorkspaceClearsNewModMarkers() async throws {
        let firstWorkspace = URL(fileURLWithPath: "/tmp/first-workspace", isDirectory: true)
        let secondWorkspace = URL(fileURLWithPath: "/tmp/second-workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: firstWorkspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(firstWorkspace)
        await waitForQuickVerify()

        service.summary = summary(workspace: firstWorkspace, mods: [
            modSummary(folderName: "new-alpha", archiveName: "new-alpha.pak", workspace: firstWorkspace)
        ])
        await model.addMods([URL(fileURLWithPath: "/mods/new-alpha.pak")])
        await waitForQuickVerify()
        XCTAssertTrue(model.isNewMod(folderName: "new-alpha"))

        service.summary = summary(workspace: secondWorkspace, mods: [
            modSummary(folderName: "new-alpha", archiveName: "new-alpha.pak", workspace: secondWorkspace)
        ])
        await model.openWorkspace(secondWorkspace)
        await waitForQuickVerify()
        XCTAssertFalse(model.isNewMod(folderName: "new-alpha"))

        service.summary = summary(workspace: secondWorkspace, mods: [
            modSummary(folderName: "new-beta", archiveName: "new-beta.pak", workspace: secondWorkspace)
        ])
        await model.addMods([URL(fileURLWithPath: "/mods/new-beta.pak")])
        await waitForQuickVerify()
        XCTAssertTrue(model.isNewMod(folderName: "new-beta"))

        model.closeWorkspace()
        XCTAssertFalse(model.isNewMod(folderName: "new-beta"))
    }

    func testRemoveModPrunesNewModMarker() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(workspace)
        await waitForQuickVerify()

        service.summary = summary(workspace: workspace, mods: [
            modSummary(folderName: "new-alpha", archiveName: "new-alpha.pak", workspace: workspace)
        ])
        await model.addMods([URL(fileURLWithPath: "/mods/new-alpha.pak")])
        await waitForQuickVerify()
        XCTAssertTrue(model.isNewMod(folderName: "new-alpha"))

        service.summary = summary(workspace: workspace, mods: [])
        await model.removeMod(folderName: "new-alpha")
        await waitForQuickVerify()

        XCTAssertFalse(model.isNewMod(folderName: "new-alpha"))
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

    func testFailedBuildClearsPreviousBuildResultAndReportsError() async {
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

        service.buildResult = nil
        service.error = PakWorkspaceError.missingSourceCache("/tmp/workspace/.snowrunner/sources/demo.pak")
        await model.build()

        XCTAssertNil(model.buildResult)
        XCTAssertEqual(
            model.errorMessage,
            "Workspace manifest references missing cached source PAK: /tmp/workspace/.snowrunner/sources/demo.pak"
        )
    }

    func testResolveConflictCallsServiceRefreshesQuickVerifyAndStaysOnConflictDetails() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
            WorkspaceModConflict(
                targetArchive: .initial,
                internalName: "[media]\\classes\\trucks\\same.xml",
                targetPath: "[media]\\classes\\trucks\\same.xml",
                candidates: [
                    WorkspaceModConflictCandidate(modFolderName: "first", originalName: "classes/trucks/same.xml", byteSize: 1, sha256: "a"),
                    WorkspaceModConflictCandidate(modFolderName: "second", originalName: "classes/trucks/same.xml", byteSize: 1, sha256: "b")
                ]
            )
        ])
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(workspace)
        await waitForQuickVerify()
        model.showConflictDetails()

        await model.resolveConflict(
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "second"
        )
        await waitForQuickVerify()

        XCTAssertEqual(service.resolvedConflicts, [
            FakeWorkspaceService.ResolvedConflict(
                workspace: workspace,
                targetArchive: .initial,
                internalName: "[media]\\classes\\trucks\\same.xml",
                selectedMod: "second"
            )
        ])
        XCTAssertEqual(model.screen, .conflictDetails)
        XCTAssertEqual(service.quickVerifyCalls, 2)
    }

    func testResolveConflictKeepsCurrentConflictDetailsVisibleWhileQuickVerifyRefreshes() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let unresolvedConflict = WorkspaceModConflict(
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            targetPath: "[media]\\classes\\trucks\\same.xml",
            candidates: [
                WorkspaceModConflictCandidate(modFolderName: "first", originalName: "classes/trucks/same.xml", byteSize: 1, sha256: "a"),
                WorkspaceModConflictCandidate(modFolderName: "second", originalName: "classes/trucks/same.xml", byteSize: 1, sha256: "b")
            ]
        )
        let originalResult = WorkspaceQuickVerifyResult(conflicts: [unresolvedConflict])
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = originalResult
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(workspace)
        await waitForQuickVerify()
        model.showConflictDetails()

        service.quickVerifyDelayNanoseconds = 50_000_000
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        await model.resolveConflict(
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "second"
        )

        XCTAssertEqual(model.screen, .conflictDetails)
        XCTAssertEqual(model.busyState, .quickVerifying)
        XCTAssertEqual(model.quickVerifyResult, originalResult)
    }

    func testClearConflictResolutionCallsServiceRefreshesQuickVerifyAndStaysOnConflictDetails() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
            WorkspaceModConflict(
                targetArchive: .initial,
                internalName: "[media]\\classes\\trucks\\same.xml",
                targetPath: "[media]\\classes\\trucks\\same.xml",
                candidates: [
                    WorkspaceModConflictCandidate(modFolderName: "first", originalName: "classes/trucks/same.xml", byteSize: 1, sha256: "a"),
                    WorkspaceModConflictCandidate(modFolderName: "second", originalName: "classes/trucks/same.xml", byteSize: 1, sha256: "b")
                ],
                selectedMod: "second"
            )
        ])
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(workspace)
        await waitForQuickVerify()
        model.showConflictDetails()

        await model.clearConflictResolution(
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml"
        )
        await waitForQuickVerify()

        XCTAssertEqual(service.clearedConflicts, [
            FakeWorkspaceService.ClearedConflict(
                workspace: workspace,
                targetArchive: .initial,
                internalName: "[media]\\classes\\trucks\\same.xml"
            )
        ])
        XCTAssertEqual(model.screen, .conflictDetails)
        XCTAssertEqual(service.quickVerifyCalls, 2)
    }

    private func summary(
        workspace: URL,
        mods: [PakWorkspaceModSummary],
        buildOutput: PakWorkspaceBuildOutputSummary? = nil
    ) -> PakWorkspaceSummary {
        PakWorkspaceSummary(
            workspace: workspace,
            initialSourcePath: "/game/initial.pak",
            mods: mods,
            buildInitialPak: workspace.appendingPathComponent("build/initial.pak"),
            buildReport: workspace.appendingPathComponent("build/workspace-build-report.md"),
            buildOutput: buildOutput
        )
    }

    private func modSummary(
        folderName: String,
        archiveName: String,
        workspace: URL,
        enabled: Bool = true
    ) -> PakWorkspaceModSummary {
        PakWorkspaceModSummary(
            folderName: folderName,
            archiveName: archiveName,
            sourcePath: "/mods/\(archiveName)",
            modDirectory: workspace.appendingPathComponent("mods/\(folderName)", isDirectory: true),
            sourceCache: workspace.appendingPathComponent(".snowrunner/sources/\(archiveName)"),
            enabled: enabled
        )
    }

    private func waitForQuickVerify() async {
        await Task.yield()
        await Task.yield()
    }

    private func makeRecentWorkspaceStore() -> FakeRecentWorkspaceStore {
        FakeRecentWorkspaceStore()
    }

    private func byteIdenticalConflict() -> WorkspaceModConflict {
        WorkspaceModConflict(
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            targetPath: "[media]\\classes\\trucks\\same.xml",
            candidates: [
                WorkspaceModConflictCandidate(modFolderName: "first", originalName: "classes/trucks/same.xml", byteSize: 1, sha256: "same"),
                WorkspaceModConflictCandidate(modFolderName: "second", originalName: "classes/trucks/same.xml", byteSize: 1, sha256: "same")
            ]
        )
    }

    private func differentByteConflict() -> WorkspaceModConflict {
        WorkspaceModConflict(
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\different.xml",
            targetPath: "[media]\\classes\\trucks\\different.xml",
            candidates: [
                WorkspaceModConflictCandidate(modFolderName: "first", originalName: "classes/trucks/different.xml", byteSize: 1, sha256: "a"),
                WorkspaceModConflictCandidate(modFolderName: "second", originalName: "classes/trucks/different.xml", byteSize: 1, sha256: "b")
            ]
        )
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
    struct ResolvedConflict: Equatable {
        var workspace: URL
        var targetArchive: ModMergeTargetArchive
        var internalName: String
        var selectedMod: String
    }

    struct ClearedConflict: Equatable {
        var workspace: URL
        var targetArchive: ModMergeTargetArchive
        var internalName: String
    }

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
    var resolvedConflicts: [ResolvedConflict] = []
    var clearedConflicts: [ClearedConflict] = []
    var addedPackages: [URL] = []
    var onOpenWorkspace: ((URL) -> Void)?

    func createWorkspace(workspace: URL, initialPak: URL) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        return summary
    }

    func openWorkspace(_ workspace: URL) async throws -> PakWorkspaceSummary {
        if let openWorkspaceError { throw openWorkspaceError }
        if let error { throw error }
        onOpenWorkspace?(workspace)
        return summary
    }

    func addModPackages(workspace: URL, packages: [URL]) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        addedPackages = packages
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

    func resolveConflict(
        workspace: URL,
        targetArchive: ModMergeTargetArchive,
        internalName: String,
        selectedMod: String
    ) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        resolvedConflicts.append(ResolvedConflict(
            workspace: workspace,
            targetArchive: targetArchive,
            internalName: internalName,
            selectedMod: selectedMod
        ))
        return summary
    }

    func clearConflictResolution(
        workspace: URL,
        targetArchive: ModMergeTargetArchive,
        internalName: String
    ) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        clearedConflicts.append(ClearedConflict(
            workspace: workspace,
            targetArchive: targetArchive,
            internalName: internalName
        ))
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

private final class FakeRecentWorkspaceStore: RecentWorkspaceStoring {
    private var workspaces: [URL] = []
    var accessedWorkspaces: [URL] = []
    var isAccessingWorkspace = false

    func load() -> [URL] {
        workspaces
    }

    func record(_ workspace: URL) {
        workspaces = [workspace] + workspaces.filter { $0 != workspace }
    }

    func remove(_ workspace: URL) {
        workspaces.removeAll { $0 == workspace }
    }

    func startAccessing(_ workspace: URL) -> RecentWorkspaceAccess {
        accessedWorkspaces.append(workspace)
        isAccessingWorkspace = true
        return RecentWorkspaceAccess(url: workspace) {
            self.isAccessingWorkspace = false
        }
    }
}
