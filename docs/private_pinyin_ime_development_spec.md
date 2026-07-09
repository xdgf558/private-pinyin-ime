# PrivatePinyin IME 开发文档

版本：v1.0  
目标读者：Codex、开发者、测试人员  
项目目标：开发一款隐私优先、安装简单、可在 Windows 和 macOS 使用，后期可扩展到 iOS 的中文拼音输入法。

---

## 0. 给 Codex 的强制执行规则

Codex 必须把本文件当作项目主开发规范。任何阶段开始、继续、收尾时，都要先核对本文件，避免遗忘前面已经定义过的产品目标、隐私要求、接口约束和验收标准。

### 0.1 每次开始开发前必须执行

1. 读取本文件：`docs/private_pinyin_ime_development_spec.md`。
2. 读取进度文件：`docs/DEVELOPMENT_PROGRESS.md`。
3. 读取变更记录：`CHANGELOG.md`。
4. 确认当前阶段编号、阶段目标、阶段验收标准。
5. 只实现当前阶段要求的内容，除非修复前置阶段缺陷需要改动公共模块。
6. 开始编码前，在 `docs/DEVELOPMENT_PROGRESS.md` 中把当前阶段状态标记为 `in_progress`。

### 0.2 每个阶段完成后必须执行

1. 重新读取本文件对应阶段的任务和验收标准。
2. 对照阶段验收清单逐项核对。
3. 运行该阶段要求的测试命令。
4. 更新 `docs/DEVELOPMENT_PROGRESS.md`。
5. 更新 `CHANGELOG.md`。
6. 如有技术决策，更新 `docs/DECISIONS.md`。
7. 如有未完成事项，写入 `docs/OPEN_ITEMS.md`。
8. 保存全部修改。
9. 如果当前目录是 Git 仓库，执行一次本地提交。不要推送远程仓库，除非用户明确要求。

建议提交信息格式：

```text
stage-01: implement core pinyin engine
stage-02: add user lexicon and prediction
stage-03: expose C ABI
stage-04: add Windows TSF prototype
stage-05: add macOS InputMethodKit prototype
stage-06: add installers and settings UI
stage-07: add iOS keyboard extension
stage-08: add platform validation and CI hardening
stage-09: harden core engine for production dictionaries
stage-10: polish platform host experience
stage-11: close settings privacy and ios storage gaps
stage-12: prepare release packaging and distribution
```

### 0.3 进度文件模板

Codex 在项目初始化时必须创建 `docs/DEVELOPMENT_PROGRESS.md`，内容使用以下模板：

```markdown
# Development Progress

Last updated: YYYY-MM-DD HH:mm
Current stage: stage-01
Current status: not_started | in_progress | blocked | completed

## Stage Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| 01 | Rust core engine | not_started | | |
| 02 | User lexicon and prediction | not_started | | |
| 03 | C ABI and CLI integration | not_started | | |
| 04 | Windows TSF prototype | not_started | | |
| 05 | macOS InputMethodKit prototype | not_started | | |
| 06 | Installers and settings | not_started | | |
| 07 | iOS keyboard extension | not_started | | |

## Completed Work

- 

## Current Work

- 

## Validation Results

- Command:
- Result:
- Notes:

## Open Items

- 

## Files Changed In Latest Stage

- 

## Next Step

- 
```

### 0.4 变更记录模板

Codex 在项目初始化时必须创建 `CHANGELOG.md`：

```markdown
# Changelog

## Unreleased

### Added

- 

### Changed

- 

### Fixed

- 

### Security and Privacy

- 
```

### 0.5 技术决策模板

Codex 在项目初始化时必须创建 `docs/DECISIONS.md`：

```markdown
# Technical Decisions

## Decision 001: Core engine language

Date: YYYY-MM-DD
Status: accepted
Decision: Use Rust for the shared IME core.
Reason: Memory safety, cross-platform library support, good FFI support.
Consequences: Platform hosts call Rust through C ABI.
```

### 0.6 未完成事项模板

Codex 在项目初始化时必须创建 `docs/OPEN_ITEMS.md`：

```markdown
# Open Items

| ID | Stage | Item | Priority | Owner | Status | Notes |
|---|---|---|---|---|---|---|
| OI-001 | 01 | Replace sample lexicon with licensed production lexicon | High | TBD | open | Must verify license before release |
```

### 0.7 Codex 不得违反的规则

1. 不添加遥测 SDK。
2. 不添加账号系统。
3. 不添加云同步。
4. 不上传用户按键、拼音、候选词、上屏文本、用户词库。
5. 不把用户输入内容写进日志。
6. 不读取剪贴板，除非未来产品文档明确添加此功能，并要求用户主动开启。
7. 不把平台宿主逻辑写死到核心引擎中。
8. 不绕过系统输入法安全限制。
9. 不使用未授权商业词库。
10. 不跳过阶段验收。

---

## 1. 产品目标

PrivatePinyin IME 是一款中文拼音输入法。核心卖点是隐私保护、本地计算、中文联想、快速中英文切换、安装流程简单。

首版目标平台：

| 平台 | 优先级 | 技术路线 | 目标 |
|---|---:|---|---|
| Windows 11 | P0 | TSF Text Service | 可安装、可启用、可输入中文 |
| macOS 14+ | P0 | InputMethodKit | 可安装、可启用、可输入中文 |
| iOS 18+ | P1 | Custom Keyboard Extension | 第二阶段移动端版本 |

MVP 必须完成：

1. 用户输入 `nihao`，候选栏显示 `你好`、`你号` 等候选。
2. 用户输入连续拼音，例如 `woxiangqu`，候选栏显示 `我想去`、`我想取` 等候选。
3. 上屏中文词后可以给出本地中文联想。例如上屏 `今天` 后，候选栏显示 `天气`、`晚上`、`下午` 等候选。
4. 支持快速中英文切换。默认 Shift 切换，用户可以在设置中改为 Ctrl Space 或 Caps Lock。
5. 英文模式下直接输出英文字符，不触发中文候选。
6. 中文模式下 Space 选择第一个候选。
7. 中文模式下数字 1 到 9 选择对应候选。
8. 中文模式下 Enter 上屏原始拼音。
9. Esc 取消当前组合输入。
10. Backspace 删除当前拼音输入。
11. 支持本地用户词库学习，用户可以关闭学习。
12. 支持严格隐私模式，开启后不写入任何学习数据。
13. 安装流程尽量少步骤。
14. 默认无网络访问、无遥测、无账号体系、无云同步。
15. 提供清空本地词库、导出本地词库、关闭个性化学习的设置入口。

首版暂缓：

1. 云同步。
2. 账号登录。
3. 语音输入。
4. 图片识别。
5. 表情包商店。
6. 复杂双拼方案。
7. 大模型补全。
8. 移动端滑行输入。
9. 多设备同步词库。

