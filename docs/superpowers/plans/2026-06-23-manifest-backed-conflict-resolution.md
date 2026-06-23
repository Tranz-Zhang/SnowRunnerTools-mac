# Manifest-Backed Conflict Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manifest-backed per-target conflict resolution so the macOS app can choose winning mod versions without moving or deleting mod files.

**Architecture:** Store conflict choices in `PakWorkspaceManifest.conflictResolutions`, keyed by target archive and internal path. `PakWorkspaceManager.quickVerify` classifies current duplicate mapped targets as unresolved or resolved, prunes irrelevant saved choices, and `PakWorkspaceManager.build` filters resolved duplicate candidates before calling `ModMerger.mergeWorkspaceInitial`. The app service and view model expose resolve/clear operations, and `ConflictDetailsView` becomes a two-pane resolver.

**Tech Stack:** Swift, SwiftPM, XCTest, SwiftUI, Observation, existing SnowRunnerCore workspace/merge APIs.

## Global Constraints

- Mod files stay in their original `mods/<mod>/...` paths.
- No losing files are moved, renamed, or deleted.
- `conflictResolutions` changes only through `Use This Version`, `Keep One Copy`, `Clear Resolution`, or automatic stale-choice pruning on open / quick verify / build.
- Conflict discovery is otherwise read-only.
- The user-facing conflict states are only `Unresolved` and `Resolved`.
- Stale-resolution-only information must not appear in the UI.
- Different candidate bytes use `Use This Version`.
- Byte-identical candidate bytes use `Keep One Copy`.
- The lower-level merger does not own manifest resolution.

---

## File Structure

- `Sources/SnowRunnerCore/ModMerge/ModArchiveMapper.swift`
  - Make `ModMergeTargetArchive` `Codable` and `Hashable` so it can be stored in manifest choices and used directly in public conflict models.
- `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManifest.swift`
  - Add `PakWorkspaceConflictResolution`.
  - Add `conflictResolutions` to `PakWorkspaceManifest`, decoding missing values as `[]` for existing workspaces.
- `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift`
  - Add public resolve/clear APIs.
  - Enrich `WorkspaceQuickVerifyResult`, `WorkspaceModConflict`, and add `WorkspaceModConflictCandidate`.
  - Build conflict groups from mapped entries, validate/prune saved choices, and classify conflicts.
  - Apply valid choices before build.
- `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceAppService.swift`
  - Add async service methods for resolve/clear.
- `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceViewModel.swift`
  - Add resolve/clear methods that refresh quick verify and keep the user on conflict details.
- `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceOperationView.swift`
  - Update quick verify copy/state so resolved conflicts do not look like blocking unresolved conflicts.
- `SnowRunnerModEditor/SnowRunnerModEditor/ConflictDetailsView.swift`
  - Replace the simple list with a two-pane resolver.
- `Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift`
  - Add core manifest, quick verify, pruning, and build tests.
- `SnowRunnerModEditor/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`
  - Add app service/view model tests for resolve/clear refresh behavior.

---

### Task 1: Manifest Schema And Resolution Mutation APIs

**Files:**
- Modify: `Sources/SnowRunnerCore/ModMerge/ModArchiveMapper.swift`
- Modify: `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManifest.swift`
- Modify: `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift`
- Test: `Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift`

**Interfaces:**
- Consumes: `PakWorkspaceManager.loadManifest(workspace:)`, `PakWorkspaceManager.initialize(workspace:initialPak:)`, `PakWorkspaceManager.addMods(workspace:modPaks:)`
- Produces:
  - `public struct PakWorkspaceConflictResolution: Codable, Equatable, Identifiable`
  - `public var PakWorkspaceManifest.conflictResolutions: [PakWorkspaceConflictResolution]`
  - `public static func resolveConflict(workspace: URL, targetArchive: ModMergeTargetArchive, internalName: String, selectedMod: String) throws`
  - `public static func clearConflictResolution(workspace: URL, targetArchive: ModMergeTargetArchive, internalName: String) throws`

