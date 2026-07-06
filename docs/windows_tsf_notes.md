# Windows TSF Notes

Stage 4 implements the Windows Text Services Framework host prototype.

## Target

- Windows 11.
- C++ 20.
- TSF in-process text service DLL.
- Calls the shared Rust core through the C ABI.
- Local `regsvr32` registration scripts for development builds.
- A simple non-activating candidate window.

## Required References

- Microsoft Text Services Framework overview: https://learn.microsoft.com/en-us/windows/win32/tsf/text-services-framework
- `ITfTextInputProcessorEx`: https://learn.microsoft.com/en-us/windows/win32/api/msctf/nn-msctf-itftextinputprocessorex
- `ITfKeyEventSink`: https://learn.microsoft.com/en-us/windows/win32/api/msctf/nn-msctf-itfkeyeventsink

## Constraints

- Do not directly set the system default input method through registry writes.
- Do not access the network by default.
- Candidate windows must not take focus.

## Implemented In Stage 04

- `ITfTextInputProcessorEx` activation/deactivation.
- `ITfKeyEventSink` key interception through `ITfKeystrokeMgr::AdviseKeyEventSink`.
- `ITfCompositionSink` composition lifetime callback.
- C ABI bridge from Windows key events to `ime_session_feed_key`.
- TSF edit sessions for composition text and committed text.
- Candidate popup that shows numbered candidates without taking focus.
- HKCU COM registration and TSF profile registration hooks.

## Manual Windows Smoke Test

1. Build with `.\scripts\build_windows_tsf.ps1`.
2. Register with `.\platform\windows_tsf\installer\register-ime.ps1`.
3. Enable the input method in Windows input settings.
4. In Notepad, type `nihao`, press `Space`, and confirm `你好` commits.
5. Press `Shift` to toggle Chinese/English.
6. Type `nihao`, press `Esc`, and confirm composition clears.