---

## 2. 总体架构

采用“核心输入引擎 + 平台宿主”的架构。

核心输入引擎使用 Rust 开发，编译为静态库或动态库，暴露 C ABI。Windows、macOS、iOS 平台层只负责接收系统按键事件、展示候选 UI、提交文字到目标应用。拼音解析、候选生成、排序、联想、用户词库学习全部放在核心引擎中。

### 2.1 推荐目录结构

```text
private_pinyin_ime/
  README.md
  LICENSE
  CHANGELOG.md
  docs/
    private_pinyin_ime_development_spec.md
    DEVELOPMENT_PROGRESS.md
    DECISIONS.md
    OPEN_ITEMS.md
    privacy_spec.md
    windows_tsf_notes.md
    macos_inputmethodkit_notes.md
    ios_keyboard_extension_notes.md
  ime_core/
    Cargo.toml
    src/
      lib.rs
      api.rs
      session.rs
      key_event.rs
      pinyin_parser.rs
      syllable.rs
      lexicon.rs
      candidate.rs
      ranker.rs
      predictor.rs
      user_lexicon.rs
      settings.rs
      privacy.rs
      logger.rs
      error.rs
    tests/
      parser_tests.rs
      candidate_tests.rs
      ranking_tests.rs
      prediction_tests.rs
      privacy_tests.rs
      ffi_tests.rs
    assets/
      base_lexicon_sample.tsv
      bigram_sample.tsv
      lexicon_manifest.json
  ffi/
    c_api.h
    c_api.rs
    examples/
      c_demo.c
  platform/
    windows_tsf/
      README.md
      PrivatePinyinTsf.sln
      src/
      installer/
    macos_imk/
      README.md
      PrivatePinyinInputMethod.xcodeproj
      Sources/
      installer/
    ios_keyboard/
      README.md
      PrivatePinyinKeyboard.xcodeproj
      KeyboardExtension/
      ContainerApp/
  tools/
    build_lexicon/
    test_cli/
  scripts/
    build_windows.ps1
    build_macos.sh
    run_core_tests.sh
```

### 2.2 模块边界

| 模块 | 位置 | 职责 |
|---|---|---|
| ime_core | Rust | 拼音解析、候选生成、排序、联想、设置、隐私、用户词库 |
| ffi | Rust + C header | 对外暴露稳定 C ABI |
| windows_tsf | C++ | Windows TSF 输入法宿主、候选窗口、安装注册 |
| macos_imk | Swift / Objective-C | macOS InputMethodKit 宿主、候选窗口、安装包 |
| ios_keyboard | Swift | iOS 自定义键盘、候选栏、容器 App 设置入口 |
| tools | Rust / Python | 词库构建、CLI 测试、开发辅助工具 |
| docs | Markdown | 开发规范、进度保存、决策记录、未完成事项 |

---

## 3. 核心模块设计

### 3.1 InputSession

InputSession 是一次输入过程的状态机。每个文本框激活时平台宿主创建 session，文本框失焦或组合输入结束时重置 session。

状态字段：

```text
mode: Chinese | English
raw_input: 当前拼音字符串，例如 nihao
parsed_syllables: 解析后的音节，例如 ni hao
preedit_text: 展示在输入框中的组合文本
candidates: 当前候选词列表
candidate_page: 当前候选页
context_tokens: 最近上屏词 token，用于联想
settings_snapshot: 当前设置快照
privacy_mode: 是否严格隐私模式
```

主要行为：

```text
feed_key(event) -> ImeOutput
commit_candidate(index) -> ImeOutput
commit_raw_input() -> ImeOutput
cancel_composition() -> ImeOutput
toggle_mode() -> ImeOutput
reset() -> ImeOutput
predict_next() -> CandidateList
```

### 3.2 KeyEvent

平台层需要把系统按键转换成统一 KeyEvent。

字段：

```text
key_code: 字符或特殊键
text: 用户输入的字符
modifiers: shift, ctrl, alt, meta
is_repeat: 是否长按重复
timestamp_ms: 时间戳
```

必须支持的键：

```text
a 到 z
0 到 9
space
enter
backspace
escape
shift
ctrl space
caps lock
comma
period
minus
equal
apostrophe
semicolon
page_up
page_down
arrow_up
arrow_down
```

### 3.3 PinyinParser

负责把原始输入切成合法拼音音节。

要求：

1. 支持完整拼音：`nihao` -> `ni hao`。
2. 支持撇号分隔：`xi'an` -> `xi an`。
3. 支持 `v` 表示 `ü`：`nv` -> `nü`，`lv` -> `lü`。
4. 支持前缀输入：`zhongg` 可以匹配 `中国`、`中共` 等。
5. 支持动态规划解析，返回多个可行解析路径。
6. 默认关闭模糊音。
7. 后期可配置 `zh/z`、`ch/c`、`sh/s`、`n/l`、`an/ang`、`en/eng`、`in/ing`。

核心算法：

```text
输入 raw_input
从左到右扫描所有合法音节
用动态规划保存可行切分路径
每条路径记录 syllables、coverage、penalty
优先返回覆盖完整输入且 penalty 最低的路径
```

测试样例：

```text
nihao -> ni hao
zhongguo -> zhong guo
xian -> xi an 或 xian
xi'an -> xi an
lvshi -> lü shi
nver -> nü er
```

### 3.4 Lexicon

词库分三层：

| 层级 | 名称 | 读写 | 说明 |
|---|---|---|---|
| 1 | base_lexicon | 只读 | 内置基础词库 |
| 2 | user_lexicon | 可读写 | 用户本地词库 |
| 3 | session_lexicon | 临时 | 当前会话临时学习，应用关闭后丢弃 |

`base_lexicon_sample.tsv` 格式：

```text
phrase	pinyin	frequency
你好	ni hao	900000
中国	zhong guo	950000
今天	jin tian	800000
天气	tian qi	700000
我们	wo men	850000
我想去	wo xiang qu	300000
```

生产词库要求：

1. 不复制未授权商业词库。
2. 每个词库文件必须有 LICENSE 说明。
3. 构建脚本必须生成 `lexicon_manifest.json`。
4. `lexicon_manifest.json` 必须记录词库来源、许可证、构建时间、条目数。
5. MVP 可以只放小型测试词库，先把引擎和平台链路跑通。

### 3.5 Candidate

候选对象结构：

```text
id: string
text: string
pinyin: string
score: float
source: base | user | prediction | symbol | raw
comment: optional string
```

候选生成规则：

1. `raw_input` 为空时，只显示联想候选。
2. `raw_input` 非空时，先解析拼音，再从 `base_lexicon` 和 `user_lexicon` 查找匹配项。
3. 精确拼音匹配优先。
4. 前缀匹配其次。
5. 用户高频词优先级高于普通基础词。
6. 候选最多返回 50 个。
7. UI 每页显示 5 或 9 个候选，默认 5 个。