- [ ] **Step 1: Write failing manifest and mutation tests**

Add these tests near the existing workspace quick verify tests in `Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift`:

```swift
func testWorkspaceManifestDefaultsConflictResolutionsForExistingManifest() throws {
    let workspace = try temporaryDirectory(named: "workspace-manifest-default-resolutions")
    let manifestURL = PakWorkspacePaths.manifestURL(root: workspace)
    let json = """
    {
      "initialSourcePath" : "/game/initial.pak",
      "mods" : [],
      "policy" : {
        "allowInitialOverwrite" : true,
        "textureMode" : "inlineInitial"
      },
      "version" : 1
    }
    """
    try json.data(using: .utf8)!.write(to: manifestURL)

    let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)

    XCTAssertEqual(manifest.conflictResolutions, [])
}

func testWorkspaceResolveConflictWritesSelectedModToManifest() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-resolve-conflict-manifest")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)

    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "first"
    )

    let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
    XCTAssertEqual(manifest.conflictResolutions, [
        PakWorkspaceConflictResolution(
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "first"
        )
    ])
}

func testWorkspaceClearConflictResolutionRemovesSavedChoice() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-clear-conflict-manifest")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "first"
    )

    try PakWorkspaceManager.clearConflictResolution(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml"
    )

    let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
    XCTAssertEqual(manifest.conflictResolutions, [])
}

func testWorkspaceResolveConflictReplacesExistingChoiceForTarget() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-replace-conflict-manifest")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "first"
    )

    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "second"
    )

    let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
    XCTAssertEqual(manifest.conflictResolutions, [
        PakWorkspaceConflictResolution(
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "second"
        )
    ])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceManifestDefaultsConflictResolutionsForExistingManifest
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceResolveConflictWritesSelectedModToManifest
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceClearConflictResolutionRemovesSavedChoice
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceResolveConflictReplacesExistingChoiceForTarget
```

Expected: FAIL because `conflictResolutions`, `PakWorkspaceConflictResolution`, `resolveConflict`, and `clearConflictResolution` do not exist yet.

- [ ] **Step 3: Implement manifest model and mutation APIs**

In `Sources/SnowRunnerCore/ModMerge/ModArchiveMapper.swift`, change the enum declaration:

```swift
public enum ModMergeTargetArchive: String, Codable, Equatable, Hashable {
    case initial = "initial.pak"
    case sharedTexturesBase = "shared_textures_base.pak"
    case sharedTextures = "shared_textures.pak"
}
```

In `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManifest.swift`, update `PakWorkspaceManifest` and add `PakWorkspaceConflictResolution`:

```swift
public struct PakWorkspaceManifest: Codable, Equatable {
    public let version: Int
    public var initialSourcePath: String
    public var mods: [PakWorkspaceMod]
    public var policy: PakWorkspacePolicy
    public var conflictResolutions: [PakWorkspaceConflictResolution]

    private enum CodingKeys: String, CodingKey {
        case version
        case initialSourcePath
        case mods
        case policy
        case conflictResolutions
    }

    public init(
        version: Int,
        initialSourcePath: String,
        mods: [PakWorkspaceMod],
        policy: PakWorkspacePolicy,
        conflictResolutions: [PakWorkspaceConflictResolution] = []
    ) {
        self.version = version
        self.initialSourcePath = initialSourcePath
        self.mods = mods
        self.policy = policy
        self.conflictResolutions = conflictResolutions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        initialSourcePath = try container.decode(String.self, forKey: .initialSourcePath)
        mods = try container.decode([PakWorkspaceMod].self, forKey: .mods)
        policy = try container.decode(PakWorkspacePolicy.self, forKey: .policy)
        conflictResolutions = try container.decodeIfPresent(
            [PakWorkspaceConflictResolution].self,
            forKey: .conflictResolutions
        ) ?? []
    }
}

public struct PakWorkspaceConflictResolution: Codable, Equatable, Identifiable {
    public var id: String { "\(targetArchive.rawValue):\(internalName)" }
    public var targetArchive: ModMergeTargetArchive
    public var internalName: String
    public var selectedMod: String

    public init(targetArchive: ModMergeTargetArchive, internalName: String, selectedMod: String) {
        self.targetArchive = targetArchive
        self.internalName = internalName
        self.selectedMod = selectedMod
    }
}
```

