# PAK Workspace CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the top-level `snowrunner-tool workspace` CLI for initializing editable PAK workspaces, adding editable mod folders, verifying the workspace with a temporary build, and publishing a verified `build/initial.pak`.

**Architecture:** Add a focused `PakWorkspace` module for workspace metadata, transactions, load-list rebuilding, and CLI orchestration. Reuse the existing `ModMerge` path mapping, duplicate resolution, string merging, texture header generation, load-list overlay, and PAK writer logic by extracting shared merge-core helpers instead of duplicating merge semantics. Directory-backed mods carry cached source PAK metadata so unchanged PCT texture entries can preserve compressed payloads and supported ZIP metadata.

**Tech Stack:** Swift 6 package, XCTest, Foundation file APIs, CryptoKit SHA-256, existing `PakReader`/`PakWriter`/`PakVerifier`, existing `ModArchiveMapper`/`ModMerger`.

---

## File Map

- Create `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManifest.swift`
  - Codable workspace manifest, mod entries, source-entry hashes, stable path constants.
- Create `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceError.swift`
  - User-facing workspace errors with path-specific messages.
- Create `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceReporter.swift`
  - Workspace stdout and markdown report formatting.
- Create `Sources/SnowRunnerTool/PakWorkspace/WorkspaceInitialLoadListBuilder.swift`
  - Rebuilds `initial.pak`-sourced records from `initial/`, preserves non-initial records.
- Create `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift`
  - Implements `init`, `addMods`, `verify`, and `build` orchestration.
- Modify `Sources/SnowRunnerTool/ModMerge/ModArchiveMapper.swift`
  - Add directory-backed mapping using cached source archive metadata for unchanged entries.
- Modify `Sources/SnowRunnerTool/ModMerge/ModMerger.swift`
  - Extract shared core that accepts base file sources + base manifest + mapped entries.
- Modify `Sources/SnowRunnerTool/CLI.swift`
  - Add top-level `workspace` command parsing.
- Modify `README.md`
  - Document workspace commands and generated output policy.
- Create `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`
  - Workspace manager, load-list, source-cache, verify/build behavior.
- Modify `Tests/SnowRunnerToolTests/CLITests.swift`
  - Top-level workspace CLI usage tests.

---

### Task 1: Workspace Manifest And Errors

**Files:**
- Create: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManifest.swift`
- Create: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceError.swift`
- Test: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Write manifest round-trip tests**

Add `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift` with:

```swift
import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakWorkspaceTests: XCTestCase {
    func testWorkspaceManifestRoundTrips() throws {
        let manifest = PakWorkspaceManifest(
            version: 1,
            initialSourcePath: "/game/initial.pak",
            mods: [
                PakWorkspaceMod(
                    sourcePath: "/mods/demo.pak",
                    folderName: "demo",
                    archiveName: "demo.pak",
                    sourceCachePath: ".snowrunner/sources/demo.pak",
                    entries: [
                        PakWorkspaceSourceEntry(
                            sourceEntryName: "prebuild/textures/pct/foo.pct",
                            workspacePath: "mods/demo/prebuild/textures/pct/foo.pct",
                            sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                        )
                    ]
                )
            ],
            policy: PakWorkspacePolicy(textureMode: "inlineInitial", allowInitialOverwrite: true)
        )

        let data = try JSONEncoder.pakWorkspace.encode(manifest)
        let decoded = try JSONDecoder.pakWorkspace.decode(PakWorkspaceManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }

    func testWorkspacePathsAreStable() {
        let root = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)

        XCTAssertEqual(PakWorkspacePaths.manifestURL(root: root).path, "/tmp/workspace/.snowrunner-workspace.json")
        XCTAssertEqual(PakWorkspacePaths.initialDirectory(root: root).path, "/tmp/workspace/initial")
        XCTAssertEqual(PakWorkspacePaths.modsDirectory(root: root).path, "/tmp/workspace/mods")
        XCTAssertEqual(PakWorkspacePaths.buildInitialPak(root: root).path, "/tmp/workspace/build/initial.pak")
        XCTAssertEqual(PakWorkspacePaths.buildReport(root: root).path, "/tmp/workspace/build/workspace-build-report.md")
        XCTAssertEqual(PakWorkspacePaths.sourceCache(root: root, folderName: "demo").path, "/tmp/workspace/.snowrunner/sources/demo.pak")
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceManifestRoundTrips
```

Expected: compile failure because `PakWorkspaceManifest`, `PakWorkspaceMod`, `PakWorkspaceSourceEntry`, `PakWorkspacePolicy`, `PakWorkspacePaths`, and JSON coder helpers do not exist.

- [ ] **Step 3: Implement manifest and path types**

Create `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManifest.swift`:

```swift
import Foundation

public struct PakWorkspaceManifest: Codable, Equatable {
    public let version: Int
    public var initialSourcePath: String
    public var mods: [PakWorkspaceMod]
    public var policy: PakWorkspacePolicy

    public init(version: Int, initialSourcePath: String, mods: [PakWorkspaceMod], policy: PakWorkspacePolicy) {
        self.version = version
        self.initialSourcePath = initialSourcePath
        self.mods = mods
        self.policy = policy
    }
}

public struct PakWorkspaceMod: Codable, Equatable {
    public var sourcePath: String
    public var folderName: String
    public var archiveName: String
    public var sourceCachePath: String
    public var entries: [PakWorkspaceSourceEntry]

    public init(
        sourcePath: String,
        folderName: String,
        archiveName: String,
        sourceCachePath: String,
        entries: [PakWorkspaceSourceEntry]
    ) {
        self.sourcePath = sourcePath
        self.folderName = folderName
        self.archiveName = archiveName
        self.sourceCachePath = sourceCachePath
        self.entries = entries
    }
}

public struct PakWorkspaceSourceEntry: Codable, Equatable {
    public var sourceEntryName: String
    public var workspacePath: String
    public var sha256: String

    public init(sourceEntryName: String, workspacePath: String, sha256: String) {
        self.sourceEntryName = sourceEntryName
        self.workspacePath = workspacePath
        self.sha256 = sha256
    }
}

public struct PakWorkspacePolicy: Codable, Equatable {
    public var textureMode: String
    public var allowInitialOverwrite: Bool

    public init(textureMode: String, allowInitialOverwrite: Bool) {
        self.textureMode = textureMode
        self.allowInitialOverwrite = allowInitialOverwrite
    }
}

public enum PakWorkspacePaths {
    public static let manifestName = ".snowrunner-workspace.json"
    public static let initialDirectoryName = "initial"
    public static let modsDirectoryName = "mods"
    public static let metadataDirectoryName = ".snowrunner"
    public static let sourcesDirectoryName = "sources"
    public static let buildDirectoryName = "build"
    public static let buildReportName = "workspace-build-report.md"

    public static func manifestURL(root: URL) -> URL {
        root.appendingPathComponent(manifestName)
    }

    public static func initialDirectory(root: URL) -> URL {
        root.appendingPathComponent(initialDirectoryName, isDirectory: true)
    }

    public static func modsDirectory(root: URL) -> URL {
        root.appendingPathComponent(modsDirectoryName, isDirectory: true)
    }

    public static func modDirectory(root: URL, folderName: String) -> URL {
        modsDirectory(root: root).appendingPathComponent(folderName, isDirectory: true)
    }

    public static func metadataDirectory(root: URL) -> URL {
        root.appendingPathComponent(metadataDirectoryName, isDirectory: true)
    }

    public static func sourcesDirectory(root: URL) -> URL {
        metadataDirectory(root: root).appendingPathComponent(sourcesDirectoryName, isDirectory: true)
    }

    public static func sourceCache(root: URL, folderName: String) -> URL {
        sourcesDirectory(root: root).appendingPathComponent(folderName + ".pak")
    }

    public static func buildDirectory(root: URL) -> URL {
        root.appendingPathComponent(buildDirectoryName, isDirectory: true)
    }

    public static func buildInitialPak(root: URL) -> URL {
        buildDirectory(root: root).appendingPathComponent("initial.pak")
    }

    public static func buildReport(root: URL) -> URL {
        buildDirectory(root: root).appendingPathComponent(buildReportName)
    }
}

public extension JSONEncoder {
    static var pakWorkspace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var pakWorkspace: JSONDecoder {
        JSONDecoder()
    }
}
```

- [ ] **Step 4: Implement workspace errors**

Create `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceError.swift`:

```swift
import Foundation

public enum PakWorkspaceError: Error, CustomStringConvertible, Equatable {
    case missingManifest(String)
    case unsupportedManifestVersion(Int)
    case missingInitialDirectory(String)
    case initialDirectoryAlreadyExists(String)
    case modDirectoryAlreadyExists(String)
    case duplicateModFolderName(String)
    case missingModDirectory(String)
    case missingSourceCache(String)
    case invalidCommand(String)
    case verificationFailed(name: String, issues: [VerifierIssue])

    public var description: String {
        switch self {
        case let .missingManifest(path):
            return "Not a pak workspace; missing \(path)"
        case let .unsupportedManifestVersion(version):
            return "Unsupported workspace manifest version: \(version)"
        case let .missingInitialDirectory(path):
            return "Workspace has no initial contents: \(path)"
        case let .initialDirectoryAlreadyExists(path):
            return "Workspace initial directory already exists and is not empty: \(path)"
        case let .modDirectoryAlreadyExists(path):
            return "Workspace mod directory already exists: \(path)"
        case let .duplicateModFolderName(name):
            return "Duplicate workspace mod folder name: \(name)"
        case let .missingModDirectory(path):
            return "Workspace manifest references missing mod directory: \(path)"
        case let .missingSourceCache(path):
            return "Workspace manifest references missing cached source PAK: \(path)"
        case let .invalidCommand(message):
            return message
        case let .verificationFailed(name, issues):
            let details = issues.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
            return "\(name) failed:\n\(details)"
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceManifestRoundTrips
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManifest.swift Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceError.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: add pak workspace manifest"
```

---

### Task 2: Workspace Initial Load-List Builder

**Files:**
- Create: `Sources/SnowRunnerTool/PakWorkspace/WorkspaceInitialLoadListBuilder.swift`
- Test: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Add load-list builder tests**

Append to `PakWorkspaceTests`:

```swift
func testWorkspaceInitialLoadListBuilderPreservesNonInitialRecordsAndAddsMeshAsInitial() throws {
    let root = try temporaryDirectory(named: "workspace-load-list")
    let initial = root.appendingPathComponent("initial", isDirectory: true)
    try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: true)
    try writeFile(root: initial, relativePath: "[media]/classes/trucks/new.xml", data: Data("<Truck/>".utf8))
    try writeFile(root: initial, relativePath: "[media]/_templates/trucks.xml", data: Data("<Templates/>".utf8))
    try writeFile(root: initial, relativePath: "[meshes]/new_mesh", data: Data([1, 2, 3]))
    try writeFile(root: initial, relativePath: "[strings]/strings_english.str", data: Data("KEY\t\t\"Value\"".utf8))
    try writeFile(root: initial, relativePath: "initial.cache_block", data: Data("cache".utf8))

    let baseManifest = try LoadListBuilder.buildManifest(records: [
        LoadListRecord(
            manifestPath: "<meshes>\\shared_mesh",
            loaderType: "mesh_loader",
            sourcePak: "shared.pak",
            phase: "MESH load"
        ),
        LoadListRecord(
            manifestPath: "<sound>\\sound.sound_list",
            loaderType: "sound_loader",
            sourcePak: "shared_sound.pak",
            phase: "SOUND load"
        ),
        LoadListRecord(
            manifestPath: "<media>\\classes\\trucks\\old.xml",
            loaderType: "cls_loader",
            sourcePak: "initial.pak",
            phase: "CLASSES load"
        )
    ])

    let records = try WorkspaceInitialLoadListBuilder.records(fromInitialDirectory: initial, preservingFrom: baseManifest)

    XCTAssertTrue(records.contains {
        $0.manifestPath == "<meshes>\\shared_mesh" && $0.sourcePak == "shared.pak"
    })
    XCTAssertTrue(records.contains {
        $0.manifestPath == "<sound>\\sound.sound_list" && $0.sourcePak == "shared_sound.pak"
    })
    XCTAssertFalse(records.contains { $0.manifestPath == "<media>\\classes\\trucks\\old.xml" })
    XCTAssertTrue(records.contains {
        $0.manifestPath == "<media>\\classes\\trucks\\new.xml"
            && $0.loaderType == "cls_loader"
            && $0.sourcePak == "initial.pak"
    })
    XCTAssertTrue(records.contains {
        $0.manifestPath == "<media>\\_templates\\trucks.xml"
            && $0.loaderType == "tpl_loader"
            && $0.sourcePak == "initial.pak"
    })
    XCTAssertTrue(records.contains {
        $0.manifestPath == "<meshes>\\new_mesh"
            && $0.loaderType == "mesh_loader"
            && $0.sourcePak == "initial.pak"
    })
    XCTAssertFalse(records.contains { $0.manifestPath.hasPrefix("<strings>\\") })
}

func testWorkspaceInitialLoadListBuilderRejectsUnknownLoadListedPath() throws {
    let root = try temporaryDirectory(named: "workspace-load-list-invalid")
    let initial = root.appendingPathComponent("initial", isDirectory: true)
    try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: true)
    try writeFile(root: initial, relativePath: "[media]/unknown/demo.bin", data: Data([1]))

    let baseManifest = try LoadListBuilder.buildManifest(records: [])

    XCTAssertThrowsError(try WorkspaceInitialLoadListBuilder.records(fromInitialDirectory: initial, preservingFrom: baseManifest))
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceInitialLoadListBuilder
```