### 3.6 Ranker

候选排序公式：

```text
score =
  base_frequency_score * 1.0
  + user_frequency_score * 1.4
  + context_bigram_score * 1.2
  + recency_score * 0.5
  + exact_match_bonus
  - prefix_penalty
  - fuzzy_penalty
```

排序要求：

1. 同样拼音下，高频词排前。
2. 用户最近选择过的词适当上升。
3. 一次误选不能永久改变排序。
4. 严格隐私模式下不更新 `user_frequency_score`。
5. 用户可以在设置中删除错误学习词。

### 3.7 Predictor

中文联想功能由 Predictor 提供。

触发场景：

1. 用户刚上屏中文词。
2. 当前 `raw_input` 为空。
3. 当前 `mode` 为 `Chinese`。
4. 当前文本框允许输入普通文本。

输入：

```text
context_tokens: 最近 1 到 5 个上屏词
```

输出：

```text
CandidateList
```

联想来源：

1. 本地 bigram 文件。
2. 本地 trigram 文件，后期添加。
3. 用户本地词库统计。
4. 固定短语规则，例如日期、问候、常见搭配。

示例：

```text
上屏：今天
联想：天气，晚上，下午，早上，有空

上屏：我想
联想：去，吃，看，买，问

上屏：谢谢
联想：你，不客气，啦，老师
```

隐私要求：

1. 默认只保存词频和短语，不保存完整句子。
2. 用户开启严格隐私模式后，不保存任何新词和上下文。
3. 不访问剪贴板。
4. 不主动读取输入框前后文。
5. 高级联想功能必须由用户主动开启。

---

## 4. FFI API 设计

Rust core 暴露 C ABI，平台层只调用这些函数。

```c
typedef struct ImeEngine ImeEngine;
typedef struct ImeSession ImeSession;

typedef enum {
  IME_MODE_CHINESE = 0,
  IME_MODE_ENGLISH = 1
} ImeMode;

typedef struct {
  int key_code;
  const char* text;
  int shift;
  int ctrl;
  int alt;
  int meta;
  int is_repeat;
  long long timestamp_ms;
} ImeKeyEvent;

typedef struct {
  const char* text;
  const char* pinyin;
  double score;
  const char* source;
} ImeCandidate;

typedef struct {
  const char* preedit;
  const char* commit_text;
  ImeMode mode;
  int should_update_preedit;
  int should_commit;
  int should_show_candidates;
  int candidate_count;
  ImeCandidate* candidates;
} ImeOutput;

ImeEngine* ime_engine_new(const char* config_json_path);
void ime_engine_free(ImeEngine* engine);

ImeSession* ime_session_new(ImeEngine* engine);
void ime_session_free(ImeSession* session);

ImeOutput* ime_session_feed_key(ImeSession* session, ImeKeyEvent event);
ImeOutput* ime_session_commit_candidate(ImeSession* session, int index);
ImeOutput* ime_session_toggle_mode(ImeSession* session);
ImeOutput* ime_session_reset(ImeSession* session);

void ime_output_free(ImeOutput* output);
```

FFI 要求：

1. 所有字符串使用 UTF-8。
2. FFI 边界不得 panic。
3. Rust 内部错误转换为 error output。
4. 所有分配给平台层的内存必须提供 free 函数。
5. 平台层不得直接访问 Rust 内部结构。
6. 增加 C header 和 Swift/C++ 调用样例。
7. FFI 测试必须覆盖创建、输入、候选读取、提交、释放。

---

## 5. 平台宿主设计

### 5.1 Windows TSF 宿主

目标：实现 Windows 11 可安装、可启用、可输入中文的 TSF IME。

技术选择：

| 项 | 内容 |
|---|---|
| 实现语言 | C++ 20 |
| 系统框架 | Text Services Framework |
| 核心调用 | 通过 C ABI 调用 ime_core |
| 输出形式 | TSF text service DLL |
| 安装形式 | MSI 或 EXE installer |
| 生产要求 | 代码签名 |

Windows 关键要求：

1. 使用 TSF。
2. 实现 COM in-process server。
3. 注册 text service profile。
4. 实现按键拦截、composition、candidate window、mode switching。
5. 不直接写注册表设置默认输入法。
6. 支持 x64，后期支持 ARM64。
7. IME DLL 默认不访问网络。

建议实现接口：

```text
ITfTextInputProcessorEx
ITfThreadMgrEventSink
ITfKeyEventSink
ITfCompositionSink
ITfDisplayAttributeProvider
ITfFnConfigure
```

Windows 事件流程：

```text
用户按键
TSF 调用 OnKeyDown
Windows 宿主转换为 ImeKeyEvent
调用 ime_session_feed_key
根据 ImeOutput 更新 composition
根据 candidates 更新 candidate window
如果 should_commit 为 true，提交 commit_text 到目标应用
```

CandidateWindow 要求：

1. 跟随光标位置。
2. 显示 1 到 9 编号。
3. 支持深色模式。
4. 支持高 DPI。
5. 支持键盘翻页。
6. 候选栏不能抢焦点。

Windows 安装流程：

```text
运行安装包
复制 IME DLL 和 core library
注册 COM server
注册 TSF profile
提示用户到 Settings > Time & Language > Typing > Advanced keyboard settings 启用输入法
提供安装完成后的测试文本框
```

Windows 验收标准：

1. Notepad 中可以输入 `nihao` 并选择 `你好`。
2. Edge 地址栏中英文模式可正常直接输入英文。
3. Word 或常见编辑器中组合输入不丢字。
4. 卸载后输入法从系统列表移除。
5. 默认安装后不发起任何网络请求。

### 5.2 macOS InputMethodKit 宿主

目标：实现 macOS 可安装、可启用、可输入中文的输入法。

技术选择：

| 项 | 内容 |
|---|---|
| 实现语言 | Swift + Objective-C bridge |
| 系统框架 | InputMethodKit |
| 核心调用 | 通过 C ABI 调用 ime_core |
| 输出形式 | `.app` input method bundle |
| 安装形式 | signed and notarized `.pkg` |

macOS 关键要求：

1. 使用 InputMethodKit。
2. 创建 IMKServer。
3. 实现 IMKInputController 子类。
4. 处理 key down 事件。
5. 使用 marked text 显示组合输入。
6. 使用 candidate panel 显示候选。
7. 支持菜单栏输入法图标和设置入口。
8. 默认不访问网络。

macOS 事件流程：

```text
用户按键
IMKInputController 接收事件
macOS 宿主转换为 ImeKeyEvent
调用 ime_session_feed_key
根据 ImeOutput 设置 marked text
根据 candidates 刷新候选窗口
如果 should_commit 为 true，commit 到 client
```