In `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift`, add public mutation APIs near `setModEnabled`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceManifestDefaultsConflictResolutionsForExistingManifest
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceResolveConflictWritesSelectedModToManifest
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceClearConflictResolutionRemovesSavedChoice
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceResolveConflictReplacesExistingChoiceForTarget
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerCore/ModMerge/ModArchiveMapper.swift Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManifest.swift Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift
git commit -m "feat: store workspace conflict resolutions"
```

---

### Task 2: Resolution-Aware Quick Verify Details

**Files:**
- Modify: `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift`
- Test: `Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift`

**Interfaces:**
- Consumes:
  - `PakWorkspaceManifest.conflictResolutions`
  - `PakWorkspaceManager.resolveConflict(workspace:targetArchive:internalName:selectedMod:)`
- Produces:
  - `public struct WorkspaceModConflictCandidate: Equatable, Identifiable`
  - Enriched `public struct WorkspaceModConflict`
  - `public var WorkspaceQuickVerifyResult.unresolvedConflictCount: Int`
  - `public var WorkspaceQuickVerifyResult.resolvedConflictCount: Int`

- [ ] **Step 1: Write failing quick verify tests**

In existing quick verify tests that compare the whole `WorkspaceModConflict`
value, replace whole-struct equality with field assertions. For example,
`testWorkspaceQuickVerifyFlagsDuplicateTargetsWithDifferentBytes` keeps these
assertions after the new model lands:

```swift
let conflict = try XCTUnwrap(result.conflicts.first)
XCTAssertEqual(conflict.targetPath, "[media]\\classes\\trucks\\same.xml")
XCTAssertEqual(conflict.mods, ["first", "second"])
XCTAssertFalse(conflict.isResolved)
```

`testWorkspaceQuickVerifyFlagsDuplicateNonInitialTargetsWithIdenticalBytes`
keeps these assertions:

```swift
let conflict = try XCTUnwrap(result.conflicts.first)
XCTAssertEqual(conflict.targetPath, "shared_textures_base.pak:[textures]\\foo.dds")
XCTAssertEqual(conflict.mods, ["first", "second"])
XCTAssertTrue(conflict.isByteIdentical)
```

Then add these new tests:

```swift
func testWorkspaceQuickVerifyIncludesCandidateDetailsForUnresolvedConflict() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-quick-conflict-details")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

    let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

    let conflict = try XCTUnwrap(result.conflicts.first)
    XCTAssertFalse(conflict.isResolved)
    XCTAssertFalse(conflict.isByteIdentical)
    XCTAssertEqual(conflict.targetArchive, .initial)
    XCTAssertEqual(conflict.internalName, "[media]\\classes\\trucks\\same.xml")
    XCTAssertEqual(conflict.targetPath, "[media]\\classes\\trucks\\same.xml")
    XCTAssertEqual(conflict.mods, ["first", "second"])
    XCTAssertEqual(conflict.candidates.map(\.modFolderName), ["first", "second"])
    XCTAssertEqual(conflict.candidates.map(\.originalName), [
        "classes/trucks/same.xml",
        "classes/trucks/same.xml"
    ])
    XCTAssertTrue(conflict.candidates.allSatisfy { $0.byteSize > 0 })
    XCTAssertTrue(conflict.candidates.allSatisfy { $0.sha256.count == 64 })
    XCTAssertNil(conflict.selectedMod)
    XCTAssertEqual(result.unresolvedConflictCount, 1)
    XCTAssertEqual(result.resolvedConflictCount, 0)
}