Expected: compile failure because `WorkspaceInitialLoadListBuilder` does not exist.

- [ ] **Step 3: Implement builder**

Create `Sources/SnowRunnerTool/PakWorkspace/WorkspaceInitialLoadListBuilder.swift`:

```swift
import Foundation

public enum WorkspaceInitialLoadListBuilder {
    public static func records(
        fromInitialDirectory directory: URL,
        preservingFrom baseManifest: LoadListManifest
    ) throws -> [LoadListRecord] {
        let preserved = baseManifest.phaseOrder
            .flatMap { baseManifest.recordsByPhase[$0] ?? [] }
            .filter { $0.sourcePak != "initial.pak" }

        let sources = try PakDirectoryScanner.scan(
            rootDirectory: directory,
            excludingTopLevelDirectories: [],
            additionalFileSources: []
        )
        let rebuilt = try sources.flatMap { try classifyInitialSource($0.internalName) }
        return preserved + rebuilt
    }

    public static func classifyInitialSource(_ internalName: String) throws -> [LoadListRecord] {
        if internalName == LoadListConstants.manifestEntryName
            || internalName == CacheBlockConstants.initialCacheBlockName
            || internalName == "[ssl_cache]\\initial_pak" {
            return []
        }
        if internalName.hasPrefix("[strings]\\")
            || internalName.hasPrefix("[sound]\\")
            || internalName.hasPrefix("[ps]\\")
            || internalName.hasPrefix("[ps_common]\\")
            || internalName.hasPrefix("[ui]\\") {
            return []
        }
        if internalName.hasPrefix("[textures]\\") {
            if internalName.hasPrefix("[textures]\\pct\\") && internalName.hasSuffix(".pct_header") {
                let manifestPath = convertNamespaceBrackets(internalName)
                return [
                    LoadListRecord(
                        manifestPath: manifestPath,
                        loaderType: "pct_mr2_header",
                        sourcePak: "initial.pak",
                        phase: "TEXTURE load"
                    ),
                    LoadListRecord(
                        manifestPath: manifestPath,
                        loaderType: "pct_faces",
                        sourcePak: "initial.pak",
                        phase: "TEXTURE load"
                    )
                ]
            }
            return []
        }

        return try LoadListClassifier.classifyMergedModEntry(internalName, textureSourcePak: "initial.pak")
    }

    private static func convertNamespaceBrackets(_ name: String) -> String {
        guard name.first == "[", let closing = name.firstIndex(of: "]") else {
            return name
        }
        let namespace = name[name.index(after: name.startIndex)..<closing]
        let rest = name[name.index(after: closing)...]
        return "<\(namespace)>\(rest)"
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceInitialLoadListBuilder
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/PakWorkspace/WorkspaceInitialLoadListBuilder.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: add workspace load-list builder"
```

---

### Task 3: Directory-Backed Mod Mapping With Source Cache

**Files:**
- Modify: `Sources/SnowRunnerTool/ModMerge/ModArchiveMapper.swift`
- Test: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Add directory mapper tests**

Append to `PakWorkspaceTests`:

```swift
func testDirectoryModMappingReusesCachedCompressedPCTWhenUnchanged() throws {
    let root = try temporaryDirectory(named: "workspace-directory-map")
    let modRoot = root.appendingPathComponent("mods/pc", isDirectory: true)
    let pct = makeSyntheticPCT(tableCount: 2)
    try writeFile(root: modRoot, relativePath: "prebuild/textures/pct/demo.pct", data: pct)
    let sourcePak = try makePak(named: "pc.pak", entries: [
        "prebuild/textures/pct/demo.pct": pct
    ])
    let sha = ModArchiveMapper.sha256Hex(uncompressedPayload: pct)
    let entries = [
        PakWorkspaceSourceEntry(
            sourceEntryName: "prebuild/textures/pct/demo.pct",
            workspacePath: "mods/pc/prebuild/textures/pct/demo.pct",
            sha256: sha
        )
    ]

    let mapped = try ModArchiveMapper.mapDirectory(
        at: modRoot,
        archiveName: "pc.pak",
        sourceCache: sourcePak,
        sourceEntries: entries,
        workspaceRoot: root
    )

    let pctEntry = try XCTUnwrap(mapped.first { $0.internalName == "[textures]\\pct\\demo.pct" })
    XCTAssertNotNil(pctEntry.compressedPayload)
    XCTAssertEqual(pctEntry.data, pct)
    XCTAssertTrue(mapped.contains { $0.internalName == "[textures]\\pct\\demo.pct_header" })
}

func testDirectoryModMappingRecompressesEditedPCT() throws {
    let root = try temporaryDirectory(named: "workspace-directory-map-edited")
    let modRoot = root.appendingPathComponent("mods/pc", isDirectory: true)
    let original = makeSyntheticPCT(tableCount: 2)
    var edited = original
    edited.append(0x7F)
    try writeFile(root: modRoot, relativePath: "prebuild/textures/pct/demo.pct", data: edited)
    let sourcePak = try makePak(named: "pc.pak", entries: [
        "prebuild/textures/pct/demo.pct": original
    ])
    let entries = [
        PakWorkspaceSourceEntry(
            sourceEntryName: "prebuild/textures/pct/demo.pct",
            workspacePath: "mods/pc/prebuild/textures/pct/demo.pct",
            sha256: ModArchiveMapper.sha256Hex(uncompressedPayload: original)
        )
    ]

    let mapped = try ModArchiveMapper.mapDirectory(
        at: modRoot,
        archiveName: "pc.pak",
        sourceCache: sourcePak,
        sourceEntries: entries,
        workspaceRoot: root
    )

    let pctEntry = try XCTUnwrap(mapped.first { $0.internalName == "[textures]\\pct\\demo.pct" })
    XCTAssertNil(pctEntry.compressedPayload)
    XCTAssertEqual(pctEntry.data, edited)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testDirectoryModMapping
```