macOS 安装流程：

```text
运行 pkg
复制输入法 app 到 /Library/Input Methods 或 ~/Library/Input Methods
提示用户打开 System Settings > Keyboard > Input Sources
用户添加 PrivatePinyin
添加后可以通过系统输入法菜单切换
```

macOS 验收标准：

1. TextEdit 中可以输入 `zhongguo` 并选择 `中国`。
2. Safari、Chrome、VS Code 文本框中基本输入可用。
3. Shift 可以切换中英文。
4. 候选窗口跟随光标。
5. 卸载脚本可以移除输入法 bundle 和可选用户配置。

### 5.3 iOS Keyboard Extension 第二阶段

目标：实现 iOS 自定义键盘版本。

技术选择：

| 项 | 内容 |
|---|---|
| 实现语言 | Swift |
| 系统框架 | Custom Keyboard Extension |
| 核心调用 | ime_core 编译为 iOS static library |
| 输出形式 | Container App + Keyboard Extension |

iOS 关键要求：

1. 使用 UIInputViewController。
2. 键盘必须有 Globe 或 Next Keyboard 按钮。
3. 默认 `RequestsOpenAccess` 设置为 false。
4. 首版不请求网络权限。
5. 候选栏在键盘顶部展示。
6. 用户词库保存在 App Group container，前提是用户明确开启。
7. 密码框、电话键盘字段、拒绝自定义键盘的 App 中可能无法使用自定义键盘。

iOS 键盘 UI：

```text
候选栏
第一行：qwertyuiop
第二行：asdfghjkl
第三行：shift zxcvbnm backspace
第四行：globe 123 space 中/英 enter
```

iOS 验收标准：

1. Notes 中可以输入 `nihao` 并选择 `你好`。
2. Safari 普通文本框可以输入中文。
3. 密码框中系统自动切换到系统键盘。
4. 未开启 open access 时无网络访问。
5. 用户可以在容器 App 中清空本地词库。

---

## 6. 隐私与安全设计

隐私原则：

1. 默认本地计算。
2. 默认无网络。
3. 默认无遥测。
4. 默认无账号。
5. 默认不读取剪贴板。
6. 默认不保存完整句子。
7. 用户词库可以一键清空。
8. 用户可以关闭个性化学习。
9. 严格隐私模式下不写入任何学习数据。
10. 日志中不能包含 raw_input、候选词、上屏文本。

本地数据文件：

```text
settings.json
user_lexicon.sqlite
user_stats.sqlite
debug.log
```

debug.log 规则：

```text
允许记录：模块启动、错误码、耗时、版本号
禁止记录：按键内容、拼音内容、候选中文、上屏中文、用户上下文
```

隐私测试：

1. 单元测试检查日志函数，禁止写入 raw_input。
2. 构建脚本扫描网络 API 使用，例如 socket、http client、NSURLSession、WinHTTP。
3. 集成测试开启输入后抓包，确认无外连。
4. 严格隐私模式下输入 100 次，user_lexicon.sqlite 不新增记录。
5. 清空词库后，用户学习候选不再出现。

---

## 7. 设置项设计

设置文件示例：

```json
{
  "default_mode": "Chinese",
  "toggle_key": "Shift",
  "candidate_page_size": 5,
  "enable_prediction": true,
  "enable_user_learning": true,
  "strict_privacy_mode": false,
  "fuzzy_pinyin": {
    "zh_z": false,
    "ch_c": false,
    "sh_s": false,
    "n_l": false,
    "an_ang": false,
    "en_eng": false,
    "in_ing": false
  },
  "theme": "system",
  "candidate_font_size": 14
}
```

设置项要求：

1. 修改后立即生效。
2. 平台宿主启动 session 时读取 settings snapshot。
3. 设置损坏时回退默认值。
4. 设置文件写入使用原子写入，避免崩溃造成损坏。
5. 严格隐私模式优先级高于普通学习设置。

---

## 8. 安装与卸载

### 8.1 Windows

安装：

```text
1. 安装 core library
2. 安装 TSF DLL
3. 注册 COM
4. 注册 TSF profile
5. 提供启用说明
6. 打开测试文本框
```

卸载：

```text
1. 注销 TSF profile
2. 注销 COM
3. 删除程序文件
4. 询问是否保留用户词库
```

### 8.2 macOS

安装：

```text
1. 安装 input method bundle
2. 提示用户到 Keyboard 设置添加输入法
3. 提供重启输入法服务按钮
4. 打开测试页面
```

卸载：

```text
1. 删除 input method bundle
2. 清理 launch 相关缓存
3. 询问是否保留用户词库
```

### 8.3 iOS

安装：

```text
1. 用户安装容器 App
2. 用户到 Settings > General > Keyboard > Keyboards 添加键盘
3. App 内显示图文引导
4. 默认不要求 Allow Full Access
```

---

## 9. 测试计划

核心引擎测试命令：

```bash
cargo test
```

必须覆盖：

1. 拼音解析。
2. 候选生成。
3. 候选排序。
4. 联想预测。
5. 用户词库学习。
6. 严格隐私模式。
7. FFI 内存释放。
8. UTF-8 字符串边界。
9. 错误输入，例如空字符串、非法字符、超长输入。

输入样例：

```text
nihao -> 你好
zhongguo -> 中国
woxiangqu -> 我想去
jintian -> 今天
tianqi -> 天气
xiexie -> 谢谢
```

平台测试：

Windows：

```text
Notepad
Microsoft Edge
Word
VS Code
Windows Search
UAC 或安全桌面场景下不崩溃
```

macOS：

```text
TextEdit
Safari
Chrome
Notes
VS Code
Spotlight
```

iOS：

```text
Notes
Messages
Safari
普通第三方 App 文本框
密码框
电话字段
```

性能目标：

```text
普通候选响应：小于 30 ms
连续拼音响应：小于 60 ms
候选翻页响应：小于 16 ms
内存占用：core 小于 80 MB，平台宿主小于 150 MB
启动时间：小于 500 ms
```

---

## 10. 阶段开发计划

Codex 必须按阶段开发。每个阶段结束后，必须回到第 0 节执行核对、保存、更新进度。

### 阶段 1：创建 ime_core

任务：

1. 创建 Rust crate `ime_core`。
2. 实现 InputSession、KeyEvent、ImeOutput、Candidate。
3. 实现基本 PinyinParser。
4. 加载 `base_lexicon_sample.tsv`。
5. 实现候选生成和简单排序。
6. 实现 CLI 测试工具。
7. 创建根目录 Cargo workspace，成员包含 `ime_core` 和 `tools/test_cli`。
8. 提交 `Cargo.lock`，保证 CLI 和发布构建可复现。
9. 增加最小 GitHub Actions，运行 fmt、clippy 和测试。
10. 创建 `docs/DEVELOPMENT_PROGRESS.md`、`CHANGELOG.md`、`docs/DECISIONS.md`、`docs/OPEN_ITEMS.md`。

