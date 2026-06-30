# First GitHub Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the first trustworthy GitHub release for SnowRunnerModEditor with a signed, notarized, validated macOS ZIP and clear release notes.

**Architecture:** Treat the GitHub release as a distribution gate, not just an upload. The release is publishable only after version metadata, package contents, code signature, notarization, stapling, Gatekeeper acceptance, checksum, tag, and release notes all agree.

**Tech Stack:** macOS, Xcode, Developer ID signing, Apple notarytool, Git tags, GitHub Releases.

---

## Current State

- Repository: `https://github.com/Tranz-Zhang/SnowRunnerTools-mac.git`
- Branch: `main`
- Existing artifact: `dist/SnowRunnerModEditor/SnowRunnerModEditor.zip`
- Existing checksum: `5c828be1ed61eb374129fde2fa0c18125f97bef893f3001eb0d779344af2bf93`
- App version in built `Info.plist`: `0.1.0`
- Build number in built `Info.plist`: `1`
- Minimum macOS in built `Info.plist`: `15.3`
- Local tags: none
- Local signing identity status after unsandboxed keychain check: `Developer ID Application: QUAN ZHANG (68VX6HX6SX)`

## Release Blockers

1. The current built app failed:

   ```bash
   codesign --verify --deep --strict --verbose=2 dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
   ```

   Observed:

   ```text
   invalid signature (code or signature have been modified)
   In architecture: arm64
   ```

2. The current ZIP contains AppleDouble sidecar files such as `._CodeResources`, generated from extended attributes during packaging.

3. The release version needs a deliberate decision: keep `v1.0.0`, or change the app marketing version to `0.1.0` for a first public release.

## Files

- Modify: `scripts/publish-snowrunner-mod-editor.sh`
  - Ensure public ZIP creation does not include AppleDouble sidecar files.
- Modify if choosing `v0.1.0`: `SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj/project.pbxproj`
  - Change `MARKETING_VERSION` for the app target from `1.0` to `0.1.0`.
- Modify if needed: `README.md`
  - Add a download/install section after the release URL exists.
- Create at release time: Git tag `v0.1.0` or `v1.0.0`
- Upload at release time:
  - `dist/SnowRunnerModEditor/SnowRunnerModEditor.zip`
  - `dist/SnowRunnerModEditor/SnowRunnerModEditor.zip.sha256`

---

### Task 1: Decide Release Version

- [x] **Step 1: Pick the version**

  Recommendation:

  ```text
  v0.1.0
  ```

  Why: this is the first public publish, the app likely still has compatibility limits, and `0.1.0` sets correct user expectations.

- [x] **Step 2: If choosing `v0.1.0`, update Xcode marketing version**

  File:

  ```text
  SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj/project.pbxproj
  ```

  Replace app target `MARKETING_VERSION = 1.0;` entries with:

  ```text
  MARKETING_VERSION = 0.1.0;
  ```

  Leave `CURRENT_PROJECT_VERSION = 1;` unchanged for the first build.

- [x] **Step 3: Verify the build settings**

  Run:

  ```bash
  xcodebuild -project SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj -scheme SnowRunnerModEditor -showBuildSettings | rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER|MACOSX_DEPLOYMENT_TARGET'
  ```

  Expected if choosing `v0.1.0`:

  ```text
  MARKETING_VERSION = 0.1.0
  CURRENT_PROJECT_VERSION = 1
  PRODUCT_BUNDLE_IDENTIFIER = com.bychance.SnowRunnerModEditor
  ```

---

### Task 2: Fix Public ZIP Package Hygiene

- [x] **Step 1: Update publish script ZIP creation**

  File:

  ```text
  scripts/publish-snowrunner-mod-editor.sh
  ```

  Change the final public ZIP command to suppress AppleDouble metadata:

  ```bash
  ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"
  ```

  Keep the notary submission ZIP unchanged unless notarization also shows metadata-related problems.

  Local verification: a fresh temp ZIP created with `--norsrc` contained no `._*` entries.

- [x] **Step 2: Rebuild public artifact**

  Run on a machine with the Developer ID identity installed:

  ```bash
  DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (YOUR_TEAM_ID)" \
    NOTARY_PROFILE=YOUR_NOTARY_PROFILE \
    scripts/publish-snowrunner-mod-editor.sh
  ```

  Expected:

  ```text
  Published artifact:
  dist/SnowRunnerModEditor/SnowRunnerModEditor.zip
  dist/SnowRunnerModEditor/SnowRunnerModEditor.zip.sha256
  ```

- [x] **Step 3: Verify ZIP does not contain sidecar files**

  Run:

  ```bash
  unzip -l dist/SnowRunnerModEditor/SnowRunnerModEditor.zip | rg '(^|/)\._'
  ```

  Expected:

  ```text
  no output
  ```

---

### Task 3: Rebuild and Validate Signing

- [x] **Step 1: Confirm Developer ID identity exists**

  Run:

  ```bash
  security find-identity -p codesigning -v
  ```

  Expected:

  ```text
  Developer ID Application: ...
  ```

  Current status on 2026-06-30 after normal keychain access:

  ```text
  Developer ID Application: QUAN ZHANG (68VX6HX6SX)
  ```

