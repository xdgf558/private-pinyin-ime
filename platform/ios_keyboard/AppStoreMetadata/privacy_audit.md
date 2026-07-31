# STORE-01 隐私审计

## App Store 隐私回答

- 跟踪：否
- 收集数据：否
- 广告或第三方分析：无
- 账号、登录或云端用户资料：无
- 键盘完全访问：不申请，`RequestsOpenAccess=false`
- 加密出口合规：`ITSAppUsesNonExemptEncryption=false`

## 目标级清单

| Target | 需要理由的 API | 理由 | 用途 |
| --- | --- | --- | --- |
| Container App | `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | 保存容器 App 自身的布局和输出偏好备份 |
| Keyboard Extension | `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | 保存扩展自身的布局和输出偏好备份 |
| Keyboard Extension | `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | 限定输入回调抑制和调试冒烟的本地时间窗 |

两个 target 各自携带 `PrivacyInfo.xcprivacy`。它们都声明不跟踪、没有跟踪域名、不收集数据。

## 网络边界

- 键盘扩展源码不使用 `URLSession`、`Network.framework` 或第三方网络库。
- 容器 App 只在用户明确点击后，通过短生命周期 `URLSession` 下载已固定来源与哈希的雾凇拼音词库文件。
- 下载请求不携带输入内容、用户学习数据、设备标识符或账号信息。

## 本地数据保留与删除

- 组词与候选状态只在当前会话内存中保留。
- 用户学习记录和导入词库保存于 App Group 或应用容器。
- 用户可在 App 中关闭学习、清除学习记录或清除导入词库；卸载 App 也会删除应用本地数据。
- 项目不运行服务器端用户数据库，因此不存在服务器端账号删除流程。
