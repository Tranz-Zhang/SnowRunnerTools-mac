# SnowRunner PAK Technical Spec

This document is the working reference for the PAK-related formats implemented
by this repository. It records what we observed from fixtures, what the CLI
round-trips, and what remains inferred.

Primary implementation references:

- PAK ZIP reader/writer: `Sources/SnowRunnerCore/Pak/`
- `pak.load_list`: `Sources/SnowRunnerCore/LoadList/`
- `initial.cache_block`: `Sources/SnowRunnerCore/CacheBlock/`
- Mod merge semantics: `Sources/SnowRunnerCore/ModMerge/`
- PCT companion headers: `Sources/SnowRunnerCore/ModMerge/PCTHeaderGenerator.swift`
- Fixture archive: `fixtures/initial.pak`
- PCT fixture: `fixtures/level_ru_02_03.pak`

## 1. `initial.pak` Layout

`initial.pak` is a standard ZIP container with SnowRunner-specific path and
layout rules. Paths use backslashes and bracketed virtual namespaces, for
example `[media]\classes\trucks\hummer_h2.xml`. The bracketed prefix is a VFS
namespace, not a normal filesystem directory.

Observed fixture summary:

| Property | Value |
| --- | --- |
| Entry count | 10,308 |
| First entry | `pak.load_list` |
| First entry method | stored |
| Stored entries | 8,325 |
| Deflated entries | 1,983 |
| Central directory offset | 25,545,070 |
| Central directory size | 1,183,775 |

The writer used by this project creates a SnowPakTool-compatible layout:

1. `pak.load_list`
2. `initial.cache_block`
3. `[media]\classes\...`
4. `[media]\_dlc\...`
5. `[media]\_templates\...`
6. `[ssl_cache]\...`
7. `[strings]\...`
8. `[meshes]\...`
9. `[textures]\...`
10. `[ui]\...`
11. any remaining namespaces

The original fixture has `initial.cache_block` near the end rather than second;
that is valid for the game but not the normalized writer layout.

### Top-Level Entries

| Top-level entry | Count | Purpose |
| --- | ---: | --- |
| `pak.load_list` | 1 | Boot-time resource manifest. Stored, first entry. |
| `initial.cache_block` | 1 | Secondary binary bundle for compiled scripts, platform resources, and related payloads. |
| `[media]` | 10,289 | XML gameplay/class/template/DLC data. |
| `[ssl_cache]` | 4 | Shader/SSL cache files plus `initial_pak` marker. |
| `[strings]` | 13 | Loose localized string-table files. Not indexed by `pak.load_list`. |

### `[media]`

Observed second-level layout:

| Path | Count | Purpose |
| --- | ---: | --- |
| `[media]\classes` | 2,653 | Base-game XML class data. Includes trucks, engines, gearboxes, suspensions, wheels, plants, particles, overlays, terrain layers, weather, etc. |
| `[media]\_dlc` | 7,631 | DLC and regional XML class data. Subfolders such as `dlc_10`, `ru_08`, `us_16`, and `stuff_01` mirror the base `classes` shape. |
| `[media]\_templates` | 5 | Template XML: `environment.xml`, `models.xml`, `plants.xml`, `trailers.xml`, `trucks.xml`. |

Important `[media]\classes` groups in the fixture:

| Group | Count | Meaning |
| --- | ---: | --- |
| `trucks` | 908 | Vehicle, addon, trailer, and tuning XML. |
| `models` | 1,099 | Model descriptor XML. |
| `plants` | 172 | Plant descriptors. |
| `particles` | 142 | Particle descriptors. |
| `grass` | 48 | Grass descriptors. |
| `suspensions` | 42 | Suspension definitions. |
| `wheels` | 36 | Wheel/tire definitions. |
| `terrain_layers` | 31 | Terrain layer definitions. |
| `cargo_types` | 25 | Cargo type definitions. |
| `customization_presets` | 1 | Shared truck customization preset registry. |

### `[ssl_cache]`

Observed entries:

- `[ssl_cache]\initial_debug.sslbundle`
- `[ssl_cache]\initial_profile.sslbundle`
- `[ssl_cache]\initial_release.sslbundle`
- `[ssl_cache]\initial_pak`

The `.sslbundle` entries are indexed in `pak.load_list` as `sslbundle` records.
The `initial_pak` marker exists in the ZIP but is intentionally not indexed by
`pak.load_list`.

### `[strings]`

Observed loose language tables:

- `strings_brazilian_portuguese.str`
- `strings_chinese_simplified.str`
- `strings_chinese_traditional.str`
- `strings_czech.str`
- `strings_english.str`
- `strings_french.str`
- `strings_german.str`
- `strings_italian.str`
- `strings_japanese.str`
- `strings_korean.str`
- `strings_polish.str`
- `strings_russian.str`
- `strings_spanish.str`

These loose `[strings]` files are not indexed by `pak.load_list` in the current
classifier. Mod string merging can still update them because they are normal ZIP
entries.

## 2. ZIP Container Rules

The game accepts a narrow ZIP dialect:

- Path separator is `\`, not `/`.
- Names are encoded with CP437-compatible bytes.
- Directory entries are not needed; the tree is implicit in filenames.
- `pak.load_list` must be stored and should be first.
- SnowPakTool-compatible output stores only `pak.load_list`; other entries are
  deflated unless copied as preserved texture payloads.
- ZIP64, encryption, comments, data descriptors, and extra fields are avoided.
- Timestamps are fixed to DOS `1980-01-01 03:00:00` in normalized output.
- CRC-32 is real and must match the uncompressed payload.

For mod texture entries copied from source archives, this project may preserve
existing compressed payloads and selected texture ZIP metadata. That behavior is
intentional: some game texture PAKs contain central extra fields for PCT entries,
and preserving them avoids changing bytes that the game already accepts.

## 3. `pak.load_list`

`pak.load_list` is a custom binary manifest inside `initial.pak`. It is not a
ZIP. The game uses it to decide which resources to load, which loader to run,
and which source PAK owns each resource.

The key path rule:

- ZIP entry path: `[media]\classes\trucks\hummer_h2.xml`
- Manifest path: `<media>\classes\trucks\hummer_h2.xml`

Square brackets are used in the ZIP namespace. Angle brackets are used in
`pak.load_list`.

### Binary Layout

All integer fields are little-endian.

```text
u32 version_tag        observed: 1
u8  marker             observed: 1
u32 entry_count
u32 header_tail        observed: 3, semantics unknown
u8  marker             observed: 1

u8[entry_count] entry_kinds
u8 marker              observed: 1

for each entry:
    u32 dependency_count
    u8  marker          observed: 1
    i32[dependency_count] dependency_entry_indices

u8 marker              observed: 1

for each entry:
    u32 string_count
    u32 magic_b_count   observed: 2
    u8[string_count] magic_a_bytes, each observed as 1
    u8[magic_b_count] magic_b_bytes, each observed as 1
    for each string:
        u32 byte_length
        u8[byte_length] CP437 string bytes
