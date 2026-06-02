# SnowRunner Mod Merge Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Keep checkbox status current. Do not skip the discovery gates; the fragile part is source-pak/load-list semantics, not writing ZIP bytes.

## Goal

Merge SnowRunner mod archives, such as:

```text
fixtures/loadstar_1700_jbe_pc.1/loadstar_1700_jbe.pak
fixtures/loadstar_1700_jbe_pc.1/pc.pak
```

into a base-game `initial.pak` namespace, rebuild `pak.load_list`, repack a SnowPakTool-compatible `initial.pak`, and produce a candidate that can be manually validated in-game.

The essence of the problem:

- Mod PAKs use mod-package paths (`classes/...`, `prebuild/...`, `ui/...`).
- Base `initial.pak` uses runtime namespaces (`[media]\...`, `[meshes]\...`, `[textures]\...`, `[ui]\...`).
- The outer PAK writer can already add bytes.
- The missing product feature is a controlled namespace merge plus correct load-list metadata.

## Non-Goals

- No generic arbitrary ZIP merge command.
- No blind mutation of `pak.load_list` bytes.
- No guessing unknown loader types.
- No support for every mod package shape in the first implementation.
- No automatic game-file replacement. The command writes a candidate output only.
- No destructive overwrite of user files without an explicit output path.
- No byte-for-byte equivalence with the original `initial.pak`; merged content changes the archive.

## Initial Supported Shape

Support the two-archive PC mod shape represented by the Loadstar JBE fixture:

```text
<mod>.pak
  classes/...
  prebuild/meshes/...
  ui/textures/...

pc.pak
  prebuild/textures/...
```

Namespace mapping:

```text
classes/<path>             -> [media]\classes\<path>
prebuild/meshes/<path>     -> [meshes]\<path>
prebuild/textures/<path>   -> [textures]\<path>
ui/textures/<path>         -> [ui]\textures\<path>
```

For the fixture inspected on 2026-06-02:

```text
loadstar_1700_jbe.pak:
  classes:          87 entries
  prebuild/meshes:  19 entries
  ui/textures:       3 entries

pc.pak:
  prebuild/textures: 42 entries

mapped total:       151 entries
base-name collisions after mapping: 8
```

Known collisions:

```text
[media]\classes\customization_presets\customization_preset.xml
[media]\classes\trucks\international_loadstar_1700.xml
[media]\classes\wheels\wheels_heavy_double2.xml
[media]\classes\wheels\wheels_medium_ank_mk38.xml
[media]\classes\wheels\wheels_medium_double.xml
[media]\classes\wheels\wheels_scout_yar_87.xml
[media]\classes\wheels\wheels_scout_yar_871.xml
[media]\classes\wheels\wheels_superheavy_single.xml
```

These collisions are expected for this fixture, but they must still require an explicit overwrite decision. Without `--allow-overwrite`, the command fails before writing. With `--allow-overwrite`, the command replaces those base entries and reports the replacement list.

## Target CLI

Add one command:

```text
snowrunner-tool pak merge-mod [options] <base-initial.pak> <output-initial.pak> <mod.pak> [<mod.pak> ...]
```

Options:

```text
--shared <shared.pak>              Required for rebuilding base shared records.
--shared-sound <shared_sound.pak>  Required for rebuilding sound records.
--allow-overwrite                  Allow mapped mod entries to replace existing base entries.
--dry-run                          Print mapping/collision/load-list summary without writing output.
--report <path>                    Write a merge report as UTF-8 Markdown.
```

Recommended first runtime command:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache \
swift run snowrunner-tool pak merge-mod \
  --shared validation/input/shared.pak \
  --shared-sound validation/input/shared_sound.pak \
  --allow-overwrite \
  --report validation/output/loadstar-merge-report.md \
  validation/input/initial.pak \
  validation/output/initial.loadstar-jbe.pak \
  fixtures/loadstar_1700_jbe_pc.1/loadstar_1700_jbe.pak \
  fixtures/loadstar_1700_jbe_pc.1/pc.pak
```

## Design

Build a merge pipeline that never relies on temporary extraction as the source of truth:

```text
base initial.pak
  -> read base archive
  -> expand base entries into PakFileSource payloads
  -> read mod archives
  -> map mod entry names into runtime namespaces
  -> validate duplicates/collisions
  -> build merged source set
  -> rebuild pak.load_list from merged entries + shared.pak + shared_sound.pak
  -> write output initial.pak with existing PakWriter layout policy
  -> verify-basic + verify-snowpak-layout
