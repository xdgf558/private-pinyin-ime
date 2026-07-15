# 猫栈拼音 / PrivatePinyin IME

猫栈拼音是一个隐私优先的中文拼音输入法项目。项目代号为
PrivatePinyin，当前 macOS 输入源显示名为「猫栈拼音」；核心目标是在
Windows、macOS 和 iOS 上提供本地计算、可审计、可打包发布的拼音输入体验。

项目目前仍处于预览和发布准备阶段，不建议当作正式生产输入法依赖。当前代码已经具备
Rust 核心引擎、C ABI、macOS InputMethodKit 原型、Windows TSF 原型、iOS 键盘扩展原型、
本地用户词库、基础预测、生产词库导入工具、CI 校验和打包脚本。

## 中文说明

### 主要特性

- 本地拼音解析和候选排序，默认不依赖云端服务。
- 已导入 AOSP/pinyin-data 来源的基础词库，覆盖常用单字和常用词。
- 支持本地用户词库学习：会记录你选过的候选词、拼音、频率和更新时间，用于后续排序。
- 支持本地 bigram、短句和 trigram 联想；最近两个已选词可以共同影响下一个候选，目前基础 bigram 数据仍较小。
- macOS 版本提供偏好设置入口，可切换预测、用户学习、严格隐私模式和可选的版本检查。
- 严格隐私模式会关闭用户学习。
- 支持清空和导出本地用户词库。

### macOS 本地体验

本地构建安装包：

```bash
bash scripts/package_macos_pkg.sh
```

安装生成的 pkg：

```bash
sudo installer -pkg dist/macos_imk/PrivatePinyin-0.1.10.pkg -target /
```

安装完成后会打开猫栈拼音的本地引导。若 macOS 仍保留安装前启动的旧输入法进程，引导会先让你确认“重新加载猫栈拼音”；正常情况下无需注销或重启。只有旧进程没有正常退出时，才会提示先保存工作并注销后重新登录。然后打开：

系统设置 -> 键盘 -> 输入法 -> 编辑 -> + -> 简体中文 -> 添加「猫栈拼音」

如果之前安装过旧版并看到重复输入源，请先切回「简体拼音」，删除旧的
PrivatePinyin/猫栈拼音条目，再重新添加一次。

### 隐私和学习功能

猫栈拼音默认走本地计算，不上传按键、拼音、候选词或提交内容。用户学习数据保存在本机：

```text
~/Library/Application Support/PrivatePinyin/user_lexicon.sqlite
```

用户词库只用于改善本地排序、一步联想、短句补全和 trigram（最近两词上下文）联想。它不是云同步，也不会自动读取剪贴板或应用上下文。当前学习能力包括
「候选选择记忆」「已选词转移记忆」「短句补全记忆」和「最近两词预测」：你经常选的词会逐渐排得更靠前，`今天 -> 天气 -> 不错` 与 `昨天 -> 天气 -> 很冷` 可以形成不同的本地候选。学习权重按 30 天半衰期自然降低，长期不用的记录会逐渐让位；数据库还会按容量淘汰低权重旧记录，不会无限增长。该功能只保存有限的候选关系，不保存完整句子、原始按键或周围文档内容。

macOS 的自动版本检查默认关闭；只有用户主动开启或点击「检查更新」时，宿主才会读取 `wwwstationcat.org` 上的固定公开版本清单。请求不包含输入内容或用户词库，严格隐私模式会暂停后台检查。发现新版本后，只有点击「下载并验证」才会下载安装包；客户端会核对精确大小、SHA-256、指定 Developer ID Installer 签名和 Apple 公证，并在交给 macOS 系统安装器前再次征求确认。猫栈拼音不会静默安装，也不会代填系统密码。

升级安装后，安装器会启动一个不承载输入服务的独立检查窗口。它只读取猫栈拼音自身进程的 PID 和启动时间，并且只有在你点击确认后，才会请求安装前启动的猫栈拼音旧进程正常退出。浏览器、编辑器和其他应用不会被关闭；刷新失败时只提供注销/重新登录指引，不会自动注销或重启电脑。

### 开发状态

Stage 13 已完成词库导入和生产词库骨架，后续重点是：

- macOS/Windows/iOS 真机冒烟记录。
- 正式签名、notarization、安装包发布流程。
- 最终项目许可证和第三方数据许可材料。
- 更完整的预测数据和输入体验打磨。

PrivatePinyin IME is a privacy-first Chinese pinyin input method project targeting Windows, macOS, and iOS.

