# SnowRunnerModEditor Notarized Publish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a repeatable Developer ID signed, hardened-runtime, notarized, stapled, Gatekeeper-accepted SnowRunnerModEditor release artifact.

**Architecture:** Keep development signing separate from distribution publishing. Add a small release script and release documentation instead of hard-coding private signing details into the Xcode project. The script builds a Release app, signs it with the locally installed Developer ID Application identity, packages it, submits it to Apple notarization, staples the accepted ticket, and verifies the result.

**Tech Stack:** Xcode `xcodebuild`, macOS `codesign`, `spctl`, `ditto`, `xcrun notarytool`, `xcrun stapler`, existing `SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj`.

---

## Current Status

The project is not notarization-ready yet.

- `SnowRunnerModEditor` Release build now resolves `ENABLE_HARDENED_RUNTIME = YES`.
- `SnowRunnerModEditor` Release build now sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`.
- `SnowRunnerModEditor` Release build now requests secure Developer ID signing timestamps with `OTHER_CODE_SIGN_FLAGS = "--timestamp"`.
- Local keychain contains a valid `Developer ID Application: Your Name (YOUR_TEAM_ID)` identity.
- The reusable notary profile is supplied by `NOTARY_PROFILE`.
- A previous notarization submission was rejected only because the signature did not include a secure timestamp.
- The public ZIP must be created after stapling; a ZIP created before stapling does not contain the offline notarization ticket.
- Existing discovered Debug artifacts remain unsuitable for distribution if they are ad-hoc signed or contain `com.apple.security.get-task-allow`.
- Existing entitlements file is `SnowRunnerModEditor/SnowRunnerModEditor/SnowRunnerModEditor.entitlements` and contains sandbox, user-selected read/write file access, and app-scope bookmarks.

## File Structure

- Modify: `SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj/project.pbxproj`
  - Set Release hardened runtime to `YES`.
  - Set Release signing to request secure timestamping.
  - Do not store private credentials.
  - Only add stable distribution-safe build settings.
- Create: `scripts/publish-snowrunner-mod-editor.sh`
  - Owns build, signing validation, zip packaging, notarization, stapling, and Gatekeeper verification.
  - Uses a temporary notary submission ZIP, then creates the public ZIP after stapling.
  - Reads signing/notary inputs from environment variables and local keychain state.
- Create: `docs/release/snowrunner-mod-editor-publish.md`
  - Human checklist for certificate setup, notary profile setup, command usage, and expected validation output.
- Optional Modify: `.gitignore`
  - Ignore generated release output if `dist/` is not already ignored.

---

### Task 1: Establish Local Apple Signing Prerequisites

**Files:**
- No repo changes.

- [ ] **Step 1: Verify Developer ID Application identity exists**

Run:

```bash
security find-identity -p codesigning -v
```

Expected:

```text
1) <hash> "Developer ID Application: Your Name (YOUR_TEAM_ID)"
```

If the command reports `0 valid identities found`, install the Developer ID Application certificate and private key into the login keychain using Xcode Accounts or Keychain Access, then rerun the command.

- [ ] **Step 2: Capture the Team ID**

Run:

```bash
security find-identity -p codesigning -v | sed -n 's/.*Developer ID Application: .* (\([A-Z0-9]*\)).*/\1/p'
```

Expected:

```text
YOUR_TEAM_ID
```

Use the printed value for `DEVELOPMENT_TEAM` during release.

- [ ] **Step 3: Create a notarytool keychain profile**

Run:

```bash
xcrun notarytool store-credentials YOUR_NOTARY_PROFILE
```

Expected interaction:

```text
Apple ID:
Team ID:
Password:
Validating your credentials...
Success. Credentials validated.
```

Use an app-specific password or App Store Connect API key credentials. Use the same profile name later through `NOTARY_PROFILE`.

- [ ] **Step 4: Verify notary profile is readable**

Run:

```bash
xcrun notarytool history --keychain-profile YOUR_NOTARY_PROFILE
```

Expected:

```text
Successfully received submission history.
```

An empty history is acceptable.

---

### Task 2: Make Release Build Settings Distribution-Safe

**Files:**
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj/project.pbxproj`

- [ ] **Step 1: Set hardened runtime on the app target Release configuration**

In the `DE5415D72FEA372A00117FF0 /* Release */` build settings for target `SnowRunnerModEditor`, add:

```text
CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;
ENABLE_HARDENED_RUNTIME = YES;
OTHER_CODE_SIGN_FLAGS = "--timestamp";
```

Do not add Apple account credentials, notary credentials, or private certificate names to the project file.

- [ ] **Step 2: Keep development signing flexible**

Leave these existing settings unchanged:

```text
CODE_SIGN_ENTITLEMENTS = SnowRunnerModEditor/SnowRunnerModEditor.entitlements;
CODE_SIGN_STYLE = Automatic;
PRODUCT_BUNDLE_IDENTIFIER = com.bychance.SnowRunnerModEditor;
```