Expected: compile failure because `mapDirectory` and `sha256Hex` do not exist.

- [ ] **Step 3: Implement directory mapper entry points**

Modify `ModArchiveMapper.swift`:

```swift
import CryptoKit
```

Add public helpers inside `ModArchiveMapper`:

```swift
public static func sha256Hex(uncompressedPayload data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

public static func mapDirectory(
    at directory: URL,
    archiveName: String,
    sourceCache: URL?,
    sourceEntries: [PakWorkspaceSourceEntry],
    workspaceRoot: URL
) throws -> [ModMappedEntry] {
    let sources = try PakModDirectoryScanner.scan(rootDirectory: directory)
    try validateMergeCompatiblePackagePaths(sources.map(\.internalName), archiveName: archiveName)
    let role = try role(
        forPackagePaths: sources.map(\.internalName).map(normalizedPackagePath),
        archiveName: archiveName
    )
    let cacheArchive = try sourceCache.map { try PakReader.readArchive(at: $0) }
    let cacheByName = Dictionary(uniqueKeysWithValues: (cacheArchive?.entries ?? []).map { ($0.name, $0) })
    let sourceHashByName = Dictionary(uniqueKeysWithValues: sourceEntries.map { ($0.sourceEntryName, $0.sha256) })

    var mapped: [ModMappedEntry] = []
    for source in sources {
        let payload = try source.readData()
        let destinations = try map(source.internalName, role: role, archiveURL: URL(fileURLWithPath: archiveName), payload: payload)
        let unchanged = sourceHashByName[source.internalName] == sha256Hex(uncompressedPayload: payload)
        let cachedEntry = cacheByName[source.internalName]
        let compressedPayload: PakCompressedPayload?
        if unchanged, let cacheArchive, let cachedEntry {
            compressedPayload = PakCompressedPayload(
                compressionMethod: cachedEntry.compressionMethod,
                data: try PakReader.readCompressedPayload(entry: cachedEntry, in: cacheArchive),
                crc32: cachedEntry.crc32,
                uncompressedSize: cachedEntry.uncompressedSize
            )
        } else {
            compressedPayload = nil
        }

        for destination in destinations {
            mapped.append(ModMappedEntry(
                archiveURL: directory,
                originalName: source.internalName,
                internalName: destination.internalName,
                targetArchive: destination.targetArchive,
                data: destination.data,
                localExtraField: destination.preserveZipExtraFields && unchanged ? (cachedEntry?.localExtraField ?? Data()) : Data(),
                centralExtraField: destination.preserveZipExtraFields && unchanged ? (cachedEntry?.centralExtraField ?? Data()) : Data(),
                compressedPayload: destination.preserveCompressedPayload && unchanged ? compressedPayload : nil
            ))
        }
    }
    return mapped
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testDirectoryModMapping
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/ModMerge/ModArchiveMapper.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: map workspace mod directories"
```

---

### Task 4: Shared Mod Merge Core For Workspace Inputs

**Files:**
- Modify: `Sources/SnowRunnerTool/ModMerge/ModMerger.swift`
- Modify: `Sources/SnowRunnerTool/ModMerge/ModMergePlan.swift`
- Test: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Add core merge test with directory base sources**

Append to `PakWorkspaceTests`:

```swift
func testModMergerWritesInlineTextureWorkspaceCandidateFromDirectorySources() throws {
    let workspace = try temporaryDirectory(named: "workspace-merge-core")
    let initial = PakWorkspacePaths.initialDirectory(root: workspace)
    try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: true)
    let baseManifest = try LoadListBuilder.buildManifest(records: [
        LoadListRecord(
            manifestPath: "<media>\\classes\\trucks\\existing.xml",
            loaderType: "cls_loader",
            sourcePak: "initial.pak",
            phase: "CLASSES load"
        )
    ])
    try LoadListWriter.writeManifest(baseManifest, to: initial.appendingPathComponent("pak.load_list"))
    try writeFile(root: initial, relativePath: "initial.cache_block", data: Data("cache".utf8))
    try writeFile(root: initial, relativePath: "[media]/classes/trucks/existing.xml", data: Data("<Truck/>".utf8))
    try writeFile(root: initial, relativePath: "[ssl_cache]/initial_pak", data: Data("ssl".utf8))
    try writeFile(root: initial, relativePath: "[strings]/strings_english.str", data: stringTableData("BASE_KEY\t\t\"Base\""))

    let mod = try makePak(named: "pc.pak", entries: [
        "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 2)
    ])
    let modDir = PakWorkspacePaths.modDirectory(root: workspace, folderName: "pc")
    try PakModUnpacker.unpack(archiveURL: mod, toDirectory: modDir)
    let archive = try PakReader.readArchive(at: mod)
    let sourceEntries = try archive.entries.map {
        PakWorkspaceSourceEntry(
            sourceEntryName: $0.name,
            workspacePath: "mods/pc/" + try PakModPath.fileSystemRelativePath(forArchiveName: $0.name),
            sha256: ModArchiveMapper.sha256Hex(uncompressedPayload: try PakReader.readUncompressedPayload(entry: $0, in: archive))
        )
    }
    let mapped = try ModArchiveMapper.mapDirectory(
        at: modDir,
        archiveName: "pc.pak",
        sourceCache: mod,
        sourceEntries: sourceEntries,
        workspaceRoot: workspace
    )
    let records = try WorkspaceInitialLoadListBuilder.records(fromInitialDirectory: initial, preservingFrom: baseManifest)
    let rebuiltManifest = try LoadListBuilder.buildManifest(records: records)
    let output = workspace.appendingPathComponent("candidate.pak")

    let result = try ModMerger.mergeWorkspaceInitial(
        initialDirectory: initial,
        baseManifest: rebuiltManifest,
        mappedEntries: mapped,
        outputInitialPak: output,
        reportURL: nil,
        verifyOutput: true
    )

    XCTAssertEqual(result.outputURL, output)
    let archive = try PakReader.readArchive(at: output)
    XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct" })
    XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct_header" })
    XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testModMergerWritesInlineTextureWorkspaceCandidateFromDirectorySources
```

