# Mod List Sorting And New Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show workspace mods sorted by name and tag mods added during the current open workspace lifetime as `NEW`.

**Architecture:** Keep manifest and merge semantics unchanged. Add presentation-only state to `WorkspaceViewModel`: one computed sorted mod list and one in-memory set of newly added mod folder names. `WorkspaceOperationView` renders those values without owning workspace state.

**Tech Stack:** Swift, SwiftUI, Observation, XCTest, existing `SnowRunnerCore` workspace summary models.

---

## File Structure

- Modify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceViewModel.swift`
  - Owns current-workspace lifetime state for `newModFolderNames`.
  - Exposes `modsSortedByName` and `isNewMod(folderName:)` for the view.
  - Marks newly added mods only after `addMods(_:)` succeeds.
  - Clears markers when opening, creating, or closing a workspace.
  - Prunes markers after removal.
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceOperationView.swift`
  - Iterates `viewModel.modsSortedByName`.
  - Shows a compact `NEW` badge next to rows whose folder name is marked new.
- Modify: `SnowRunnerModEditor/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`
  - Tests sorting, new marker creation, new marker clearing, and removal pruning.

No `SnowRunnerCore` changes are needed. Sorting and the `NEW` badge are UI presentation behavior, not workspace manifest behavior.

---

### Task 1: Add View-Model Sorting And New-Mod State

**Files:**
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceViewModel.swift:29-145`
- Test: `SnowRunnerModEditor/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`

- [ ] **Step 1: Write failing tests for sorted mods and new markers**

Add these helper and tests inside `WorkspaceViewModelTests`, near the existing add-mod tests:

```swift
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
```

Add this test helper near the existing `summary(...)` helper:

```swift
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
```

- [ ] **Step 2: Run focused tests and verify they fail**

Run:

```bash
xcodebuild test -project SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj -scheme SnowRunnerModEditor -destination "platform=macOS" -only-testing:SnowRunnerModEditorTests/WorkspaceViewModelTests
```

Expected: FAIL because `modsSortedByName` and `isNewMod(folderName:)` do not exist.

- [ ] **Step 3: Implement the view-model state and computed list**

In `WorkspaceViewModel`, add a public marker set near `recentWorkspaces`:

```swift
public var newModFolderNames: Set<String> = []
```

Add computed/read helper APIs near `lastBuildOutputDate`:

```swift
public var modsSortedByName: [PakWorkspaceModSummary] {
    (summary?.mods ?? []).sorted { lhs, rhs in
        lhs.folderName.localizedCaseInsensitiveCompare(rhs.folderName) == .orderedAscending
    }
}