验收：

```text
cargo fmt --check 通过
cargo clippy --workspace --all-targets -- -D warnings 通过
cargo test --workspace 通过
cargo run -p test_cli -- nihao
输入 nihao
输出候选中包含 你好
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-01 标记为 completed。
2. 在 `CHANGELOG.md` 写入新增的核心引擎能力。
3. 在 `docs/OPEN_ITEMS.md` 写入生产词库授权待办。
4. 如果是 Git 仓库，提交 `stage-01: implement core pinyin engine`。

### 阶段 2：实现中文联想和用户词库

任务：

1. 增加 SQLite 用户词库。
2. 增加本地 bigram sample。
3. 上屏后更新本地词频。
4. 实现 `predict_next()`。
5. 增加严格隐私模式。
6. 增加关闭个性化学习配置。

验收：

```text
输入 jintian
选择 今天
raw_input 为空时 candidates 包含 天气
关闭 enable_user_learning 后不写入用户词库
strict_privacy_mode 开启后不写入任何学习数据
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-02 标记为 completed。
2. 在 `CHANGELOG.md` 写入用户词库、联想、隐私模式变更。
3. 在 `docs/DECISIONS.md` 记录 SQLite 数据结构。
4. 如果是 Git 仓库，提交 `stage-02: add user lexicon and prediction`。

### 阶段 3：实现 C ABI

任务：

1. 增加 `ffi/c_api.h`。
2. Rust 导出 C ABI。
3. 写 C 测试程序调用 core。
4. 测试内存释放。
5. FFI 不允许 panic 穿透。
6. 提供 Swift 和 C++ 调用说明。

验收：

```text
C demo 可以创建 engine
C demo 可以输入 nihao
C demo 可以获得 你好
valgrind 或平台等价工具无明显泄漏
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-03 标记为 completed。
2. 在 `CHANGELOG.md` 写入 C ABI 能力。
3. 在 `docs/DECISIONS.md` 记录 FFI 内存所有权规则。
4. 如果是 Git 仓库，提交 `stage-03: expose C ABI`。

### 阶段 4：Windows TSF POC

任务：

1. 创建 C++ TSF DLL 工程。
2. 实现最小 COM 注册。
3. 能接收按键并调用 ime_core。
4. 能显示 composition。
5. 能提交候选。
6. 实现简易 candidate window。
7. 编写 Windows 平台 README。

验收：

```text
Notepad 中可以输入 nihao 并选择 你好
Shift 可以切换中英文
Space 可以选择第一个候选
Esc 可以取消
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-04 标记为 completed。
2. 在 `CHANGELOG.md` 写入 Windows TSF POC 进展。
3. 在 `docs/OPEN_ITEMS.md` 写入签名、安装器、高 DPI 待办。
4. 如果是 Git 仓库，提交 `stage-04: add Windows TSF prototype`。

### 阶段 5：macOS InputMethodKit POC

任务：

1. 创建 macOS InputMethodKit 工程。
2. 创建 IMKServer 和 IMKInputController。
3. 接收 key down。
4. 调用 ime_core。
5. 设置 marked text 和 commit text。
6. 显示候选窗口。
7. 编写 macOS 平台 README。

验收：

```text
TextEdit 中可以输入 zhongguo 并选择 中国
Shift 可以切换中英文
候选窗口跟随光标
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-05 标记为 completed。
2. 在 `CHANGELOG.md` 写入 macOS POC 进展。
3. 在 `docs/OPEN_ITEMS.md` 写入 notarization、安装包、候选窗口优化待办。
4. 如果是 Git 仓库，提交 `stage-05: add macOS InputMethodKit prototype`。

### 阶段 6：安装器与设置页

任务：

1. Windows 生成 installer。
2. macOS 生成 pkg。
3. 增加设置 UI。
4. 增加清空用户词库。
5. 增加导出用户词库。
6. 增加隐私模式开关。
7. 增加安装和卸载说明。

验收：

```text
用户可以完成安装
用户可以启用输入法
用户可以卸载
用户可以清空词库
默认无网络请求
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-06 标记为 completed。
2. 在 `CHANGELOG.md` 写入安装器、设置 UI、隐私开关变更。
3. 在 `docs/OPEN_ITEMS.md` 写入发布签名、自动更新待办。
4. 如果是 Git 仓库，提交 `stage-06: add installers and settings UI`。

### 阶段 7：iOS Keyboard Extension

任务：

1. 创建 iOS 容器 App。
2. 创建 Keyboard Extension。
3. 集成 ime_core static library。
4. 实现键盘 UI。
5. 实现候选栏。
6. 实现 Globe key。
7. 默认 `RequestsOpenAccess=false`。
8. 编写 iOS 平台 README。

验收：

```text
Notes 中可以输入 nihao 并选择 你好
密码框中系统自动使用系统键盘
未开启 open access 时无网络访问
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-07 标记为 completed。
2. 在 `CHANGELOG.md` 写入 iOS Keyboard Extension 进展。
3. 在 `docs/OPEN_ITEMS.md` 写入 App Store、App Group、iOS 权限说明待办。
4. 如果是 Git 仓库，提交 `stage-07: add iOS keyboard extension`。

### 阶段 8：平台验证与 CI 补强

任务：

1. 增加固定到 `windows-2022` 的 CI job，运行 `cargo test --workspace` 并真实编译 Windows TSF C++ DLL。
2. 保留 Ubuntu Rust workspace job，继续覆盖 fmt、clippy、tests、C demo 和 source scaffold checks。
3. 编写跨平台 smoke test record/checklist，覆盖 Windows 11、macOS 和 iOS。
4. 明确哪些验证可以自动化、哪些必须在真实系统 UI 中手动验证。
5. 增加 Rust 缓存，避免 Windows job 重复从头编译 SQLite 等依赖。
6. 增加脚本检查 Stage 8 验证文档和 CI wiring，防止后续漂移。
7. 更新 `docs/OPEN_ITEMS.md`：自动编译类待办可关闭；真实系统冒烟待办必须保留到完成验证。

验收：

```text
GitHub Actions 包含 Ubuntu Rust job
GitHub Actions 在 Windows 上运行 cargo test --workspace
GitHub Actions 包含 Windows TSF compile job
bash scripts/check_platform_validation_sources.sh 通过
Windows smoke checklist 覆盖 Notepad、设置 UI、安装/卸载、快捷键透传、焦点切换清理、多进程学习
macOS smoke checklist 覆盖 TextEdit、候选窗、数字选词、Shift 行为、切应用清理、菜单设置
iOS smoke checklist 覆盖 Notes、预测候选保留、Full Access off、密码/电话字段 fallback
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-08 标记为 completed。
2. 在 `CHANGELOG.md` 写入平台验证和 CI 补强变更。
3. 在 `docs/OPEN_ITEMS.md` 关闭已自动化验证的 CI 待办，保留未跑过的真实系统冒烟待办。
4. 如果是 Git 仓库，提交 `stage-08: add platform validation and CI hardening`。

