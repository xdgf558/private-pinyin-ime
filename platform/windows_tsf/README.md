# Windows TSF Host

This directory contains the Windows Text Services Framework prototype for stage 04.

The Windows host remains thin:

- Convert TSF key events into core `ImeKeyEvent` values.
- Update composition text from core output.
- Render candidates without taking focus.
- Commit selected text through TSF APIs.

## Contents

- `CMakeLists.txt`: MSVC/CMake DLL project for `PrivatePinyinTsf`.
- `src/`: COM class factory, TSF text service, key mapping, candidate window, registration, and Rust C ABI bridge.
- `installer/register-ime.ps1`: calls `regsvr32` for local registration.
- `installer/unregister-ime.ps1`: unregisters the DLL.
- `../../scripts/build_windows_tsf.ps1`: builds the Rust FFI library and the TSF DLL on Windows.

## Build

Run from a Windows Developer PowerShell with Rust, CMake, and Visual Studio 2022 installed:

```powershell
.\scripts\build_windows_tsf.ps1
```

The script builds `private_pinyin_ime_ffi` first, then configures and builds the TSF DLL.
If the build links against `private_pinyin_ime.dll.lib`, copy `target\release\private_pinyin_ime.dll`
next to `PrivatePinyinTsf.dll` before registration.

## Local Registration

```powershell
.\platform\windows_tsf\installer\register-ime.ps1 -DllPath .\build\windows_tsf\Release\PrivatePinyinTsf.dll
```

Then enable the input method from Windows language/input settings. Do not set it as the default input method by editing the registry directly.

Unregister:

```powershell
.\platform\windows_tsf\installer\unregister-ime.ps1 -DllPath .\build\windows_tsf\Release\PrivatePinyinTsf.dll
```

## Manual Smoke Test

1. Open Notepad.
2. Switch to PrivatePinyin IME.
3. Type `nihao`.
4. Confirm the composition shows `nihao` and the candidate window shows `你好`.
5. Press `Space` to commit `你好`.
6. Press `Shift` to toggle Chinese/English mode.
7. Type `nihao`, press `Esc`, and confirm composition is cancelled.

## Stage 04 Limits

- Candidate UI is intentionally simple and non-activating.
- High DPI polishing, installer packaging, code signing, and production registration flow are tracked as open items.
- This prototype should be validated on Windows 11; macOS/Linux CI cannot load TSF DLLs.