public func isNewMod(folderName: String) -> Bool {
    newModFolderNames.contains(folderName)
}
```

Update `createWorkspace(workspace:initialPak:)` to clear markers before starting a new workspace lifetime:

```swift
public func createWorkspace(workspace: URL, initialPak: URL) async {
    newModFolderNames = []
    let access = recentWorkspaceStore.startAccessing(workspace)
    await runWorkspaceMutation(
        .creatingWorkspace,
        recordsRecentWorkspace: true,
        newWorkspaceAccess: access
    ) {
        try await service.createWorkspace(workspace: access.url, initialPak: initialPak)
    }
}
```

Update `openWorkspace(_:)` to clear markers before loading:

```swift
public func openWorkspace(_ workspace: URL) async {
    cancelQuickVerify()
    newModFolderNames = []
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
```

Update `closeWorkspace()` to clear markers:

```swift
public func closeWorkspace() {
    cancelQuickVerify()
    releaseWorkspaceAccess()
    summary = nil
    quickVerifyResult = nil
    buildResult = nil
    errorMessage = nil
    newModFolderNames = []
    busyState = .idle
    screen = .launch
}
```

Update `addMods(_:)` to compute the before/after folder-name difference only after a successful add:

```swift
public func addMods(_ modPaks: [URL]) async {
    guard let workspace = summary?.workspace, !modPaks.isEmpty else { return }
    let existingFolderNames = Set(summary?.mods.map(\.folderName) ?? [])
    await runWorkspaceMutation(.addingMods) {
        try await service.addModPackages(workspace: workspace, packages: modPaks)
    }
    let currentFolderNames = Set(summary?.mods.map(\.folderName) ?? [])
    newModFolderNames.formUnion(currentFolderNames.subtracting(existingFolderNames))
}
```

Update `removeMod(folderName:)` to prune the marker only after the refreshed summary no longer contains the removed mod:

```swift
public func removeMod(folderName: String) async {
    guard let workspace = summary?.workspace else { return }
    await runWorkspaceMutation(.updatingMod) {
        try await service.removeMod(workspace: workspace, folderName: folderName)
    }
    let stillExists = summary?.mods.contains { $0.folderName == folderName } ?? false
    if !stillExists {
        newModFolderNames.remove(folderName)
    }
}
```

- [ ] **Step 4: Run focused tests and verify they pass**

Run:

```bash
xcodebuild test -project SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj -scheme SnowRunnerModEditor -destination "platform=macOS" -only-testing:SnowRunnerModEditorTests/WorkspaceViewModelTests
```

Expected: PASS.

---

### Task 2: Render Sorted Mods And The NEW Badge

**Files:**
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceOperationView.swift:88-160`

- [ ] **Step 1: Update the mod list to use sorted view-model data**

Replace the current `if let mods = viewModel.summary?.mods, !mods.isEmpty` block with:

```swift
let mods = viewModel.modsSortedByName
if !mods.isEmpty {
    ScrollView(.vertical) {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            ForEach(mods) { mod in
                modRow(mod)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
    }
    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
} else {
    Text("No mods added.")
        .foregroundStyle(.secondary)
}
```

If SwiftUI rejects a local `let` directly inside the `ViewBuilder`, extract it instead:

```swift
private var visibleMods: [PakWorkspaceModSummary] {
    viewModel.modsSortedByName
}
```

Then use `let mods = visibleMods` or `if !visibleMods.isEmpty`.

- [ ] **Step 2: Replace the plain name text with a label row**

In `modRow(_:)`, replace:

```swift
Text(mod.folderName)
    .font(.system(size: 15, weight: .regular))
    .textSelection(.enabled)
```

with:

```swift
HStack(spacing: 8) {
    Text(mod.folderName)
        .font(.system(size: 15, weight: .regular))
        .textSelection(.enabled)
    if viewModel.isNewMod(folderName: mod.folderName) {
        newModBadge
    }
}
```

Add this view near `modCountText`:

```swift
private var newModBadge: some View {
    Text("NEW")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.green.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.green.opacity(0.35))
        }
        .accessibilityLabel("New")
}
```

- [ ] **Step 3: Update the preview to show the badge and sorting**

In the `WorkspaceOperationPreview.viewModel` setup, change the preview mods to intentionally unsorted order and mark one as new:

```swift
model.summary = PakWorkspaceSummary(
    workspace: workspace,
    initialSourcePath: "/Applications/SnowRunner/preload/paks/client/initial.pak",
    mods: [
        modSummary(folderName: "old-truck-addon", archiveName: "old_truck_addon.pak", workspace: workspace, enabled: false),
        modSummary(folderName: "loadstar-rescue-kit", archiveName: "loadstar_rescue.pak", workspace: workspace, enabled: true),
        modSummary(folderName: "azov-tuning-pack", archiveName: "azov_tuning.pak", workspace: workspace, enabled: true)
    ],
    buildInitialPak: workspace.appendingPathComponent("build/initial.pak"),
    buildReport: workspace.appendingPathComponent("build/workspace-build-report.md")
)
model.newModFolderNames = ["loadstar-rescue-kit"]
```

- [ ] **Step 4: Build the app**

Run:

```bash
xcodebuild -project SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj -scheme SnowRunnerModEditor -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED.

---

### Task 3: Final Verification

**Files:**
- Verify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceViewModel.swift`
- Verify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceOperationView.swift`
- Verify: `SnowRunnerModEditor/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`

- [ ] **Step 1: Run the focused view-model test suite**

Run:

```bash
xcodebuild test -project SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj -scheme SnowRunnerModEditor -destination "platform=macOS" -only-testing:SnowRunnerModEditorTests/WorkspaceViewModelTests
```

Expected: PASS.

- [ ] **Step 2: Run an app build**

Run:

```bash
xcodebuild -project SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj -scheme SnowRunnerModEditor -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke check**

Launch the app from Xcode or the built product and verify:

- Existing workspace mods display alphabetically by folder name.
- Adding a new mod places it alphabetically, not necessarily at the bottom.
- The newly added row shows `NEW`.
- Enable, disable, quick verify, and build do not remove the `NEW` badge.
- Removing that mod removes its row and no stale badge appears if another mod is later added.
- Closing and reopening the workspace clears all `NEW` badges.

---

## Self-Review

- Spec coverage: The plan covers name-only sorting, current-workspace-lifetime `NEW` markers, marker clearing, successful-removal marker pruning, UI rendering, tests, and build verification.
- Placeholder scan: No `TBD`, `TODO`, or unspecified “add tests” steps remain.
- Type consistency: The plan uses existing `PakWorkspaceModSummary`, `PakWorkspaceSummary`, `WorkspaceViewModel`, and `WorkspaceOperationView` names. New APIs are consistently named `modsSortedByName`, `newModFolderNames`, and `isNewMod(folderName:)`.
