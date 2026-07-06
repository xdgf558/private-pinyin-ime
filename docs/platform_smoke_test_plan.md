# Platform Smoke Test Plan

Stage 08 defines the manual platform validation record for release-readiness work. Automated CI can compile and test shared code, but Windows TSF activation, macOS InputMethodKit routing, and iOS keyboard behavior must still be verified on real platform hosts.

## Automated Gates

Record the GitHub Actions run URL for each Stage 08 pull request:

| Gate | Required result | Evidence |
|---|---|---|
| Ubuntu Rust workspace | pass | `cargo fmt`, clippy, tests, C demo, scaffold checks |
| Windows Rust workspace | pass | `windows-2022` runs `cargo test --workspace` |
| Windows TSF compile | pass | `windows-2022` builds `PrivatePinyinTsf.dll` with MSVC/CMake |

## Windows 11 TSF Smoke

Environment:

| Field | Value |
|---|---|
| Tester | |
| Date | |
| Windows version | |
| Architecture | |
| Commit | |
| Build artifact | |

Checklist:

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Build | `scripts/build_windows_tsf.ps1` produces `PrivatePinyinTsf.dll` | | |
| Package | `scripts/package_windows_tsf.ps1` produces zip; MSI if WiX is installed | | |
| Install | Per-user install/register succeeds without admin-only HKCU mismatch | | |
| Enable IME | PrivatePinyin appears in Windows language/input settings | | |
| Notepad composition | Typing `nihao` shows composition and candidate `你好` | | |
| Commit | `Space` commits `你好` | | |
| Cancel | `Esc` clears composition without leaking keys | | |
| Shortcuts | `Ctrl+C`, `Ctrl+V`, `Ctrl+A` pass through while IME is active | | |
| Idle keys | Idle digits, arrows, Backspace, PageUp/PageDown are not swallowed | | |
| Focus cleanup | Start `nihao`, switch to another window, return and type `a`; no stale `nihao` or phantom `nihaoa` composition appears | | |
| Multi-process learning | Use the IME in two apps and select candidates in both; learned selections persist without visible write failures | | |
| Settings UI | Privacy, learning, prediction, clear, and export actions run | | |
| Uninstall | Unregister/uninstall removes the input method from the user account | | |

## macOS InputMethodKit Smoke

Environment:

| Field | Value |
|---|---|
| Tester | |
| Date | |
| macOS version | |
| Architecture | |
| Commit | |
| Build artifact | |

Checklist:

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Build | `scripts/build_macos_imk.sh` produces `dist/macos_imk/PrivatePinyin.app` | | |
| Install | `platform/macos_imk/installer/install-local.sh` installs into Input Methods | | |
| TextEdit composition | Typing `zhongguo` shows composition and candidate `中国` | | |
| Commit | `Space` commits `中国` | | |
| Candidate position | Candidate panel follows the insertion point in TextEdit | | |
| Number selection | Number-key selection does not double-select through `IMKCandidates` | | |
| Shift behavior | Standalone Shift toggles mode; `Shift+A` inserts uppercase text | | |
| App switch cleanup | Start partial composition, switch apps, return, and type again; stale preedit/candidates do not reappear | | |
| Settings menu | Strict privacy toggle, clear, export, and open-settings actions run | | |
| Browser/editor pass | Repeat basic `nihao -> 你好` in Safari, Chrome, and VS Code | | |
| Uninstall | `platform/macos_imk/installer/uninstall-local.sh` removes the app | | |

## iOS Keyboard Smoke

Environment:

| Field | Value |
|---|---|
| Tester | |
| Date | |
| iOS/iPadOS version | |
| Simulator/device | |
| Commit | |
| Build artifact | |

Checklist:

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Build | `scripts/build_ios_keyboard.sh` produces simulator app and keyboard extension | | |
| Install | Container app installs on simulator/device | | |
| Enable keyboard | PrivatePinyin can be added from Settings > General > Keyboard | | |
| Full Access | Full Access remains off by default | | |
| Notes composition | Typing `nihao` shows candidate `你好`; tapping it commits `你好` | | |
| Prediction retention | `jintian -> 今天` keeps prediction candidates such as `天气` after commit | | |
| Self-change callback | If prediction disappears, reset self-text-operation state from `textDidChange` instead of synchronous `defer` | | |
| Globe key | Globe switches to the next input mode | | |
| Password fallback | Password fields force the system keyboard | | |
| Phone fallback | Phone-number fields force the system keyboard | | |
| No network | With Full Access off, there is no network API usage or network prompt | | |

## Blocking Rules

- A failed automated gate blocks merge.
- A failed manual smoke test does not block Stage 08 documentation/CI work unless it is caused by code changed in the same branch.
- Failed manual smoke checks must produce or update an `OPEN_ITEMS` entry before release-readiness work continues.