### 阶段 9：核心引擎生产化

任务：

1. 建立生产词库数据政策，要求 manifest 记录文件、来源、许可证和条目数量；在没有 owner 批准许可证前不得导入第三方词库。
2. 把基础词库查询改为 compact pinyin 索引化前缀查询，避免生产词库规模下全表扫描。
3. 把用户词库查询改为 SQLite 范围前缀查询，并保证低频精确匹配不会被高频前缀词挤出。
4. 实现候选分页，使用 `candidate_page_size`、PageUp/PageDown 和方向键翻页，数字键选择当前页候选。
5. 改进标点上屏行为：组合中输入标点时提交当前页首选候选加标点，无候选时才回退提交原始输入加标点。
6. 融合用户词库和基础词库排序，按 exact/prefix 层级、用户词加成、频率和稳定 tie-break 排序，而不是把用户词整体置顶。
7. 接线结构化、脱敏错误日志；数据库失败只能记录错误码，不能记录 raw input、拼音、候选词或上下文。
8. 增加 Stage 9 source scaffold 检查并纳入 CI。

验收：

```text
base lexicon lookup uses compact-pinyin prefix index
user lexicon lookup uses compact_pinyin range query instead of LIKE
exact user matches survive prefix query limits
PageUp/PageDown changes visible candidate page
digit selection applies to current visible page
nihao, commits 你好,
user lexicon failures emit sanitized error-code log events
bash scripts/check_stage09_core_sources.sh 通过
cargo test --workspace 通过
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-09 标记为 completed。
2. 在 `CHANGELOG.md` 写入核心引擎生产化变更。
3. 在 `docs/OPEN_ITEMS.md` 关闭已完成的 core open items，并保留生产词库许可证待办。
4. 如果是 Git 仓库，提交 `stage-09: harden core engine for production dictionaries`。

### 阶段 10：平台宿主体验打磨

任务：

1. Windows 候选窗优先使用 `ITfContextView::GetTextExt` 定位，拿不到 text extent 时才回退旧 caret 位置。
2. Windows 候选窗增加高 DPI 缩放、系统明暗主题适配、屏幕工作区裁剪和窗口类反注册。
3. macOS 输入法菜单增加偏好设置窗口，支持常用设置开关并在保存后重载输入引擎。
4. 增加 Stage 10 source scaffold 检查并纳入 CI。
5. 保留需要真实 Windows/macOS 应用验证的体验项，不把未验证项标为完成。

验收：

```text
Windows candidate popup uses ITfContextView::GetTextExt when available
Windows candidate popup uses DPI-aware sizing
Windows candidate popup follows Windows app light/dark preference
Windows candidate popup class unregisters on DLL unload
macOS IMK menu exposes Preferences...
macOS preferences window edits strict privacy, prediction, and user learning settings
bash scripts/check_stage10_platform_host_sources.sh 通过
bash scripts/build_macos_imk.sh 通过
Windows TSF compile CI 通过
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-10 标记为 completed。
2. 在 `CHANGELOG.md` 写入平台宿主体验打磨变更。
3. 在 `docs/OPEN_ITEMS.md` 关闭已完成的 host polish open items，并保留真实平台验证和 TSF display attribute 待办。
4. 如果是 Git 仓库，提交 `stage-10: polish platform host experience`。

### 阶段 11：设置、隐私与 iOS 存储闭环

任务：

1. 将 `config/default_settings.json` 作为平台宿主的默认设置模板来源；Windows、macOS、iOS 只在运行时补平台本地 `user_lexicon_path`。
2. 强化 Rust settings JSON 和用户词库 TSV 导出的写入路径，使用同目录临时文件和替换/回滚清理，避免直接 remove+rename。
3. 在平台设置 UI 中继续隐藏 CapsLock toggle，直到 Windows/macOS/iOS 宿主具备明确的 CapsLock 语义支持。
4. 为 iOS 容器 App 和 Keyboard Extension 增加 App Group entitlement、共享 settings 文件、共享用户词库路径，并保持用户学习默认关闭，只有用户在容器 App 明确开启后才写入学习数据。
5. 完善 iOS 容器 App 的 Full Access、无网络、App Group、本地学习说明，并支持清理共享 SQLite/WAL/SHM 文件。
6. iOS 键盘模式 UI 必须从 C ABI `ImeOutput.mode` 推导，不再用本地布尔值猜测。
7. iOS Globe key 必须尊重 `needsInputModeSwitchKey`，系统不要求时隐藏该键。
8. 增加 Stage 11 source scaffold 检查并纳入 CI。

验收：

```text
config/default_settings.json parses and matches Rust ImeSettings::default
desktop hosts reference packaged default_settings.json
settings JSON and user lexicon TSV exports use shared AtomicFile helper
platform settings UI does not expose CapsLock toggle
iOS App Group entitlements exist for app and extension
iOS learning is opt-in and disabled by default
iOS bridge passes settings path into ime_engine_new
iOS mode UI derives from ImeOutput.mode
iOS Globe key respects needsInputModeSwitchKey
bash scripts/check_stage11_settings_privacy_sources.sh 通过
cargo test --workspace 通过
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-11 标记为 completed。
2. 在 `CHANGELOG.md` 写入设置、隐私和 iOS 存储闭环变更。
3. 在 `docs/OPEN_ITEMS.md` 关闭已完成的 settings/privacy/iOS open items，并保留需要真实 iOS 烟测或发布签名的事项。
4. 如果是 Git 仓库，提交 `stage-11: close settings privacy and ios storage gaps`。

### 阶段 12：发布打包与分发

任务：

1. 编写 `docs/release_distribution_plan.md`，明确 public release gates：最终 License、生产词库来源/许可证、签名证书、notarization、iOS provisioning、平台 smoke records、隐私姿态和版本号一致性。
2. Windows 打包脚本增加 SignTool 支持，可签名 staged `.dll`、`.exe` 和 MSI；release candidate 必须能通过 `-RequireSigning` 强制失败而不是静默产出未签名包。
3. macOS app build 支持 Developer ID Application 签名和 hardened runtime；pkg 脚本支持 Developer ID Installer 签名、notarytool 提交和 stapler。
4. iOS 增加 App Store archive/export 脚本，要求 owner 提供 Apple team ID 和 ExportOptions plist；补充 App Store metadata/provisioning 模板。
5. 决定首版自动更新策略：首个公开版本先走平台原生分发渠道，不内置 Sparkle/MSIX/App Installer，直到签名、更新密钥、回滚和隐私文案准备好。
6. 增加 Stage 12 source scaffold 检查并纳入 CI。
7. 更新 `docs/OPEN_ITEMS.md`：关闭已形成决策的自动更新项；保留最终 License、生产词库、签名凭证、notarization/App Store provisioning 和真实平台 smoke evidence。

验收：

```text
docs/release_distribution_plan.md includes release gates
Windows packaging supports Sign-Artifact, TimestampUrl, and -RequireSigning
macOS build supports PRIVATE_PINYIN_MAC_APP_SIGN_IDENTITY and hardened runtime
macOS package script supports PRIVATE_PINYIN_MAC_INSTALLER_SIGN_IDENTITY, notarytool, and stapler
iOS package script requires PRIVATE_PINYIN_IOS_TEAM_ID and runs xcodebuild -exportArchive
iOS App Store metadata/export-options templates exist
automatic update strategy is recorded
bash scripts/check_stage12_release_sources.sh 通过
existing Rust and platform scaffold checks 通过
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-12 标记为 completed。
2. 在 `CHANGELOG.md` 写入发布打包与分发准备变更。
3. 在 `docs/DECISIONS.md` 记录发布打包边界和自动更新策略。
4. 在 `docs/OPEN_ITEMS.md` 更新 License、生产词库、签名、notarization、App Store provisioning 和 smoke-test release gates。
5. 如果是 Git 仓库，提交 `stage-12: prepare release packaging and distribution`。

