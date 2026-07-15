# N4 原生 macOS 验收矩阵

> 状态：In Progress · 2026-07-15  
> 目标：使用可复现证据判断原生版本是否具备替代 Catalyst 的条件；没有证据的项目不记为完成。

## 验收矩阵

| 领域 | 原生完成条件 | 当前证据 | 状态 |
|---|---|---|---|
| 构建与启动 | `SensenStoryNative` 无签名 Debug 构建并启动 | `xcodebuild` 成功；Computer Use 可读取主窗口和五个导航入口 | 通过 |
| 首条发送 | quick 先到，UI 不冻结，plan/deep 后续完成 | 真实 DeepSeek quick `1.34s`、总计 `10.46s`；隔离数据库实机发送未复现 AttributeGraph 循环 | 通过 |
| 双阶段消息 | quick/deep 均保留，不覆盖、不重复开头 | N2 契约测试、真实 3 条持久化消息、重复前缀清理测试 | 通过 |
| 三形态头像 | quick/deep 使用同一形态，表情属于该形态，右栏随最新回复变化 | 7+8+5 张资源入包；契约覆盖三形态与 quick/plan 冲突；可控 fixture 实机确认默默兔 quick-only、悠然兔 quick+deep 的标题、消息头像和右栏头像同步变化 | 通过 |
| 对话轨迹 | 位于左侧，不遮挡系统滚动条；每轮连续命中、可跳转 | 44pt 连续命中区；预览不接收点击；实机可见 | 通过 |
| 本周心流 | 聊天时不自动切换；页面返回时推进；可进入完整详情 | 实机停留 2.5 秒保持不变；返回夜谈推进一次；标题栏入口可点击 | 通过 |
| 本地资料 | 记忆、日记、状态、会话分类清楚，来源可进入 | 8 类记忆计数守恒；日记按 session 去重；状态历史字段、会话关联详情实机可见 | 通过 |
| 总结闭环 | 结束后展示 journal、记忆、长期状态更新并可再次总结 | 重复总结契约通过；隔离数据库实机完成真实总结，卡片默认展开、按钮禁用、后台心流不阻塞 | 通过 |
| TTS | 只朗读实时新回复；页面返回或打开历史会话不重播；停止会中止后台生成；失败不阻塞文字 | Native/Catalyst 均改用 live-assistant 事件；真实 4-bit 服务短句流式 `5.6s`、108 字长文本 `22.4s`、缓存 `0.001s`；4 个长文本分段全部一次成功；离线、停止和真实生成中取消后恢复均通过 | 部分通过：待解锁后完成原生 UI 试听 |
| 内存 | 无持续单调增长，不接近 2GB 保护线 | 20 分钟净增 `112 KB`；最新 Native 20 秒 peak `121.9 MB`、early `121.9 MB`、late `121.8 MB`、growth `-0.1 MB` | 通过 |
| Catalyst 对照 | 同一脱敏数据完成核心功能和性能对比 | 两端同版本构建通过；20 秒空闲 RSS：Native peak `131.6 MB` / growth `11.2 MB`，Catalyst peak `151.5 MB` / growth `8.1 MB` | 部分通过：待同数据 UI 功能对照 |

## 固定验证命令

```bash
./scripts/test_native_n2.sh
./scripts/test_native_n2_memory.sh
./scripts/test_native_deepseek_smoke.sh
./scripts/test_native_speech_offline.sh
./scripts/test_tts_service.sh
./scripts/test_tts_cancel.sh
xcodebuild -project ios/XiaodongwuYetanhui.xcodeproj \
  -scheme SensenStoryNative -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ios/DerivedData-Native \
  CODE_SIGNING_ALLOWED=NO build
```

## 下一批验收

1. 解锁 Mac 后，在原生 UI 覆盖 quick 播放、deep 预取、停止与页面返回不重播。
2. 使用同一份脱敏数据运行 Catalyst/原生关键页面对照，再决定是否进入 N5。
