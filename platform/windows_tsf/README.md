# Windows TSF Host

This directory contains the Windows Text Services Framework prototype.

The Windows host remains thin:

- Convert TSF key events into core `ImeKeyEvent` values.
- Update composition text from core output.
- Render candidates without taking focus.
- Commit selected text through TSF APIs.
- Load a settings snapshot from `%LOCALAPPDATA%\PrivatePinyin\settings.json`.

## Contents

- `CMakeLists.txt`: MSVC/CMake DLL project for `PrivatePinyinTsf`.
- `src/`: COM class factory, TSF text service, key mapping, candidate window, registration, and Rust C ABI bridge.
- `installer/register-ime.ps1`: calls `regsvr32` for local registration.
- `installer/unregister-ime.ps1`: unregisters the DLL.
- `installer/open-settings.ps1`: opens a local settings window for privacy mode, user learning, prediction, lexicon clear, and lexicon export.
- `installer/open-onboarding.ps1`: opens the post-install setup guide with language-settings and preferences shortcuts.
- `installer/ReleaseNotes.zh-Hans.txt`: Simplified Chinese release notes installed with the package.
- `installer/PrivatePinyinTsf.wxs`: WiX source for the per-user MSI package.
- `installer/PrivatePinyinTsf.nsi`: NSIS source for the per-user EXE installer.
- `installer/PrivatePinyinInstaller.ico`: cat-brand installer icon used by the EXE, uninstaller, and Start Menu shortcuts.
- `../../scripts/build_windows_tsf.ps1`: builds the Rust FFI library and the TSF DLL on Windows.
- `../../scripts/package_windows_tsf.ps1`: stages installer files and builds a zip bundle; builds an MSI when WiX is installed.

## Build

Run from a Windows Developer PowerShell with Rust, CMake, and Visual Studio 2022 installed:

```powershell
.\scripts\build_windows_tsf.ps1
```

The script builds `private_pinyin_ime_ffi` first, then configures and builds the TSF DLL.
Pass `-Architecture x64 -RustTarget x86_64-pc-windows-msvc` for 64-bit hosts or
`-Architecture Win32 -RustTarget i686-pc-windows-msvc` for 32-bit applications.

## Package

Run from a Windows Developer PowerShell with Rust, CMake, Visual Studio 2022, and optional NSIS/WiX installed:

```powershell
.\scripts\package_windows_tsf.ps1
```

The script writes:

```text
dist\windows_tsf\PrivatePinyin-0.1.23.zip
dist\windows_tsf\PrivatePinyin-0.1.23-setup.exe
dist\windows_tsf\PrivatePinyin-0.1.23.msi
```

The `.exe` is generated when NSIS is available. It is the preferred unsigned
internal-test installer because it does not depend on Windows Installer MSI
custom actions, requests administrator rights for TSF profile registration,
calls the 64-bit and 32-bit `regsvr32.exe` explicitly, and opens a setup guide after
installation without showing a PowerShell console. Each NSIS release uses an
`app-<version>` runtime directory with separate `x64` and `x86` TSF/FFI DLLs,
so 64-bit applications and 32-bit applications such as QQ can both load the
input method. An upgrade never overwrites DLLs still
loaded by Windows. Older runtime files are removed after their processes exit
or at the next restart. The `.msi` is generated only when WiX is available.
The packaging script supports both WiX v4+ `wix build` and WiX v3
`candle.exe`/`light.exe`. Both installers are per-user, install under
`%LOCALAPPDATA%\PrivatePinyin`, and run TSF registration in the installing
user's context so the existing HKCU registration path is visible to that user.

Unsigned internal-test packages can also be built from GitHub Actions:

1. Open the `Windows Unsigned Package` workflow.
2. Run it manually with the desired version, such as `0.1.23`.
3. Download the `PrivatePinyin-Windows-<version>-unsigned` artifact, which contains the `.zip` bundle, `.exe` setup installer, and `.msi`.

These artifacts are for internal testing only and are expected to show Windows SmartScreen or trust warnings until production signing is configured.

Packages also contain `PrivatePinyinAIHelper.exe`, the dormant AI-09 process
boundary for future optional Writer features. It is not loaded by normal TSF
typing or AI Lite ranking. The host-side skeleton creates a random unidirectional
request/response named-pipe pair with protected current-user-only DACLs, rejects
remote clients, and requires a random per-launch authentication token before
accepting health or work frames.

Release-candidate packaging must sign staged binaries and the MSI:

```powershell
.\scripts\package_windows_tsf.ps1 `
  -Version 0.1.23 `
  -SignCertSubject "CN=Example Code Signing Certificate" `
  -TimestampUrl "http://timestamp.digicert.com" `
  -RequireSigning
```

Without `-RequireSigning`, unsigned artifacts are for local testing only.

## Local Registration

Build both variants, place them under one package root as `x64` and `x86`, then run:

```powershell
.\register-ime.ps1 -InstallRoot .
```

Then enable the input method from Windows language/input settings. Do not set it as the default input method by editing the registry directly.

Unregister:

```powershell
.\unregister-ime.ps1 -InstallRoot .
```

## Settings

```powershell
.\platform\windows_tsf\installer\open-settings.ps1
```

The settings window edits `%LOCALAPPDATA%\PrivatePinyin\settings.json`. Clear/export operations call `private-pinyin-settings.exe`, which is included in packaged builds.

## Post-install guide

After a successful interactive NSIS `.exe` installation, closing the installer
automatically launches:

```powershell
.\platform\windows_tsf\installer\open-onboarding.ps1
```

Silent installations do not launch the guide.

The guide links to Windows language settings, links to the preferences window,
detects whether both the x64 and x86 TSF components are registered, detects
whether the TSF profile is already enabled, and offers a one-click action
that appends `猫栈拼音` to the current user's Simplified Chinese input-method list.
It preserves existing languages, keyboards, and the default input method. After
setup, it can open Notepad for a `Win+Space` typing test. The MSI path does not
yet launch the onboarding UI; use the `.exe` installer when onboarding matters.

Both PowerShell UI scripts are stored with a UTF-8 BOM for Windows PowerShell 5.1.
The package script also forces NSIS to read its source as UTF-8, and the TSF DLL
is compiled with MSVC `/utf-8`; these settings keep the installer and registered
input-method display name from being decoded through the build machine's ANSI
code page.

## Manual Smoke Test

Use the shared record template in `../../docs/platform_smoke_test_plan.md` when validating release-readiness behavior.

1. Open Notepad.
2. Switch to `猫栈拼音`.
3. Type `nihao`.
4. Confirm the composition shows `nihao` and the candidate window shows `你好`.
5. Press `Space` to commit `你好`.
6. Press `Shift` to toggle Chinese/English mode.
7. Type `nihao`, press `Esc`, and confirm composition is cancelled.
8. Open QQ, focus a chat input box, switch to `猫栈拼音`, and repeat the `nihao` test.
9. Run `.\scripts\test_windows_ai_helper.ps1` after the x64 build and confirm
   authentication, health, cancellation, forced helper termination, restart,
   and graceful shutdown all pass.

## Known Gaps

- Candidate UI is non-activating and now DPI/theme aware, but visual styling should still be smoke-tested in target applications.
- Owner code-signing certificate access and signed-artifact validation are still required before release.
- TSF display attributes and production installer validation are tracked as open items.
- This prototype should be validated on Windows 11; macOS/Linux CI cannot load TSF DLLs.
- GitHub Actions runs Rust workspace tests and compiles the TSF DLL on `windows-2022`, but runtime activation and Notepad behavior still require manual validation.
