# SnowRunnerTools-mac

macOS Swift command-line tools for inspecting, unpacking, repacking, verifying,
and rebuilding SnowRunner PAK assets.

The current implementation can:

- Read and verify SnowRunner-style PAK archives.
- Unpack and repack `initial.pak` with SnowPakTool-compatible layout.
- Unpack and rebuild `initial.cache_block`.
- Inspect and rebuild `pak.load_list`.
- Generate a runtime-validation `initial.pak` with a rebuilt load list.
- Merge supported PC mod PAKs into an `initial.pak` candidate.

## Requirements

- macOS with Xcode command line tools.
- Swift Package Manager.
- Local SnowRunner PAK files for runtime validation.

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
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak inspect fixtures/initial.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-basic fixtures/initial.pak
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-snowpak-layout fixtures/initial.repacked.pak
```

Unpack and repack a PAK:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak unpack fixtures/initial.pak /tmp/snowrunner-initial
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak pack /tmp/snowrunner-initial /tmp/initial.repacked.pak
```

Work with `initial.cache_block`:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block unpack /tmp/snowrunner-initial/initial.cache_block /tmp/snowrunner-cache
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool cache-block pack /tmp/snowrunner-cache /tmp/initial.cache_block
```

Inspect and create `pak.load_list`:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list inspect /tmp/snowrunner-initial/pak.load_list
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list create-initial /tmp/pak.load_list validation/input/initial.pak validation/input/shared.pak validation/input/shared_sound.pak
```

Merge a supported PC mod package into an `initial.pak` candidate:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache \
swift run snowrunner-tool pak merge-mod \
  --allow-overwrite \
  --report validation/output/loadstar-merge-report.md \
  validation/input/initial.pak \
  validation/output/initial.loadstar-jbe.pak \
  fixtures/loadstar_1700_jbe.pak \
  fixtures/pc.pak
```

Use `--dry-run` first to print the mapping, collision, and load-list summary
without writing an output PAK. The command refuses in-place writes; back up the
game's original `initial.pak` before manually copying a verified candidate into
the game directory.

First-version mod merge support is intentionally narrow:

```text
<mod>.pak: classes/...           -> [media]\classes\...
<mod>.pak: prebuild/meshes/...   -> [meshes]\...
<mod>.pak: ui/textures/...       -> [textures]\...
<mod>.pak: texts/*.str           -> [strings]\*.str
pc.pak:    prebuild/textures/... -> [textures]\...
```

## Runtime Validation

`validation/` is the local workspace for game-runtime validation. It is ignored
by git because it contains large game files and generated output.

Expected input layout:

```text
validation/input/initial.pak
validation/input/shared.pak
validation/input/shared_sound.pak
```

Generate a rebuilt runtime candidate:

```bash
scripts/phase4-runtime-validation.sh
```

Generate a Loadstar JBE mod-merge candidate:

```bash
scripts/mod-merge-loadstar-validation.sh
```

The script writes:

```text
validation/output/initial.pak
validation/output/created.load_list
validation/output/inspect.txt
validation/output/initial.loadstar-jbe.pak
validation/output/loadstar-merge-report.md
```

`validation/output/initial.pak` is the candidate to copy into the game for
manual launch validation. Back up the game's original `initial.pak` before
replacing it.

The runtime validation script intentionally does not use `--mixed-cache-block`.
It isolates load-list validation by preserving the original loose `[strings]`
entries in the outer PAK while rebuilding only `pak.load_list`.

## Fixtures

`fixtures/` is for automated-test fixtures that belong in the repository.
`validation/` is for local runtime PAKs and generated candidates.

Large runtime PAKs such as `shared.pak` and `shared_sound.pak` should not be
committed. Current runtime versions may be supersets of the historical PAKs that
created `fixtures/initial.pak`'s embedded `pak.load_list`; tests therefore use
containment checks instead of exact record-count parity for those inputs.

## Phase 4 Status

Phase 4 load-list rebuilding is complete.

- Full test suite passed: `85 tests, 0 failures`.
- Runtime validation produced `validation/output/initial.pak`.
- `verify-basic` and `verify-snowpak-layout` passed for the rebuilt output.
- Manual game launch succeeded with the rebuilt output PAK.