func testWorkspaceQuickVerifyMarksValidResolutionAsResolved() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-quick-resolved-conflict")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "second"
    )

    let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

    let conflict = try XCTUnwrap(result.conflicts.first)
    XCTAssertTrue(conflict.isResolved)
    XCTAssertEqual(conflict.selectedMod, "second")
    XCTAssertEqual(result.unresolvedConflictCount, 0)
    XCTAssertEqual(result.resolvedConflictCount, 1)
}

func testWorkspaceQuickVerifyPrunesResolutionWhenNoCurrentConflictRemains() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-quick-prune-resolved-conflict")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "second"
    )
    try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "first", enabled: false)

    let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

    XCTAssertEqual(result.conflicts, [])
    XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).conflictResolutions, [])
}

func testWorkspaceQuickVerifyTreatsInvalidSavedChoiceAsUnresolved() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-quick-invalid-choice")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "missing"
    )

    let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

    let conflict = try XCTUnwrap(result.conflicts.first)
    XCTAssertFalse(conflict.isResolved)
    XCTAssertNil(conflict.selectedMod)
    XCTAssertEqual(result.unresolvedConflictCount, 1)
    XCTAssertEqual(result.resolvedConflictCount, 0)
    XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).conflictResolutions, [])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyIncludesCandidateDetailsForUnresolvedConflict
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyMarksValidResolutionAsResolved
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyPrunesResolutionWhenNoCurrentConflictRemains
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyTreatsInvalidSavedChoiceAsUnresolved
```

Expected: FAIL because quick verify still returns only `targetPath + mods`.

- [ ] **Step 3: Implement enriched models**

In `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift`, replace `WorkspaceQuickVerifyResult` and `WorkspaceModConflict`, and add `WorkspaceModConflictCandidate`:

```swift
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
```

- [ ] **Step 4: Implement resolution-aware quick verify and pruning**

In `PakWorkspaceManager.quickVerify`, replace the body with this structure:

```swift
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
        .map { candidates in
            makeWorkspaceConflict(
                candidates: candidates,
                selectedMod: resolutionResult.validSelections[candidates[0].key]
            )
        }
        .sorted { $0.targetPath < $1.targetPath }

    return WorkspaceQuickVerifyResult(conflicts: conflicts)
}
```

Add these private helpers inside `PakWorkspaceManager`:

```swift
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
        targetPath: targetPathDisplay(for: key),
        candidates: sortedCandidates.map(\.candidate),
        selectedMod: selectedMod
    )
}

private static func pruneConflictResolutionsIfNeeded(
    workspace: URL,
    manifest: inout PakWorkspaceManifest,
    grouped: [MappedTargetKey: [MappedConflictCandidate]]
) throws -> (validSelections: [MappedTargetKey: String]) {
    var validSelections: [MappedTargetKey: String] = [:]
    var pruned = false
    var kept: [PakWorkspaceConflictResolution] = []

    for resolution in manifest.conflictResolutions {
        let key = MappedTargetKey(targetArchive: resolution.targetArchive, internalName: resolution.internalName)
        guard let candidates = grouped[key],
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

    return (validSelections: validSelections)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyIncludesCandidateDetailsForUnresolvedConflict
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyMarksValidResolutionAsResolved
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyPrunesResolutionWhenNoCurrentConflictRemains
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyTreatsInvalidSavedChoiceAsUnresolved
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyFlagsDuplicateTargetsWithDifferentBytes
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceQuickVerifyFlagsDuplicateTargetsWithIdenticalBytes
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift
git commit -m "feat: enrich workspace conflict verification"
```

---

### Task 3: Resolution-Aware Workspace Build

**Files:**
- Modify: `Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift`
- Test: `Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift`

**Interfaces:**
- Consumes:
  - `PakWorkspaceManifest.conflictResolutions`
  - `groupedMappedCandidates(_:)`
  - `pruneConflictResolutionsIfNeeded(workspace:manifest:grouped:)`
- Produces:
  - resolution-aware mapped entry filtering before `ModMerger.mergeWorkspaceInitial(...)`

- [ ] **Step 1: Write failing build tests**

Add these tests in `Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift` near the existing mod conflict build tests:

```swift
func testWorkspaceBuildUsesSelectedConflictResolutionCandidate() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-build-resolved-conflict")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "second"
    )

    _ = try PakWorkspaceManager.build(workspace: workspace)

    let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
    let entry = try XCTUnwrap(archive.entries.first { $0.name == "[media]\\classes\\trucks\\same.xml" })
    XCTAssertEqual(
        try PakReader.readUncompressedPayload(entry: entry, in: archive),
        Data("<Truck id=\"second\"/>".utf8)
    )
}

