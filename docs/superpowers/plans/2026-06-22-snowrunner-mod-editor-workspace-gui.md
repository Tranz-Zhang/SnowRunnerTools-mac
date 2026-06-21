# SnowRunnerModEditor Workspace GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native macOS `SnowRunnerModEditor` workspace app while keeping `SnowRunnerTool` as a headless library shared by the CLI and GUI adapters.

**Architecture:** Add shared workspace use-case APIs to `SnowRunnerTool` first: manifest enabled state, enabled-only verify/build, mod removal, workspace summary, and quick conflict verification. Then add a SwiftUI app adapter named `SnowRunnerModEditor` that calls those APIs directly and owns file panels, Finder reveal actions, and view state.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, SwiftUI, AppKit `NSOpenPanel`/`NSWorkspace`, existing `PakWorkspaceManager`, `ModArchiveMapper`, `ModMerger`, `PakVerifier`.

---

## File Map

- Modify `Package.swift`
  - Add executable product/target for `SnowRunnerModEditor` and a testable `SnowRunnerModEditorCore` target.
- Modify `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManifest.swift`
  - Add `enabled` to `PakWorkspaceMod` with backwards-compatible decoding.
- Modify `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift`
  - Add workspace summary, enabled state changes, mod removal, enabled-only mapping, and quick verify.
- Modify `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceError.swift`
  - Add mod-not-found and invalid-mod-state errors used by shared use-case APIs.
- Modify `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`
  - Add coverage for manifest compatibility, enable/disable/remove, enabled-only build/verify, and quick verify.
- Create `Sources/SnowRunnerModEditor/SnowRunnerModEditorApp.swift`
  - SwiftUI app entry point.
- Create `Sources/SnowRunnerModEditorCore/WorkspaceAppService.swift`
  - Thin GUI adapter around headless workspace APIs and AppKit file/Finder operations.
- Create `Sources/SnowRunnerModEditorCore/WorkspaceViewModel.swift`
  - Main actor state machine for launch and workspace screens.
- Create `Sources/SnowRunnerModEditorCore/LaunchWorkspaceView.swift`
  - Step 1 UI.
- Create `Sources/SnowRunnerModEditorCore/WorkspaceOperationView.swift`
  - Step 2 vertical workspace/mods/quick-verify/build UI.
- Create `Sources/SnowRunnerModEditorCore/AppFilePanels.swift`
  - `NSOpenPanel` helpers isolated from the library.
- Create `Sources/SnowRunnerModEditorCore/FinderActions.swift`
  - `NSWorkspace` reveal/open helpers isolated from the library.
- Create `Tests/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`
  - View-model state transition tests with a fake service.
- Modify `README.md`
  - Document the app target, launch command, and V1 workflow.

## Implementation Contracts

Use these public library types. They are intentionally headless and must stay free of CLI, SwiftUI, and AppKit concerns.

```swift
public struct PakWorkspaceSummary: Equatable {
    public var workspace: URL
    public var initialSourcePath: String
    public var mods: [PakWorkspaceModSummary]
    public var buildInitialPak: URL
    public var buildReport: URL
}

public struct PakWorkspaceModSummary: Equatable, Identifiable {
    public var id: String { folderName }
    public var folderName: String
    public var archiveName: String
    public var sourcePath: String
    public var modDirectory: URL
    public var sourceCache: URL
    public var enabled: Bool
}

public struct WorkspaceQuickVerifyResult: Equatable {
    public var conflicts: [WorkspaceModConflict]
}

public struct WorkspaceModConflict: Equatable, Identifiable {
    public var id: String { targetPath }
    public var targetPath: String
    public var mods: [String]
}
```

`PakWorkspaceMod.enabled` must default to `true` when decoding older manifests.

## Task 1: Manifest Enabled State

**Files:**
- Modify: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManifest.swift`
- Modify: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Write failing manifest compatibility tests**

Append these tests to `PakWorkspaceTests`:

```swift
func testWorkspaceManifestDecodesMissingEnabledAsTrue() throws {
    let json = Data("""
    {
      "version": 1,
      "initialSourcePath": "/game/initial.pak",
      "mods": [
        {
          "sourcePath": "/mods/demo.pak",
          "folderName": "demo",
          "archiveName": "demo.pak",
          "sourceCachePath": ".snowrunner/sources/demo.pak",
          "entries": []
        }
      ],
      "policy": {
        "textureMode": "inlineInitial",
        "allowInitialOverwrite": true
      }
    }
    """.utf8)

    let manifest = try JSONDecoder.pakWorkspace.decode(PakWorkspaceManifest.self, from: json)

    XCTAssertEqual(manifest.mods.count, 1)
    XCTAssertTrue(manifest.mods[0].enabled)
}

