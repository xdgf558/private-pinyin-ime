# Release Distribution Plan

Stage 12 turns the prototype build outputs into auditable release-candidate
inputs. It does not claim a public release is ready without owner-provided
licenses, signing identities, provisioning profiles, notarization credentials,
and platform smoke-test evidence.

## Release Gates

Every public release candidate must have:

- Final project license selected and committed.
- Production lexicon source, license, version, and transformation manifest
  approved.
- `cargo fmt --check`, clippy, `cargo test --workspace`, C ABI demo, and all
  stage scaffold checks passing.
- Windows `windows-2022` CI passing.
- Windows 11 TSF smoke-test record completed.
- macOS IMK smoke-test record completed.
- iOS keyboard smoke-test record completed, including `RequestsOpenAccess=false`
  App Group behavior.
- No telemetry SDKs, account system, network API use, or raw-input logging added.
- Version number recorded consistently in release artifacts and release notes.

## Windows Release

Artifacts:

- `dist/windows_tsf/PrivatePinyin-<version>.zip`
- `dist/windows_tsf/PrivatePinyin-<version>-setup.exe` when NSIS is installed
- `dist/windows_tsf/PrivatePinyin-<version>.msi` when WiX is installed

Signing:

```powershell
.\scripts\package_windows_tsf.ps1 `
  -Version 0.1.12 `
  -SignCertSubject "CN=Example Code Signing Certificate" `
  -TimestampUrl "http://timestamp.digicert.com" `
  -RequireSigning
```

The package script signs staged `.dll` and `.exe` files with SignTool, signs
staged `.ps1` installer/settings scripts with `Set-AuthenticodeSignature`, and
signs the NSIS setup EXE and MSI after the installer toolchains build them.
`-RequireSigning` must be used for release candidates. Without it, unsigned
prototype artifacts are allowed for local testing only.

Unsigned internal-test packages can be generated without a signing certificate
through the manual `Windows Unsigned Package` GitHub Actions workflow. The
workflow runs on `windows-2022`, installs NSIS and WiX, calls
`scripts/package_windows_tsf.ps1`, and uploads a
`PrivatePinyin-Windows-<version>-unsigned` artifact containing the `.zip` bundle,
preferred `.exe` setup installer, and `.msi`. These artifacts are not release
candidates and may trigger Windows trust warnings.

Manual gates:

- Install the EXE setup as a normal user on Windows 11.
- Confirm the finish-page setup guide opens and can launch Windows language
  settings.
- Confirm `猫栈拼音` appears in language/input settings.
- Smoke-test Notepad and at least one browser/editor.
- Uninstall and confirm the TSF profile is removed.

## macOS Release

Artifacts:

- `dist/macos_imk/PrivatePinyin.app`
- `dist/macos_imk/PrivatePinyin-<version>.pkg`

Signing and notarization:

```bash
PRIVATE_PINYIN_MAC_APP_SIGN_IDENTITY="Developer ID Application: Example" \
PRIVATE_PINYIN_MAC_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Example" \
PRIVATE_PINYIN_NOTARY_PROFILE="private-pinyin-notary" \
bash scripts/package_macos_pkg.sh
```

The app build uses Developer ID signing and hardened runtime when an app signing
identity is provided. The package script signs the pkg when an installer identity
is provided and submits/staples notarization when a notarytool keychain profile
is provided. Unsigned/ad-hoc artifacts are local testing only.

Manual gates:

- Install the signed and notarized pkg on a clean macOS user account.
- Run `bash scripts/check_macos_public_release.sh` and publish the reported
  SHA256 checksum with the website download.
- Confirm the input method can be added from System Settings.
- Smoke-test TextEdit, Safari, Chrome, and VS Code.
- Confirm uninstall guidance removes the app bundle and no stale process keeps
  an old binary loaded.

## iOS Release

The detailed iOS release-preparation sequence is tracked in
`docs/ios_release_stage_plan.md`:

- Stage 14: signing and App Group configuration.
- Stage 15: simulator/local development build and basic smoke.
- Stage 16: TestFlight archive and upload.
- Stage 17: device keyboard behavior and privacy closure.
- Stage 18: App Store release preparation.

Artifacts:

- `dist/ios/PrivatePinyin.xcarchive`
- App Store Connect upload or exported `.ipa`, depending on the supplied export
  options.

Build:

```bash
. platform/ios_keyboard/AppStoreMetadata/Signing.env
bash scripts/package_ios_app_store.sh
```

Use `ExportOptions.plist.template` for local App Store export, or
`ExportOptions.upload.plist.template` for TestFlight upload. Upload mode
requires `PRIVATE_PINYIN_IOS_ASC_KEY_PATH`,
`PRIVATE_PINYIN_IOS_ASC_KEY_ID`, and
`PRIVATE_PINYIN_IOS_ASC_ISSUER_ID` in `Signing.env`. The package script writes
`dist/ios/package_summary.txt`; copy the App Store Connect build number and
processing state into `docs/ios_testflight_upload_record.md` after upload.

Owner-provided App Store Connect metadata, bundle IDs, provisioning profiles,
and App Group capability configuration are required. Stage 14 makes
`PRIVATE_PINYIN_IOS_APP_BUNDLE_ID`,
`PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID`, and
`PRIVATE_PINYIN_IOS_APP_GROUP_ID` explicit release inputs and checks that the
export-options plist contains both provisioning profile mappings. Keep
`RequestsOpenAccess=false` unless the owner explicitly decides that iOS learning
requires Full Access after real-device validation.

Manual gates:

- Install via TestFlight.
- Verify Notes/Safari/password-field behavior.
- Verify Globe-key behavior.
- Verify whether App Group storage is available without Full Access; if not,
  learning must remain disabled and typing must continue through built-in
  defaults.

## Automatic Update Strategy

Initial public releases should not add an in-app auto-updater.

- Windows: distribute signed MSI/zip through a release page first; revisit MSIX
  or App Installer after TSF registration and update semantics are validated.
- macOS: use signed/notarized pkg first; revisit Sparkle after Developer ID
  signing, update signing keys, rollback policy, and privacy copy are ready.
- iOS: use App Store/TestFlight updates only.

This keeps update behavior platform-native until release signing and smoke-test
evidence exist.
