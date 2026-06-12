# SnowRunnerTools PAK Workspace CLI Design

## Purpose

Add a disk-backed workspace workflow for editing and merging SnowRunner PAK
contents before producing a final `initial.pak`.

The existing `pak merge-mod` command is a one-shot archive workflow: it reads a
base `initial.pak`, reads mod PAKs, applies merge rules, and writes a candidate.
The new workspace workflow keeps the same merge semantics but makes the inputs
editable on disk.

The core need is:

- unpack the base `initial.pak` into an editable workspace,
- unpack one or more mod PAKs into editable per-mod folders,
- verify that the current workspace can build,
- build one final self-contained `initial.pak` from the current workspace.

## V1 Scope

In scope:

- A new top-level `workspace` CLI command.
- Source-preserving workspace layout:
  - `initial/` stores unpacked runtime `initial.pak` contents.
  - `mods/<name>/` stores unpacked mod package contents.
  - `.snowrunner/sources/` stores cached source PAKs for metadata reuse.
  - `build/` stores generated outputs.
- Workspace metadata in `.snowrunner-workspace.json`.
- Automatic mod folder naming from each PAK basename without `.pak`.
- Rejection of duplicate mod folder names.
- `--verify` as a real temporary build plus verifier run.
- `--build` producing one generated `build/initial.pak`.
- `--build` using the same texture behavior as
  `pak merge-mod --experimental-inline-textures`.
- Manual edits, additions, and deletions in `initial/` reflected in the
  generated `pak.load_list` when the path has a known loader rule.
- Reuse of cached source PAK texture ZIP metadata for unchanged mod texture
  files.
- Mod-over-initial overwrites allowed by default.
- Mod-over-mod mapped path conflicts rejected when bytes differ.
- Generated build report at `build/workspace-build-report.md`.

Out of scope for v1:

- Removing mods from an existing workspace.
- Replacing an existing `initial/` folder.
- Replacing an existing mod folder.
- Building sidecar texture PAKs.
- Writing directly over the original source `initial.pak`.
- Preserving or interpreting manual edits under `build/`.
- Supporting unsupported mod package shapes beyond the current merge mapper.

## CLI Shape

Create or initialize the workspace from a base initial PAK:

```bash
snowrunner-tool workspace path/to/workspace --init /path/to/initial.pak
```

Add mod PAKs:

```bash
snowrunner-tool workspace path/to/workspace --add-mods /path/to/mod1.pak /path/to/mod2.pak
```

Verify the current workspace:

```bash
snowrunner-tool workspace path/to/workspace --verify
```

Build the current workspace:

```bash
snowrunner-tool workspace path/to/workspace --build
```

`--build` writes:

```text
workspace/build/initial.pak
workspace/build/workspace-build-report.md
```

No `--output` argument is required in v1. The workspace owns its generated build
output.

## Workspace Layout

Example layout:

```text
workspace/
  .snowrunner-workspace.json
  initial/
    pak.load_list
    initial.cache_block
    [media]/
    [strings]/
    [ssl_cache]/
  .snowrunner/
    sources/
      loadstar_1700_jbe.pak
      loadstar_1700_jbe_pc.pak
  mods/
    loadstar_1700_jbe/
      classes/
      prebuild/
      ui/
      texts/
    loadstar_1700_jbe_pc/
      prebuild/
        textures/
  build/
    initial.pak
    workspace-build-report.md
```

`initial/` uses the existing `pak unpack` filesystem mapping for runtime PAK
paths.

Each `mods/<name>/` folder uses the existing `pak unpack-mod` filesystem mapping
for mod package paths.

`.snowrunner/sources/` is tool-owned. It stores copies of the original mod PAKs
added to the workspace so unchanged texture entries can reuse the same
compressed payloads and ZIP extra fields that `pak merge-mod` preserves today.

`build/` is generated. The tool may overwrite `build/initial.pak` and
`build/workspace-build-report.md` on each successful build. The build pipeline
must not read source inputs from `build/`.