func testWorkspaceManifestEncodesEnabledState() throws {
    let manifest = PakWorkspaceManifest(
        version: 1,
        initialSourcePath: "/game/initial.pak",
        mods: [
            PakWorkspaceMod(
                sourcePath: "/mods/demo.pak",
                folderName: "demo",
                archiveName: "demo.pak",
                sourceCachePath: ".snowrunner/sources/demo.pak",
                enabled: false,
                entries: []
            )
        ],
        policy: PakWorkspacePolicy(textureMode: "inlineInitial", allowInitialOverwrite: true)
    )

    let data = try JSONEncoder.pakWorkspace.encode(manifest)
    let text = String(decoding: data, as: UTF8.self)
    let decoded = try JSONDecoder.pakWorkspace.decode(PakWorkspaceManifest.self, from: data)

    XCTAssertTrue(text.contains("\"enabled\" : false") || text.contains("\"enabled\": false"))
    XCTAssertFalse(decoded.mods[0].enabled)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceManifestDecodesMissingEnabledAsTrue
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceManifestEncodesEnabledState
```

Expected: compile failure because `PakWorkspaceMod` has no `enabled` parameter/property.

- [ ] **Step 3: Add backwards-compatible enabled state**

Replace `PakWorkspaceMod` in `PakWorkspaceManifest.swift` with:

```swift
public struct PakWorkspaceMod: Codable, Equatable {
    public var sourcePath: String
    public var folderName: String
    public var archiveName: String
    public var sourceCachePath: String
    public var enabled: Bool
    public var entries: [PakWorkspaceSourceEntry]

    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case folderName
        case archiveName
        case sourceCachePath
        case enabled
        case entries
    }

    public init(
        sourcePath: String,
        folderName: String,
        archiveName: String,
        sourceCachePath: String,
        enabled: Bool = true,
        entries: [PakWorkspaceSourceEntry]
    ) {
        self.sourcePath = sourcePath
        self.folderName = folderName
        self.archiveName = archiveName
        self.sourceCachePath = sourceCachePath
        self.enabled = enabled
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        folderName = try container.decode(String.self, forKey: .folderName)
        archiveName = try container.decode(String.self, forKey: .archiveName)
        sourceCachePath = try container.decode(String.self, forKey: .sourceCachePath)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        entries = try container.decode([PakWorkspaceSourceEntry].self, forKey: .entries)
    }
}
```

- [ ] **Step 4: Run the focused tests and verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceManifest
```

Expected: all manifest tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManifest.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: add workspace mod enabled state"
```

## Task 2: Workspace Summary And Enabled Filtering

**Files:**
- Modify: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift`
- Modify: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Write failing summary and enabled-only tests**

Append these tests to `PakWorkspaceTests`:

```swift
func testWorkspaceSummaryReportsEnabledAndDisabledMods() throws {
    let workspace = try temporaryDirectory(named: "workspace-summary")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
    let active = try makePak(named: "active.pak", entries: ["classes/trucks/active.xml": Data("<Truck/>".utf8)])
    let disabled = try makePak(named: "disabled.pak", entries: ["classes/trucks/disabled.xml": Data("<Truck/>".utf8)])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [active, disabled])
    try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "disabled", enabled: false)

    let summary = try PakWorkspaceManager.summary(workspace: workspace)

    XCTAssertEqual(summary.workspace, workspace)
    XCTAssertEqual(summary.initialSourcePath, TestFixtures.initialPak.path)
    XCTAssertEqual(summary.mods.map(\.folderName), ["active", "disabled"])
    XCTAssertEqual(summary.mods.map(\.enabled), [true, false])
    XCTAssertEqual(summary.buildInitialPak, PakWorkspacePaths.buildInitialPak(root: workspace))
    XCTAssertEqual(summary.buildReport, PakWorkspacePaths.buildReport(root: workspace))
}

func testWorkspaceVerifyIgnoresDisabledConflictingMod() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-verify-disabled-conflict")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
    try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "second", enabled: false)

    let result = try PakWorkspaceManager.verify(workspace: workspace)

    XCTAssertGreaterThan(result.plan.mappedModEntryCount, 0)
}

func testWorkspaceBuildIgnoresDisabledModPayload() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-build-disabled")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let active = try makePak(named: "active.pak", entries: [
        "classes/trucks/active.xml": Data("<Truck id=\"active\"/>".utf8)
    ])
    let disabled = try makePak(named: "disabled.pak", entries: [
        "classes/trucks/disabled.xml": Data("<Truck id=\"disabled\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [active, disabled])
    try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "disabled", enabled: false)

    _ = try PakWorkspaceManager.build(workspace: workspace)

    let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
    XCTAssertTrue(archive.entries.contains { $0.name == "[media]\\classes\\trucks\\active.xml" })
    XCTAssertFalse(archive.entries.contains { $0.name == "[media]\\classes\\trucks\\disabled.xml" })
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceSummaryReportsEnabledAndDisabledMods
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceVerifyIgnoresDisabledConflictingMod
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuildIgnoresDisabledModPayload
```

