# SnowRunnerModEditor Publish Guide

## One-Time Setup

Install the Developer ID Application certificate and private key into the login keychain.

Verify:

```bash
security find-identity -p codesigning -v
```

Expected:

```text
"Developer ID Application: Your Name (YOUR_TEAM_ID)"
```

Create the reusable notarization profile:

```bash
xcrun notarytool store-credentials YOUR_NOTARY_PROFILE \
  --key "$HOME/.config/apple/appstoreconnect/keys/AuthKey_YOUR_KEY_ID.p8" \
  --key-id YOUR_KEY_ID \
  --issuer "YOUR_ISSUER_UUID"
```

Verify:

```bash
xcrun notarytool history --keychain-profile YOUR_NOTARY_PROFILE
```

`No submission history.` is a valid result.

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

If the Mac has more than one Developer ID Application identity installed, choose one explicitly:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (YOUR_TEAM_ID)" \
  NOTARY_PROFILE=YOUR_NOTARY_PROFILE \
  scripts/publish-snowrunner-mod-editor.sh
```

## Validation Gates

The release is publishable only if all checks pass:

```bash
codesign --verify --deep --strict --verbose=2 dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
xcrun stapler validate dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
spctl -a -vv dist/SnowRunnerModEditor/build/Build/Products/Release/SnowRunnerModEditor.app
```

`spctl` must report an accepted notarized Developer ID app.

The signed Release entitlements must not contain:

```text
com.apple.security.get-task-allow
```

The Developer ID signature must include a secure timestamp. Apple notarization rejects Developer ID apps signed with `--timestamp=none`, even when the certificate, hardened runtime, and entitlements are otherwise valid.

The public ZIP must be created after stapling. A ZIP created before `xcrun stapler staple` can still pass online Gatekeeper checks, but it does not carry the offline notarization ticket.

## Secret Handling

Keep the App Store Connect `.p8` key outside the repository:

```text
~/.config/apple/appstoreconnect/keys/AuthKey_YOUR_KEY_ID.p8
```

Do not commit the `.p8` file. Keep a backup in a password manager or encrypted vault because Apple only allows downloading an API private key once.
