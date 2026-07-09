# iOS Keyboard Smoke Record

Stage 15 records the automated readiness checks that can run from the repository
and separates the remaining iOS keyboard behavior that must be verified in
Simulator or on a device.

## Environment

| Field | Value |
|---|---|
| Tester | Codex automated readiness |
| Date | 2026-07-09 |
| Commit | `stage-15: add ios smoke readiness automation` |
| Build artifact | `build/ios_keyboard/Build/Products/Debug-iphonesimulator/PrivatePinyin.app` |
| App bundle ID | `com.privatepinyin.ios` |
| Keyboard bundle ID | `com.privatepinyin.ios.keyboard` |
| App Group ID | `group.com.privatepinyin.ios` |

## Automated Readiness

Run:

```bash
bash scripts/run_ios_smoke_readiness.sh
```

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Source scaffold | Existing iOS and Stage 14 checks pass before build | passed | `scripts/run_ios_smoke_readiness.sh` ran source gates first |
| Build | `scripts/build_ios_keyboard.sh` produces simulator app and keyboard extension | passed | Xcode reported `BUILD SUCCEEDED` |
| Container bundle ID | Built app Info.plist expands to `com.privatepinyin.ios` | passed | Script checked `CFBundleIdentifier` |
| Keyboard bundle ID | Built extension Info.plist expands to `com.privatepinyin.ios.keyboard` | passed | Script checked `CFBundleIdentifier` |
| App Group expansion | Built app and extension expose `group.com.privatepinyin.ios` through `PrivatePinyinAppGroupIdentifier` | passed | Script checked both Info.plist files |
| Full Access request | Keyboard extension keeps `RequestsOpenAccess=false` | passed | Script checked extension Info.plist |
| Primary language | Keyboard extension primary language remains `zh-Hans` | passed | Script checked extension Info.plist |
| Default settings resource | App and extension bundle `default_settings.json` | passed | Script checked both products |
| No network source usage | Keyboard Extension Swift sources contain no network APIs or URLs | passed | Script scanned Keyboard Extension Swift files |

## Manual Smoke Checklist

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Install | Container app installs on simulator/device | pending | |
| Enable keyboard | Keyboard can be added from Settings > General > Keyboard > Keyboards | pending | |
| Full Access | Full Access remains off by default | pending | |
| Learning opt-in | Container app shows learning disabled by default; toggle enables only when App Group storage is available | pending | |
| App Group storage | With Full Access off, verify whether the keyboard extension can read/write the shared App Group settings and SQLite path; if denied, typing still works through built-in defaults and learning remains disabled | pending | |
| Notes composition | Typing `nihao` shows candidate `你好`; tapping it commits `你好` | pending | |
| Prediction retention | `jintian -> 今天` keeps prediction candidates such as `天气` after commit | pending | |
| Globe key | Globe appears only when `needsInputModeSwitchKey` requires it and switches input modes | pending | |
| Password fallback | Password fields force the system keyboard | pending | |
| Phone fallback | Phone-number fields force the system keyboard | pending | |
| No network prompt | With Full Access off, there is no network prompt | pending | |

Manual failures should update `docs/OPEN_ITEMS.md` before release-readiness work
continues.