Expected: compile failure because `summary` and `setModEnabled` do not exist.

- [ ] **Step 3: Add summary structs and set enabled API**

Add these structs near the top of `PakWorkspaceManager.swift` after `PakWorkspaceAddModsResult`:

```swift
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
```

Add these public methods inside `PakWorkspaceManager`:

```swift
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
```

Add this helper near `commitManifestLast`:

```swift
private static func commitManifestOnly(workspace: URL, manifest: PakWorkspaceManifest) throws {
    try commitManifestLast(workspace: workspace, manifest: manifest) {
        // Manifest-only mutation.
    } rollback: {
        // Nothing to roll back.
    }
}
```

- [ ] **Step 4: Add mod-not-found error**

Add case to `PakWorkspaceError`:

```swift
case modNotFound(String)
```

Add this branch to `description`:

```swift
case let .modNotFound(folderName):
    return "Workspace manifest has no mod named: \(folderName)"
```

- [ ] **Step 5: Filter build/verify to enabled mods**

In `buildCandidate`, replace:

```swift
let mapped = try manifest.mods.flatMap { mod -> [ModMappedEntry] in
```

with:

```swift
let mapped = try manifest.mods.filter(\.enabled).flatMap { mod -> [ModMappedEntry] in
```

- [ ] **Step 6: Run focused tests and verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceSummaryReportsEnabledAndDisabledMods
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceVerifyIgnoresDisabledConflictingMod
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuildIgnoresDisabledModPayload
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceError.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: add workspace summary and enabled filtering"
```

## Task 3: Remove Mod Use Case

**Files:**
- Modify: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift`
- Modify: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Write failing remove tests**

Append these tests to `PakWorkspaceTests`:

```swift
func testWorkspaceRemoveModDeletesFolderCacheAndManifestEntry() throws {
    let workspace = try temporaryDirectory(named: "workspace-remove-mod")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
    let mod = try makePak(named: "demo.pak", entries: ["classes/trucks/demo.xml": Data("<Truck/>".utf8)])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])

    try PakWorkspaceManager.removeMod(workspace: workspace, folderName: "demo")

    XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo").path))
    XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).mods, [])
}

func testWorkspaceRemoveMissingModFailsClearly() throws {
    let workspace = try temporaryDirectory(named: "workspace-remove-missing")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

    XCTAssertThrowsError(try PakWorkspaceManager.removeMod(workspace: workspace, folderName: "missing")) { error in
        XCTAssertTrue(String(describing: error).contains("missing"))
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceRemove
```

Expected: compile failure because `removeMod` does not exist.

- [ ] **Step 3: Implement removeMod**

Add this public method to `PakWorkspaceManager`:

```swift
public static func removeMod(workspace: URL, folderName: String) throws {
    var manifest = try loadManifest(workspace: workspace)
    guard let index = manifest.mods.firstIndex(where: { $0.folderName == folderName }) else {
        throw PakWorkspaceError.modNotFound(folderName)
    }
    let mod = manifest.mods.remove(at: index)
    let modDirectory = PakWorkspacePaths.modDirectory(root: workspace, folderName: mod.folderName)
    let sourceCache = workspace.appendingPathComponent(mod.sourceCachePath)
    let removedModBackup = workspace.appendingPathComponent(".removed-mod-\(mod.folderName)-\(UUID().uuidString)", isDirectory: true)
    let removedCacheBackup = workspace.appendingPathComponent(".removed-source-\(mod.folderName)-\(UUID().uuidString).pak")

    var movedMod = false
    var movedCache = false
    do {
        if FileManager.default.fileExists(atPath: modDirectory.path) {
            try FileManager.default.moveItem(at: modDirectory, to: removedModBackup)
            movedMod = true
        }
        if FileManager.default.fileExists(atPath: sourceCache.path) {
            try FileManager.default.moveItem(at: sourceCache, to: removedCacheBackup)
            movedCache = true
        }
        try commitManifestOnly(workspace: workspace, manifest: manifest)
        try? FileManager.default.removeItem(at: removedModBackup)
        try? FileManager.default.removeItem(at: removedCacheBackup)
    } catch {
        if movedMod, !FileManager.default.fileExists(atPath: modDirectory.path) {
            try? FileManager.default.moveItem(at: removedModBackup, to: modDirectory)
        }
        if movedCache, !FileManager.default.fileExists(atPath: sourceCache.path) {
            try? FileManager.default.moveItem(at: removedCacheBackup, to: sourceCache)
        }
        throw error
    }
}
```