Expected: compile failure because `ModMerger.mergeWorkspaceInitial` does not exist.

- [ ] **Step 3: Extract shared merge helpers**

Modify `ModMerger.swift` so existing `merge(...)` still works, and add:

```swift
public static func mergeWorkspaceInitial(
    initialDirectory: URL,
    baseManifest: LoadListManifest,
    mappedEntries rawMappedEntries: [ModMappedEntry],
    outputInitialPak: URL,
    reportURL: URL?,
    verifyOutput: Bool
) throws -> ModMergeResult
```

Implement `mergeWorkspaceInitial` with this structure:

```swift
let initialSources = try PakDirectoryScanner.scan(rootDirectory: initialDirectory)
let baseNames = Set(initialSources.map(\.internalName))
let partitionedEntries = try partitionStringTableEntries(rawMappedEntries)
let duplicateResolution = try resolveMappedDuplicates(partitionedEntries.regularEntries)
let mappedEntries = duplicateResolution.entries
let initialEntries = mappedEntries.filter { $0.targetArchive == .initial }
let inlineTextureEntries = try combinedExperimentalTextureEntries(
    mappedEntries.filter { $0.targetArchive == .sharedTexturesBase || $0.targetArchive == .sharedTextures }
)
let collisions = initialEntries.map(\.internalName).filter { baseNames.contains($0) }.sorted()
let inlineTextureCollisions = inlineTextureEntries.map(\.internalName).filter { baseNames.contains($0) }.sorted()
let overlay = try ModLoadListOverlay.overlay(
    baseManifest: baseManifest,
    mappedEntries: mappedEntries,
    textureSourcePakOverride: "initial.pak"
)
let loadListData = try LoadListWriter.encodeManifest(overlay.manifest)
let sources = try buildMergedSources(
    baseSources: initialSources,
    mappedEntries: initialEntries + inlineTextureEntries,
    stringMergeEntries: partitionedEntries.stringMergeEntries,
    loadListData: loadListData,
    requirePakLoadList: true
)
let written = try PakWriter.writeArchive(fileSources: sources, to: outputInitialPak)
if verifyOutput {
    let writtenArchive = try PakReader.readArchive(at: outputInitialPak)
    let basicIssues = try PakVerifier.verifyBasic(writtenArchive)
    if !basicIssues.isEmpty { throw ModMergeError.verificationFailed(name: "verify-basic", issues: basicIssues) }
    let layoutIssues = try PakVerifier.verifySnowPakLayout(writtenArchive)
    if !layoutIssues.isEmpty { throw ModMergeError.verificationFailed(name: "verify-snowpak-layout", issues: layoutIssues) }
}
```

Also add a new overload:

```swift
private static func buildMergedSources(
    baseSources: [PakFileSource],
    mappedEntries: [ModMappedEntry],
    stringMergeEntries: [ModMappedEntry],
    loadListData: Data?,
    requirePakLoadList: Bool
) throws -> [PakFileSource]
```

Use the existing archive-based `buildMergedSources` as a template, but read base data through `PakFileSource.readData()`.

- [ ] **Step 4: Run existing merge tests and new core test**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter ModMergerTests
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testModMergerWritesInlineTextureWorkspaceCandidateFromDirectorySources
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/ModMerge/ModMerger.swift Sources/SnowRunnerTool/ModMerge/ModMergePlan.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: share merge core with workspace"
```

---

### Task 5: Workspace Manager Init And Add Mods

**Files:**
- Create: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift`
- Test: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Add init and add-mod tests**

Append to `PakWorkspaceTests`:

```swift
func testWorkspaceInitCreatesManifestAndUnpacksInitial() throws {
    let workspace = try temporaryDirectory(named: "workspace-init")

    let result = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

    XCTAssertEqual(result.initialEntryCount, 10308)
    XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.manifestURL(root: workspace).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.initialDirectory(root: workspace).appendingPathComponent("pak.load_list").path))
    let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
    XCTAssertEqual(manifest.initialSourcePath, TestFixtures.initialPak.path)
    XCTAssertEqual(manifest.mods, [])
}

func testWorkspaceInitRejectsExistingNonEmptyInitial() throws {
    let workspace = try temporaryDirectory(named: "workspace-init-existing")
    try writeFile(root: PakWorkspacePaths.initialDirectory(root: workspace), relativePath: "file.txt", data: Data("x".utf8))

    XCTAssertThrowsError(try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)) { error in
        XCTAssertTrue(String(describing: error).contains("initial directory already exists"))
    }
}

func testWorkspaceAddModsUnpacksCachesAndRecordsManifest() throws {
    let workspace = try temporaryDirectory(named: "workspace-add-mod")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
    let mod = try makePak(named: "demo.pak", entries: [
        "classes/trucks/demo.xml": Data("<Truck/>".utf8)
    ])

    let result = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])

    XCTAssertEqual(result.addedMods.map(\.folderName), ["demo"])
    XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo").appendingPathComponent("classes/trucks/demo.xml").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo").path))
    let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
    XCTAssertEqual(manifest.mods.count, 1)
    XCTAssertEqual(manifest.mods[0].entries.count, 1)
}

func testWorkspaceAddModsRejectsDuplicateFolderName() throws {
    let workspace = try temporaryDirectory(named: "workspace-add-duplicate")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
    let first = try makePak(named: "demo.pak", entries: ["classes/trucks/a.xml": Data("<Truck/>".utf8)])
    let second = try makePak(named: "demo.pak", entries: ["classes/trucks/b.xml": Data("<Truck/>".utf8)])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first])

    XCTAssertThrowsError(try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [second]))
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspace
```

