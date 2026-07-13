# N2 数据字段与界面矩阵

本矩阵用于确认 SQLite/API 中的资料不会只被保存而无法查看。Native 使用本地 SQLite；Web/Catalyst 保留 Python API 兼容路径。

| 数据 | 关键字段 | Web UI | Mac Catalyst | iOS | Native macOS |
|---|---|---|---|---|---|
| Session | 时间、消息数、预览、结束状态 | Session 看板与详情 | 历史会话，可展开并续聊 | 历史会话详情 | 本地资料 → 会话，可续聊 |
| Message | 角色、正文、形态、表情、quick/deep、知识卡 | 对话与调试面板 | 夜谈、阶段标签、对话轨迹 | 夜谈消息 | 夜谈、阶段标签、对话轨迹 |
| Memory | 大类、小类、正文、证据、关键词、重要度、来源、更新时间 | 分类地图、最近更新、Session 关联 | 分类地图、最近更新、叶节点详情 | 记忆列表与详情 | 本地资料 → 记忆 |
| Journal | 总结、情绪曲线、关键词、洞察、下一步、心情分、主情绪、Session | 日记与 Session 总结 | 周报、心情曲线、日记详情、Session 关联 | 日记列表与 Session 详情 | 本地资料 → 日记 |
| State profile | 六类 domain、阶段、总结、强度、趋势、置信度、证据、支持方式、来源、更新时间 | 长期状态看板 | 六类卡片与详情 | 长期状态页 | 本地资料 → 长期状态 |

## 验证入口

- Python/Web：`python3 -m app.evaluation.runner` 与 `python3 -m app.evaluation.check_sse_stream`。
- Swift 数据契约：`./scripts/test_native_n2.sh`，覆盖消息阶段以及 Journal、Memory、State profile 字段往返。
- Mac 构建：Native、Mac Catalyst 分别执行对应 `xcodebuild`。
- 性能：`./scripts/test_native_n2_memory.sh` 检查原生 App 空闲 RSS 上界与增长。
