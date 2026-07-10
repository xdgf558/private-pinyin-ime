# macOS Public Release Checklist

This checklist is for publishing the macOS `.pkg` on a personal website.
Unsigned packages are for local testing only and must not be presented as a
public release.

## Current Position

The project can already build a local package:

```bash
bash scripts/package_macos_pkg.sh
```

The `0.1.13` release candidate is signed with Developer ID Application and
Developer ID Installer, accepted by Apple notarization, stapled, and accepted
by Gatekeeper. It still needs a clean-user install/upgrade/uninstall smoke test
and website checksum publication before public distribution.

Current artifact evidence:

- Package: `dist/macos_imk/PrivatePinyin-0.1.13.pkg`
- Notarization submission: `edc25310-8b8f-4558-84c3-706bcad40dbb` (`Accepted`)
- SHA256: `9c17738382c030a87db4208ba456e1abcf73545af85bb63a451ea8147ca1451e`

## One-Time Owner Setup

1. Join the Apple Developer Program.
2. Create and install these certificates in Keychain Access:
   - `Developer ID Application`
   - `Developer ID Installer`
3. Create a notarytool keychain profile:

```bash
xcrun notarytool store-credentials private-pinyin-notary \
  --apple-id "owner@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"
```

4. Confirm the local machine can see the credentials:

```bash
security find-identity -v -p codesigning
xcrun notarytool history --keychain-profile private-pinyin-notary
```

## Build A Public macOS Package

Set the exact identity names from `security find-identity`:

```bash
PRIVATE_PINYIN_MAC_APP_SIGN_IDENTITY="Developer ID Application: Owner Name (TEAMID1234)" \
PRIVATE_PINYIN_MAC_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Owner Name (TEAMID1234)" \
PRIVATE_PINYIN_NOTARY_PROFILE="private-pinyin-notary" \
bash scripts/package_macos_pkg.sh
```

Then run the release preflight:

```bash
bash scripts/check_macos_public_release.sh
```

The preflight must pass before uploading the package to a website. It verifies
the Developer ID identities, package signature, Gatekeeper install assessment,
stapled notarization ticket, notarytool profile, and SHA256 checksum.

## Website Download Page

The download page should show:

- Product name: `猫栈拼音`
- Version, release date, and target macOS version.
- A direct `.pkg` download link.
- SHA256 checksum from `scripts/check_macos_public_release.sh`.
- Short install steps: install the pkg, log out and log back in, then add
  `猫栈拼音` in System Settings > Keyboard > Input Sources.
- User-facing install copy must say `猫栈拼音`, not `PrivatePinyin`.
- Architecture copy must match the signed package actually published; do not
  label the download as Intel-compatible until an x86_64/universal package is
  built and verified.
- Privacy copy: local computation, no account, no telemetry, no cloud sync, and
  no raw-input logging.
- Third-party data notice link to `THIRD_PARTY_NOTICES.md`.
- Changelog link for the version.

Do not upload `PrivatePinyin-<version>-unsigned.pkg` or any package that fails
`check_macos_public_release.sh`.

## Manual Smoke Test

Before publishing, install the signed and notarized package on a clean macOS
user account and record:

- `猫栈拼音` appears exactly once in System Settings.
- The input method can be added and selected.
- TextEdit can commit `nihao -> 你好`.
- A browser text field can type and commit candidates.
- The menu entry `偏好设置...` opens the redesigned preferences window.
- Strict privacy mode can be toggled.
- Uninstall guidance removes `/Library/Input Methods/PrivatePinyin.app`.

## Update Flow

Initial public releases use manual updates:

1. Bump the version, for example `0.1.9 -> 0.1.10`.
2. Build, sign, notarize, and staple the new `.pkg`.
3. Run `bash scripts/check_macos_public_release.sh`.
4. Update the website download link, version, date, SHA256 checksum, and
   changelog.
5. Users install the new pkg over the old version, then log out and log back in
   if macOS keeps the old input-method process cached.

Do not add Sparkle or another auto-updater until Developer ID signing,
notarization, rollback policy, update-signing keys, and input-method upgrade
smoke tests are proven.
