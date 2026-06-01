#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATION_DIR="${1:-"$ROOT_DIR/validation"}"
INPUT_DIR="$VALIDATION_DIR/input"
WORK_DIR="$VALIDATION_DIR/work"
OUTPUT_DIR="$VALIDATION_DIR/output"

initial_pak="$INPUT_DIR/initial.pak"
shared_pak="$INPUT_DIR/shared.pak"
shared_sound_pak="$INPUT_DIR/shared_sound.pak"

missing=0
for path in "$initial_pak" "$shared_pak" "$shared_sound_pak"; do
    if [[ ! -f "$path" ]]; then
        printf 'missing required validation input: %s\n' "$path" >&2
        missing=1
    fi
done

if [[ "$missing" -ne 0 ]]; then
    cat >&2 <<EOF

Expected layout:
  validation/input/initial.pak
  validation/input/shared.pak
  validation/input/shared_sound.pak

You can also pass another validation directory:
  scripts/phase4-runtime-validation.sh /path/to/validation
EOF
    exit 2
fi

cd "$ROOT_DIR"

rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

initial_dir="$WORK_DIR/initial"
rebuilt_pak="$OUTPUT_DIR/initial.pak"
created_load_list="$OUTPUT_DIR/created.load_list"
inspect_report="$OUTPUT_DIR/inspect.txt"

swift_tool=(env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-swift-module-cache swift run snowrunner-tool)

"${swift_tool[@]}" pak unpack "$initial_pak" "$initial_dir"
"${swift_tool[@]}" load-list inspect "$initial_dir/pak.load_list" > "$inspect_report"
"${swift_tool[@]}" load-list create-initial "$created_load_list" "$initial_pak" "$shared_pak" "$shared_sound_pak"
"${swift_tool[@]}" pak pack --rebuild-load-list "$initial_dir" "$rebuilt_pak" "$shared_pak" "$shared_sound_pak"
"${swift_tool[@]}" pak verify-basic "$rebuilt_pak"
"${swift_tool[@]}" pak verify-snowpak-layout "$rebuilt_pak"

cat <<EOF

Phase 4 runtime candidate is ready:
  $rebuilt_pak

Generated validation artifacts:
  $created_load_list
  $inspect_report

Next manual step:
  Back up the game's original initial.pak, replace it with the rebuilt candidate, and launch SnowRunner.
EOF
