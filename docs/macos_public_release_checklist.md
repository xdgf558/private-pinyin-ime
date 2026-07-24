# macOS Public Release Checklist

This checklist is for publishing the macOS `.pkg` on a personal website.
Unsigned packages are for local testing only and must not be presented as a
public release.

## Current Position

The project can already build a local package:

```bash
bash scripts/package_macos_pkg.sh
```

The `0.1.27` release candidate is signed with Developer ID Application and
Developer ID Installer, accepted by Apple notarization, stapled, and accepted
by Gatekeeper. It adds compact tiered Station Board preferences, retains Writer
V1, and prevents stale development or staging copies from competing with the
installed InputMethodKit server. Its `0.1.22`
predecessor passed an installed-upgrade smoke in TextEdit, Chrome, and Safari;
the current release still needs an installed-upgrade smoke, a clean-user
install/uninstall smoke test, Writer model and strict-privacy validation,
visible horizontal overflow and `1` through `9` candidate interaction checks,
VS Code coverage, and website checksum publication before public distribution.

Current artifact evidence:

- Package: `dist/macos_imk/PrivatePinyin-0.1.27.pkg`
- Size: `14,072,621` bytes
- Notarization submission: `1539ece0-a619-49c7-a77c-82d51543a1ac` (`Accepted`)
- SHA256: `00eca727600f37476e1676207c0307bf685d4883b3b8f6be63cb6e56216d16bf`
- Static release validation on 2026-07-24: trusted Developer ID Installer signature, expanded-payload nested-code signatures, stapled notarization ticket, Gatekeeper `Notarized Developer ID`, usable notary profile, and complete repository public-release preflight.
- Installed-upgrade smoke on 2026-07-19: TextEdit, Chrome, and Safari each committed `nihao -> 你好`; 20 rapid TextEdit commits completed without loss or duplication. The installed app reports `0.1.22 (22)`, and the packaged AI Lite dylib passed activation, secure fallback, and bounded pressure checks.
- Unexecuted on `0.1.27`: installed-upgrade smoke, clean-user install/uninstall, Writer model and strict-privacy checks, visible horizontal overflow plus `1` through `9` candidate selection, and VS Code coverage remain release gates.

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
