#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj"
SCHEME="SnowRunnerModEditor"
CONFIGURATION="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DIST_DIR="$ROOT_DIR/dist/SnowRunnerModEditor"
BUILD_DIR="$DIST_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/SnowRunnerModEditor.app"
ZIP_PATH="$DIST_DIR/SnowRunnerModEditor.zip"
NOTARY_ZIP_PATH="$DIST_DIR/SnowRunnerModEditor-notary-submit.zip"
NOTARY_RESULT_PATH="$DIST_DIR/notarytool-submit.json"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set NOTARY_PROFILE to the notarytool keychain profile to use for notarization." >&2
  exit 1
fi

IDENTITIES="$(security find-identity -p codesigning -v)"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION"
else
  IDENTITY_COUNT="$(printf "%s\n" "$IDENTITIES" | grep -c "Developer ID Application" || true)"

  if [[ "$IDENTITY_COUNT" -ne 1 ]]; then
    echo "Expected exactly one Developer ID Application identity, found $IDENTITY_COUNT." >&2
    printf "%s\n" "$IDENTITIES" >&2
    echo "Set DEVELOPER_ID_APPLICATION to choose one explicitly." >&2
    exit 1
  fi

  SIGNING_IDENTITY="$(printf "%s\n" "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)"
fi

TEAM_ID="$(printf "%s\n" "$SIGNING_IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"

if [[ -z "$TEAM_ID" ]]; then
  echo "Could not parse Team ID from identity: $SIGNING_IDENTITY" >&2
  exit 1
fi

case "$DIST_DIR" in
  "$ROOT_DIR"/dist/SnowRunnerModEditor) ;;
  *)
    echo "Refusing to remove unexpected DIST_DIR: $DIST_DIR" >&2
    exit 1
    ;;
esac

rm -rf "$DIST_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  clean build \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  ONLY_ACTIVE_ARCH=NO

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app not found at $APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvvv --entitlements :- "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"

set +e
xcrun notarytool submit "$NOTARY_ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_RESULT_PATH"
NOTARY_EXIT_CODE=$?
set -e

cat "$NOTARY_RESULT_PATH"

NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "$NOTARY_RESULT_PATH" 2>/dev/null || true)"
NOTARY_ID="$(/usr/bin/plutil -extract id raw -o - "$NOTARY_RESULT_PATH" 2>/dev/null || true)"

if [[ "$NOTARY_EXIT_CODE" -ne 0 || "$NOTARY_STATUS" != "Accepted" ]]; then
  echo "Notarization was not accepted. Status: ${NOTARY_STATUS:-unknown}" >&2
  if [[ -n "$NOTARY_ID" ]]; then
    echo "Fetch details with:" >&2
    echo "xcrun notarytool log $NOTARY_ID --keychain-profile $NOTARY_PROFILE" >&2
  fi
  exit 1
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

spctl -a -vv "$APP_PATH"

ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "Published artifact:"
echo "$ZIP_PATH"
echo "$ZIP_PATH.sha256"
