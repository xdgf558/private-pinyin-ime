# Scripts

This directory contains project scripts.

Current scripts:

- `run_c_demo.sh`: builds the FFI library, checks C ABI layout, and runs the C demo.
- `check_windows_tsf_sources.sh`: verifies the Windows TSF source scaffold on non-Windows CI.
- `build_windows_tsf.ps1`: builds the Rust FFI library and Windows TSF DLL on Windows.
- `package_windows_tsf.ps1`: stages Windows installer files and builds a zip bundle, plus an MSI when WiX is installed.
- `check_macos_imk_sources.sh`: verifies the macOS InputMethodKit source scaffold and bundle plist.
- `build_macos_imk.sh`: builds the Rust FFI library and local macOS InputMethodKit app bundle.
- `package_macos_pkg.sh`: builds an unsigned local macOS `.pkg` installer.
- `check_installers_settings_sources.sh`: verifies Stage 6 installer and settings scaffold files.
- `build_ios_keyboard.sh`: builds the Rust iOS static library and the iOS container app/keyboard extension.
- `check_ios_keyboard_sources.sh`: verifies the iOS keyboard source scaffold, plist privacy defaults, and Xcode project wiring.
- `check_platform_validation_sources.sh`: verifies Stage 8 platform smoke-test documentation and Windows TSF CI wiring.
- `check_stage09_core_sources.sh`: verifies Stage 9 core hardening for indexed lookup, paging, ranking, logging, and lexicon data policy.
- `check_stage10_platform_host_sources.sh`: verifies Stage 10 Windows/macOS host polish sources.

Planned scripts:

- Privacy validation helpers.