- [ ] **Step 4: Run focused tests and verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceRemove
```

Expected: remove tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: support removing workspace mods"
```

## Task 4: Quick Verify Conflict Detection

**Files:**
- Modify: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift`
- Modify: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Write failing quick verify tests**

Append these tests to `PakWorkspaceTests`:

```swift
func testWorkspaceQuickVerifyFlagsDuplicateTargetsWithDifferentBytes() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-quick-conflict-different")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

    let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

    XCTAssertEqual(result.conflicts, [
        WorkspaceModConflict(
            targetPath: "[media]\\classes\\trucks\\same.xml",
            mods: ["first", "second"]
        )
    ])
}

func testWorkspaceQuickVerifyFlagsDuplicateTargetsWithIdenticalBytes() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-quick-conflict-identical")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"same\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"same\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

    let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

    XCTAssertEqual(result.conflicts.map(\.targetPath), ["[media]\\classes\\trucks\\same.xml"])
    XCTAssertEqual(result.conflicts[0].mods, ["first", "second"])
}

func testWorkspaceQuickVerifyIgnoresDisabledMods() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-quick-disabled")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
    try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "second", enabled: false)

    let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

    XCTAssertEqual(result.conflicts, [])
}

func testWorkspaceQuickVerifyIgnoresModOverInitialReplacement() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-quick-over-initial")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let replacement = try makePak(named: "replacement.pak", entries: [
        "classes/trucks/existing.xml": Data("<Truck id=\"replacement\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [replacement])

    let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

    XCTAssertEqual(result.conflicts, [])
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerify
```

Expected: compile failure because `quickVerify` and quick-verify result types do not exist.

- [ ] **Step 3: Add quick verify result types**

Add these structs near `PakWorkspaceSummary` in `PakWorkspaceManager.swift`:

```swift
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
```

- [ ] **Step 4: Add a shared enabled-mod mapping helper**

In `PakWorkspaceManager`, extract the mapping loop from `buildCandidate` into:

```swift
private static func mappedEntriesForEnabledMods(workspace: URL, manifest: PakWorkspaceManifest) throws -> [(mod: PakWorkspaceMod, entries: [ModMappedEntry])] {
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
        return (mod, entries)
    }
}
```

Then replace the mapping block in `buildCandidate` with:

```swift
let mapped = try mappedEntriesForEnabledMods(workspace: workspace, manifest: manifest)
    .flatMap(\.entries)
```

- [ ] **Step 5: Implement quickVerify**

Add this public method to `PakWorkspaceManager`:

```swift
public static func quickVerify(workspace: URL) throws -> WorkspaceQuickVerifyResult {
    let manifest = try loadManifest(workspace: workspace)
    let mappedByMod = try mappedEntriesForEnabledMods(workspace: workspace, manifest: manifest)
    var modsByTarget: [String: Set<String>] = [:]

    for item in mappedByMod {
        for entry in item.entries where entry.targetArchive == .initial {
            modsByTarget[entry.internalName, default: []].insert(item.mod.folderName)
        }
    }

    let conflicts = modsByTarget
        .filter { $0.value.count > 1 }
        .map { target, mods in
            WorkspaceModConflict(targetPath: target, mods: mods.sorted())
        }
        .sorted { $0.targetPath < $1.targetPath }

    return WorkspaceQuickVerifyResult(conflicts: conflicts)
}
```

- [ ] **Step 6: Run focused tests and verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerify
```

Expected: quick verify tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: add workspace quick verify conflicts"
```

## Task 5: SwiftUI App Target Skeleton

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SnowRunnerModEditor/SnowRunnerModEditorApp.swift`
- Create: `Sources/SnowRunnerModEditorCore/LaunchWorkspaceView.swift`
- Create: `Sources/SnowRunnerModEditorCore/WorkspaceOperationView.swift`

- [ ] **Step 1: Add the app target to Package.swift**

Modify products:

```swift
products: [
    .executable(name: "snowrunner-tool", targets: ["snowrunner-tool"]),
    .executable(name: "SnowRunnerModEditor", targets: ["SnowRunnerModEditor"]),
    .library(name: "SnowRunnerTool", targets: ["SnowRunnerTool"])
],
```

Add the target after `snowrunner-tool`:

```swift
.executableTarget(
    name: "SnowRunnerModEditor",
    dependencies: ["SnowRunnerModEditorCore"]
),
.target(
    name: "SnowRunnerModEditorCore",
    dependencies: ["SnowRunnerTool"]
),
```

- [ ] **Step 2: Add a minimal launchable SwiftUI app**

Create `Sources/SnowRunnerModEditor/SnowRunnerModEditorApp.swift`:

```swift
import SwiftUI
import SnowRunnerModEditorCore

@main
struct SnowRunnerModEditorApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchWorkspaceView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.titleBar)
    }
}
```

