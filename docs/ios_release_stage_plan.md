# iOS Release Stage Plan

本文档记录 iOS 版本从签名配置到 App Store 发布准备的后续阶段。共享 Rust
引擎、Keyboard Extension 原型、设置存储和签名脚手架已经存在；后续按下面阶段推进。

| 阶段 | 目标 | 主要产出 | 验收标准 |
|---|---|---|---|
| Stage 14 | iOS 签名与 App Group 配置 | Bundle ID、App Group、entitlements、ExportOptions 正式模板 | Xcode 能识别团队和 profiles，容器 App 与 Keyboard Extension 都带 App Group |
| Stage 15 | iOS 模拟器/本地开发构建 | 修通 `build_ios_keyboard.sh`，跑模拟器基础冒烟 | 模拟器可安装、可添加键盘、可输入 `nihao -> 你好` |
| Stage 16 | TestFlight Archive 与上传 | 修通 `package_ios_app_store.sh`，产出 archive/export，上传 App Store Connect | TestFlight build 出现在 App Store Connect，可分发测试 |
| Stage 17 | 真机键盘行为与隐私闭环 | 真机冒烟记录，确认 Full Access / App Group / 学习功能策略 | Notes/Safari 可输入；密码/电话框回退系统键盘；Full Access 默认关闭；学习开关行为明确 |
| Stage 18 | App Store 发布准备 | 截图、描述、隐私标签、年龄分级、支持/隐私 URL、发布 checklist | App Store Connect 元数据完整，TestFlight 审查/提交前检查通过 |

## Notes

- Stage 15 可以自动化构建和产物检查，但添加键盘、Notes 输入等系统交互仍需要模拟器或真机人工证据，除非后续找到稳定自动化路径。
- Stage 16 依赖 Owner 提供 Apple Developer team、bundle identifiers、App Group capability、provisioning profiles 和 App Store Connect 权限。
- Stage 17 必须确认 `RequestsOpenAccess=false` 下 iOS 学习功能是否可用；如果系统沙箱阻止共享存储，需要记录产品决策。
