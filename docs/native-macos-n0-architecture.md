# N0 原生 macOS 架构盘点与迁移 ADR

> 状态：Accepted · 2026-07-13  
> N = Native macOS；0 = 正式迁移前的第零阶段。

## 结论

采用**同一 Xcode 工程、独立原生 macOS target、共享现有源码**的渐进迁移方案。保留 Catalyst 作为可运行基线，直到原生版本完成夜谈纵切和稳定性对比；不进行一次性重写。原生 macOS 路径使用本地 SQLite 并直接调用 DeepSeek，不要求启动 Python 后端；Web/Catalyst 暂时保留 Python API 兼容路径。

当前工程约 22 个 Swift 文件、20,558 行。只有 3 个文件直接 `import UIKit`，共有 16 处 Catalyst 条件分支，因此大部分 Models、Services 和 SwiftUI 视图具备复用基础。主要成本来自平台适配和现有大文件拆分，而不是业务逻辑重写。

## 目标架构

```text
Web / Catalyst                     Native macOS（新主线）
Python API + data/app.db           LocalDeepSeekService + local SQLite
          ↘                         ↙
       Shared Swift Core（Models / Services / data contract）
```

原生 App 使用自己的沙盒 SQLite 作为运行数据源，不直接读写仓库数据库。聊天采用 `quick + plan` 并行，plan 决定是否继续 deep；这条路径不使用 SSE。SSE 只作为 Web/Catalyst 的兼容协议保留。

## 依赖矩阵

| 区域 | 复用判断 | N1 处理 |
|---|---|---|
| `Models/CompanionModels.swift` | 高 | 共享；保留平台颜色适配 |
| `LocalDeepSeekService` | 高 | 原生直连 DeepSeek 的 Foundation 网络层 |
| `ChatService` | 中 | 仅供 Web/Catalyst Python/SSE 兼容路径复用，不加入原生发送链路 |
| `InteractionService`、`RecommendationService` | 高 | 直接共享 |
| `SpeechService` | 中高 | 共享 AVFoundation；验证 macOS 音频会话与播放队列 |
| `SQLiteDatabase` | 中高 | 共享 schema；抽离数据库 URL 策略 |
| `CompanionStore` | 中 | 共享业务状态；逐步消除散落的 Catalyst 编译判断 |
| `SendInstrumentation` | 高 | 共享日志、关联 ID 和 heartbeat |
| `SecureSettingsStore` | 中 | N1 前改为 Keychain；当前实现实际使用 UserDefaults |
| `MacPrototypeView` | 中高 | 作为原生夜谈 UI 来源；后续按页面拆分 3,500+ 行大文件 |
| `SettingsView` | 中 | 用 `fileImporter` 或 `NSOpenPanel` 替换 UIKit 文档选择器 |
| `SharedViews` | 中高 | 用平台中立资源加载替换 `UIImage` |
| `ChatView`、`CompanionGardenView` | 低/暂缓 | iOS 体验保留，不加入 N1 原生 target |

## 已识别的平台阻塞

1. `SharedViews`、`ChatView`、`CompanionGardenView` 直接依赖 UIKit 图像或触觉 API。
2. `SettingsView` 使用 `UIDocumentPickerViewController`、`UIApplication` 和 iOS 导航修饰符。
3. `CompanionStore`、`SQLiteDatabase`、`SettingsView` 中平台能力通过编译条件分散表达，应收敛为运行环境能力。
4. `SecureSettingsStore` 文案声称使用系统钥匙串，实际存入 UserDefaults；必须在原生版本接入真实数据前修复并迁移旧值。
5. `MacPrototypeView`、`ChatView`、`StateOverviewView` 都超过 3,000 行。N1 不整体重构，N2 按纵切拆分。

## N1 原生壳范围（已实现）

新增一个原生 macOS SwiftUI application target，并完成：

- 独立 App 入口、单窗口和三栏导航。
- 设置页基础框架、DeepSeek 连接状态和诊断入口。
- 空夜谈页面及缓存只读加载。
- 原生菜单：新夜谈、结束总结、设置、显示/隐藏侧栏。
- Models、网络、SQLite、日志代码通过共享 target membership 引入，不复制文件。

N1 **不包含**真实发送、流式回复、TTS 自动播放、完整数据页面或移除 Catalyst。

实现落点：独立 scheme/target `SensenStoryNative`，入口与壳界面位于 `ios/SensenStoryMac/`。原生壳已能启动、切换侧栏、读取沙盒 SQLite 概览，并提供 DeepSeek 诊断与设置入口；`scripts/run_native_mac.sh` 可从命令行构建并启动。Catalyst target 同时保持可构建。

## N1 进入条件与验收

进入前：移除敏感 Key 日志；确定 Keychain 迁移策略；建立 Catalyst 当前启动内存基线。

完成条件：原生 target 可无签名 Debug 构建并启动；导航与设置可点击；离线时展示缓存或明确空状态；空闲 10 分钟无持续内存增长；Catalyst 仍可构建运行。当前构建、启动、导航、缓存读取与 Catalyst 回归已通过；长时间空闲内存观察并入 N2 纵切前的稳定性基线。

## 后续顺序

1. N1 原生壳（已完成）。
2. N2 夜谈纵切（已实现）：DeepSeek 直连、quick/plan 并行、按需 deep、轨迹和本地持久化。
3. N3 数据纵切：同步、记忆、日记、长期状态和心流。
4. N4 使用相同数据进行 Catalyst/原生功能与性能对比。
5. N5 达到稳定性退出门槛后切换默认产品。
