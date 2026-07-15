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
| Package | `scripts/package_windows_tsf.ps1` produces zip, EXE setup when NSIS is installed, and MSI when WiX is installed | | |
| Install | EXE per-user install/register succeeds without admin-only HKCU mismatch or 32-bit regsvr32 redirection | | |
| Post-install guide | EXE finish page can open the setup guide, and the guide opens Windows language settings and preferences | | |
| Enable IME | `猫栈拼音` appears in Windows language/input settings | | |
| Notepad composition | Typing `nihao` shows composition and candidate `你好` | | |
| Continuous pinyin | Typing a longer sentence pinyin such as `wojintianxiangquchifan` can produce a multi-word candidate when the segments exist in the lexicon | | |
| Initials shorthand | Typing shorthand initials such as `nh` produces phrase candidates such as `你好` | | |
| Chinese punctuation | Chinese mode commits full-width punctuation such as `，` and `。` | | |
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
| Package install | `scripts/package_macos_pkg.sh` pkg installs into `/Library/Input Methods` | | |
| Post-install onboarding | Fresh pkg install launches a new UI-only helper and opens the setup guide with an Open Keyboard Settings button; the helper does not create a second IMK server | | |
| Upgrade process detection | With 猫栈拼音 already active, upgrade install shows `猫栈拼音已更新` and detects only the pre-install same-bundle process | | Keep TextEdit, Safari, Chrome, and VS Code open while testing |
| Consent and app isolation | Before clicking reload, typing continues through the old process; after clicking, no browser, editor, document, or unrelated process closes | | |
| Successful refresh | `重新加载猫栈拼音` completes, switching to another input source and back activates the new version, and the guide says no logout or restart is required | | |
| Refresh fallback | If normal exit is deliberately prevented in a controlled test, guidance asks the tester to save work and logout/login; it does not force-kill, log out, or restart macOS | | Source policy and offline tests must pass even when this path is not induced manually |
| Input source discovery | PrivatePinyin appears exactly once under Chinese/Simplified Chinese input sources after installing the actual `.pkg`; re-open System Settings or logout/login if the list is cached | | TIS keys changed in macOS onboarding work: mode `TISInputSourceID`, top-level `TISInputSourceID`, and `smSimpChinese` must be revalidated. `tsInputModeDefaultStateKey` must remain `false`; setting it to `true` can make third-party modes disappear from the add-input-source selector before the user enables them |
| Input source icon/name | System Settings, the input menu, and the menu bar show the new template icon and Chinese display name `猫栈拼音` in a Simplified Chinese user session | | Revalidate after version bumps, logout/login, or TIS cache cleanup; template icon should adapt to light/dark menu bar states |
| Consecutive upgrade input-source dedupe | After consecutive upgrade installs across two versions, System Settings and the menu bar input menu show at most one PrivatePinyin entry | | Regression for stale `AppleEnabledInputSources` / `AppleEnabledThirdPartyInputSources` records created by older default-enabled builds or manual `TISEnableInputSource` diagnostics |
| Enable input source | PrivatePinyin can be added and selected from the menu bar input menu | | |
| TextEdit composition | Typing `nihao` shows composition and candidate `你好`; typing `zhongguo` shows candidate `中国` | | |
| Commit | `Space` commits `你好` for `nihao` and `中国` for `zhongguo` | | |
| Candidate position | Candidate panel follows the insertion point in TextEdit | | |
| Horizontal candidate layout | A pinyin query with at least nine matches displays candidates `1` through `9` in one horizontal row; number keys select the matching visible entry | | macOS `0.1.17` uses the native 9-column stepping panel and migrates the previous default page size from 5 to 9 |
| Number-key selection | In TextEdit, Safari, Chrome, and VS Code, each key `1` through `9` selects exactly the matching visible candidate once | | `IMKCandidatesSendServerKeyEventFirst=true` makes the controller/core the first and only handling path for consumed digit keys |
| Shift behavior | Standalone Shift toggles mode; `Shift+A` inserts uppercase text | | |
| App switch cleanup | Start partial composition, switch apps, return, and type again; stale preedit/candidates do not reappear | | |
| Candidate panel lifecycle | Switch repeatedly among TextEdit, Safari, and Chrome with candidates visible/hidden at least 20 times; typing keeps working and no new `PrivatePinyin` crash report appears | | |
| Settings menu | Strict privacy toggle, clear, export, and open-settings actions run | | |
| Browser/editor pass | Repeat basic `nihao -> 你好` in Safari, Chrome, and VS Code | | |
| Stale process check | After the guided refresh or logout/login fallback, no pre-install PrivatePinyin PID remains before smoke testing | | |
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
| Automated readiness | `scripts/run_ios_smoke_readiness.sh` passes, including Info.plist, App Group, Full Access, default settings, and Keyboard Extension no-network source checks | | |
| Install | Container app installs on simulator/device | | |
| Enable keyboard | PrivatePinyin can be added from Settings > General > Keyboard | | |
| Full Access | Full Access remains off by default | | |
| Learning opt-in | Container app shows learning disabled by default; the toggle enables only when App Group storage is available | | |
| App Group storage | With Full Access off, verify whether the keyboard extension can read/write the shared App Group settings and SQLite path; if denied, typing still works through built-in defaults and learning remains disabled | | |
| Notes composition | Typing `nihao` shows candidate `你好`; tapping it commits `你好` | | |
| QWERTY preserved | The original full keyboard and symbols page remain available after the nine-key update | | |
| Nine-key switch | Tap `九宫` to show the 1/2-9 layout, tap `ABC` to return to QWERTY, and reopen the keyboard to confirm the selected Chinese layout persists | | |
| Nine-key composition | In the nine-key layout, typing `64426` shows `你好`; Space or tapping the candidate commits exactly once | | |
| Nine-key continuous input | A longer 2-9 digit sequence can produce a segmented phrase candidate without switching back to QWERTY | | |
| Nine-key mode isolation | Switching to English shows QWERTY; switching back to Chinese restores the saved nine-key layout without stale composition | | |
| Prediction retention | `jintian -> 今天` keeps prediction candidates such as `天气` after commit | | |
| Self-change callback | If prediction disappears, reset self-text-operation state from `textDidChange` instead of synchronous `defer` | | |
| Globe key | Globe appears only when `needsInputModeSwitchKey` requires it and switches to the next input mode | | |
| Password fallback | Password fields force the system keyboard | | |
| Phone fallback | Phone-number fields force the system keyboard | | |
| No network | With Full Access off, there is no network API usage or network prompt | | |

## Blocking Rules

- A failed automated gate blocks merge.
- A failed manual smoke test does not block Stage 08 documentation/CI work unless it is caused by code changed in the same branch.
- Failed manual smoke checks must produce or update an `OPEN_ITEMS` entry before release-readiness work continues.