func testWorkspaceBuildStillRejectsUnresolvedDifferentBytesConflict() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-build-unresolved-conflict")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

    XCTAssertThrowsError(try PakWorkspaceManager.build(workspace: workspace)) { error in
        XCTAssertTrue(String(describing: error).contains("[media]\\classes\\trucks\\same.xml"))
    }
}

func testWorkspaceBuildPrunesStaleResolutionAndUsesRemainingSingleCandidate() throws {
    let base = try makeSyntheticInitialPak()
    let workspace = try temporaryDirectory(named: "workspace-build-prune-stale-resolution")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
    let first = try makePak(named: "first.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
    ])
    let second = try makePak(named: "second.pak", entries: [
        "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
    ])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
    try PakWorkspaceManager.resolveConflict(
        workspace: workspace,
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\same.xml",
        selectedMod: "second"
    )
    try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "first", enabled: false)

    _ = try PakWorkspaceManager.build(workspace: workspace)

    XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).conflictResolutions, [])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuildUsesSelectedConflictResolutionCandidate
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuildStillRejectsUnresolvedDifferentBytesConflict
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuildPrunesStaleResolutionAndUsesRemainingSingleCandidate
```

Expected: `testWorkspaceBuildUsesSelectedConflictResolutionCandidate` FAILS because build still sees both differing entries; `testWorkspaceBuildStillRejectsUnresolvedDifferentBytesConflict` PASSES with current behavior; `testWorkspaceBuildPrunesStaleResolutionAndUsesRemainingSingleCandidate` FAILS because build does not prune stale manifest entries yet.

- [ ] **Step 3: Implement mapped entry filtering for build**

In `buildCandidate`, replace:

```swift
let mapped = try mappedEntriesForEnabledMods(workspace: workspace, manifest: manifest).flatMap(\.entries)
```

with:

```swift
let mappedMods = try mappedEntriesForEnabledMods(workspace: workspace, manifest: manifest)
let mapped = try resolutionAwareMappedEntries(workspace: workspace, manifest: manifest, mappedMods: mappedMods)
```

Add this private helper in `PakWorkspaceManager`:

```swift
private static func resolutionAwareMappedEntries(
    workspace: URL,
    manifest: PakWorkspaceManifest,
    mappedMods: [(mod: PakWorkspaceMod, entries: [ModMappedEntry])]
) throws -> [ModMappedEntry] {
    var mutableManifest = manifest
    let grouped = groupedMappedCandidates(mappedMods)
    let resolutionResult = try pruneConflictResolutionsIfNeeded(
        workspace: workspace,
        manifest: &mutableManifest,
        grouped: grouped
    )
    let selectedByKey = resolutionResult.validSelections

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuildUsesSelectedConflictResolutionCandidate
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuildStillRejectsUnresolvedDifferentBytesConflict
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuildPrunesStaleResolutionAndUsesRemainingSingleCandidate
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceVerifyRejectsModToModConflict
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerCore/PakWorkspace/PakWorkspaceManager.swift Tests/SnowRunnerCoreTests/PakWorkspaceTests.swift
git commit -m "feat: apply conflict resolutions during workspace build"
```

---

### Task 4: App Service And ViewModel Resolution Flow

**Files:**
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceAppService.swift`
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceViewModel.swift`
- Test: `SnowRunnerModEditor/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`

**Interfaces:**
- Consumes:
  - `PakWorkspaceManager.resolveConflict(workspace:targetArchive:internalName:selectedMod:)`
  - `PakWorkspaceManager.clearConflictResolution(workspace:targetArchive:internalName:)`
- Produces:
  - `WorkspaceAppServicing.resolveConflict(...)`
  - `WorkspaceAppServicing.clearConflictResolution(...)`
  - `WorkspaceViewModel.resolveConflict(...)`
  - `WorkspaceViewModel.clearConflictResolution(...)`

- [ ] **Step 1: Write failing ViewModel tests**

In `SnowRunnerModEditor/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift`, add:

```swift
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
```

Extend `FakeWorkspaceService` with:

```swift
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

var resolvedConflicts: [ResolvedConflict] = []
var clearedConflicts: [ClearedConflict] = []
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter WorkspaceViewModelTests/testResolveConflictCallsServiceRefreshesQuickVerifyAndStaysOnConflictDetails
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter WorkspaceViewModelTests/testClearConflictResolutionCallsServiceRefreshesQuickVerifyAndStaysOnConflictDetails
```

Expected: FAIL because service and view model methods do not exist.

- [ ] **Step 3: Add service methods**

In `WorkspaceAppService.swift`, add to `WorkspaceAppServicing`:

```swift
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
```

Add implementations to `WorkspaceAppService`:

```swift
public func resolveConflict(
    workspace: URL,
    targetArchive: ModMergeTargetArchive,
    internalName: String,
    selectedMod: String
) async throws -> PakWorkspaceSummary {
    try await detachedValue(priority: .userInitiated) {
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
    try await detachedValue(priority: .userInitiated) {
        try PakWorkspaceManager.clearConflictResolution(
            workspace: workspace,
            targetArchive: targetArchive,
            internalName: internalName
        )
        return try PakWorkspaceManager.summary(workspace: workspace)
    }
}
```

Add matching methods to `FakeWorkspaceService`:

```swift
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
```

- [ ] **Step 4: Add ViewModel methods**

In `WorkspaceViewModel.swift`, add:

```swift
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
        startQuickVerify()
    } catch {
        errorMessage = String(describing: error)
        busyState = .idle
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter WorkspaceViewModelTests/testResolveConflictCallsServiceRefreshesQuickVerifyAndStaysOnConflictDetails
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter WorkspaceViewModelTests/testClearConflictResolutionCallsServiceRefreshesQuickVerifyAndStaysOnConflictDetails
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceAppService.swift SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceViewModel.swift SnowRunnerModEditor/SnowRunnerModEditorTests/WorkspaceViewModelTests.swift
git commit -m "feat: expose conflict resolution in workspace view model"
```

---

### Task 5: Conflict Resolver UI And Quick Verify Summary

**Files:**
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor/ConflictDetailsView.swift`
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceOperationView.swift`

**Interfaces:**
- Consumes:
  - `WorkspaceQuickVerifyResult.conflicts`
  - `WorkspaceQuickVerifyResult.unresolvedConflictCount`
  - `WorkspaceQuickVerifyResult.resolvedConflictCount`
  - `WorkspaceModConflict.candidates`
  - `WorkspaceViewModel.resolveConflict(...)`
  - `WorkspaceViewModel.clearConflictResolution(...)`
- Produces:
  - two-pane `ConflictDetailsView`
  - unresolved/resolved quick verify copy

- [ ] **Step 1: Update quick verify card copy**

In `WorkspaceOperationView.swift`, update `hasQuickVerifyConflicts` to mean unresolved conflicts:

```swift
private var hasQuickVerifyConflicts: Bool {
    (viewModel.quickVerifyResult?.unresolvedConflictCount ?? 0) > 0
}
```

Add a visibility helper for the details button:

```swift
private var hasAnyQuickVerifyConflicts: Bool {
    !(viewModel.quickVerifyResult?.conflicts.isEmpty ?? true)
}
```

Use `hasAnyQuickVerifyConflicts` for the `Show Conflict Details` button condition:

```swift
if hasAnyQuickVerifyConflicts {
    Button("Show Conflict Details") {
        viewModel.showConflictDetails()
    }
    .buttonStyle(SRButtonStyle(colorStyle: hasQuickVerifyConflicts ? .destructive : .normal, size: .small))
}
```

Replace `quickVerifyText` with:

```swift
private var quickVerifyText: String {
    guard let result = viewModel.quickVerifyResult else { return "Checking..." }
    if result.conflicts.isEmpty {
        return "No conflicts found"
    }
    if result.unresolvedConflictCount == 0 {
        return "All conflicts resolved"
    }
    return "\(result.unresolvedConflictCount) unresolved conflict\(result.unresolvedConflictCount == 1 ? "" : "s")"
}
```

- [ ] **Step 2: Replace ConflictDetailsView with two-pane resolver**

Replace the body implementation in `ConflictDetailsView.swift` with this structure:

```swift
public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        header

        if conflicts.isEmpty {
            Text("No conflicts found.")
                .foregroundStyle(.secondary)
        } else {
            HSplitView {
                List(conflicts, selection: $selectedConflictID) { conflict in
                    conflictRow(conflict)
                        .tag(conflict.id)
                }
                .frame(minWidth: 260, idealWidth: 320)

                if let conflict = selectedConflict {
                    conflictDetail(conflict)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text("Select a conflict.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
        selectedConflictID = selectedConflictID ?? conflicts.first?.id
    }
    .onChange(of: conflicts.map(\.id)) { _, ids in
        if let selectedConflictID, ids.contains(selectedConflictID) {
            return
        }
        selectedConflictID = ids.first
    }
}
```

Add state and helpers:

```swift
@State private var selectedConflictID: String?

private var conflicts: [WorkspaceModConflict] {
    viewModel.quickVerifyResult?.conflicts ?? []
}

private var selectedConflict: WorkspaceModConflict? {
    conflicts.first { $0.id == selectedConflictID }
}

private var header: some View {
    HStack {
        Text("Conflict Details")
            .font(.title3.weight(.semibold))
        Spacer()
        Button("Back to Workspace") {
            viewModel.showWorkspace()
        }
        .keyboardShortcut(.cancelAction)
    }
}
```

Add row/detail builders:

```swift
private func conflictRow(_ conflict: WorkspaceModConflict) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        HStack {
            Text(conflict.isResolved ? "Resolved" : "Unresolved")
                .font(.caption.weight(.semibold))
                .foregroundStyle(conflict.isResolved ? .green : .red)
            Spacer()
        }
        Text(conflict.targetPath)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
            .textSelection(.enabled)
        Text(conflict.mods.joined(separator: ", "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
    .padding(.vertical, 4)
}

private func conflictDetail(_ conflict: WorkspaceModConflict) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text(conflict.targetPath)
                .font(.headline)
                .textSelection(.enabled)

            HStack {
                Text(conflict.isResolved ? "Resolved by \(conflict.selectedMod ?? "")" : "Choose a version")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(conflict.isResolved ? .green : .primary)
                Spacer()
                if conflict.isResolved {
                    Button("Clear Resolution") {
                        Task {
                            await viewModel.clearConflictResolution(
                                targetArchive: conflict.targetArchive,
                                internalName: conflict.internalName
                            )
                        }
                    }
                    .buttonStyle(SRButtonStyle(colorStyle: .normal, size: .small))
                    .disabled(viewModel.isBusy)
                }
            }

            VStack(spacing: 10) {
                ForEach(conflict.candidates) { candidate in
                    candidateRow(candidate, conflict: conflict)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
    }
}
```

Add candidate row:

```swift
private func candidateRow(
    _ candidate: WorkspaceModConflictCandidate,
    conflict: WorkspaceModConflict
) -> some View {
    HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(candidate.modFolderName)
                    .font(.callout.weight(.semibold))
                if conflict.selectedMod == candidate.modFolderName {
                    Text("Selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            Text(candidate.originalName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("\(candidate.byteSize) bytes · \(candidate.sha256.prefix(12))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        Spacer()
        Button(conflict.isByteIdentical ? "Keep One Copy" : "Use This Version") {
            Task {
                await viewModel.resolveConflict(
                    targetArchive: conflict.targetArchive,
                    internalName: conflict.internalName,
                    selectedMod: candidate.modFolderName
                )
            }
        }
        .buttonStyle(SRButtonStyle(colorStyle: .main, size: .small))
        .disabled(viewModel.isBusy || conflict.selectedMod == candidate.modFolderName)
    }
    .padding(12)
    .background {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor))
    }
    .overlay {
        RoundedRectangle(cornerRadius: 8)
            .stroke(conflict.selectedMod == candidate.modFolderName ? Color.green.opacity(0.6) : Color.gray.opacity(0.2))
    }
}
```

- [ ] **Step 3: Update preview data**

Replace the preview conflicts with enriched models:

```swift
model.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
    WorkspaceModConflict(
        targetArchive: .initial,
        internalName: "[media]\\classes\\trucks\\azov_64131.xml",
        targetPath: "[media]\\classes\\trucks\\azov_64131.xml",
        candidates: [
            WorkspaceModConflictCandidate(modFolderName: "azov-tuning-pack", originalName: "classes/trucks/azov_64131.xml", byteSize: 2_048, sha256: "aaaaaaaaaaaa0000000000000000000000000000000000000000000000000000"),
            WorkspaceModConflictCandidate(modFolderName: "loadstar-rescue-kit", originalName: "classes/trucks/azov_64131.xml", byteSize: 2_212, sha256: "bbbbbbbbbbbb0000000000000000000000000000000000000000000000000000")
        ]
    ),
    WorkspaceModConflict(
        targetArchive: .initial,
        internalName: "[media]\\classes\\wheels\\offroad.xml",
        targetPath: "[media]\\classes\\wheels\\offroad.xml",
        candidates: [
            WorkspaceModConflictCandidate(modFolderName: "loadstar-rescue-kit", originalName: "classes/wheels/offroad.xml", byteSize: 1_024, sha256: "cccccccccccc0000000000000000000000000000000000000000000000000000"),
            WorkspaceModConflictCandidate(modFolderName: "trail-wheel-pack", originalName: "classes/wheels/offroad.xml", byteSize: 1_024, sha256: "cccccccccccc0000000000000000000000000000000000000000000000000000")
        ],
        selectedMod: "trail-wheel-pack"
    )
])
```

- [ ] **Step 4: Build/test the app target**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter WorkspaceViewModelTests
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build
```

Expected: PASS build and tests.

- [ ] **Step 5: Commit**

```bash
git add SnowRunnerModEditor/SnowRunnerModEditor/ConflictDetailsView.swift SnowRunnerModEditor/SnowRunnerModEditor/WorkspaceOperationView.swift
git commit -m "feat: add conflict resolver UI"
```

---

### Task 6: Full Verification And Polish

**Files:**
- Modify only files already changed in Tasks 1-5 if verification finds compile errors, wording mistakes, or layout issues.

**Interfaces:**
- Consumes all interfaces produced in Tasks 1-5.
- Produces a passing implementation of the approved design.

- [ ] **Step 1: Run full SwiftPM tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
```

Expected: PASS.

- [ ] **Step 2: Run app build**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift build
```

Expected: PASS.

- [ ] **Step 3: Inspect status**

Run:

```bash
git status --short
```

Expected: no unstaged or uncommitted source changes. If verification forced small fixes, stage and commit them:

```bash
git add Sources/SnowRunnerCore SnowRunnerModEditor Tests
git commit -m "fix: polish conflict resolution implementation"
```

- [ ] **Step 4: Summarize implementation**

Prepare a final summary with:

- core manifest and verify/build behavior
- app resolver behavior
- test commands run
- any remaining known limitations
