#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_INITIAL_PAK="${BASE_INITIAL_PAK:-$ROOT_DIR/build/input/initial.pak}"

usage() {
  cat <<'EOF'
Usage: restore-game-icon.sh [--file-name <truck.xml>] <mod.pak> [output.pak]

Restores truck icon fields from the original truck XML in build/input/initial.pak
and removes unsupported ui/textures/*.png entries from the mod PAK.

Options:
  --file-name <truck.xml>
      Use this original truck XML filename under [media]\classes\trucks instead
      of auto-detecting it from the mod's classes/trucks/*.xml filename.

Environment:
  BASE_INITIAL_PAK  Override the original initial.pak path.
  OVERWRITE=1       Allow replacing an existing output file.
EOF
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

escape_unzip_pattern() {
  local name="$1"
  name="${name//\\/\\\\}"
  name="${name//[/\\[}"
  name="${name//]/\\]}"
  printf '%s' "$name"
}

extract_attribute() {
  local attr="$1"
  local file="$2"

  ATTR="$attr" perl -0ne '
    my $attr = $ENV{"ATTR"};
    if (/\b\Q$attr\E="([^"]*)"/) {
      print $1;
      exit 0;
    }
  ' "$file"
}

replace_attribute_if_present() {
  local attr="$1"
  local value="$2"
  local file="$3"

  ATTR="$attr" VALUE="$value" perl -0pi -e '
    my $attr = $ENV{"ATTR"};
    my $value = $ENV{"VALUE"};
    s/(\b\Q$attr\E=")[^"]*(")/$1$value$2/g;
  ' "$file"
}

FILE_NAME_OVERRIDE=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --file-name)
      [[ $# -ge 2 ]] || die "--file-name requires a truck XML filename"
      [[ -z "$FILE_NAME_OVERRIDE" ]] || die "--file-name can only be provided once"
      FILE_NAME_OVERRIDE="$2"
      shift 2
      ;;
    --file-name=*)
      [[ -z "$FILE_NAME_OVERRIDE" ]] || die "--file-name can only be provided once"
      FILE_NAME_OVERRIDE="${1#--file-name=}"
      [[ -n "$FILE_NAME_OVERRIDE" ]] || die "--file-name requires a truck XML filename"
      shift
      ;;
    --)
      shift
      args+=("$@")
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ -n "$FILE_NAME_OVERRIDE" ]]; then
  [[ "$FILE_NAME_OVERRIDE" != */* && "$FILE_NAME_OVERRIDE" != *\\* ]] || die "--file-name expects a filename, not a path"
  [[ "$FILE_NAME_OVERRIDE" == *.xml ]] || die "--file-name must end with .xml"
fi

set -- "${args[@]}"

[[ $# -ge 1 && $# -le 2 ]] || {
  usage >&2
  exit 2
}

need_command zipinfo
need_command unzip
need_command zip
need_command perl
need_command find

MOD_PAK="$1"
OUTPUT_PAK="${2:-}"

[[ -f "$MOD_PAK" ]] || die "missing mod PAK: $MOD_PAK"
[[ -f "$BASE_INITIAL_PAK" ]] || die "missing base initial.pak: $BASE_INITIAL_PAK"

mod_entries="$(zipinfo -1 "$MOD_PAK")"
if ! grep -Eiq '^ui/textures/.*[.]png$' <<< "$mod_entries"; then
  printf 'no ui/textures/*.png entries found; leaving PAK untouched: %s\n' "$MOD_PAK"
  exit 0
fi

if [[ -z "$OUTPUT_PAK" ]]; then
  pak_dir="$(cd "$(dirname "$MOD_PAK")" && pwd)"
  pak_name="$(basename "$MOD_PAK")"
  OUTPUT_PAK="$pak_dir/${pak_name%.pak}.restored-icons.pak"
fi

MOD_ABS="$(cd "$(dirname "$MOD_PAK")" && pwd)/$(basename "$MOD_PAK")"
OUTPUT_DIR="$(dirname "$OUTPUT_PAK")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_ABS="$(cd "$OUTPUT_DIR" && pwd)/$(basename "$OUTPUT_PAK")"

[[ "$MOD_ABS" != "$OUTPUT_ABS" ]] || die "output path must be different from input PAK"
[[ ! -e "$OUTPUT_ABS" || "${OVERWRITE:-0}" == "1" ]] || die "output already exists: $OUTPUT_ABS"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/restore_game_icon.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

unpacked="$work_dir/unpacked"
mkdir -p "$unpacked"
unzip -q "$MOD_ABS" -d "$unpacked"

truck_dir="$unpacked/classes/trucks"
[[ -d "$truck_dir" ]] || die "mod PAK has ui textures but no classes/trucks directory"

base_entries="$(zipinfo -1 "$BASE_INITIAL_PAK")"

truck_xmls=()
while IFS= read -r truck_xml; do
  truck_xmls+=("$truck_xml")
done < <(find "$truck_dir" -maxdepth 1 -type f -name '*.xml' | sort)
[[ "${#truck_xmls[@]}" -gt 0 ]] || die "mod PAK has ui textures but no classes/trucks/*.xml files"
if [[ -n "$FILE_NAME_OVERRIDE" && "${#truck_xmls[@]}" -ne 1 ]]; then
  die "--file-name can only be used when the mod PAK has exactly one classes/trucks/*.xml file"
fi

icon_attrs=(
  TruckImage
  UiIcon30x30
  UiIcon40x40
  UiIcon328x458
  UiIconLogo
)

restored_count=0
for mod_xml in "${truck_xmls[@]}"; do
  if [[ -n "$FILE_NAME_OVERRIDE" ]]; then
    file_name="$FILE_NAME_OVERRIDE"
  else
    file_name="$(basename "$mod_xml")"
  fi
  original_internal="[media]\\classes\\trucks\\$file_name"

  if ! grep -Fqx "$original_internal" <<< "$base_entries"; then
    die "missing original truck XML in initial.pak: $original_internal"
  fi

  original_xml="$work_dir/$file_name.original.xml"
  unzip -p "$BASE_INITIAL_PAK" "$(escape_unzip_pattern "$original_internal")" > "$original_xml"

  for attr in "${icon_attrs[@]}"; do
    if original_value="$(extract_attribute "$attr" "$original_xml")" && [[ -n "$original_value" ]]; then
      replace_attribute_if_present "$attr" "$original_value" "$mod_xml"
    fi
  done

  restored_count=$((restored_count + 1))
done

if [[ -d "$unpacked/ui/textures" ]]; then
  find "$unpacked/ui/textures" -type f -iname '*.png' -delete
fi

tmp_output="$work_dir/output.pak"
(
  cd "$unpacked"
  find . -type f -print | sed 's#^\./##' | LC_ALL=C sort | zip -q -@ "$tmp_output"
)

mv "$tmp_output" "$OUTPUT_ABS"

printf 'restored icon fields for %d truck XML file(s)\n' "$restored_count"
printf 'wrote %s\n' "$OUTPUT_ABS"