## Workspace Manifest

Store metadata in:

```text
workspace/.snowrunner-workspace.json
```

V1 shape:

```json
{
  "version": 1,
  "initialSourcePath": "/path/to/initial.pak",
  "mods": [
    {
      "sourcePath": "/path/to/mod1.pak",
      "folderName": "mod1",
      "archiveName": "mod1.pak",
      "sourceCachePath": ".snowrunner/sources/mod1.pak",
      "entries": [
        {
          "sourceEntryName": "prebuild/textures/pct/foo.pct",
          "workspacePath": "mods/mod1/prebuild/textures/pct/foo.pct",
          "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        }
      ]
    }
  ],
  "policy": {
    "textureMode": "inlineInitial",
    "allowInitialOverwrite": true
  }
}
```

The manifest records provenance and stable folder-to-archive names. It does not
make the original `initial.pak` a build target.

The `archiveName` is important because current mod mapping uses archive
identity for diagnostics and role validation. Directory-backed mod mapping
should behave as if the folder came from that archive name.

The cached source PAK and per-entry hashes are used only to decide whether a
workspace file is unchanged from the source archive. If unchanged, directory
mapping may reuse preserved compressed payloads and ZIP metadata from the cached
source PAK. If edited, the workspace file bytes win and the entry is recompressed
normally.

## Workspace Transaction Model

Workspace mutations must be all-or-nothing.

`--init` transaction rules:

- Unpack the source PAK into a temporary sibling of `initial/`.
- Write the new manifest to a temporary file.
- Commit by moving the temporary initial folder into place and atomically
  replacing `.snowrunner-workspace.json`.
- If any step fails before commit, remove temporary files and leave the existing
  workspace unchanged.

`--add-mods` transaction rules:

- Validate every input PAK and derived folder name before committing any one of
  them.
- Unpack each mod into a temporary folder.
- Copy each source PAK into a temporary source-cache location.
- Write the updated manifest to a temporary file.
- Commit all new mod folders, source-cache files, and the manifest together.
- If any mod in the invocation fails, remove temporary files and leave the
  workspace unchanged.

The implementation should prefer same-directory temporary paths so final moves
can use filesystem atomic rename semantics where available.

## Command Semantics

### `--init`

Rules:

- Create the workspace directory if needed.
- Create or update `.snowrunner-workspace.json`.
- Unpack the source PAK into `initial/` using `PakUnpacker`.
- Record `initialSourcePath`.
- Reject an existing non-empty `initial/`.
- Validate the source PAK with `verify-basic`.
- Do not require `verify-snowpak-layout`; original game PAK layout may differ
  from normalized writer output.

The command should not remove or mutate existing mod folders.

### `--add-mods`

Rules:

- Require an existing workspace manifest.
- Create `mods/` if needed.
- For each PAK:
  - derive the folder name from the PAK basename without `.pak`,
  - reject duplicate folder names already in the workspace or inside the same
    command invocation,
  - unpack with `PakModUnpacker` into `mods/<folderName>/`,
  - copy the original PAK into `.snowrunner/sources/<folderName>.pak`,
  - record source-entry hashes in the manifest,
  - append manifest metadata.
- Preserve mod package paths on disk.
- Apply all mod additions atomically. If any PAK in a multi-mod invocation
  fails validation or unpacking, do not commit any new mod folder, source-cache
  file, or manifest entry from that invocation.

Example:

```text
/path/to/loadstar_1700_jbe.pak
  -> workspace/mods/loadstar_1700_jbe/
```

### `--verify`

`--verify` is a temporary build and verifier run.

Rules:

- Load and validate the workspace manifest.
- Validate `initial/` exists.
- Scan `initial/` as runtime PAK sources.
- Scan each `mods/<name>/` as mod package sources.
- Map mod directory entries through the same rules used by `merge-mod`.
- Rebuild `initial.pak`-sourced load-list records from the current `initial/`
  directory and preserve non-`initial.pak` records from the unpacked
  `initial/pak.load_list`.