The project follows the staged development plan in `docs/private_pinyin_ime_development_spec.md`. The core architecture is a Rust input engine exposed through a C ABI, with thin platform hosts for Windows TSF, macOS InputMethodKit, and iOS Keyboard Extension.

## Privacy Defaults

- Local computation by default.
- No telemetry by default.
- No account system.
- No cloud sync.
- No clipboard access unless a future product spec explicitly adds an opt-in feature.
- Logs must not contain raw keys, pinyin input, candidates, committed text, or user context.
- Error logs must use structured error codes and must not embed the input string that caused the error.

## Current Status

Stage 17 is in progress: the Rust workspace, core engine crate, indexed production base lexicon, SQLite user lexicon range lookup, local bigram/short-phrase/trigram learning with decay and capacity eviction, AOSP/pinyin-data lexicon import tooling, CLI smoke tools, C ABI crate, C demo, Windows TSF prototype with unsigned internal MSI packaging, macOS InputMethodKit prototype with preferences/onboarding UI, JSON settings loading, iOS container app and keyboard extension with App Group settings storage, learning opt-in, explicit signing/App Group release inputs, iOS smoke-readiness automation, TestFlight archive/upload scaffolding, tests, CI workflows, platform smoke-test plan, and staged source checks are in place.

Public release is still gated on the final project license, owner-provided signing/provisioning credentials, notarization/App Store setup, and completed platform smoke-test records. The bundled base lexicon source/license/version gate is closed for the current AOSP+pinyin-data import.

## Development Workflow

All stage work should use this review flow:

1. Create a branch named `codex/<stage-or-task>`.
2. Implement only the current stage scope from the development spec.
3. Update progress, changelog, decisions, and open items as required.
4. Run the relevant validation commands.
5. Commit the completed stage locally and share the local review summary, diff scope, and validation results.
6. Fix review feedback on the same local branch until approved.
7. Push the approved branch to GitHub.
8. Merge to `main` only after approval, then sync local `main`.

## Rust Workspace

The root `Cargo.toml` defines a workspace with:

- `ime_core` is the core engine crate.
- `ffi/ime_ffi` exposes the C ABI as `libprivate_pinyin_ime`.
- `tools/test_cli` is a CLI package that depends on `ime_core`.
- `tools/settings_cli` manages settings snapshots and user lexicon clear/export actions for installer scripts.
- `tools/lexicon_builder` converts local lexicon source files into the project base-lexicon TSV format and writes an audit manifest.
- `tools/ai_eval_runner` freezes required pre-AI behavior and reports improvement opportunities from first-party offline cases.
- `tools/ai_benchmark` records report-only initialization and lookup latency percentiles for local AI planning.
- `Cargo.lock` must be committed to keep CLI and release builds reproducible.

Validation:

```bash
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo run -p test_cli -- nihao
cargo run -p private_pinyin_settings -- write-default --settings /tmp/private_pinyin_settings.json
cargo run -p private_pinyin_lexicon -- build-base --format private-pinyin-tsv --input ime_core/assets/base_lexicon_sample.tsv --output /tmp/private_pinyin_base.tsv --manifest /tmp/private_pinyin_lexicon_manifest.json --source-name "PrivatePinyin sample" --source-license "project-internal sample data"
bash scripts/run_c_demo.sh
bash scripts/check_windows_tsf_sources.sh
bash scripts/check_macos_imk_sources.sh
bash scripts/check_installers_settings_sources.sh
bash scripts/check_ios_keyboard_sources.sh
bash scripts/check_platform_validation_sources.sh
bash scripts/check_stage09_core_sources.sh
bash scripts/check_stage10_platform_host_sources.sh
bash scripts/check_stage11_settings_privacy_sources.sh
bash scripts/check_stage12_release_sources.sh
bash scripts/check_stage13_lexicon_sources.sh
bash scripts/check_stage14_ios_signing_sources.sh
bash scripts/check_stage15_ios_smoke_sources.sh
bash scripts/check_stage16_ios_testflight_sources.sh
bash scripts/check_ai01_evaluation_sources.sh
bash scripts/check_update01_sources.sh
bash scripts/check_update02_sources.sh
bash scripts/run_ai_eval.sh
bash scripts/build_macos_imk.sh
bash scripts/package_macos_pkg.sh
bash scripts/build_ios_keyboard.sh
bash scripts/run_ios_smoke_readiness.sh
```

## Next Stage

UPDATE-02 now verifies and hands a signed/notarized macOS pkg to the system
Installer with explicit consent. Next update work is UPDATE-03 post-install
process refresh guidance. Local AI resumes at AI-02 only after the update
stages are reviewed.