### 阶段 13：词库导入与生产词库

任务：

1. 将运行时嵌入词库切换到 active 资产 `ime_core/assets/base_lexicon.tsv` 和 `ime_core/assets/bigram.tsv`，保留原始 sample 文件作为测试 fixture。
2. 提供第一方 starter 词库，让本地安装包不再只包含八条开发样例词。
3. 新增 `tools/lexicon_builder`，支持把本地 `private-pinyin-tsv`、CC-CEDICT 风格文件、mozillazg pinyin-data、AOSP PinyinIME rawdict 转换为项目标准 TSV，并生成 manifest。
4. manifest 必须记录来源、许可证、版本、输出条目数和 `release_approved`，默认不得把第三方导入结果视为可发布。
5. 更新 `docs/lexicon_data_policy.md`，明确 starter 数据不等于正式生产词库；owner 批准生产来源后，记录确切来源版本、第三方声明和 release-approved manifest。
6. 增加 Stage 13 source scaffold 检查并纳入 CI。

验收：

```text
ime_core embeds base_lexicon.tsv and bigram.tsv
production base lexicon can return common terms such as 干嘛, 什么, 电脑
private-pinyin-lexicon build-base can convert project TSV, pinyin-data, and AOSP rawdict inputs into validated output plus manifest
manifest records release_approved and defaults to false
docs/lexicon_data_policy.md explains the production data source and remaining release gates
bash scripts/check_stage13_lexicon_sources.sh 通过
cargo test --workspace 通过
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-13 标记为 local review 或 completed。
2. 在 `CHANGELOG.md` 写入生产词库和导入工具变更。
3. 在 `docs/DECISIONS.md` 记录词库导入边界和生产数据来源。
4. 在 `docs/OPEN_ITEMS.md` 更新生产词库 open item。
5. 如果是 Git 仓库，提交 `stage-13: add lexicon import pipeline and production dictionary`。

### 阶段 14：iOS 签名与 App Group 配置

任务：

1. 将 iOS App Store 打包脚本改为显式要求 Apple Team ID、容器 App bundle ID、Keyboard Extension bundle ID、App Group ID 和 ExportOptions plist。
2. Xcode 工程中的 `PRODUCT_BUNDLE_IDENTIFIER` 和 App Group entitlement 必须通过 build setting 注入，保留本地开发默认值，但发布时可由环境变量覆盖。
3. iOS 运行时读取 App Group ID 时应从 Info.plist/build setting 获取，并保留本地默认兜底；不得只依赖源码硬编码。
4. 提供 owner 本地复制使用的 signing env 示例文件，并忽略真实 `Signing.env` 和 `ExportOptions.plist`。
5. 打包脚本必须在 archive 前校验 ExportOptions plist 是否包含与当前 bundle ID 一致的 provisioning profile 映射。
6. 增加 Stage 14 source scaffold 检查并纳入 CI。

验收：

```text
scripts/package_ios_app_store.sh requires PRIVATE_PINYIN_IOS_TEAM_ID
scripts/package_ios_app_store.sh requires app bundle, keyboard bundle, and App Group inputs
Xcode project PRODUCT_BUNDLE_IDENTIFIER uses PRIVATE_PINYIN_IOS_* build settings
iOS App Group entitlements use PRIVATE_PINYIN_IOS_APP_GROUP_ID build setting
IosSettingsStore reads PrivatePinyinAppGroupIdentifier from Info.plist with a default fallback
Signing.env.example exists and local Signing.env/ExportOptions.plist are ignored
bash scripts/check_stage14_ios_signing_sources.sh 通过
bash scripts/check_ios_keyboard_sources.sh 通过
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-14 标记为 local review 或 completed。
2. 在 `CHANGELOG.md` 写入 iOS 签名与 App Group 配置变更。
3. 在 `docs/DECISIONS.md` 记录 iOS signing 配置边界。
4. 在 `docs/OPEN_ITEMS.md` 更新 iOS provisioning/TestFlight open item。
5. 如果是 Git 仓库，提交 `stage-14: configure ios signing and app group inputs`。

### 阶段 15：iOS 模拟器/本地开发构建

任务：

1. 修通并验证 `scripts/build_ios_keyboard.sh` 的模拟器构建路径。
2. 新增 iOS smoke readiness 脚本，自动构建 iOS Simulator app 和 Keyboard Extension。
3. readiness 脚本必须检查 build 产物存在、app/extension bundle ID 展开、App Group ID 展开、`RequestsOpenAccess=false`、`PrimaryLanguage=zh-Hans`、默认设置资源打包和 Keyboard Extension 无网络源码姿态。
4. 新增 iOS keyboard smoke record，明确自动项和必须人工验证的系统交互项。
5. 模拟器基础冒烟必须覆盖：容器 App 可安装、系统设置可添加键盘、Notes 中可输入 `nihao -> 你好`。
6. 平台 smoke test plan 必须指向 readiness 脚本。
7. 增加 Stage 15 source scaffold 检查并纳入 CI。

验收：

