#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="${INPUT_DIR:-validation/input}"
OUTPUT_DIR="${OUTPUT_DIR:-validation/output}"
BASE_PAK="$INPUT_DIR/initial.pak"
BASE_TEXTURES_PAK="${BASE_TEXTURES_PAK:-$INPUT_DIR/shared_textures_base.pak}"
DEFAULT_MOD_PAK="fixtures/loadstar_1700_jbe_pc.1/loadstar_1700_jbe.pak"
DEFAULT_PC_PAK="fixtures/loadstar_1700_jbe_pc.1/pc.pak"
if [[ ! -f "$DEFAULT_MOD_PAK" && -f "fixtures/loadstar_1700_jbe.pak" ]]; then
  DEFAULT_MOD_PAK="fixtures/loadstar_1700_jbe.pak"
fi
if [[ ! -f "$DEFAULT_PC_PAK" && -f "fixtures/loadstar_1700_jbe_pc.pak" ]]; then
  DEFAULT_PC_PAK="fixtures/loadstar_1700_jbe_pc.pak"
fi
MOD_PAK="${MOD_PAK:-$DEFAULT_MOD_PAK}"
PC_PAK="${PC_PAK:-$DEFAULT_PC_PAK}"
OUTPUT_PAK="$OUTPUT_DIR/initial.loadstar-jbe.pak"
OUTPUT_TEXTURES_PAK="$OUTPUT_DIR/shared_textures_base.loadstar-jbe.pak"
REPORT="$OUTPUT_DIR/loadstar-merge-report.md"

for path in "$BASE_PAK" "$BASE_TEXTURES_PAK" "$MOD_PAK" "$PC_PAK"; do
  if [[ ! -f "$path" ]]; then
    echo "missing required input: $path" >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIR"

swift_tool=(env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool)

"${swift_tool[@]}" pak merge-mod \
  --allow-overwrite \
  --report "$REPORT" \
  --input-initial "$BASE_PAK" \
  --output-initial "$OUTPUT_PAK" \
  --input-textures "$BASE_TEXTURES_PAK" \
  --output-textures "$OUTPUT_TEXTURES_PAK" \
  --mods \
  "$MOD_PAK" \
  "$PC_PAK"

"${swift_tool[@]}" pak verify-basic "$OUTPUT_PAK"
"${swift_tool[@]}" pak verify-snowpak-layout "$OUTPUT_PAK"

cat <<EOF
Automated validation passed.

Manual validation:
1. Back up the game's original initial.pak.
2. Copy $OUTPUT_PAK into the game directory as initial.pak.
3. Copy $OUTPUT_TEXTURES_PAK into the game directory as shared_textures_base.pak.
4. Launch SnowRunner and check the Loadstar JBE truck, wheels, meshes, textures, and UI images.
5. Record the result in $REPORT or docs/mod-merge-notes.md.
EOF