Expected: compile failure because `PakWorkspaceManager` does not exist.

- [ ] **Step 3: Implement manager init/add**

Create `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift` with:

```swift
import Foundation

public struct PakWorkspaceInitResult: Equatable {
    public let initialEntryCount: Int
}

public struct PakWorkspaceAddModsResult: Equatable {
    public let addedMods: [PakWorkspaceMod]
}

public enum PakWorkspaceManager {
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

        var staged: [(mod: PakWorkspaceMod, tempMod: URL, finalMod: URL, tempCache: URL, finalCache: URL)] = []
        for pak in modPaks {
            let folderName = folderName(forPak: pak)
            let finalMod = PakWorkspacePaths.modDirectory(root: workspace, folderName: folderName)
            if FileManager.default.fileExists(atPath: finalMod.path) {
                throw PakWorkspaceError.modDirectoryAlreadyExists(finalMod.path)
            }
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

        defer {
            for item in staged {
                try? FileManager.default.removeItem(at: item.tempMod)
                try? FileManager.default.removeItem(at: item.tempCache)
            }
        }

        manifest.mods.append(contentsOf: staged.map(\.mod))
        try commitManifestLast(workspace: workspace, manifest: manifest) {
            try FileManager.default.createDirectory(at: PakWorkspacePaths.modsDirectory(root: workspace), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: PakWorkspacePaths.sourcesDirectory(root: workspace), withIntermediateDirectories: true)
            for item in staged {
                try FileManager.default.moveItem(at: item.tempMod, to: item.finalMod)
                try FileManager.default.moveItem(at: item.tempCache, to: item.finalCache)
            }
        }
        return PakWorkspaceAddModsResult(addedMods: staged.map(\.mod))
    }
}
```

Add these private helpers to `PakWorkspaceManager`:

```swift
private static func folderName(forPak url: URL) -> String {
    let name = url.deletingPathExtension().lastPathComponent
    return name.isEmpty ? url.lastPathComponent : name
}

private static func sourceEntries(for pak: URL, folderName: String) throws -> [PakWorkspaceSourceEntry] {
    let archive = try PakReader.readArchive(at: pak)
    return try archive.entries
        .filter { !$0.name.hasSuffix("/") && !$0.name.hasSuffix("\\") }
        .map { entry in
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: archive)
            return PakWorkspaceSourceEntry(
                sourceEntryName: entry.name,
                workspacePath: "mods/\(folderName)/" + try PakModPath.fileSystemRelativePath(forArchiveName: entry.name),
                sha256: ModArchiveMapper.sha256Hex(uncompressedPayload: payload)
            )
        }
}

private static func commitManifestLast(
    workspace: URL,
    manifest: PakWorkspaceManifest,
    fileMoves: () throws -> Void
) throws {
    let manifestURL = PakWorkspacePaths.manifestURL(root: workspace)
    let tempManifest = workspace.appendingPathComponent(".snowrunner-workspace-\(UUID().uuidString).json")
    let data = try JSONEncoder.pakWorkspace.encode(manifest)
    try data.write(to: tempManifest, options: .atomic)
    try fileMoves()
    if FileManager.default.fileExists(atPath: manifestURL.path) {
        try FileManager.default.removeItem(at: manifestURL)
    }
    try FileManager.default.moveItem(at: tempManifest, to: manifestURL)
}

private static func isNonEmptyDirectory(_ url: URL) throws -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return false
    }
    return try !FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty
}

private static func replaceItem(at source: URL, with destination: URL) throws {
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: source, to: destination)
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspace
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: initialize pak workspaces"
```

---

### Task 6: Workspace Verify And Build

**Files:**
- Modify: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift`
- Create: `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceReporter.swift`
- Test: `Tests/SnowRunnerToolTests/PakWorkspaceTests.swift`

- [ ] **Step 1: Add verify/build tests**

Append to `PakWorkspaceTests`:

```swift
func testWorkspaceVerifyWritesNoBuildOutput() throws {
    let workspace = try temporaryDirectory(named: "workspace-verify")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

    let result = try PakWorkspaceManager.verify(workspace: workspace)

    XCTAssertGreaterThan(result.plan.baseEntryCount, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildReport(root: workspace).path))
}

func testWorkspaceBuildPublishesVerifiedOutputAndReport() throws {
    let workspace = try temporaryDirectory(named: "workspace-build")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

    let result = try PakWorkspaceManager.build(workspace: workspace)

    XCTAssertEqual(result.outputURL, PakWorkspacePaths.buildInitialPak(root: workspace))
    XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildReport(root: workspace).path))
    let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
    XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
    XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
}