```

Supported entry kinds:

| Raw byte | Kind | Strings |
| ---: | --- | --- |
| `1` | start | none |
| `2` | asset | `[manifestPath, loaderType, sourcePak]` or `[manifestPath, loaderType, sourcePak, json]` |
| `5` | stage | `[phaseName]` |
| `6` | end | none |

The reference fixture has no asset records with the optional fourth `json`
string, but the parser/writer supports it.

### Phase Ownership

The physical entry order is:

```text
Start
assets for phase 1
Stage phase 1
assets for phase 2
Stage phase 2
...
assets for phase N
Stage phase N
End
```

An asset belongs to the next `stage` entry after it. This is why the compact
inspector prints the phase tag after the assets that belong to that phase.

Canonical phases from the fixture:

| Phase | Asset count in fixture | Purpose |
| --- | ---: | --- |
| `RES3_INIT load` | 0 | Empty phase marker. |
| `SSL_SOURCES_PARSE load` | 0 | Empty phase marker. |
| `SSL_INITIAL load` | 6 | `.spdb` and `.sslbundle` shader/SSL resources. |
| `TEMPLATES load` | 5 | XML templates under `[media]\_templates`. |
| `CLASSES load` | 10,284 | XML classes under `[media]\classes` and `[media]\_dlc\...\classes`. |
| `TEXTURE_PREPARE load` | 0 | Empty phase marker in this fixture. |
| `TEXTURE load` | 0 | Empty for the base fixture; mod PCT records are added here. |
| `MESH load` | 7,606 | Mesh records from `shared.pak`. |
| `SOUND load` | 1 | `sound.sound_list` from `shared_sound.pak`. |
| `RES3_PROJECT load` | 0 | Empty phase marker. |
| `PROJECT load` | 0 | Empty phase marker. |
| `DEFAULT load` | 0 | Empty phase marker. |
| `DESC_BLOCK load` | 0 | Empty phase marker. |

The fixture has 17,902 asset records and 17,917 compact inspector lines
including start, end, and 13 stage markers.

### Dependency Rules

The writer follows the dependency graph observed in SnowPakTool-compatible
manifests:

- Start entry has no dependencies.
- Asset entries usually depend on the previous phase's stage entry, or Start
  for the first phase.
- Stage entries depend on every asset in their phase. If a phase has no assets,
  the stage depends on the previous entry.
- End depends on the last stage.
- For PCT textures, `pct_faces` and `pct_inplace_faces` depend on the matching
  `pct_mr2_header` asset for the same manifest path.

### Loader Classification

Current full-rebuild classifier rules:

| ZIP entry | Manifest path | Loader | Source PAK | Phase |
| --- | --- | --- | --- | --- |
| `[ssl_cache]\*.spdb` | `<ssl_cache>\*.spdb` | `spdb` | `shared_debug.pak` | `SSL_INITIAL load` |
| `[ssl_cache]\*.sslbundle` | `<ssl_cache>\*.sslbundle` | `sslbundle` | `initial.pak` | `SSL_INITIAL load` |
| `[media]\_templates\*.xml` | `<media>\_templates\*.xml` | `tpl_loader` | `initial.pak` | `TEMPLATES load` |
| `[media]\...\classes\*.xml` | `<media>\...\classes\*.xml` | `cls_loader` | `initial.pak` | `CLASSES load` |
| `[meshes]\...` | `<meshes>\...` | `mesh_loader` | `shared.pak` | `MESH load` |
| `sound.sound_list` | `sound.sound_list` | `sound_loader` | `shared_sound.pak` | `SOUND load` |

Entries intentionally excluded from `pak.load_list`:

- `pak.load_list`
- `initial.cache_block`
- `[ssl_cache]\initial_pak`
- `[strings]\...`
- `[sound]\...`
- `[ps]\...`
- `[ps_common]\...`

Known source PAK names observed or supported by the current constants:

- `initial.pak`
- `shared_debug.pak`
- `shared.pak`
- `shared_sound.pak`
- `shared_textures_base.pak`
- `shared_textures.pak`

### Mutation Rules

Editing an existing ZIP entry without changing its path usually does not require
changing `pak.load_list`. Adding or renaming a load-listed resource does.

Common cases:

| Operation | Load-list change? | Why |
| --- | --- | --- |
| Modify existing XML in place | No | Manifest path, loader, and source PAK are unchanged. |
| Add new class XML | Yes | Needs a `cls_loader` asset record. |
| Add new template XML | Yes | Needs a `tpl_loader` asset record. |
| Add new mesh | Yes | Needs a `mesh_loader` asset record. |
| Add new PCT texture | Yes | Needs `pct_mr2_header` and `pct_faces` records for the `.pct_header` path. |
| Add loose `[strings]\*.str` | No in current classifier | Loose strings are not load-list records. |

### Mod Merge Semantics

Supported mod archives are mapped into runtime namespaces before merging:

| Mod path | Runtime path | Notes |
| --- | --- | --- |
| `classes/...` | `[media]\classes\...` | Class XML; load-listed as `cls_loader` when new. |
| `prebuild/meshes/...` | `[meshes]\...` | Mesh payloads; load-listed as `mesh_loader`. |
| `ui/textures/...` | `[textures]\...` | UI texture payloads for the texture output path. |
| `texts/*.str` | `[strings]\*.str` | Loose string tables; not load-listed. |

Most mapped entries are opaque payloads. If a mapped mod entry has the same
runtime path as a base entry, `pak merge-mod` rejects it unless
`--allow-overwrite` is supplied. With overwrite allowed, the mod payload
replaces the base payload at that runtime path.

Two file families have semantic merge rules because a file-level replacement
would delete unrelated base-game data:

| Runtime path | Merge key | Rule | Load-list effect |
| --- | --- | --- | --- |
| `[strings]\*.str` | string key before the first tab | Remove all base rows whose key appears in the mod table, then append mod rows. | None; loose strings are not load-listed. |
| `[media]\classes\customization_presets\customization_preset.xml` | direct `<Truck Name="...">` child of root `<TruckSet>` | Preserve base truck order, replace matching truck blocks, append new mod truck blocks in mod order. If multiple mods define the same truck, later mod order wins. | Path remains one `cls_loader` class entry; existing path edits do not add a new load-list record. |

The customization preset merge validates that the XML root is `<TruckSet>` and
that every direct `<Truck>` child has a non-empty `Name` attribute. It treats
the whole `<Truck>` block as the merge unit; it does not merge individual
`<CustomizationPreset Id="...">` children.

These semantic merges do not require `--allow-overwrite` when the semantic file
path already exists in the base archive. They are still reported separately in
CLI and Markdown merge reports, for example as `string table merges` and
`customization preset merges`.

Workspace conflict detection must use the same rule for
`[media]\classes\customization_presets\customization_preset.xml`. Multiple
enabled mods that map to this path are not a user-resolvable mod-to-mod
conflict; they are automatic merge inputs. Quick verify therefore suppresses
this target from the conflict list, and saved manual conflict resolutions for
this target are stale and should be pruned rather than applied. Applying a
manual winner would discard other mods' truck preset blocks and bypass the
semantic merge.

Some modded customization preset XML has duplicate `TintColor1`,
`TintColor2`, or `TintColor3` attributes inside a single
`<CustomizationPreset>` tag. XML parsers reject duplicate attribute names, but
the observed intent is positional tint slots. Before parsing, the merge repair
step promotes duplicate tint attributes to the first unused tint slot in
`TintColor1`/`TintColor2`/`TintColor3` order while preserving the attribute
values. This repair is limited to `<CustomizationPreset>` tags and only runs
when the original XML parse fails.

## 4. `initial.cache_block`

`initial.cache_block` is a secondary binary bundle stored as one ZIP entry
inside `initial.pak`. It has its own table of internal names, offsets, sizes,
and concatenated payloads.

Observed fixture content after unpacking:

| Namespace | Count | Purpose |
| --- | ---: | --- |
| `[ps]` | 1,777 | Game/platform scripts, UI controllers, gameplay systems, tasks, settings, and compiled resources. |
| `[ps_common]` | 171 | Shared script/resource definitions, common presets, graphics/postprocess resources, debug/common systems. |

Observed extension counts:

| Extension | Count |
| --- | ---: |
| `.sso` | 1,816 |
| `.ps` | 66 |
| `.ssolib` | 41 |
| `.prop` | 8 |
| `.td` | 8 |
| `.sd` | 6 |
| `.cls` | 1 |
| `.mml_cfg` | 1 |
| `.ssl` | 1 |

### Binary Layout

All integer fields are little-endian.

```text
u8[64] signature
i32     version_marker       observed: 1
u8      marker               observed: 1
i32     entry_count
i32     table_count_marker   observed: 4
u8      names_marker         observed: 1

for each entry:
    i32 name_length
    u8[name_length] CP437 internal name

u8 offsets_marker            observed: 1
i64[entry_count] relative_offsets

u8 sizes_marker              observed: 1
i32[entry_count] sizes

u8 zeroes_marker             observed: 1
i32[entry_count] zeroes      each observed: 0

u8[...] concatenated_payloads
```

The 64-byte signature starts with ASCII `1SERcache_block`, contains zero
padding, then includes ASCII `S3DRESOURCE`.

Offsets are relative to the first payload byte, not to the beginning of the
file. Payload `N` starts at:

```text
payload_base_offset + relative_offsets[N]
```

### Cache-Block Paths

Internal names use angle-bracket namespaces:

```text
<ps>:hud.xml
<strings>\ui\menu.str
<ps_common>\presets\screen_effect.ps
```

When unpacked to disk, the tool maps them to bracketed directory paths:

```text
[ps]/hud.xml
[strings]/ui/menu.str
[ps_common]/presets/screen_effect.ps
```

The colon form means the file is directly under the namespace root. The
backslash form means it has nested directories.

Validation rules:

- Internal names must start with `<namespace>`.
- The remainder must be either `:filename` or `\dir\filename`.
- Empty names, `.`, `..`, duplicate names, and case-insensitive duplicate names
  are rejected.
- Names must be CP437-encodable.
- Payload offsets and sizes must be non-negative and within the file.
- Every zero-column value must be `0`.

### Mixed Cache-Block Packing

The `--mixed-cache-block` pack mode treats `[ps]`, `[ps_common]`, and
`[strings]` directories as cache-block contents and packs them into
`initial.cache_block`. Other top-level directories stay as normal PAK entries.

This exists because some unpack workflows expand cache-block contents beside
normal PAK namespaces.

## 5. PCT Textures

PCT is SnowRunner's texture payload format used for many game textures. The
important practical point is that the game expects two PAK entries for each PCT
texture:

```text
[textures]\pct\foo.pct
[textures]\pct\foo.pct_header
```

`foo.pct` is the full texture payload. `foo.pct_header` is a small companion
file derived from the beginning of `foo.pct`.

### PCT File Header Fields Used by This Tool

The project does not fully decode PCT texture data. It only validates and copies
the header region needed to generate `.pct_header`.

Observed/implemented fields:

| Offset | Size | Meaning |
| ---: | ---: | --- |
| `0` | at least 64 bytes | Fixed-size leading header region. |
| `6` | 4 | ASCII magic `TCIP`. |
| `48` | 4 | Little-endian table count. |
| `64` | `table_count * 8` | Header table entries copied into `.pct_header`. |

The derived header length is:

```text
header_length = 64 + table_count * 8
```

The source PCT must be at least `header_length` bytes long.

### `.pct_header` Generation

To generate `[textures]\pct\foo.pct_header`:

1. Validate that the PCT data is at least 64 bytes.
2. Validate that bytes `6...9` are `TCIP`.
3. Read `table_count` as little-endian `u32` from bytes `48...51`.
4. Copy the first `64 + table_count * 8` bytes.
5. Patch byte `header_length - 6` to `0x01`.
6. Patch bytes `header_length - 4 ... header_length - 1` to the little-endian
   `u32` value of `header_length`.

The fixture test proves this rule against
`fixtures/level_ru_02_03.pak`:

```text
[textures]\pct\level_ru_02_03_blend_map__cmp.pct
[textures]\pct\level_ru_02_03_blend_map__cmp.pct_header
```

For that fixture, the generated `.pct_header` is 72 bytes, so the PCT table
count is 1.

Malformed PCT payloads are rejected if:

- the file is shorter than 64 bytes,
- the `TCIP` magic is missing,
- or the computed header length is outside the payload.

### PCT Load-List Records

The `.pct` payload itself is not the manifest path used for texture loading.
`pak.load_list` records point at the companion header path:

```text
<textures>\pct\foo.pct_header
```

Each new PCT texture gets two asset records in `TEXTURE load`:

| Manifest path | Loader | Dependency |
| --- | --- | --- |
| `<textures>\pct\foo.pct_header` | `pct_mr2_header` | previous phase/stage anchor |
| `<textures>\pct\foo.pct_header` | `pct_faces` | the matching `pct_mr2_header` entry |

The source PAK is normally `shared_textures.pak` for separate texture output.
The current normal merge path can also write mod textures into the generated
`initial.pak`, in which case these records are rewritten to source from
`initial.pak`.

### Mod Texture Mapping

Supported texture PAK input shape:

```text
prebuild/textures/pct/foo.pct
```

Mapped output entries:

```text
[textures]\pct\foo.pct
[textures]\pct\foo.pct_header
```

The `.pct` payload is copied. For source texture entries, the merge pipeline can
preserve the original compressed payload and ZIP extra fields so the generated
archive stays close to the accepted source bytes. The `.pct_header` companion is
generated by this project and does not preserve source ZIP metadata.

### Inferred Game Loading Process

The observed load-list and fixture behavior imply this loading sequence:

1. The game reads `pak.load_list` from `initial.pak`.
2. During `TEXTURE load`, it sees `pct_mr2_header` for
   `<textures>\pct\foo.pct_header`.
3. It loads the small `.pct_header` companion first. This gives the texture
   loader enough metadata to understand the texture tables without reading the
   entire `.pct` payload up front.
4. It then runs `pct_faces`, which depends on the header record and resolves the
   corresponding `.pct` payload beside the header by removing the `_header`
   suffix.
5. The texture bytes are loaded from the source PAK named in the record.

The exact Saber engine internals are not documented. The dependency graph and
required companion file are confirmed by fixtures and runtime validation.

## 6. UI Textures

SnowRunner UI textures use the same PCT container family as other game
textures, but they are stored and referenced through the UI/GFX pipeline rather
than through truck/model XML material paths.

Observed example from the Azov 64131 truck XML:

```xml
<UiDesc UiIcon328x458="shopImgAzov64131" ... />
```

The XML value is a UI symbol name, not a PAK path. The symbol was found inside
`gfx.pak`'s GFX bundle and resolves to a generated UI texture entry:

```text
gfx.pak:[gfx]\gfxbundle.gfxbundle
  symbol: shopImgAzov64131

gfx.pak:[textures]\ui\flash_auto\trucks_img_lib_i130.pct
gfx.pak:[textures]\ui\flash_auto\trucks_img_lib_i130.pct_header
```

The corresponding `gfx.pak` load-list records point at the header path:

```text
<textures>\ui\flash_auto\trucks_img_lib_i130.pct_header
```

### `gfx.pak`

`gfx.pak` is a normal SnowRunner PAK/ZIP archive for UI resources. It contains:

- `pak.load_list`
- `[gfx]\gfxbundle.gfxbundle`
- `[ps]\_\ui_textures.mml_cfg`
- `[textures]\ui\flash_auto\*.pct`
- `[textures]\ui\flash_auto\*.pct_header`

Unlike `initial.pak`, this archive has a populated texture load-list. UI PCT
entries are load-listed the same way as other PCT textures: the manifest path is
the `.pct_header` path, and the loader records use `pct_mr2_header` plus
`pct_faces`.

### `gfxbundle.gfxbundle`

`gfxbundle.gfxbundle` is not a ZIP file. Its leading bytes are:

```text
53 33 44 42
S3DB
```

`zipinfo` does not recognize it as a ZIP. The file appears to be a custom
`S3DB` bundle containing embedded Scaleform/GFX UI libraries. Observed embedded
library names include:

```text
font_en.gfx
trucks_img_lib.gfx
trucks_lib.gfx
ui_root.gfx
```

The bundle also contains Flash/Scaleform-style markers and symbols such as
`GFX`, `CWS`, `flash.display`, `MovieClip`, `BitmapData`, and concrete exported
UI names like `shopImgAzov64131`.

This means UI XML values such as `UiIcon328x458` resolve through
`gfxbundle.gfxbundle`; they do not directly name the backing `.pct` file.

### UI PCT Shape

UI PCT files use the same `TCIP` header family as normal model/material PCTs.
The observed differences are content and metadata size, not a separate file
format.

Concrete comparison:

| Texture | PAK path | PCT size | Header size | Dimensions | Table count |
| --- | --- | ---: | ---: | ---: | ---: |
| Azov 64131 shop icon | `[textures]\ui\flash_auto\trucks_img_lib_i130.pct` | 150,958 | 72 | 328 x 460 | 1 |
| Azov 64131 truck material | `[textures]\pct\trucks_azov_64131_front__d.pct` | 5,597,350 | 160 | 2048 x 2048 | 12 |

Both files start with `TCIP` at bytes `6...9`. Both use a companion
`.pct_header` derived from the start of the `.pct` payload using the same
header-length rule described in section 5.

The shorter UI header comes from the lower table count. For the observed truck
shop icon:

```text
header_length = 64 + 1 * 8 = 72
```

For the observed truck material:

```text
header_length = 64 + 12 * 8 = 160
```

The `UiIcon328x458` name in truck XML does not exactly match the raw PCT height
for the observed backing file (`328 x 460`). The difference is likely UI
padding, trim, or Scaleform layout metadata in the GFX symbol. Treat the XML
attribute as the UI slot/class, not as a direct statement of the PCT dimensions.

### UI Texture Metadata

`[ps]\_\ui_textures.mml_cfg` lists generated UI texture ids and load behavior,
for example:

```text
"trucks_img_lib_i130": {
    "loadOnDemand": true
}
```

This file identifies which generated texture ids exist and whether they are
loaded on demand. It does not by itself map XML symbols such as
`shopImgAzov64131` to generated PCT ids. That mapping lives in the embedded GFX
data inside `gfxbundle.gfxbundle`.

### Replacing vs Adding UI Images

Replacing an existing UI image is the shorter path:

1. Keep the existing symbol in `gfxbundle.gfxbundle`.
2. Replace the existing backing `.pct` payload.
3. Regenerate or preserve the matching `.pct_header`.
4. Keep the existing `gfx.pak` load-list records unless the path changes.

Adding a brand-new named UI image is harder:

1. Add `[textures]\ui\flash_auto\new_id.pct`.
2. Add `[textures]\ui\flash_auto\new_id.pct_header`.
3. Add `pct_mr2_header` and `pct_faces` records for
   `<textures>\ui\flash_auto\new_id.pct_header` in `gfx.pak`'s `pak.load_list`.
4. Update `[ps]\_\ui_textures.mml_cfg` if the generated texture id must be
   known to the UI texture metadata.
5. Modify or rebuild the relevant embedded GFX library inside
   `gfxbundle.gfxbundle` so a new symbol name resolves to the new texture id.

Step 5 is the limiting factor. `gfxbundle.gfxbundle` is a custom packed
Scaleform/GFX bundle, not a text manifest, so adding a new symbol requires a GFX
editing/rebuild workflow that this project does not currently implement.

## 7. Practical Rules for Future Changes

- Keep `pak.load_list` first and stored.
- Keep namespace paths byte-stable: `[name]\...` in ZIP, `<name>\...` in
  manifests/cache-block internals.
- Treat `pak.load_list` as required when adding any new class/template/mesh/PCT
  resource.
- Do not add ZIP features the game does not need: ZIP64, comments, encryption,
  data descriptors, or arbitrary extra fields.
- Preserve source compressed bytes and texture metadata when copying known-good
  PCT entries from texture PAKs.
- For cache-block edits, unpack, edit the expanded namespace files, then rebuild
  `initial.cache_block`; do not treat it as a directory inside the ZIP.
- When in doubt, verify with:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-basic <pak>
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool pak verify-snowpak-layout <pak>
env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool load-list inspect <pak.load_list>
```
