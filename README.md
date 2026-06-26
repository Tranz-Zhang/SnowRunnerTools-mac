# SnowRunnerTools-mac

macOS Swift command-line tools for inspecting, unpacking, repacking, verifying,
and rebuilding SnowRunner PAK assets.

The current implementation can:

- Read and verify SnowRunner-style PAK archives.
- Unpack and repack `initial.pak` with SnowPakTool-compatible layout.
- Unpack and repack merge-compatible PC mod PAKs.
- Unpack and rebuild `initial.cache_block`.
- Inspect and rebuild `pak.load_list`.
- Merge supported PC mod PAKs into an `initial.pak` candidate.

## Requirements

- macOS with Xcode command line tools.
- Swift Package Manager.
- Local SnowRunner PAK files for commands that rebuild load lists or merge mods.

## Build And Test

Run the full automated test suite:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift test
```

Run the CLI:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool
```

## Core Commands

Inspect and verify a PAK:

```bash
TEST_FIXTURES=Tests/SnowRunnerCoreTests/Fixtures
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak inspect "$TEST_FIXTURES/initial.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-basic "$TEST_FIXTURES/initial.pak"
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-snowpak-layout "$TEST_FIXTURES/initial.repacked.pak"
```

Unpack and repack `initial.pak`:

```bash
TEST_FIXTURES=Tests/SnowRunnerCoreTests/Fixtures
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak unpack "$TEST_FIXTURES/initial.pak" /tmp/snowrunner-initial
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak pack /tmp/snowrunner-initial /tmp/initial.repacked.pak
```

Unpack and repack a supported PC mod PAK:

```bash
TEST_FIXTURES=Tests/SnowRunnerCoreTests/Fixtures
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak unpack-mod "$TEST_FIXTURES/loadstar_1700_jbe.pak" /tmp/loadstar-mod
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak pack-mod /tmp/loadstar-mod /tmp/loadstar_1700_jbe.repacked.pak
```

`pak pack-mod` writes forward-slash mod paths such as `classes/...` and
`prebuild/meshes/...`, does not require `pak.load_list`, and validates that the
output can be consumed by `pak merge-mod`.

Work with `initial.cache_block`:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block unpack /tmp/snowrunner-initial/initial.cache_block /tmp/snowrunner-cache
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block pack /tmp/snowrunner-cache /tmp/initial.cache_block
```

Inspect and create `pak.load_list`:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list inspect /tmp/snowrunner-initial/pak.load_list
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list create-initial /tmp/pak.load_list /path/to/initial.pak /path/to/shared.pak /path/to/shared_sound.pak
```

Merge a supported PC mod package into an `initial.pak` candidate:

```bash
TEST_FIXTURES=Tests/SnowRunnerCoreTests/Fixtures
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache \
swift run snowrunner-tool pak merge-mod \
  --allow-overwrite \
  --report /tmp/loadstar-merge-report.md \
  --input-initial /path/to/initial.pak \
  --output-initial /tmp/initial.loadstar-jbe.pak \
  --experimental-inline-textures \
  --mods "$TEST_FIXTURES/loadstar_1700_jbe.pak" "$TEST_FIXTURES/loadstar_1700_jbe_pc.pak"
```

Use `--dry-run` first to print the mapping, collision, and load-list summary
without writing outputs. The command refuses in-place writes; back up the
game's original PAKs before manually copying verified candidates into the game
directory.

The normal build path now writes mod textures into the generated `initial.pak`.
Runtime validation showed this works, and it keeps installation to one generated
PAK while leaving the game's original `shared_textures.pak` and
`shared_textures_base.pak` untouched.

Create an editable workspace:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace /tmp/srt-workspace --init /path/to/initial.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace /tmp/srt-workspace --add-mods /path/to/mod1.pak /path/to/mod2.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace /tmp/srt-workspace --verify
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool workspace /tmp/srt-workspace --build
```

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

The workspace keeps editable source folders under `initial/` and `mods/`.
Generated output is written only after verification succeeds:

```text
/tmp/srt-workspace/build/initial.pak
/tmp/srt-workspace/build/workspace-build-report.md
```

The original source `initial.pak` is never overwritten.

The separate texture PAK experiment also remains available for comparison:

```bash
--experimental-output-mod-textures /tmp/mod_textures.pak
```

Use that mode only when testing texture bytes outside `initial.pak`; it writes a
second generated PAK and rewrites mod-managed PCT load-list records to source
textures from that PAK.

First-version mod merge support is intentionally narrow:

```text
<mod>.pak: classes/...           -> [media]\classes\...
<mod>.pak: prebuild/meshes/...   -> [meshes]\...
<mod>.pak: ui/textures/...       -> initial.pak:[textures]\...
<mod>.pak: texts/*.str           -> [strings]\*.str
texture PAK by content:
  prebuild/textures/pct/foo.pct
    -> initial.pak:[textures]\pct\foo.pct
    -> initial.pak:[textures]\pct\foo.pct_header
```

PCT texture entries are indexed in `pak.load_list` as
`pct_mr2_header` + `pct_faces` records for the generated `.pct_header`.

## Fixtures

`Tests/SnowRunnerCoreTests/Fixtures/` is for automated-test fixtures that
belong in the repository.

Large runtime PAKs such as `shared.pak` and `shared_sound.pak` should not be
committed. Current runtime versions may be supersets of the historical PAKs that
created the test `initial.pak` fixture's embedded `pak.load_list`; tests
therefore use containment checks instead of exact record-count parity for those
inputs.