Create `Sources/SnowRunnerModEditorCore/LaunchWorkspaceView.swift`:

```swift
import SwiftUI

public struct LaunchWorkspaceView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Choose a SnowRunner workspace")
                    .font(.title2.weight(.semibold))
                Text("Create one from initial.pak or open a folder containing .snowrunner-workspace.json.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Create Workspace From initial.pak") {}
            Button("Open Existing Workspace Folder") {}
            Text("Opening fails if the selected folder is not a valid workspace.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
```

Create `Sources/SnowRunnerModEditorCore/WorkspaceOperationView.swift`:

```swift
import SwiftUI

public struct WorkspaceOperationView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Workspace", subtitle: "No workspace loaded")
                SectionHeader(title: "Mods", subtitle: "No mods")
                SectionHeader(title: "Quick Verify", subtitle: "Not run")
                SectionHeader(title: "Build Output", subtitle: "build/initial.pak")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator)
        }
    }
}
```

- [ ] **Step 3: Build the app target**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build --product SnowRunnerModEditor
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/SnowRunnerModEditor/SnowRunnerModEditorApp.swift Sources/SnowRunnerModEditorCore/LaunchWorkspaceView.swift Sources/SnowRunnerModEditorCore/WorkspaceOperationView.swift
git commit -m "feat: add SnowRunnerModEditor app target"
```

## Task 6: GUI Adapter Service And View Model

**Files:**
- Create: `Sources/SnowRunnerModEditorCore/WorkspaceAppService.swift`
- Create: `Sources/SnowRunnerModEditorCore/AppFilePanels.swift`
- Create: `Sources/SnowRunnerModEditorCore/FinderActions.swift`
- Create: `Sources/SnowRunnerModEditorCore/WorkspaceViewModel.swift`
- Create: `Tests/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Add the app test target**

Add this test target to `Package.swift`:

```swift
.testTarget(
    name: "SnowRunnerModEditorTests",
    dependencies: ["SnowRunnerModEditorCore", "SnowRunnerTool"]
)
```

- [ ] **Step 2: Add the service protocol and live implementation**

Create `Sources/SnowRunnerModEditorCore/WorkspaceAppService.swift`:

```swift
import Foundation
import SnowRunnerTool

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
        try await Task.detached(priority: .userInitiated) {
            _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: initialPak)
            return try PakWorkspaceManager.summary(workspace: workspace)
        }.value
    }

    public func openWorkspace(_ workspace: URL) async throws -> PakWorkspaceSummary {
        try await Task.detached(priority: .userInitiated) {
            try PakWorkspaceManager.summary(workspace: workspace)
        }.value
    }

    public func addMods(workspace: URL, modPaks: [URL]) async throws -> PakWorkspaceSummary {
        try await Task.detached(priority: .userInitiated) {
            _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: modPaks)
            return try PakWorkspaceManager.summary(workspace: workspace)
        }.value
    }

    public func setModEnabled(workspace: URL, folderName: String, enabled: Bool) async throws -> PakWorkspaceSummary {
        try await Task.detached(priority: .userInitiated) {
            try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: folderName, enabled: enabled)
            return try PakWorkspaceManager.summary(workspace: workspace)
        }.value
    }

    public func removeMod(workspace: URL, folderName: String) async throws -> PakWorkspaceSummary {
        try await Task.detached(priority: .userInitiated) {
            try PakWorkspaceManager.removeMod(workspace: workspace, folderName: folderName)
            return try PakWorkspaceManager.summary(workspace: workspace)
        }.value
    }

    public func quickVerify(workspace: URL) async throws -> WorkspaceQuickVerifyResult {
        try await Task.detached(priority: .utility) {
            try PakWorkspaceManager.quickVerify(workspace: workspace)
        }.value
    }

    public func build(workspace: URL) async throws -> ModMergeResult {
        try await Task.detached(priority: .userInitiated) {
            try PakWorkspaceManager.build(workspace: workspace)
        }.value
    }
}
```

- [ ] **Step 3: Add AppKit adapter helpers**

Create `Sources/SnowRunnerModEditorCore/AppFilePanels.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

@MainActor
struct AppFilePanels {
    func chooseInitialPak() -> URL? {
        chooseFile(title: "Choose initial.pak", allowedExtensions: ["pak"])
    }

    func chooseWorkspaceFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Workspace Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseModPaks() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Mod PAKs"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "pak")].compactMap { $0 }
        return panel.runModal() == .OK ? panel.urls : []
    }

    private func chooseFile(title: String, allowedExtensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
```

Create `Sources/SnowRunnerModEditorCore/FinderActions.swift`:

```swift
import AppKit
import Foundation

@MainActor
struct FinderActions {
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: Add view model tests before implementation**

Create `Tests/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`:

```swift
import Foundation
import SnowRunnerTool
import XCTest
@testable import SnowRunnerModEditorCore

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
        service.error = PakWorkspaceError.missingManifest("/tmp/bad/.snowrunner-workspace.json")
        let model = WorkspaceViewModel(service: service)

        await model.openWorkspace(URL(fileURLWithPath: "/tmp/bad", isDirectory: true))

        XCTAssertEqual(model.screen, .launch)
        XCTAssertNotNil(model.errorMessage)
    }

    func testAddModsRefreshesSummaryAndRunsQuickVerify() async throws {
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let service = FakeWorkspaceService()
        service.summary = summary(workspace: workspace, mods: [])
        service.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [])
        let model = WorkspaceViewModel(service: service)
        await model.openWorkspace(workspace)

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
    var error: Error?
    var quickVerifyCalls = 0

    func createWorkspace(workspace: URL, initialPak: URL) async throws -> PakWorkspaceSummary {
        if let error { throw error }
        return summary
    }

    func openWorkspace(_ workspace: URL) async throws -> PakWorkspaceSummary {
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
        if let error { throw error }
        return quickVerifyResult
    }

    func build(workspace: URL) async throws -> ModMergeResult {
        if let error { throw error }
        return ModMergeResult(
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
            outputURL: nil,
            outputTexturesURL: nil,
            outputSharedTexturesURL: nil,
            writtenEntryCount: nil,
            writtenTextureEntryCount: nil,
            writtenSharedTextureEntryCount: nil
        )
    }
}
```

- [ ] **Step 5: Run view model tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter WorkspaceViewModelTests
```

Expected: compile failure because `WorkspaceViewModel` does not exist.

- [ ] **Step 6: Implement WorkspaceViewModel**

Create `Sources/SnowRunnerModEditorCore/WorkspaceViewModel.swift`:

```swift
import Foundation
import Observation
import SnowRunnerTool

@MainActor
@Observable
public final class WorkspaceViewModel {
    public enum Screen: Equatable {
        case launch
        case workspace
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

    private let service: WorkspaceAppServicing
    private var quickVerifyTask: Task<Void, Never>?

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
        busyState = .openingWorkspace
        errorMessage = nil
        do {
            let loaded = try await service.openWorkspace(workspace)
            summary = loaded
            screen = .workspace
            busyState = .idle
            startQuickVerify()
        } catch {
            summary = nil
            screen = .launch
            busyState = .idle
            errorMessage = String(describing: error)
        }
    }

    public func closeWorkspace() {
        quickVerifyTask?.cancel()
        summary = nil
        quickVerifyResult = nil
        buildResult = nil
        errorMessage = nil
        busyState = .idle
        screen = .launch
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

    private func runWorkspaceMutation(_ state: BusyState, operation: () async throws -> PakWorkspaceSummary) async {
        busyState = state
        errorMessage = nil
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
        quickVerifyTask?.cancel()
        guard let workspace = summary?.workspace else { return }
        quickVerifyResult = nil
        busyState = .quickVerifying
        quickVerifyTask = Task { [service] in
            do {
                let result = try await service.quickVerify(workspace: workspace)
                guard !Task.isCancelled else { return }
                self.quickVerifyResult = result
                if self.busyState == .quickVerifying {
                    self.busyState = .idle
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = String(describing: error)
                if self.busyState == .quickVerifying {
                    self.busyState = .idle
                }
            }
        }
    }
}
```

- [ ] **Step 7: Run view model tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter WorkspaceViewModelTests
```

Expected: view-model tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/SnowRunnerModEditor Sources/SnowRunnerModEditorCore Tests/SnowRunnerModEditorTests
git commit -m "feat: add workspace app service and view model"
```

## Task 7: Launch Screen UI

**Files:**
- Modify: `Sources/SnowRunnerModEditor/SnowRunnerModEditorApp.swift`
- Modify: `Sources/SnowRunnerModEditorCore/LaunchWorkspaceView.swift`
- Modify: `Sources/SnowRunnerModEditorCore/WorkspaceOperationView.swift`

- [ ] **Step 1: Replace launch view with workspace-only UI**

Replace `LaunchWorkspaceView.swift` with:

```swift
import SwiftUI

public struct LaunchWorkspaceView: View {
    @Bindable var viewModel: WorkspaceViewModel
    private let panels = AppFilePanels()

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Workspace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Choose a SnowRunner workspace")
                    .font(.title2.weight(.semibold))
                Text("Create one from initial.pak or open a folder containing .snowrunner-workspace.json.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button("Create Workspace From initial.pak") {
                    createWorkspace()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)

                Button("Open Existing Workspace Folder") {
                    openWorkspace()
                }
                .disabled(viewModel.isBusy)
            }

            if viewModel.isBusy {
                ProgressView()
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            Text("Opening fails if the selected folder is not a valid workspace.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: 560, maxHeight: .infinity)
    }

    private func createWorkspace() {
        guard let initialPak = panels.chooseInitialPak(),
              let workspace = panels.chooseWorkspaceFolder()
        else { return }
        Task {
            await viewModel.createWorkspace(workspace: workspace, initialPak: initialPak)
        }
    }

    private func openWorkspace() {
        guard let workspace = panels.chooseWorkspaceFolder() else { return }
        Task {
            await viewModel.openWorkspace(workspace)
        }
    }
}
```