```text
scripts/run_ios_smoke_readiness.sh builds simulator app and extension
readiness checks built Info.plist identifiers and App Group expansion
readiness checks RequestsOpenAccess=false
readiness checks default_settings.json is bundled in app and extension
docs/ios_keyboard_smoke_record.md separates automated readiness from manual keyboard checks
simulator can install the container app
simulator Settings can add the keyboard
Notes can input nihao -> 你好
bash scripts/check_stage15_ios_smoke_sources.sh 通过
bash scripts/run_ios_smoke_readiness.sh 通过
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`，把 stage-15 标记为 local review 或 completed。
2. 在 `CHANGELOG.md` 写入 iOS smoke readiness 变更。
3. 在 `docs/DECISIONS.md` 记录自动 readiness 与手动 smoke 的边界。
4. 在 `docs/OPEN_ITEMS.md` 更新 OI-038，保留真实系统交互验证项。
5. 如果是 Git 仓库，提交 `stage-15: add ios smoke readiness automation`。

### 阶段 16：TestFlight Archive 与上传

任务：

1. 修通并验证 `scripts/package_ios_app_store.sh` 的 archive/export 流程。
2. 使用 Owner 的 Apple Developer Team、bundle IDs、App Group、provisioning profiles 和 ExportOptions plist 构建签名 archive。
3. 产出可上传 App Store Connect 的 export 结果。
4. 增加 TestFlight upload ExportOptions 模板，并在 upload 模式下显式要求 App Store Connect API key path、key ID 和 issuer ID。
5. 上传 App Store Connect，并记录 TestFlight build 编号、处理状态和可分发状态。

验收：

```text
package_ios_app_store.sh produces archive/export
archive/export uses configured Team ID, bundle IDs, App Group, and profiles
upload mode requires App Store Connect API key inputs
docs/ios_testflight_upload_record.md tracks build number, processing, and distribution status
uploaded build appears in App Store Connect
TestFlight build can be distributed for testing
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`。
2. 在 `CHANGELOG.md` 写入 TestFlight archive/upload 准备。
3. 在 `docs/OPEN_ITEMS.md` 更新 OI-035。
4. 在 `docs/DECISIONS.md` 记录 archive/export 与真实 upload 证据边界。
5. 如果是 Git 仓库，提交 `stage-16: prepare ios testflight archive and upload`。

### 阶段 17：真机键盘行为与隐私闭环

任务：

1. 在真实 iPhone/iPad 上完成键盘行为冒烟记录。
2. 验证 Notes/Safari 可输入，密码/电话字段回退系统键盘。
3. 验证 Full Access 默认关闭。
4. 验证 App Group、用户学习开关和本地学习数据策略。
5. 明确 `RequestsOpenAccess=false` 下 iOS 学习功能是否可用；如不可用，记录产品决策。

验收：

```text
Notes/Safari can input Chinese through the keyboard
password and phone fields fall back to system keyboard
Full Access is off by default
learning toggle behavior is documented and matches implementation
device smoke record is complete
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`。
2. 在 `docs/OPEN_ITEMS.md` 更新或关闭 OI-038。
3. 如学习策略变化，更新隐私文档和 App Store metadata。
4. 如果是 Git 仓库，提交 `stage-17: validate ios device keyboard privacy behavior`。

### 阶段 18：App Store 发布准备

任务：

1. 准备 App Store 截图、描述、关键词、年龄分级、支持 URL、隐私 URL、隐私标签和审核说明。
2. 更新 App Store Connect metadata 记录。
3. 编写提交前 release checklist。
4. 确认 TestFlight 审查/提交前检查通过。

验收：

```text
App Store Connect metadata is complete
privacy labels match local-only implementation
support/privacy URLs are ready
release checklist passes before submission
TestFlight review or pre-submission checks pass
```

阶段完成后必须保存：

1. 更新 `docs/DEVELOPMENT_PROGRESS.md`。
2. 在 `CHANGELOG.md` 写入 App Store release-prep 变更。
3. 在 `docs/OPEN_ITEMS.md` 更新 App Store metadata/release gates。
4. 如果是 Git 仓库，提交 `stage-18: prepare ios app store release metadata`。

---

## 11. Codex 首次开发提示词

把下面内容直接交给 Codex：

```text
请根据 docs/private_pinyin_ime_development_spec.md 创建一个跨平台中文拼音输入法工程。

先只实现阶段 1 到阶段 3：
1. Rust 核心输入引擎。
2. 中文候选。
3. 中文联想雏形。
4. 用户词库。
5. 严格隐私模式。
6. C ABI。
7. CLI 测试工具。

暂时不要实现 Windows、macOS、iOS 平台宿主，只创建目录和 README 占位。

硬性要求：
1. 每个阶段开始前读取 docs/private_pinyin_ime_development_spec.md、docs/DEVELOPMENT_PROGRESS.md、CHANGELOG.md。
2. 每个阶段完成后重新读取开发文档，对照验收标准核对进度。
3. 每个阶段完成后更新 docs/DEVELOPMENT_PROGRESS.md、CHANGELOG.md。
4. 有技术决策时更新 docs/DECISIONS.md。
5. 有未完成事项时更新 docs/OPEN_ITEMS.md。
6. 默认无网络访问。
7. 不引入任何遥测 SDK。
8. 不记录用户输入内容到日志。
9. 所有核心逻辑必须有单元测试。
10. 词库先使用 assets/base_lexicon_sample.tsv，小型样例即可。
11. FFI API 必须提供 c_api.h。
12. Rust FFI 边界不得 panic。
13. README 里写清楚如何运行测试和 CLI。

请输出完整文件结构、关键源码、测试文件和运行说明。
```

---

## 12. 关键验收清单

桌面 MVP 完成时，必须满足：

1. Windows 和 macOS 都能真实输入中文。
2. `nihao`、`zhongguo`、`jintian`、`woxiangqu` 有合理候选。
3. 中文联想可用。
4. Shift 中英文切换稳定。
5. 安装和卸载流程可重复。
6. 默认无网络请求。
7. 用户可以关闭学习。
8. 用户可以清空本地词库。
9. 候选响应速度达标。
10. 常见输入场景不崩溃。
11. 文档进度记录完整。
12. 每阶段完成后都有保存记录。

---

## 13. 官方参考资料

只使用英文官方资料作为技术参考。

1. Microsoft Text Services Framework and IME requirements  
   https://learn.microsoft.com/en-us/windows/apps/develop/input/input-method-editor-requirements

2. Microsoft Text Services Framework overview  
   https://learn.microsoft.com/en-us/windows/win32/tsf/text-services-framework

3. Apple InputMethodKit  
   https://developer.apple.com/documentation/inputmethodkit

4. Apple Custom Keyboard Extension  
   https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html

---

## 14. 开发建议

优先让 Codex 完成阶段 1 到阶段 3。平台宿主开发会卡在系统 API、签名、安装、权限、候选窗口细节上。先把核心引擎、测试、FFI 边界做稳，后续接 Windows TSF 和 macOS InputMethodKit 时成功率更高。