- [x] **Step 2: Rebuild, sign, notarize, staple, and package**

  Run:

  ```bash
  NOTARY_PROFILE=YOUR_NOTARY_PROFILE scripts/publish-snowrunner-mod-editor.sh
  ```

  If more than one Developer ID Application identity exists, run with `DEVELOPER_ID_APPLICATION=...`.

- [x] **Step 3: Validate code signature**

  Run:

  ```bash
  codesign --verify --deep --strict --verbose=2 dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
  ```

  Expected:

  ```text
  valid on disk
  satisfies its Designated Requirement
  ```

- [x] **Step 4: Validate stapled notarization ticket**

  Run:

  ```bash
  xcrun stapler validate dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
  ```

  Expected:

  ```text
  The validate action worked!
  ```

- [x] **Step 5: Validate Gatekeeper acceptance**

  Run:

  ```bash
  spctl -a -vv dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
  ```

  Expected:

  ```text
  accepted
  source=Notarized Developer ID
  ```

- [x] **Step 6: Verify release checksum**

  Run:

  ```bash
  shasum -a 256 dist/SnowRunnerModEditor/SnowRunnerModEditor.zip
  cat dist/SnowRunnerModEditor/SnowRunnerModEditor.zip.sha256
  ```

  Expected: both commands report the same SHA-256 hash.

  Verified checksum:

  ```text
  5c828be1ed61eb374129fde2fa0c18125f97bef893f3001eb0d779344af2bf93
  ```

  Verified notarization submission:

  ```text
  status=Accepted
  id=fa7ef187-3250-4b1d-8c4e-cceb1efb2f6c
  ```

---

### Task 4: Prepare Release Notes

- [ ] **Step 1: Draft release notes**

  Use this content as the first release body:

  ```markdown
  # SnowRunnerModEditor v0.1.0

  First public macOS release of SnowRunnerModEditor.

  ## Requirements

  - macOS 15.3 or later
  - SnowRunner PC `initial.pak`
  - Compatible SnowRunner mod `.pak` files

  ## What It Does

  - Creates a workspace from an original SnowRunner `initial.pak`
  - Imports mod `.pak` files into that workspace
  - Lets you enable, disable, and remove imported mods
  - Shows mod conflict details before building
  - Builds a verified output `initial.pak`
  - Writes a build report for review

  ## Install

  1. Download `SnowRunnerModEditor.zip`.
  2. Unzip it.
  3. Move `SnowRunnerModEditor.app` to `/Applications`.
  4. Open the app.

  ## Safety Notes

  SnowRunnerModEditor does not write directly into your SnowRunner installation. It writes generated files inside the selected workspace. Back up game files before manually replacing anything in the SnowRunner install directory.

  ## Known Limits

  - Focused on supported PC mod PAK layouts.
  - Some mod structures may fail to build or require manual conflict review.
  - No automatic game installation step yet.

  ## Checksum

  ```text
  SHA256_PLACEHOLDER  SnowRunnerModEditor.zip
  ```
  ```

- [ ] **Step 2: Replace checksum placeholder**

  Run:

  ```bash
  cat dist/SnowRunnerModEditor/SnowRunnerModEditor.zip.sha256
  ```

  Replace `SHA256_PLACEHOLDER` with the hash from the generated `.sha256` file.

---

### Task 5: Tag and Publish GitHub Release

- [ ] **Step 1: Confirm repository is clean**

  Run:

  ```bash
  git status --short --branch
  ```

  Expected:

  ```text
  ## main...origin/main
  ```

- [ ] **Step 2: Commit release-preparation changes**

  If Task 1 or Task 2 changed files, run:

  ```bash
  git add SnowRunnerModEditor/SnowRunnerModEditor.xcodeproj/project.pbxproj scripts/publish-snowrunner-mod-editor.sh
  git commit -m "Prepare first SnowRunnerModEditor release"
  git push origin main
  ```

- [ ] **Step 3: Create version tag**

  Run:

  ```bash
  git tag -a v0.1.0 -m "SnowRunnerModEditor v0.1.0"
  git push origin v0.1.0
  ```

- [ ] **Step 4: Create GitHub release**

  Use GitHub Releases for:

  ```text
  Repository: Tranz-Zhang/SnowRunnerTools-mac
  Tag: v0.1.0
  Title: SnowRunnerModEditor v0.1.0
  Assets:
    dist/SnowRunnerModEditor/SnowRunnerModEditor.zip
    dist/SnowRunnerModEditor/SnowRunnerModEditor.zip.sha256
  ```

- [ ] **Step 5: Verify public download**

  After publishing, download the ZIP from the GitHub release page and run:

  ```bash
  shasum -a 256 SnowRunnerModEditor.zip
  ```

  Expected: hash matches the release notes and `.sha256` asset.

---

## Execution Order

1. Decide `v0.1.0` versus `v1.0.0`.
2. Patch package hygiene in `scripts/publish-snowrunner-mod-editor.sh`.
3. Patch app version if choosing `v0.1.0`.
4. Rebuild on a machine with Developer ID signing identity installed.
5. Validate signature, notarization, Gatekeeper, ZIP contents, and checksum.
6. Commit release-preparation changes.
7. Tag the release.
8. Create GitHub release and upload assets.
9. Verify the public download checksum.

## First Task To Execute

Start with Task 1. The version decision affects the app metadata, tag name, release title, and release notes. The shortest clean path is:

```text
Use v0.1.0 for the first public release.
```