- [ ] **Step 2: Add a view-model initializer to the temporary workspace view**

Replace `WorkspaceOperationView.swift` with:

```swift
import SwiftUI

public struct WorkspaceOperationView: View {
    @Bindable var viewModel: WorkspaceViewModel

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Workspace", subtitle: viewModel.summary?.workspace.path ?? "No workspace loaded")
                SectionHeader(title: "Mods", subtitle: "No mods")
                SectionHeader(title: "Quick Verify", subtitle: "Not run")
                SectionHeader(title: "Build Output", subtitle: "build/initial.pak")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator)
        }
    }
}
```

- [ ] **Step 3: Wire app entry to the view model**

Replace `SnowRunnerModEditorApp.swift` with:

```swift
import SwiftUI
import SnowRunnerModEditorCore

@main
struct SnowRunnerModEditorApp: App {
    @State private var viewModel = WorkspaceViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch viewModel.screen {
                case .launch:
                    LaunchWorkspaceView(viewModel: viewModel)
                case .workspace:
                    WorkspaceOperationView(viewModel: viewModel)
                }
            }
            .frame(minWidth: 860, minHeight: 640)
        }
        .windowStyle(.titleBar)
    }
}
```

- [ ] **Step 4: Build the app target**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build --product SnowRunnerModEditor
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerModEditor/SnowRunnerModEditorApp.swift Sources/SnowRunnerModEditorCore/LaunchWorkspaceView.swift Sources/SnowRunnerModEditorCore/WorkspaceOperationView.swift
git commit -m "feat: build workspace launch screen"
```

## Task 8: Workspace Operation UI

**Files:**
- Modify: `Sources/SnowRunnerModEditorCore/WorkspaceOperationView.swift`

- [ ] **Step 1: Replace workspace operation view**

Replace `WorkspaceOperationView.swift` with:

```swift
import SwiftUI
import SnowRunnerTool

public struct WorkspaceOperationView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var showingConflicts = false
    private let panels = AppFilePanels()
    private let finder = FinderActions()

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                workspaceSection
                modsSection
                quickVerifySection
                buildSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingConflicts) {
            ConflictDetailsView(conflicts: viewModel.quickVerifyResult?.conflicts ?? [])
                .frame(minWidth: 560, minHeight: 360)
        }
    }

    private var workspaceSection: some View {
        panel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.summary?.workspace.lastPathComponent ?? "Workspace")
                        .font(.headline)
                    Text(viewModel.summary?.workspace.path ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Reveal Workspace") {
                    if let workspace = viewModel.summary?.workspace {
                        finder.reveal(workspace)
                    }
                }
                Button("Close Workspace") {
                    viewModel.closeWorkspace()
                }
            }
        }
    }

    private var modsSection: some View {
        panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mods")
                            .font(.headline)
                        Text(modCountText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add Mods") {
                        addMods()
                    }
                    .disabled(viewModel.isBusy)
                }

                Divider()

                if let mods = viewModel.summary?.mods, !mods.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            tableHeader("Name")
                            tableHeader("Status")
                            tableHeader("Conflict")
                            tableHeader("Actions")
                        }
                        ForEach(mods) { mod in
                            GridRow {
                                Text(mod.folderName)
                                    .textSelection(.enabled)
                                Text(mod.enabled ? "Active" : "Disabled")
                                    .foregroundStyle(mod.enabled ? .green : .secondary)
                                Text(conflictCountText(for: mod.folderName))
                                    .foregroundStyle(hasConflict(mod.folderName) ? .red : .secondary)
                                HStack {
                                    Button("Reveal") {
                                        finder.reveal(mod.modDirectory)
                                    }
                                    if mod.enabled {
                                        Button("Disable") {
                                            Task { await viewModel.setModEnabled(folderName: mod.folderName, enabled: false) }
                                        }
                                    } else {
                                        Button("Enable") {
                                            Task { await viewModel.setModEnabled(folderName: mod.folderName, enabled: true) }
                                        }
                                        Button("Remove", role: .destructive) {
                                            Task { await viewModel.removeMod(folderName: mod.folderName) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("No mods added.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickVerifySection: some View {
        panel {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Verify")
                        .font(.headline)
                    Text(quickVerifyText)
                        .font(.callout)
                        .foregroundStyle(hasQuickVerifyConflicts ? .red : .secondary)
                    Text("Checks duplicate mapped targets between enabled mods. Mod-over-initial replacements are ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.busyState == .quickVerifying {
                    ProgressView()
                }
                if hasQuickVerifyConflicts {
                    Button("Show Conflict Details") {
                        showingConflicts = true
                    }
                }
            }
        }
    }

    private var buildSection: some View {
        panel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build Output")
                        .font(.headline)
                    Text("build/initial.pak")
                        .font(.callout.weight(.semibold))
                    Text("Full verification runs before publishing build/initial.pak and workspace-build-report.md.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Build PAK") {
                    Task { await viewModel.build() }
                }
                .disabled(viewModel.isBusy)
                Button("Review Build") {
                    if let output = viewModel.summary?.buildInitialPak {
                        finder.reveal(output)
                    }
                }
                .disabled(viewModel.summary == nil)
            }
        }
    }

    private var modCountText: String {
        let mods = viewModel.summary?.mods ?? []
        let active = mods.filter(\.enabled).count
        let disabled = mods.count - active
        return "\(active) active, \(disabled) disabled"
    }

    private var hasQuickVerifyConflicts: Bool {
        !(viewModel.quickVerifyResult?.conflicts.isEmpty ?? true)
    }

    private var quickVerifyText: String {
        guard let result = viewModel.quickVerifyResult else { return "Checking..." }
        return result.conflicts.isEmpty ? "No conflicts found" : "Conflicts found"
    }

    private func addMods() {
        let urls = panels.chooseModPaks()
        guard !urls.isEmpty else { return }
        Task { await viewModel.addMods(urls) }
    }

    private func hasConflict(_ folderName: String) -> Bool {
        (viewModel.quickVerifyResult?.conflicts ?? []).contains { $0.mods.contains(folderName) }
    }

    private func conflictCountText(for folderName: String) -> String {
        let count = (viewModel.quickVerifyResult?.conflicts ?? []).filter { $0.mods.contains(folderName) }.count
        return count == 0 ? "None" : "\(count) target\(count == 1 ? "" : "s")"
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator)
            }
    }
}