- Use inline texture mode.
- Allow mod-over-initial overwrites by default.
- Reject conflicting mod-over-mod mapped paths when bytes differ.
- Build the candidate load-list in memory.
- Write a temporary candidate PAK outside `build/`.
- Run `verify-basic` and `verify-snowpak-layout` on the temporary candidate.
- Delete the temporary candidate after verification.
- Print a merge summary.
- Do not write or modify `workspace/build/`.

This command answers the real question: whether the current editable workspace
can produce the final `initial.pak`.

### `--build`

`--build` runs the same planner as `--verify`, then writes generated outputs.

Rules:

- Create `build/` if missing.
- Write `build/initial.pak`.
- Write `build/workspace-build-report.md`.
- Overwrite those two generated files on each successful build.
- Do not overwrite the original `initialSourcePath`.
- Verify the generated PAK with:
  - `verify-basic`
  - `verify-snowpak-layout`

If verification fails, return failure and report the verifier issues.

## Merge Semantics

Workspace build should use the same semantics as:

```bash
pak merge-mod --experimental-inline-textures --allow-overwrite
```

Differences from `merge-mod`:

- inputs are editable directories, not only PAK archives,
- output path is fixed to `workspace/build/initial.pak`,
- mod-over-initial overwrites are allowed by default,
- errors should point to workspace folder paths where possible.

Initial edit policy:

- The current `initial/` directory is the base source of truth.
- Existing files may be edited in place.
- Files may be added or deleted.
- Records in `initial/pak.load_list` whose `sourcePak` is not `initial.pak` are
  preserved. This keeps references to shared archives such as `shared.pak` and
  `shared_sound.pak`.
- Records whose `sourcePak` is `initial.pak` are rebuilt from the current
  `initial/` directory by `WorkspaceInitialLoadListBuilder`.
- Added `initial/` files that need load-list records must match a known loader
  rule, otherwise verify/build fails instead of producing a candidate with stale
  or missing metadata.
- Entries that intentionally do not appear in `pak.load_list`, such as
  `pak.load_list`, `initial.cache_block`, `[strings]\*.str`, and
  `[ssl_cache]\initial_pak`, remain allowed without records.

Workspace initial load-list builder contract:

- Own the policy for rebuilding `sourcePak == "initial.pak"` records from
  `initial/`.
- Preserve non-`initial.pak` records from the unpacked `initial/pak.load_list`
  unchanged.
- Classify files physically present in the generated `initial.pak` with
  `sourcePak == "initial.pak"`.
- Classify added `[meshes]\...` files as `mesh_loader / initial.pak / MESH load`
  because they are packed into the generated `initial.pak`, not into
  `shared.pak`.
- Reject paths that look load-listed but have no known workspace loader rule.

Texture policy:

- Texture mod entries are written into the generated `initial.pak`.
- Generated PCT `.pct_header` entries are also written into `initial.pak`.
- Mod-managed PCT load-list records source textures from `initial.pak`.
- No sidecar texture PAK is produced in v1.
- For unchanged mod PCT entries, reuse compressed payloads and supported ZIP
  metadata from the cached source PAK when available.
- For edited mod PCT entries, read the workspace file bytes, regenerate the
  `.pct_header`, recompress normally, and report that the texture was
  recompressed.

String policy:

- Keep existing `ModStringTable` merge behavior.
- Multiple mod string files targeting the same `[strings]\*.str` path merge in
  deterministic mod order.

Collision policy:

- A mod entry may replace an existing initial entry.
- Two mods may map to the same target only when decompressed bytes are
  identical.
- Two mods mapping to the same target with different bytes is a build error.

## Architecture

Add a new workspace layer and make directory-backed mod sources first-class.
Do not duplicate merge rules.