Reason: local Debug builds should remain convenient, while the publish script supplies Developer ID release signing overrides.

- [ ] **Step 3: Verify Release setting resolves**

Run:

```bash
xcodebuild -project SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj -scheme SnowRunnerModEditor -configuration Release -showBuildSettings | rg "ENABLE_HARDENED_RUNTIME|CODE_SIGN_ENTITLEMENTS|PRODUCT_BUNDLE_IDENTIFIER"
```

Expected:

```text
ENABLE_HARDENED_RUNTIME = YES
CODE_SIGN_ENTITLEMENTS = SnowRunnerModEditor/SnowRunnerModEditor.entitlements
PRODUCT_BUNDLE_IDENTIFIER = com.bychance.SnowRunnerModEditor
```

---

### Task 3: Add the Publish Script

**Files:**
- Create: `scripts/publish-snowrunner-mod-editor.sh`
- Optional Modify: `.gitignore`

- [ ] **Step 1: Create script with strict inputs and validation**

Create `scripts/publish-snowrunner-mod-editor.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj"
SCHEME="SnowRunnerModEditor"
CONFIGURATION="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DIST_DIR="$ROOT_DIR/dist/SnowRunnerModEditor"
ARCHIVE_DIR="$DIST_DIR/archive"
BUILD_DIR="$DIST_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/SnowRunnerModEditor.app"
ZIP_PATH="$DIST_DIR/SnowRunnerModEditor.zip"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set NOTARY_PROFILE to the notarytool keychain profile to use for notarization." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

IDENTITIES="$(security find-identity -p codesigning -v)"
IDENTITY_COUNT="$(printf "%s\n" "$IDENTITIES" | grep -c "Developer ID Application" || true)"

if [[ "$IDENTITY_COUNT" -ne 1 ]]; then
  echo "Expected exactly one Developer ID Application identity, found $IDENTITY_COUNT." >&2
  printf "%s\n" "$IDENTITIES" >&2
  exit 1
fi

DEVELOPER_ID_APPLICATION="$(printf "%s\n" "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)"
TEAM_ID="$(printf "%s\n" "$DEVELOPER_ID_APPLICATION" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"

if [[ -z "$TEAM_ID" ]]; then
  echo "Could not parse Team ID from identity: $DEVELOPER_ID_APPLICATION" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$ARCHIVE_DIR" "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  clean build \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
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

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

spctl -a -vv "$APP_PATH"

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "Published artifact:"
echo "$ZIP_PATH"
echo "$ZIP_PATH.sha256"
```

- [ ] **Step 2: Make script executable**

Run:

```bash
chmod +x scripts/publish-snowrunner-mod-editor.sh
```

Expected:

```text
scripts/publish-snowrunner-mod-editor.sh is executable
```

Verify with:

```bash
test -x scripts/publish-snowrunner-mod-editor.sh && echo "scripts/publish-snowrunner-mod-editor.sh is executable"
```

- [ ] **Step 3: Ensure generated artifacts are ignored**

Run:

```bash
git check-ignore dist/SnowRunnerModEditor/SnowRunnerModEditor.zip
```

Expected if already ignored:

```text
dist/SnowRunnerModEditor/SnowRunnerModEditor.zip
```

If no output is printed, add this to `.gitignore`:

```gitignore
dist/
```

---

### Task 4: Add Release Documentation

**Files:**
- Create: `docs/release/snowrunner-mod-editor-publish.md`

- [ ] **Step 1: Document one-time setup**

Create `docs/release/snowrunner-mod-editor-publish.md` with:

```markdown
# SnowRunnerModEditor Publish Guide

## One-Time Setup

Install the Developer ID Application certificate and private key into the login keychain.

Verify:

```bash
security find-identity -p codesigning -v
```

Expected:

```text
1) <hash> "Developer ID Application: Your Name (YOUR_TEAM_ID)"
```

Create the notarization profile:

```bash
xcrun notarytool store-credentials YOUR_NOTARY_PROFILE
```

Verify:

```bash
xcrun notarytool history --keychain-profile YOUR_NOTARY_PROFILE
```

## Publish

Run:

```bash
NOTARY_PROFILE=YOUR_NOTARY_PROFILE scripts/publish-snowrunner-mod-editor.sh
```

Output:

```text
dist/SnowRunnerModEditor/SnowRunnerModEditor.zip
dist/SnowRunnerModEditor/SnowRunnerModEditor.zip.sha256
```

## Validation Gates

The release is publishable only if all checks pass:

```bash
codesign --verify --deep --strict --verbose=2 dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
xcrun stapler validate dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
spctl -a -vv dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
```

`spctl` must report an accepted Developer ID app.
```

- [ ] **Step 2: Confirm docs match script paths**

Run:

```bash
rg "YOUR_NOTARY_PROFILE|dist/SnowRunnerModEditor|publish-snowrunner-mod-editor" docs/release/snowrunner-mod-editor-publish.md scripts/publish-snowrunner-mod-editor.sh
```

Expected: every path and profile name appears consistently in both files.