private struct ConflictDetailsView: View {
    let conflicts: [WorkspaceModConflict]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conflict Details")
                .font(.title3.weight(.semibold))
            List(conflicts) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.targetPath)
                        .font(.callout.weight(.semibold))
                        .textSelection(.enabled)
                    Text(conflict.mods.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(20)
    }
}
```

- [ ] **Step 2: Build the app target**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build --product SnowRunnerModEditor
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/SnowRunnerModEditorCore/WorkspaceOperationView.swift
git commit -m "feat: build workspace operation UI"
```

## Task 9: Documentation And Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README**

Add this section after the workspace CLI examples:

```markdown
## SnowRunnerModEditor App

`SnowRunnerModEditor` is the native macOS workspace GUI.

Run it from SwiftPM during development:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run SnowRunnerModEditor
```

The app opens in two steps:

1. Create a workspace from `initial.pak` or open a folder containing `.snowrunner-workspace.json`.
2. Operate the workspace: add mods, enable/disable/remove mods, review quick mod-to-mod conflicts, and build the verified output.

The app does not edit workspace files directly. Use Finder or external editors for manual changes under `initial/` and `mods/`.

Generated output is fixed to:

```text
workspace/build/initial.pak
workspace/build/workspace-build-report.md
```

The original source `initial.pak` is never overwritten.
```

- [ ] **Step 2: Run full test suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
```

Expected: all tests pass.

- [ ] **Step 3: Build both executable products**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build --product snowrunner-tool
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build --product SnowRunnerModEditor
```

Expected: both builds succeed.

- [ ] **Step 4: Manual app smoke**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run SnowRunnerModEditor
```

Manual checklist:

- App starts on the workspace-only launch screen.
- Opening a folder without `.snowrunner-workspace.json` fails and stays on launch screen.
- Creating a workspace from `fixtures/initial.pak` enters the workspace screen.
- Adding `fixtures/loadstar_1700_jbe.pak` adds an active mod.
- Disabling the mod changes it to disabled and quick verify reruns.
- Re-enabling the mod changes it to active and quick verify reruns.
- `Build PAK` writes `build/initial.pak`.
- `Review Build` reveals the generated output.

- [ ] **Step 5: Commit docs**

```bash
git add README.md
git commit -m "docs: document SnowRunnerModEditor workflow"
```

## Final Verification Before Completion

- [ ] Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build --product snowrunner-tool
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build --product SnowRunnerModEditor
git status --short
```

Expected:

- `swift test` exits 0,
- both products build,
- `git status --short` contains only intentional untracked/user files, not unstaged implementation changes.
