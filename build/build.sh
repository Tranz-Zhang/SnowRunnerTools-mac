#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT_DIR="$SCRIPT_DIR/input"
MODS_DIR="$SCRIPT_DIR/mods"
OUTPUT_DIR="$SCRIPT_DIR/output"
REPORTS_DIR="$SCRIPT_DIR/reports"

INPUT_INITIAL="$INPUT_DIR/initial.pak"

OUTPUT_INITIAL="$OUTPUT_DIR/initial.pak"
REPORT="$REPORTS_DIR/mod-merge-report.md"

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

[[ -f "$INPUT_INITIAL" ]] || die "missing required input: $INPUT_INITIAL"
[[ -d "$MODS_DIR" ]] || die "missing mods folder: $MODS_DIR"

mods=()
while IFS= read -r mod_pak; do
  mods+=("$mod_pak")
done < <(find "$MODS_DIR" -maxdepth 1 -type f -name '*.pak' | sort)

[[ "${#mods[@]}" -gt 0 ]] || die "no mod PAKs found under: $MODS_DIR"

mkdir -p "$OUTPUT_DIR" "$REPORTS_DIR"

merge_args=(
  "pak" "merge-mod"
  "--allow-overwrite"
  "--report" "$REPORT"
  "--input-initial" "$INPUT_INITIAL"
  "--output-initial" "$OUTPUT_INITIAL"
  "--experimental-inline-textures"
)

merge_args+=("--mods")
merge_args+=("${mods[@]}")

cd "$ROOT_DIR"

swift_tool=(env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool)

"${swift_tool[@]}" "${merge_args[@]}"
"${swift_tool[@]}" pak verify-basic "$OUTPUT_INITIAL"
"${swift_tool[@]}" pak verify-snowpak-layout "$OUTPUT_INITIAL"

cat <<EOF

Mod merge complete.

Outputs:
  $OUTPUT_INITIAL
EOF

cat <<EOF

Report:
  $REPORT
EOF