---

### Task 5: First Dry Validation Without Notarization

**Files:**
- No repo changes unless Task 3 exposed a script bug.

- [ ] **Step 1: Validate current signing prerequisites**

Run:

```bash
security find-identity -p codesigning -v
xcrun notarytool history --keychain-profile YOUR_NOTARY_PROFILE
```

Expected:

```text
Developer ID Application identity is present.
notarytool credentials are valid.
```

- [ ] **Step 2: Run the build/sign section through the script**

If notarization credentials are not ready yet, temporarily stop the script before `xcrun notarytool submit` by running commands manually from the script through:

```bash
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
```

Expected:

```text
codesign verification succeeds.
SnowRunnerModEditor.zip exists.
```

- [ ] **Step 3: Inspect signed app state**

Run:

```bash
codesign -dvvv --entitlements :- dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
```

Expected:

```text
Authority=Developer ID Application: ...
TeamIdentifier=YOUR_TEAM_ID
Runtime Version=...
```

The entitlements should include the app's sandbox/file access entitlements and should not include:

```text
com.apple.security.get-task-allow
```

---

### Task 6: First Full Notarization

**Files:**
- No repo changes unless notarization exposes a real project/package issue.

- [ ] **Step 1: Run the publish script**

Run:

```bash
NOTARY_PROFILE=YOUR_NOTARY_PROFILE scripts/publish-snowrunner-mod-editor.sh
```

Expected:

```text
notarytool submit ... Accepted
The staple and validate action worked.
spctl accepted
Published artifact:
dist/SnowRunnerModEditor/SnowRunnerModEditor.zip
dist/SnowRunnerModEditor/SnowRunnerModEditor.zip.sha256
```

- [ ] **Step 2: If notarization is invalid, fetch the log**

Run:

```bash
xcrun notarytool log <submission-id> --keychain-profile YOUR_NOTARY_PROFILE
```

Expected:

```text
JSON log that identifies the exact rejected file or signing issue.
```

Do not change entitlements blindly. Fix the specific file or setting named in the log, then rerun the publish script.

- [ ] **Step 3: Verify packaged zip checksum**

Run:

```bash
shasum -a 256 -c dist/SnowRunnerModEditor/SnowRunnerModEditor.zip.sha256
```

Expected:

```text
dist/SnowRunnerModEditor/SnowRunnerModEditor.zip: OK
```

---

### Task 7: Fresh-Machine Gatekeeper Smoke Test

**Files:**
- No repo changes unless smoke test exposes a launch or entitlement issue.

- [ ] **Step 1: Test quarantine behavior locally**

Run:

```bash
mkdir -p /tmp/srt-release-smoke
ditto -x -k dist/SnowRunnerModEditor/SnowRunnerModEditor.zip /tmp/srt-release-smoke
xattr -w com.apple.quarantine "0081;00000000;Codex;00000000" /tmp/srt-release-smoke/SnowRunnerModEditor.app
spctl -a -vv /tmp/srt-release-smoke/SnowRunnerModEditor.app
```

Expected:

```text
/tmp/srt-release-smoke/SnowRunnerModEditor.app: accepted
source=Notarized Developer ID
```

- [ ] **Step 2: Launch smoke test**

Run:

```bash
open /tmp/srt-release-smoke/SnowRunnerModEditor.app
```

Expected:

```text
The app launches without Gatekeeper warning.
```

Manual check: open a user-selected SnowRunner workspace/mod path and confirm the sandbox file picker/bookmark workflow still works.

---

### Task 8: Commit Release Infrastructure

**Files:**
- Modify: `SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj/project.pbxproj`
- Create: `scripts/publish-snowrunner-mod-editor.sh`
- Create: `docs/release/snowrunner-mod-editor-publish.md`
- Optional Modify: `.gitignore`

- [ ] **Step 1: Review diff**

Run:

```bash
git diff -- SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj/project.pbxproj scripts/publish-snowrunner-mod-editor.sh docs/release/snowrunner-mod-editor-publish.md .gitignore
```

Expected: diff only contains release publishing infrastructure and hardened runtime Release setting.

- [ ] **Step 2: Stage files**

Run:

```bash
git add SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj/project.pbxproj scripts/publish-snowrunner-mod-editor.sh docs/release/snowrunner-mod-editor-publish.md .gitignore
```

- [ ] **Step 3: Commit**

Run:

```bash
git commit -m "build: add notarized release publishing flow"
```

Expected:

```text
[branch <hash>] build: add notarized release publishing flow
```

---

## Self-Review

- Spec coverage: The plan covers local Developer ID prerequisites, hardened runtime, signing, packaging, notarization, stapling, Gatekeeper verification, checksum generation, documentation, and commit.
- Placeholder scan: Unknown private values are discovered from Keychain or entered into Apple tools locally; private credentials are not written into repo files.
- Type/path consistency: Script and documentation use the same app name, project path, scheme, reusable notary profile, and `dist/SnowRunnerModEditor` output path.
