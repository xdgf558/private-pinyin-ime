# macOS Public Release Checklist

This checklist is for publishing the macOS `.pkg` on a personal website.
Unsigned packages are for local testing only and must not be presented as a
public release.

## Current Position

The project can already build a local package:

```bash
bash scripts/package_macos_pkg.sh
```

The `0.1.17` release candidate is signed with Developer ID Application and
Developer ID Installer, accepted by Apple notarization, stapled, and accepted
by Gatekeeper. It still needs a clean-user install/upgrade/uninstall smoke test
including immediate post-install input-source activation, plus four-host
horizontal-candidate interaction validation and website checksum publication
before public distribution.

Current artifact evidence:

- Package: `dist/macos_imk/PrivatePinyin-0.1.17.pkg`
- Notarization submission: `90edbce9-e28f-40a9-9f98-71830dad8839` (`Accepted`)
- SHA256: `43bcec63708a16098dec51a6a0d7533795a0cf7b7d459040eb1e9abf449bdb79`
- Previous installed-upgrade smoke: `0.1.15` passed on 2026-07-11; the `0.1.17` horizontal layout, stepping, overflow, `1` through `9` selection, and bounded trigram learning still require TextEdit/Safari/Chrome/VS Code validation before release.

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

UPDATE-01 can notify users about a release after they opt in. UPDATE-02 can
download and validate the package after explicit consent, but macOS Installer
still owns authorization and installation:

1. Bump the version, for example `0.1.9 -> 0.1.10`.
2. Build, sign, notarize, and staple the new `.pkg`.
3. Run `bash scripts/check_macos_public_release.sh`.
4. Update the website download link, version, date, SHA256 checksum, and
   changelog.
5. Publish the fixed-host `stable.json` manifest only after the release page and
   immutable pkg are live and their byte size and SHA-256 are verified.
6. From the installed previous version, choose `下载并验证`; confirm download
   progress, exact-size/SHA-256 checks, pinned Developer ID Installer Team ID,
   Gatekeeper notarization, and the second handoff confirmation.
7. Confirm Apple's system Installer opens visibly and requests authorization;
   the input method must not invoke a silent installer or provide credentials.
8. Complete the install over the old version and verify the new UI-only helper
   detects the pre-install input-method process. Confirm `重新加载猫栈拼音` closes
   only that old process and leaves open applications untouched.
9. Switch to another input source and back; confirm the new version is active
   without logout or restart. If normal exit is deliberately prevented, confirm
   the helper gives logout/login guidance without performing it automatically.

The app must pass `scripts/check_update01_sources.sh` and
`scripts/check_update02_sources.sh`, and `scripts/check_update03_sources.sh`.
Automatic checks remain off by default,
strict privacy pauses checks and cancels active package transfers, and package
handoff and process refresh must remain explicit. Follow
`docs/macos_update_strategy.md` for the complete update contract.