```text
PakWorkspaceManager
  owns workspace manifest, folder layout, init/add/verify/build orchestration
  performs all-or-nothing workspace mutations

ModArchiveMapper
  existing: mapArchive(at:)
  new: mapDirectory(at:archiveName:sourceCache:)
  both return [ModMappedEntry]

WorkspaceInitialLoadListBuilder
  rebuilds initial.pak-sourced records from initial/
  preserves non-initial records from initial/pak.load_list

ModMerger
  existing PAK-based CLI entry point remains
  new shared core accepts:
    - base initial sources from archive or directory
    - mapped mod entries from archive or directory
    - texture mode set to inline initial.pak for workspace builds
```

Recommended new files:

```text
Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManifest.swift
Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceManager.swift
Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceError.swift
Sources/SnowRunnerTool/PakWorkspace/PakWorkspaceReporter.swift
Sources/SnowRunnerTool/PakWorkspace/WorkspaceInitialLoadListBuilder.swift
```

Modify:

```text
Sources/SnowRunnerTool/CLI.swift
Sources/SnowRunnerTool/ModMerge/ModArchiveMapper.swift
Sources/SnowRunnerTool/ModMerge/ModMerger.swift
Sources/SnowRunnerTool/ModMerge/ModMergePlan.swift
Sources/SnowRunnerTool/ModMerge/ModMergeReporter.swift
```

The key refactor is to extract the current archive-only merge pipeline so both
`pak merge-mod` and `workspace --build` call one shared core after their
inputs have been converted to common sources.

## Error Handling

Blocking errors:

- Workspace manifest missing for commands that require an existing workspace.
- Workspace manifest version unsupported.
- `initial/` missing for verify/build.
- Existing non-empty `initial/` during `--init`.
- Existing `mods/<name>/` during `--add-mods`.
- Missing cached source PAK for a manifest mod entry.
- Duplicate mod folder names.
- Invalid initial folder paths.
- Invalid mod package folder paths.
- Invalid PCT payloads.
- Conflicting mapped duplicates with different bytes.
- Generated PAK verification failure.

Diagnostics should name the workspace path where the bad input lives. For
example:

```text
mods/loadstar_1700_jbe/classes/trucks/demo.xml
```

is more useful than only:

```text
classes/trucks/demo.xml
```

## Testing

Add focused tests for the new workspace layer:

- `--init` creates manifest and unpacks `initial/`.
- `--init` rejects an existing non-empty `initial/`.
- `--init` accepts original fixture layout that passes `verify-basic` even when
  `verify-snowpak-layout` would fail.
- `--add-mods` unpacks one mod into `mods/<basename>/`.
- `--add-mods` copies the source PAK into `.snowrunner/sources/`.
- `--add-mods` rejects duplicate mod folder names.
- Multi-mod `--add-mods` is all-or-nothing when one mod fails.
- `--verify` writes a temporary candidate, verifies it, deletes it, and writes
  nothing under `build/`.
- `--build` writes `build/initial.pak`.
- `--build` writes `build/workspace-build-report.md`.
- `--build` with no mods repacks edited `initial/`.
- Unchanged directory-backed PCT entries reuse cached source compressed payloads
  and supported ZIP metadata.
- Edited directory-backed PCT entries recompress and regenerate headers.
- Added `[meshes]\...` files under `initial/` get `initial.pak` source records.
- Mod-over-initial overwrite succeeds by default.
- Mod-over-mod conflict fails.
- Invalid mod directory errors include workspace folder context.

Reuse existing fixtures and helper functions where possible. Add directory-based
mapper tests beside existing `PakModArchiveTests` or create a focused
`PakWorkspaceTests` file.

## Documentation

Update README command examples after implementation:

```bash
snowrunner-tool workspace /tmp/srt-workspace --init /path/to/initial.pak
snowrunner-tool workspace /tmp/srt-workspace --add-mods /path/to/mod1.pak /path/to/mod2.pak
snowrunner-tool workspace /tmp/srt-workspace --verify
snowrunner-tool workspace /tmp/srt-workspace --build
```

Document that:

- `initial/` and `mods/` are editable source folders,
- `build/` is generated,
- `build/initial.pak` is the final candidate,
- the command never overwrites the original source `initial.pak`.