func testWorkspaceBuildFailsWhenSourceCacheMissing() throws {
    let workspace = try temporaryDirectory(named: "workspace-missing-cache")
    _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
    let mod = try makePak(named: "demo.pak", entries: ["classes/trucks/demo.xml": Data("<Truck/>".utf8)])
    _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])
    try FileManager.default.removeItem(at: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo"))

    XCTAssertThrowsError(try PakWorkspaceManager.verify(workspace: workspace)) { error in
        XCTAssertTrue(String(describing: error).contains("cached source PAK"))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceVerify
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuild
```

Expected: compile failure because `verify`, `build`, and reporter do not exist.

- [ ] **Step 3: Implement reporter**

Create `Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceReporter.swift`:

```swift
import Foundation

public enum PakWorkspaceReporter {
    public static func stdout(result: ModMergeResult, mode: String) -> String {
        "\(mode) workspace\n" + ModMergeReporter.stdout(result: result)
    }

    public static func markdown(result: ModMergeResult) -> String {
        "# Workspace Build Report\n\n" + ModMergeReporter.markdown(result: result)
    }
}
```

- [ ] **Step 4: Implement verify/build manager methods**

Add to `PakWorkspaceManager`:

```swift
public static func verify(workspace: URL) throws -> ModMergeResult {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SnowRunnerWorkspaceVerify-\(UUID().uuidString).pak")
    defer { try? FileManager.default.removeItem(at: temp) }
    return try buildCandidate(workspace: workspace, output: temp, reportURL: nil, publish: false)
}

public static func build(workspace: URL) throws -> ModMergeResult {
    let buildDirectory = PakWorkspacePaths.buildDirectory(root: workspace)
    try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
    let tempPak = buildDirectory.appendingPathComponent(".initial-\(UUID().uuidString).pak")
    let tempReport = buildDirectory.appendingPathComponent(".workspace-build-report-\(UUID().uuidString).md")
    defer {
        try? FileManager.default.removeItem(at: tempPak)
        try? FileManager.default.removeItem(at: tempReport)
    }
    let result = try buildCandidate(workspace: workspace, output: tempPak, reportURL: tempReport, publish: true)
    try replaceItem(at: tempPak, with: PakWorkspacePaths.buildInitialPak(root: workspace))
    try replaceItem(at: tempReport, with: PakWorkspacePaths.buildReport(root: workspace))
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
```

Implement private `buildCandidate`:

```swift
let manifest = try loadManifest(workspace: workspace)
let initialDirectory = PakWorkspacePaths.initialDirectory(root: workspace)
guard FileManager.default.fileExists(atPath: initialDirectory.path) else {
    throw PakWorkspaceError.missingInitialDirectory(initialDirectory.path)
}
let baseManifest = try LoadListReader.readManifest(from: initialDirectory.appendingPathComponent(LoadListConstants.manifestEntryName))
let records = try WorkspaceInitialLoadListBuilder.records(fromInitialDirectory: initialDirectory, preservingFrom: baseManifest)
let rebuiltManifest = try LoadListBuilder.buildManifest(records: records)
let mapped = try manifest.mods.flatMap { mod -> [ModMappedEntry] in
    let modDirectory = PakWorkspacePaths.modDirectory(root: workspace, folderName: mod.folderName)
    let cache = workspace.appendingPathComponent(mod.sourceCachePath)
    guard FileManager.default.fileExists(atPath: modDirectory.path) else {
        throw PakWorkspaceError.missingModDirectory(modDirectory.path)
    }
    guard FileManager.default.fileExists(atPath: cache.path) else {
        throw PakWorkspaceError.missingSourceCache(cache.path)
    }
    return try ModArchiveMapper.mapDirectory(
        at: modDirectory,
        archiveName: mod.archiveName,
        sourceCache: cache,
        sourceEntries: mod.entries,
        workspaceRoot: workspace
    )
}
let result = try ModMerger.mergeWorkspaceInitial(
    initialDirectory: initialDirectory,
    baseManifest: rebuiltManifest,
    mappedEntries: mapped,
    outputInitialPak: output,
    reportURL: reportURL,
    verifyOutput: true
)
if let reportURL {
    try PakWorkspaceReporter.markdown(result: result).write(to: reportURL, atomically: true, encoding: .utf8)
}
return result
```

- [ ] **Step 5: Run tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceVerify
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter PakWorkspaceTests/testWorkspaceBuild
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceReporter.swift Tests/SnowRunnerToolTests/PakWorkspaceTests.swift
git commit -m "feat: verify and build pak workspaces"
```

---

### Task 7: Top-Level Workspace CLI

**Files:**
- Modify: `Sources/SnowRunnerTool/CLI.swift`
- Test: `Tests/SnowRunnerToolTests/CLITests.swift`

- [ ] **Step 1: Add CLI tests**

Append to `CLITests`:

```swift
func testWorkspaceCLIInitAddVerifyAndBuild() throws {
    let workspace = try temporaryDirectory(named: "cli-workspace")
    let mod = try makePak(named: "demo.pak", entries: [
        "classes/trucks/demo.xml": Data("<Truck/>".utf8)
    ])

    let initResult = CLI.run(arguments: ["workspace", workspace.path, "--init", TestFixtures.initialPak.path])
    XCTAssertEqual(initResult.exitCode, 0, initResult.stderr)
    XCTAssertTrue(initResult.stdout.contains("initialized workspace"))

    let addResult = CLI.run(arguments: ["workspace", workspace.path, "--add-mods", mod.path])
    XCTAssertEqual(addResult.exitCode, 0, addResult.stderr)
    XCTAssertTrue(addResult.stdout.contains("added 1 mod"))

    let verifyResult = CLI.run(arguments: ["workspace", workspace.path, "--verify"])
    XCTAssertEqual(verifyResult.exitCode, 0, verifyResult.stderr)
    XCTAssertTrue(verifyResult.stdout.contains("verified workspace"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))

    let buildResult = CLI.run(arguments: ["workspace", workspace.path, "--build"])
    XCTAssertEqual(buildResult.exitCode, 0, buildResult.stderr)
    XCTAssertTrue(buildResult.stdout.contains("built workspace"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))
}

func testWorkspaceCLIRejectsMissingArguments() {
    let result = CLI.run(arguments: ["workspace"])

    XCTAssertEqual(result.exitCode, 2)
    XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool workspace"))
}
```

- [ ] **Step 2: Run CLI tests to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testWorkspaceCLI
```

Expected: failure because `workspace` is an unknown top-level command.

- [ ] **Step 3: Add workspace command parser**

Modify `CLI.run(arguments:)` before the `guard arguments.first == "pak"`:

```swift
if arguments.first == "workspace" {
    return runWorkspaceCommand(Array(arguments.dropFirst()))
}
```

Update `usage()` to include:

```text
          workspace <workspace> --init <initial.pak>
          workspace <workspace> --add-mods <mod.pak> [<mod.pak> ...]
          workspace <workspace> --verify
          workspace <workspace> --build
```

Add:

```swift
private static func runWorkspaceCommand(_ arguments: [String]) -> CLIResult {
    guard arguments.count >= 2 else {
        return CLIResult(exitCode: 2, stdout: "", stderr: workspaceUsage())
    }
    let workspace = URL(fileURLWithPath: arguments[0], isDirectory: true)
    let flag = arguments[1]
    do {
        switch flag {
        case "--init":
            guard arguments.count == 3 else {
                return CLIResult(exitCode: 2, stdout: "", stderr: workspaceUsage())
            }
            let result = try PakWorkspaceManager.initialize(
                workspace: workspace,
                initialPak: URL(fileURLWithPath: arguments[2])
            )
            return CLIResult(exitCode: 0, stdout: "initialized workspace with \(result.initialEntryCount) initial entries\n", stderr: "")
        case "--add-mods":
            let modPaths = Array(arguments.dropFirst(2))
            guard !modPaths.isEmpty else {
                return CLIResult(exitCode: 2, stdout: "", stderr: workspaceUsage())
            }
            let result = try PakWorkspaceManager.addMods(
                workspace: workspace,
                modPaks: modPaths.map { URL(fileURLWithPath: $0) }
            )
            return CLIResult(exitCode: 0, stdout: "added \(result.addedMods.count) mod(s)\n", stderr: "")
        case "--verify":
            guard arguments.count == 2 else {
                return CLIResult(exitCode: 2, stdout: "", stderr: workspaceUsage())
            }
            let result = try PakWorkspaceManager.verify(workspace: workspace)
            return CLIResult(exitCode: 0, stdout: PakWorkspaceReporter.stdout(result: result, mode: "verified"), stderr: "")
        case "--build":
            guard arguments.count == 2 else {
                return CLIResult(exitCode: 2, stdout: "", stderr: workspaceUsage())
            }
            let result = try PakWorkspaceManager.build(workspace: workspace)
            return CLIResult(exitCode: 0, stdout: PakWorkspaceReporter.stdout(result: result, mode: "built"), stderr: "")
        default:
            return CLIResult(exitCode: 2, stdout: "", stderr: workspaceUsage())
        }
    } catch {
        return CLIResult(exitCode: 1, stdout: "", stderr: "\(error)\n")
    }
}

private static func workspaceUsage() -> String {
    """
    Usage: snowrunner-tool workspace <workspace> --init <initial.pak>
           snowrunner-tool workspace <workspace> --add-mods <mod.pak> [<mod.pak> ...]
           snowrunner-tool workspace <workspace> --verify
           snowrunner-tool workspace <workspace> --build
    """
}
```

- [ ] **Step 4: Run CLI tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test --filter CLITests/testWorkspaceCLI
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnowRunnerTool/CLI.swift Tests/SnowRunnerToolTests/CLITests.swift
git commit -m "feat: expose workspace cli"
```

---

### Task 8: README And Full Verification

**Files:**
- Modify: `README.md`
- Test: full Swift test suite

- [ ] **Step 1: Update README command section**

Add after the existing merge-mod examples:

```markdown
Create an editable workspace:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace /tmp/srt-workspace --init /path/to/initial.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace /tmp/srt-workspace --add-mods /path/to/mod1.pak /path/to/mod2.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace /tmp/srt-workspace --verify
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace /tmp/srt-workspace --build
```

The workspace keeps editable source folders under `initial/` and `mods/`.
Generated output is written only after verification succeeds:

```text
/tmp/srt-workspace/build/initial.pak
/tmp/srt-workspace/build/workspace-build-report.md
```

The original source `initial.pak` is never overwritten.
```

- [ ] **Step 2: Run full test suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
```

Expected: all tests pass.

- [ ] **Step 3: Run CLI smoke workflow**

Run:

```bash
WORKSPACE_DIR=/private/tmp/srt-workspace-smoke
rm -rf "$WORKSPACE_DIR"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace "$WORKSPACE_DIR" --init fixtures/initial.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace "$WORKSPACE_DIR" --add-mods fixtures/loadstar_1700_jbe.pak fixtures/loadstar_1700_jbe_pc.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace "$WORKSPACE_DIR" --verify
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace "$WORKSPACE_DIR" --build
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-basic "$WORKSPACE_DIR/build/initial.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-snowpak-layout "$WORKSPACE_DIR/build/initial.pak"
```

Expected:

```text
initialized workspace ...
added 2 mod(s)
verified workspace
built workspace
PASS verify-basic
PASS verify-snowpak-layout
```

If the Loadstar fixture pair is absent in this checkout, use synthetic PAK fixtures through tests and record the smoke command as skipped due missing fixture paths.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document workspace workflow"
```

---

### Task 9: Final Review And Integration

**Files:**
- All touched files

- [ ] **Step 1: Check git status**

Run:

```bash
git status --short
```

Expected: clean worktree after Task 8 commit.

- [ ] **Step 2: Run final verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
```

Expected: all tests pass.

- [ ] **Step 3: Review implementation against spec**

Open:

```bash
sed -n '1,520p' docs/superpowers/specs/2026-06-12-pak-workspace-cli-design.md
```

Checklist:

- top-level `workspace` command exists,
- `--init` validates with `verify-basic` only,
- `--add-mods` caches source PAKs and records uncompressed payload hashes,
- mutations use manifest-last commits,
- `--verify` writes only temporary output,
- `--build` verifies temporary output before replacing `build/initial.pak`,
- directory-backed unchanged PCT files preserve source compressed payload metadata,
- edited PCT files recompress and regenerate headers,
- `WorkspaceInitialLoadListBuilder` preserves non-`initial.pak` records,
- no sidecar texture PAK is produced.

- [ ] **Step 4: Commit review corrections only when files changed**

If the review in Step 3 required corrections, inspect the changed files:

```bash
git status --short
git diff --stat
git add Sources/SnowRunnerTool Tests/SnowRunnerToolTests README.md
git commit -m "fix: align workspace implementation with spec"
```

If no corrections were needed, do not create an empty commit.
