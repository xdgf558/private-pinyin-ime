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
- `installer/PrivatePinyinTsf.wxs`: WiX source for the per-user MSI package.
- `../../scripts/build_windows_tsf.ps1`: builds the Rust FFI library and the TSF DLL on Windows.
- `../../scripts/package_windows_tsf.ps1`: stages installer files and builds a zip bundle; builds an MSI when WiX is installed.

## Build

Run from a Windows Developer PowerShell with Rust, CMake, and Visual Studio 2022 installed:

```powershell
.\scripts\build_windows_tsf.ps1
```

The script builds `private_pinyin_ime_ffi` first, then configures and builds the TSF DLL.
If the build links against `private_pinyin_ime.dll.lib`, copy `target\release\private_pinyin_ime.dll`
next to `PrivatePinyinTsf.dll` before registration.

## Package

Run from a Windows Developer PowerShell with Rust, CMake, Visual Studio 2022, and optional WiX installed:

```powershell
.\scripts\package_windows_tsf.ps1
```

The script writes:

```text
dist\windows_tsf\PrivatePinyin-0.1.10.zip
dist\windows_tsf\PrivatePinyin-0.1.10.msi
```

The `.msi` is generated only when WiX is available. The packaging script supports both WiX v4+ `wix build` and WiX v3 `candle.exe`/`light.exe`. The installer is per-user, installs under `%LOCALAPPDATA%\PrivatePinyin`, and runs TSF registration in the installing user's context so the existing HKCU registration path is visible to that user.

Unsigned internal-test packages can also be built from GitHub Actions:

1. Open the `Windows Unsigned Package` workflow.
2. Run it manually with the desired version, such as `0.1.10`.
3. Download the `PrivatePinyin-Windows-<version>-unsigned` artifact, which contains the `.zip` bundle and `.msi`.

These artifacts are for internal testing only and are expected to show Windows SmartScreen or trust warnings until production signing is configured.

Release-candidate packaging must sign staged binaries and the MSI:

```powershell
.\scripts\package_windows_tsf.ps1 `
  -Version 0.1.10 `
  -SignCertSubject "CN=Example Code Signing Certificate" `
  -TimestampUrl "http://timestamp.digicert.com" `
  -RequireSigning
```

Without `-RequireSigning`, unsigned artifacts are for local testing only.

## Local Registration

```powershell
.\platform\windows_tsf\installer\register-ime.ps1 -DllPath .\build\windows_tsf\Release\PrivatePinyinTsf.dll
```

Then enable the input method from Windows language/input settings. Do not set it as the default input method by editing the registry directly.

Unregister:

```powershell
.\platform\windows_tsf\installer\unregister-ime.ps1 -DllPath .\build\windows_tsf\Release\PrivatePinyinTsf.dll
```

## Settings

```powershell
.\platform\windows_tsf\installer\open-settings.ps1
```

The settings window edits `%LOCALAPPDATA%\PrivatePinyin\settings.json`. Clear/export operations call `private-pinyin-settings.exe`, which is included in packaged builds.

## Manual Smoke Test

Use the shared record template in `../../docs/platform_smoke_test_plan.md` when validating release-readiness behavior.

1. Open Notepad.
2. Switch to PrivatePinyin IME.
3. Type `nihao`.
4. Confirm the composition shows `nihao` and the candidate window shows `你好`.
5. Press `Space` to commit `你好`.
6. Press `Shift` to toggle Chinese/English mode.
7. Type `nihao`, press `Esc`, and confirm composition is cancelled.

## Known Gaps

- Candidate UI is non-activating and now DPI/theme aware, but visual styling should still be smoke-tested in target applications.
- Owner code-signing certificate access and signed-artifact validation are still required before release.
- TSF display attributes and production installer validation are tracked as open items.
- This prototype should be validated on Windows 11; macOS/Linux CI cannot load TSF DLLs.
- GitHub Actions runs Rust workspace tests and compiles the TSF DLL on `windows-2022`, but runtime activation and Notepad behavior still require manual validation.