```

The writer may use temporary files internally because `PakWriter` currently accepts file URLs. The public model should be archive-entry based so later commands can avoid unnecessary disk extraction.

The output path must be distinct from every input PAK path. Refuse in-place writes; users should explicitly copy a verified candidate into the game install during manual validation.

## Merge Semantics

The merge must be deterministic and explain every replacement:

- Base `initial.pak` entries are kept unless a mapped mod entry has the same internal name.
- A mapped mod entry replaces a base entry only when `--allow-overwrite` is present.
- If two mod archives map to the same internal name:
  - keep one when decompressed bytes are identical, and report it as a duplicate identical entry
  - fail when decompressed bytes differ
- The generated `pak.load_list` always replaces the base `pak.load_list`.
- The base `initial.cache_block` is preserved unchanged in the first implementation.
- The first implementation does not push `[ui]`, `[textures]`, or `[meshes]` entries into `initial.cache_block`; they remain outer PAK entries.

Expected Loadstar fixture arithmetic with `--allow-overwrite`:

```text
mapped mod entries:          151
base entry replacements:       8
net new outer PAK entries:    143
mod-managed load-list records: 106  (87 class XML + 19 mesh payloads)
net new load-list records:     98   (106 mod records - 8 replaced class records)
```

If a mod-managed path also exists as a `shared.pak` load-list record, the merged `initial.pak` record wins for that manifest path and the shared record is dropped from the generated manifest. Report these as load-list source overrides. This prevents `LoadListBuilder` duplicate-record failures and matches the replacement intent: the merged `initial.pak` candidate should own the modded resource.

## Load-List Policy

Add metadata only when there is a proven loader rule.

For merged `initial.pak` entries:

```text
[media]\_templates\*.xml              -> tpl_loader, sourcePak initial.pak, TEMPLATES load
[media]\...\classes\...\*.xml         -> cls_loader, sourcePak initial.pak, CLASSES load
[ssl_cache]\*.sslbundle               -> sslbundle, sourcePak initial.pak, SSL_INITIAL load
[meshes]\*                            -> mesh_loader, sourcePak initial.pak, MESH load
```

Do not add load-list records for these namespaces in the first implementation:

```text
[textures]\...
[ui]\...
```

Why: the current parsed reference manifest has `TEXTURE_PREPARE load` and `TEXTURE load` phase markers but no texture asset records in the committed compact report. The first implementation should include texture/UI bytes in the output PAK and rely on runtime references from XML/mesh data. If game validation proves missing texture metadata, add a second plan step that derives texture records from a known-good manifest or a game-accepted modded output.

Required classifier change:

- Today `[meshes]\...` always classifies as `mesh_loader` with `sourcePak = "shared.pak"`.
- For mod-merged entries inside `initial.pak`, `[meshes]\...` must classify as `mesh_loader` with `sourcePak = "initial.pak"`.
- Preserve existing behavior when collecting records from `shared.pak`.
- Add a tolerant classification path for merge-owned `initial.pak` records so `[textures]\...` and `[ui]\...` return `nil` instead of throwing. Keep strict behavior for commands/tests that are meant to discover unsupported load-list-managed paths.

## Ordering And Verification

The existing writer sorts unknown namespaces after the known initial.pak sections. The mod merge must promote `[meshes]`, `[textures]`, and `[ui]` from "unknown default" to explicit layout sections so the writer and verifier agree on the merged archive policy.

Expected section order for the first merged writer:

```text
pak.load_list
initial.cache_block
[media]\classes...
[media]\_dlc...
[media]\_templates...
[ssl_cache]...
[strings]...
[meshes]...
[textures]...
[ui]...
other supported future namespaces...
```

Update `PakDirectoryScanner.writerSortKey` and `PakVerifier.layoutSectionOrder` together. Do not weaken `verify-snowpak-layout` just to pass a broken merge.

## Code Structure

Create:

```text
Sources/SnowRunnerTool/ModMerge/ModArchiveMapper.swift
Sources/SnowRunnerTool/ModMerge/ModMergePlan.swift
Sources/SnowRunnerTool/ModMerge/ModMergeReporter.swift
Sources/SnowRunnerTool/ModMerge/ModMerger.swift
Sources/SnowRunnerTool/ModMerge/ModMergeError.swift
```

Modify:

```text
Sources/SnowRunnerTool/CLI.swift
Sources/SnowRunnerTool/LoadList/LoadListClassifier.swift
Sources/SnowRunnerTool/Pak/PakWriter.swift
Sources/SnowRunnerTool/Pak/PakDirectoryScanner.swift
Sources/SnowRunnerTool/Pak/PakWriterError.swift
Sources/SnowRunnerTool/Pak/PakVerifier.swift
Tests/SnowRunnerToolTests/TestFixtures.swift
```

Create tests:

```text
Tests/SnowRunnerToolTests/ModArchiveMapperTests.swift
Tests/SnowRunnerToolTests/ModMergePlanTests.swift
Tests/SnowRunnerToolTests/ModMergerTests.swift
Tests/SnowRunnerToolTests/ModMergeCLITests.swift
```

## Implementation Steps

- [ ] **Step 1: Add fixture helpers**
  - Add `TestFixtures.loadstarJbeModPak`.
  - Add `TestFixtures.loadstarJbePcPak`.
  - Add skip helpers if the fixture directory is absent in a clean checkout.

- [ ] **Step 2: Add `ModArchiveMapper`**
  - Read central-directory entries from a mod PAK using the existing `PakReader`.
  - Reject directory entries and encrypted/data-descriptor/ZIP64 entries through existing reader behavior.
  - Map supported paths with the table above.
  - Preserve payload bytes by reading uncompressed payloads through `PakReader`.
  - Throw `unsupportedModPath` for any path outside supported prefixes.
  - Test exact mapped names for representative entries.
  - Test the Loadstar fixture maps 109 entries from `loadstar_1700_jbe.pak` and 42 entries from `pc.pak`.

- [ ] **Step 3: Model merge decisions**
  - Add `ModMergePlan` with:
    - base entry count
    - mapped mod entry count
    - net new outer PAK entry count
    - collisions
    - duplicate mapped mod names
    - load-list source overrides
    - unsupported paths
    - load-list candidate records
  - Make `--dry-run` produce this plan without writing output.
  - If collisions exist and `--allow-overwrite` is absent, exit with code 2 and list the first collisions.
  - If duplicate mapped mod names exist across mod archives, fail unless they are byte-identical. If byte-identical, keep one and report it.

- [ ] **Step 4: Support in-memory/generated file sources**
  - Add a small internal source abstraction so a PAK entry can be written from `Data` or a file URL.
  - Keep the current `PakFileSource` path working.
  - Do not change the SnowPakTool layout policy.
  - Add explicit writer buckets for `[meshes]`, `[textures]`, and `[ui]` after `[strings]`.
  - Extend `PakVerifier.layoutSectionOrder` to check those namespaces in the same order.
  - Acceptance: existing pack/unpack tests still pass.

- [ ] **Step 5: Extend load-list classification for merged initial meshes**
  - Change mesh classification so source-pak attribution can be controlled by caller.
  - For `[meshes]\...` from `shared.pak`, keep `mesh_loader / shared.pak / MESH load`.
  - For `[meshes]\...` from merged `initial.pak`, emit `mesh_loader / initial.pak / MESH load`.
  - Add tolerant merge classification so `[textures]\...` and `[ui]\...` return `nil`.
  - Add tests for both source-pak outcomes.

- [ ] **Step 6: Build merged manifest records**
  - Collect records from:
    - merged initial entries, including modded class XML and modded mesh entries
    - `shared.pak`
    - `shared_sound.pak`
  - Preserve existing `nil` classifications for `pak.load_list`, `initial.cache_block`, `[strings]`, `[ps]`, `[ps_common]`, `[textures]`, and `[ui]`.
  - Resolve duplicate manifest paths by letting merged `initial.pak` records replace records from `shared.pak` or `shared_sound.pak`.
  - Reject only paths that should be load-list-managed but have no rule.
  - Acceptance for Loadstar fixture:
    - 87 mapped `[media]\classes\...` entries appear as `cls_loader / initial.pak`.
    - 19 mapped `[meshes]\...` entries appear as `mesh_loader / initial.pak`.
    - 42 `[textures]\...` entries produce no load-list records.
    - 3 `[ui]\textures\...` entries produce no load-list records.
    - 106 mod-managed records are considered.
    - 98 net-new records are expected before any shared-source override adjustment.

- [ ] **Step 7: Implement `ModMerger`**
  - Read base `initial.pak`.
  - Replace base entries with mapped mod entries only when `allowOverwrite` is true.
  - Inject generated `pak.load_list`.
  - Write output through existing `PakWriter`.
  - Return a merge report model with counts and collision decisions.

- [ ] **Step 8: Add CLI parsing**
  - Add usage text for `pak merge-mod`.
  - Support repeated mod PAK arguments.
  - Require `--shared` and `--shared-sound`, including for `--dry-run`, so dry-run can report load-list effects and source overrides.
  - Reject output paths that equal the base input path or any mod input path.
  - Write `--report` if provided.
  - Print concise stdout:

```text
merged 151 mod entries into initial.pak
overwrote 8 existing entries
mod-managed load-list records: 106
net-new load-list records before shared overrides: 98
load-list source overrides: 0
written: validation/output/initial.loadstar-jbe.pak
```

- [ ] **Step 9: Add verification**
  - After writing, run `PakVerifier.verifyBasic`.
  - Run `PakVerifier.verifySnowPakLayout`.
  - Fail the command if either verifier reports issues.
  - Do not run content-equivalence verification; merged output intentionally differs from base.

- [ ] **Step 10: Add runtime validation script**
  - Create `scripts/mod-merge-loadstar-validation.sh`.
  - Input:

```text
validation/input/initial.pak
validation/input/shared.pak
validation/input/shared_sound.pak
fixtures/loadstar_1700_jbe_pc.1/loadstar_1700_jbe.pak
fixtures/loadstar_1700_jbe_pc.1/pc.pak
```

  - Output:

```text
validation/output/initial.loadstar-jbe.pak
validation/output/loadstar-merge-report.md
```

  - Script should run the merge command and both verifiers.
  - Script should print manual validation instructions only after automated verification passes.

- [ ] **Step 11: Manual game validation**
  - Back up the game `initial.pak`.
  - Copy `validation/output/initial.loadstar-jbe.pak` into the game as `initial.pak`.
  - Launch the game.
  - Check:
    - game reaches main menu
    - International Loadstar 1700 loads in truck store/garage
    - JBE UI images appear
    - custom wheels/addons appear
    - no missing mesh placeholder
    - no missing texture placeholder
  - Record result in the merge report or a validation note.

## Acceptance Criteria

Automated:

- `swift test` passes.
- `pak merge-mod --dry-run ...` reports 151 mapped entries for the Loadstar fixture.
- Without `--allow-overwrite`, the Loadstar merge fails and reports 8 collisions.
- With `--allow-overwrite`, the Loadstar merge writes an output PAK.
- The merge report shows 151 mapped entries, 8 replacements, 143 net-new outer PAK entries, 106 mod-managed load-list records, and 98 net-new load-list records before any shared-source override adjustment.
- Output PAK passes `verify-basic`.
- Output PAK passes `verify-snowpak-layout`.
- Output PAK contains:
  - `[media]\classes\trucks\international_loadstar_1700.xml`
  - `[meshes]\wheels_PT67_Tire`
  - `[textures]\pct\wheels_PT67_Tire_mat__d_a.pct`
  - `[ui]\textures\shopImg1700Loadstar.png`
- Generated `pak.load_list` contains:
  - `<media>\classes\trucks\international_loadstar_1700.xml`, `cls_loader`, `initial.pak`
  - `<meshes>\wheels_PT67_Tire`, `mesh_loader`, `initial.pak`
- Generated `pak.load_list` does not contain records for:
  - `<textures>\pct\wheels_PT67_Tire_mat__d_a.pct`
  - `<ui>\textures\shopImg1700Loadstar.png`

Manual:

- Game launches with the merged candidate.
- The target mod content is visible and usable.
- If meshes load but textures/UI do not, the next task is texture/UI load metadata discovery, not PAK writer debugging.

## Failure Modes And Root Causes

- **Command writes a valid PAK but game ignores the truck:** missing or wrong `cls_loader` records in `pak.load_list`.
- **Truck appears but model is missing:** `[meshes]` entries missing, wrongly named, or mesh load-list source-pak is wrong.
- **Model appears but textures are missing:** `[textures]` mapping is wrong or texture metadata is required after all.
- **UI icons missing:** `[ui]\textures` mapping is wrong, or UI assets belong in another namespace/cache.
- **Game fails before menu:** malformed `pak.load_list`, broken XML overwrite, or unsupported resource path collision.
- **Verifier fails:** outer PAK writer/layout regression; fix before runtime testing.

## Open Questions

- Do `[textures]` entries require load-list records in a current game build, or are they loaded by reference?
- Do `[ui]\textures` entries belong in outer `initial.pak`, `initial.cache_block`, or another namespace for this target runtime?
- Are mod `pc.pak` texture paths always `prebuild/textures/...`, or do other mods use additional PC payload roots?
- Should future commands support multiple overwrite policies: `fail`, `allow`, `only-existing`, `only-new`?
- Should a later version support loose extracted mod directories in addition to mod PAK files?

## Documentation Updates

- Update `README.md` after implementation with:
  - `pak merge-mod` command shape
  - Loadstar validation example
  - warning to back up game files
  - note that first support targets PC mod packages with `classes`, `prebuild/meshes`, `prebuild/textures`, and `ui/textures`

- Add a short `docs/mod-merge-notes.md` after runtime validation with:
  - exact command used
  - output PAK path
  - game build/date
  - pass/fail observations
  - whether texture/UI metadata was needed
