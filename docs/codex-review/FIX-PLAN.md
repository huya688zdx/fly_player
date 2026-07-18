# FIX-PLAN —— 全项目评审修复计划

> 汇总自 8 个评审窗口共 **264 条已确认 finding**（findings/A~H.md），已按主题去重归批。
> **范围调整与收口（用户决策 2026-07-03，删除计划已完成）**：Flutter 播放页面、旧 `PlayerActivity` 宿主、Flutter 弹幕
> `render/controller` 已删除；播放契约已迁至 `lib/playback/`。`lib/danmaku/api/`、弹幕源 store、弹幕导入 parser、mpv
> 设置/书签/截图 store 为活代码，不属于废弃区。

## 1. 总览

| 分类 | 条数 | 处理 |
|---|---|---|
| 已删除废弃区（Flutter 播放器及其专属附件） | 74 | 不修，已随删除计划一次性消灭 |
| 活代码待修 | 190 | 按下方批次 S/X/M/P/R/I/O 执行 |

活代码问题的四大主题：**多后端抽象泄漏**（约 60 条，最大主题）、**错误处理空 catch**（约 35 条）、
**性能/主线程 IO/图片解码**（约 25 条）、**i18n 模型层文案**（约 22 条）；另有安全 5 条、崩溃/数据丢失约 25 条、结构拆分约 18 条。

## 1.1 已修复登记表维护规则

后续 AI 继续修复本计划中的 finding 时，必须同步更新下方表格，方便后来者一眼看清“哪些已经做完、做到什么程度、证据在哪里”。

填写规则：
1. 每完成一组 finding，就在“已修复登记表”新增或更新一行；不要只在分批章节里追加散文说明。
2. `状态` 只能填：`已修复`、`部分修复`、`已废弃不修`。如果还有尾巴，必须写成 `部分修复` 并在 `剩余事项` 写清楚。
3. `验证/证据` 至少填写测试命令、静态检查、人工验证、提交号之一；如果暂未验证，写 `待验证`，不要留空。
4. `提交/来源` 优先填 commit hash；还未提交时填 `本地未提交` 或 `本次工作区变更`。
5. 同一 finding 不要重复登记多行；补充修复时更新原行，并把 `剩余事项` 清空或改为新的尾项。
6. 如果分批章节里的“已修复”文字与本表冲突，以本表为准，并同步修正分批章节。

## 1.2 已修复登记表

| 日期 | 批次 | Finding / 范围 | 状态 | 修复内容摘要 | 提交/来源 | 验证/证据 | 剩余事项 |
|---|---|---|---|---|---|---|---|
| 2026-07-09 | S 安全 | G-029 / G-032 | 已修复 | 两个 WebView 登录页遇到 SSL 证书错误时默认 `cancel()` 并提示，不再静默 `proceed()` 或自动提交凭据。 | 本次提交 | 待验证 | 无 |
| 2026-07-09 | S 安全 | B-027 | 已修复 | `PrivateNetworkHttpOverrides` 仅允许 RFC1918、loopback、link-local、IPv6 ULA 和显式注册 NAS host 跳过证书校验，公网 IP 不再放行。 | 本次提交 | 待验证 | 无 |
| 2026-07-09 | S 安全 | B-011 | 已修复 | 新增平台安全凭据存储；登录历史、后端连接、飞牛旧会话的密码/token 迁入安全存储，SharedPreferences 只留非敏感描述和存在标记，并迁移清理旧明文。 | `2ccdb49` | 待验证 | 无 |
| 2026-07-16 | S 安全加固 | B-011 回归/加固 | 已修复 | 安全凭据读取采用 `value/missing/unavailable` 三态；瞬时读取失败时保留飞牛和服务器族现有会话，Android 读取失败不再删除密文，写入/删除失败向调用方传播；初始化失败可重试且不会误进入登录页；并发启动、前台恢复和快速重试按单一加载代次合并，避免状态覆盖和重复读取；加载与登录、更新 token、退出、后端保存通过异常安全 FIFO 串行，防止旧快照覆盖新会话；mutation barrier 保证 `load1 → mutation → load2` 不跨屏障合并。 | `76b19a5` / `c8d2065` / `c1112d8` / `520bb2d` / `d3a600d` / `0c50f24` / `7c6d607` / `46a85a6` / `aa97e58` | `flutter test test/services/secure_credential_store_test.dart test/providers/nas_provider_session_stability_test.dart test/providers/backend_session_provider_test.dart test/provider_gate_retry_test.dart test/screens/connection_automatic_load_failure_test.dart`；Android `SecureCredentialStoreTest` | 无 |
| 2026-07-16 | M API/服务层 | A-006 | 已修复 | 普通接口返回 401 时，网络层不再直接调用 `logout()` 清除会话；请求错误仍按原路径向调用方透传。 | `035e1f1` | `flutter test test/feiniu_api_fn_connect_test.dart` | 无 |
| 2026-07-16 | S/P 回归 | 飞牛登录协议选择 | 已修复 | 飞牛登录恢复显式 HTTP/HTTPS 选择，按选择提交实际 URL；Emby 表单与窄屏/大字体响应式布局保持兼容。 | `90896be` / `26efa2e` / `58b956f` | `flutter test test/screens/connection_feiniu_compatibility_test.dart test/screens/connection_backend_selection_test.dart` | 无 |
| 2026-07-09 | S 安全 | A-019 | 已修复 | Emby 媒体图片 URL 移除 `api_key` query，access token 改走 `MediaImageRef.headers`。 | 本次提交 | 待验证 | 无 |
| 2026-07-09 | X 崩溃/数据丢失 | A-001 / F-043 | 已修复 | 新增 `RouteQueryJson` 安全解析 helper，主路由与副栏路由不再因畸形 query JSON 抛异常。 | `1f75fd1` | 待验证 | l10n 文案仍归批次 I 跟进 |
| 2026-07-09 | X 崩溃/数据丢失 | A-040 / A-044 | 已修复 | `MediaInfo` 与 `PlaybackStreamData.header` 增加嵌套类型防护，非法 payload 降级或跳过，合法数据保留。 | `1f75fd1` | 待验证 | 无 |
| 2026-07-09 | X 崩溃/数据丢失 | A-025 | 已修复 | 未知后端 kind 不再静默反序列化为飞牛，连接 store 会过滤坏记录。 | `1f75fd1` | 待验证 | 无 |
| 2026-07-09 | X 崩溃/数据丢失 | B-023 | 已修复 | `AsyncActionGuard` 清理 Future 不再把已由调用方处理的失败变成旁路未处理异步错误。 | `1f75fd1` | 待验证 | 无 |
| 2026-07-09 | X 崩溃/数据丢失 | B-006 | 已修复 | 下载记录持久化改为串行队列，`persistImmediately` 返回可等待 Future，并避免并发共享同一个 `.tmp` 文件。 | `cf41cf4` | 待验证 | 无 |
| 2026-07-12 | X 崩溃/数据丢失 | A-028 | 已修复 | 保存主题解析改为单项隔离；整包损坏时保留损坏原文备份并记录 warning，避免主题数据无迹丢失。 | 本次工作区变更 | `flutter test test/providers/app_theme_provider_corrupt_saved_themes_test.dart` | 无 |
| 2026-07-12 | X 崩溃/数据丢失 | B-018 | 已修复 | 播放统计数据库打开增加 Future 门闩，并发冷启动只共享同一打开流程，失败后允许重试。 | 本次工作区变更 | `flutter test test/services/future_open_gate_test.dart` | 无 |
| 2026-07-12 | X 崩溃/数据丢失 | A-022 | 已修复 | `MediaBackend` 默认收藏/已看操作改为抛出 `UnsupportedError`，不再把请求态伪装成服务端成功。 | 本次工作区变更 | `flutter test test/media_backend/media_backend_default_action_test.dart` | 无 |
| 2026-07-12 | X 崩溃/数据丢失 | G-004 / A-031 | 已修复 | 弹幕设置与并行窗口设置均在持久化失败时恢复旧状态；弹幕页提示失败并异步记录日志。 | 本次工作区变更 | `flutter test test/providers/parallel_window_settings_provider_test.dart test/screens/danmaku_settings_screen_test.dart` | 无 |
| 2026-07-12 | X 崩溃/数据丢失 | B-014 | 已修复 | 新增服务器族进度离线队列；Emby/服务器族原生进度 transient 失败入队，成功重放后删除，并记录异常上下文。 | 本次工作区变更 | `flutter test test/services/playback_progress_offline_queue_test.dart test/services/native_playback_reporter_test.dart` | 无 |
| 2026-07-12 | X 误操作防护 | G-012 | 已修复 | 书签清空与单条删除统一使用确认弹窗，取消时不触发存储变更。 | 本次工作区变更 | 目标 `flutter analyze` | 无 |
| 2026-07-12 | X 误操作防护 | G-013 | 已修复 | 弹幕保存源的两处删除入口统一使用确认弹窗，取消时保留原记录。 | 本次工作区变更 | 目标 `flutter analyze` | 无 |
| 2026-07-12 | X 误操作防护 | G-027 | 已修复 | 登录历史清空与单条删除统一使用确认弹窗，取消时不修改历史。 | 本次工作区变更 | 目标 `flutter analyze` | 无 |
| 2026-07-09 | X 崩溃/数据丢失 | B-007 | 已修复 | 下载转码进度轮询增加 per-record in-flight 防重入，避免并发请求和旧结果覆盖。 | `cf41cf4` | 待验证 | 无 |
| 2026-07-09 | X 崩溃/数据丢失 | A-008 | 已修复 | `recordPlayback()` 校验后端业务 payload，HTTP 200 但 `code != 0` 会进入统一异常路径。 | `cf41cf4` | 待验证 | 无 |
| 2026-07-09 | X 生命周期 | H-003 / H-012 / F-035 | 已修复 | 简介“更多/详情”链接改为 `WidgetSpan + GestureDetector`，不再在 build 中创建需 dispose 的 `TapGestureRecognizer`。 | `cf41cf4` | 待验证 | 无 |
| 2026-07-09 | X 生命周期 | H-025 / F-039 | 已修复 | `TextEditingController` 泄漏问题已按分批记录修复。 | 分批章节记录 | 待验证 | 待补充具体提交和验证 |
| 2026-07-09 | X 生命周期 | H-011 / F-038 / F-030 | 已修复 | 图片 errorBuilder、await 后 setState、bottom sheet pop 后 context 使用等 async gap 问题已按分批记录修复。 | 分批章节记录 | 待验证 | 待补充具体提交和验证 |
| 2026-07-09 | M 多后端抽象 | A-032 / A-039 | 已修复 | 播放 launcher 不再下钻具体 `FeiniuPlaybackContext` / `EmbyPlaybackContext`；新增中立 `MediaPlaybackSourceBridge`，由各后端自供装配器。 | 本次提交 | `test/media_backend/multi_backend_abstraction_boundary_test.dart` | 无 |
| 2026-07-09 | M 多后端抽象 | B-010 / B-012 | 已修复 | `EmbyNativePickerSupport`、`EmbyPlaybackReporter` 改为服务器族命名；原生反向通道飞牛分支改走 `usesLegacyFeiniuFlow` 能力位。 | 本次提交 | 架构回归测试 | 无 |
| 2026-07-12 | M 多后端抽象 | 5.1 基础扩展点 | 已修复 | 后端 kind 继续作为显式扩展点，服务器族统一由注册表描述；播放原生重解析改为注入当前后端；飞牛收藏、人物作品、源信息/版本均补齐公共接口，操作目标改用布尔已看态。 | 本次工作区变更 | `flutter test test/media_backend`；目标 `flutter analyze` | 无 |
| 2026-07-12 | M 多后端抽象 | A-002 / A-024 / A-029 / A-033 / A-020 / A-014 / A-012 | 已修复 | `MediaBackendRegistry` 统一服务器族描述符和遗留飞牛工厂；原生重解析不再直接构造具体后端；飞牛适配器补齐收藏/人物/源信息/版本公共映射；`MediaItemActionTarget.watched` 改为布尔值。 | 本次工作区变更 | `flutter test test/media_backend`；目标 `flutter analyze` | 无 |
| 2026-07-09 | M 多后端抽象 | media_list / login_history 收口 | 已修复 | 媒体列表的首页配置 gate、loadKey、登出分支改用服务器族语义；登录历史服务器族显示名与角标改从注册表描述符读取。 | 本次提交补充 | 架构回归测试 | 无 |
| 2026-07-09 | P 性能 | B-022 | 已修复 | 新增本地字幕异步扫描入口，下载/原生起播路径先异步解析 sidecar 字幕，再构造 `MpvMediaSource`。 | 本次提交 | 待验证 | 无 |
| 2026-07-09 | P 性能 | F-008 | 已修复 | 详情页本地下载文件信息改为下载记录变化时异步刷新快照，`build()` 不再执行 `existsSync/statSync`。 | 本次提交 | 待验证 | 无 |
| 2026-07-09 | P 性能 | G-007 | 已修复 | 下载列表页/下载详情页移除整页高频 `AnimatedBuilder`，列表结构按签名变化刷新，速度和转码进度改为行级局部监听。 | 本次提交 | 待验证 | 无 |
| 2026-07-16 | P 性能回归 | G-007 回归 | 已修复 | 行级监听按任务 ID 重新读取当前 `DownloadTaskRecord`，下载列表和详情不再因闭包持有旧记录而停止刷新。 | `aaea330` | `flutter test test/screens/download_list_back_behavior_test.dart test/download_task_record_test.dart`（覆盖列表/详情刷新） | 无 |
| 2026-07-09 | P 性能 | G-015 | 已修复 | 截图库缩略图按卡片尺寸传入目标解码宽高，全屏预览仍走原图。 | 本次提交 | 待验证 | 无 |
| 2026-07-09 | P 性能 | G-016 | 已修复 | 分辨率排序 metadata 预热改为小批量加载，避免一次性并发解码全部截图。 | 本次提交 | 待验证 | 无 |
| 2026-07-09 | P 性能 | G-017 | 已修复 | 截图库可见项过滤/排序只计算一次，并按分组使用懒构建 `SliverGrid`，不再通过 `Wrap` 一次性构建全部卡片。 | 本次提交 | 待验证 | 无 |
| 2026-07-12 | P 性能 | H-001 | 已修复 | `BottomGlassPanel` 移除真实 `BackdropFilter` 路径，保留兼容参数但统一使用纯色渐变面板。 | 本次工作区变更 | 目标 `flutter analyze` | 无 |
| 2026-07-12 | P 性能 | B-013 | 已修复 | 原生弹幕评论缓存增加 7 天 TTL，payload 临时文件增加 24 小时 TTL，并用带门闩的低频清理避免临时目录持续膨胀。 | 本次工作区变更 | 目标 `flutter analyze`；`flutter test test/services` | 无 |
| 2026-07-12 | P 性能 | A-011 | 已修复 | 飞牛 API 共享读取缓存增加显式清理入口，NAS 登出时同步清理旧 token 对应缓存和进行中的共享请求。 | 本次工作区变更 | 目标 `flutter analyze`；`flutter test test/services` | 无 |
| 2026-07-12 | P 性能 | H-028 | 已修复 | 移除没有实际渲染效果的 `LiquidGlassLevel.liquid` 配置挡位，旧存储值自动降级为 frosted。 | 本次工作区变更 | 目标 `flutter analyze` | 无 |
| 2026-07-12 | P 性能 | G-011 | 已修复 | 存储明细按系列分页展示（单页最多 8 组），展开项只构建当前页内容，避免长列表一次性渲染。 | `e67bafe` | 代码核对：`_storageEntryPageSize` | 无 |
| 2026-07-12 | P 性能 | E-004 | 已修复 | 弹幕文件解析统一通过 `Isolate.run` 执行，网络/本地导入不在 UI isolate 同步解析。 | `735a8e9` | 代码核对：`DanmakuImportParser` | 无 |
| 2026-07-09 | R 结构 | G-002 | 已修复 | mpv 设置标题/副标题映射双份已收敛到 `MpvSettingsL10n.definitionByKey`。 | `abb06d4` | 待验证 | 无 |
| 2026-07-09 | R 结构 | G-034 | 已修复 | 两个 Web 登录页的注入脚本抽为共享 `FnWebLoginBridgeScript`，保留 FN OAuth 探测与 entry-token 阻断页检测差异配置。 | `abb06d4` | 待验证 | 无 |
| 2026-07-09 | R 结构 | H-013 | 已修复 | `TvSeasonDetailPanel` 引入 `TvSeasonPanelHeader/Layout/Actions/Content` 配置对象，现有调用走 `legacy` 过渡工厂。 | `abb06d4` | 待验证 | 无 |
| 2026-07-09 | R 结构 | F-011 / F-013 / F-020 / G-026 / C-001 | 已修复 | 删除不可达或未调用旧代码；`FlutterHostActivity` 补齐 `getGpuProfile` 原生实现。 | `abb06d4` | 待验证 | 无 |
| 2026-07-09 | I i18n / 模型层文案 | 模型/DTO fallback | 已修复 | 模型/DTO 层不再产出用户可见 fallback；空值保持空或结构化 token，由 UI 层负责本地化展示。 | `840a7c0` | 待验证 | 无 |
| 2026-07-09 | I i18n / 模型层文案 | `StreamListOption` 与展示名 fallback | 已修复 | `StreamListOption` 移除对 UI mapper 的反向依赖；语言映射、音轨/字幕显示名、人物演职员展示 fallback 改为后端中立输出。 | `840a7c0` | 待验证 | 无 |
| 2026-07-09 | I i18n / 模型层文案 | 主题展示文案 | 已修复 | `AppThemeProvider` 不再提供英文主题展示文案；主题预设名与自定义名称建议改由 l10n 生成。 | `840a7c0` | 待验证 | 无 |
| 2026-07-09 | I i18n / 模型层文案 | 页面硬编码文案 | 已修复 | 路由错误页、FN Connect Web 登录页、媒体信息页、mpv 缓存滑杆端点、详情简介/链接/下载角标等页面硬编码文案已接入 l10n。 | `840a7c0` | 待验证 | 无 |
| 2026-07-09 | I i18n / 模型层文案 | `TvEpisodeCardData` | 已修复 | 状态颜色从模型层 `Color` 改为语义 tone，组件层再映射主题色。 | `840a7c0` | 待验证 | 无 |

## 2. 已删除废弃区（74 条，不修）

**清单**：
- **D 全部 44 条**（lib/player 页面宿主、core/view mixin、controllers、stores、player services）
- **E 中 22 条**：E-003（danmaku controller）、E-005/E-006（Flutter 弹幕渲染层）、E-008 ~ E-026（播放器 danmaku/settings mixin、panels、player widgets）
- **C 中 4 条**：C-002/C-003（lib/player/services 两个死桥）、C-006/C-007（播放器页面/widget 直建 system channel）
- **B 中 2 条**：B-028/B-029（mpv_proxy_server，D-035 已证实 registerStream 无调用方，本就是死路径）
- **G 中 2 条**：G-035/G-036（player_host_screen，Flutter 播放宿主）

**E 中仍是活代码、不在废弃区**（原生壳弹幕链路仍在用）：E-001/E-002/E-004（`lib/danmaku/api/` DanDanPlay API/config/resolver）、E-007（弹幕保存源 store）。

**删除计划已完成**：旧 Flutter 播放页面、旧宿主 Activity、Flutter 弹幕 render/controller 和死桥已移除；外部本地视频、详情页、剧集页、下载列表均通过 `PlaybackHost` 进入 `NativePlayerActivity`。`MpvMediaSource` 已迁至 `lib/playback/playback_source.dart`，活跃的弹幕 API、弹幕源 store、导入 parser 以及 mpv 设置/书签/截图 store 均已保留。

---

## 3. 批次 S —— 安全（5 条，最优先）

| ID | 问题 | 位置 |
|---|---|---|
| G-029 (P0) | FN Connect WebView 无条件放行 SSL 证书错误，且自动填充凭据 | fn_connect_web_login_page.dart:173 |
| G-032 (P0) | Emby FN 入口 WebView 同样 `onSslAuthError → proceed()` | emby_fn_entry_login_page.dart:100 |
| B-027 (P1) | 全局 HttpOverrides 对**任意能解析为 IP 的主机**跳过证书校验，含公网 IP | private_network_http_overrides.dart:19 |
| B-011 (P1) | 登录历史密码、后端 access token 明文写 SharedPreferences | login_history_store.dart:47 |
| A-019 (P2) | Emby 图片 URL 把 access token 拼进 query，扩散进缓存/日志 | emby_media_mappers.dart:646 |

方案要点：两个 WebView 统一改为默认取消 SSL 错误 + 可信主机显式放行（可与 G-034 的共享 Web 登录 bridge 一起做）；HttpOverrides 收紧为 RFC1918/loopback/已注册 NAS host；凭据迁移平台安全存储并清理旧明文。

**已修复（2026-07-09，本次提交）**：
- G-029 / G-032：两个 WebView 登录页遇到 SSL 证书错误时默认 `cancel()` 并提示，不再静默 `proceed()` 自动提交凭据。
- B-027：全局 `PrivateNetworkHttpOverrides` 仅允许 RFC1918、loopback、link-local、IPv6 ULA 和显式注册 NAS host 跳过证书校验，公网 IP 不再放行。
- B-011：新增平台安全凭据存储，登录历史、后端连接、飞牛旧会话的密码/token 迁入安全存储，SharedPreferences 只保留非敏感描述和存在标记，并迁移清理旧明文（`2ccdb49`）；后续将读取细化为 `value/missing/unavailable` 三态，瞬时读取失败保留现有会话，Android 读取失败不删除密文，写入/删除失败向调用方传播（`76b19a5`、`c8d2065`、`c1112d8`、`520bb2d`），并让初始化失败可重试且不会误进入登录页（`d3a600d`、`0c50f24`）；并发启动、前台恢复和快速重试按单一加载代次合并，避免状态覆盖和重复读取（`7c6d607`）；加载与登录、更新 token、退出、后端保存通过异常安全 FIFO 串行，防止旧快照覆盖新会话（`46a85a6`）；mutation barrier 保证 `load1 → mutation → load2` 不跨屏障合并（`aa97e58`）。
- A-019：Emby 媒体图片 URL 移除 `api_key` query，access token 改走 `MediaImageRef.headers`。
- 飞牛登录协议回归：恢复显式 HTTP/HTTPS 选择，并验证实际提交 URL、Emby 表单及窄屏/大字体响应式布局（`90896be`、`26efa2e`、`58b956f`）。

## 4. 批次 X —— 崩溃与数据丢失（约 25 条）

**已修复（2026-07-09，commit `1f75fd1`）**：
- A-001 + F-043：新增 `RouteQueryJson` 安全解析 helper，主路由 `_buildRoute()` 与副栏 `_buildRouteChild` 不再因畸形 query JSON 抛异常。
- A-040 / A-044：`MediaInfo` 与 `PlaybackStreamData.header` 改为嵌套类型防护，非法 payload 降级/跳过，保留合法数据。
- A-025：未知后端 kind 不再静默反序列化为飞牛，连接 store 过滤坏记录。
- B-023：`AsyncActionGuard` 清理 Future 不再把已由调用方处理的失败变成旁路未处理异步错误。

**已修复（2026-07-09，commit `cf41cf4`）**：
- B-006：下载记录持久化改为串行队列，`persistImmediately` 返回可等待 Future，并避免并发共享同一个 `.tmp` 文件。
- B-007：下载转码进度轮询增加 per-record in-flight 防重入，避免并发请求和旧结果覆盖。
- A-008：`recordPlayback()` 校验后端业务 payload，HTTP 200 但 `code != 0` 会进入统一异常路径。
- H-003 / H-012 / F-035：简介“更多/详情”链接改为 `WidgetSpan + GestureDetector`，不再在 build 中创建需 dispose 的 `TapGestureRecognizer`。

**路由/解析崩溃**：
- A-001 + F-043：`_buildRoute()` 与副栏 `_buildRouteChild` 对 query JSON 裸 `jsonDecode`+强转——同根因，做一个统一安全解析 helper，两处复用（顺带 F-042/F-044 的错误页文案走 l10n）。**已修复：安全解析已落地；l10n 文案仍留给批次 I。**
- A-040 / A-044：`MediaInfo`、`PlaybackStreamData.header` 嵌套 JSON 强转 TypeError。**已修复。**

**数据丢失/状态错乱**：
- B-006 (P0)：下载记录 `persistImmediately` 实为 unawaited + 并发共用同一 `.tmp` 文件——串行化持久化队列。**已修复。**
- A-028：保存主题整包 try/catch，一条损坏清空全部——已改为 item 级隔离 + 损坏原文备份。**已修复。**
- B-018：play_stats 数据库并发 open 无去重；B-007：下载转码进度轮询重入。**B-018 / B-007 均已修复。**
- A-008：`recordPlayback` 不校验业务 code，续播位假保存。**已修复。**
- A-022：`MediaBackend` 默认收藏/已看实现返回入参 = 假成功——已改抛 `UnsupportedError`，并由 capability 门控入口。**已修复。**
- A-025：未知后端 kind 反序列化静默回退飞牛。**已修复。**
- G-004 / A-031：设置先改内存后落盘、失败无回滚。**已修复：失败回滚并提示/记录。**
- B-014：Emby 原生进度上报失败静默丢失（可复用离线进度队列）。**已修复：服务器族中立离线队列。**
- B-023：AsyncActionGuard 旁路 Future 把失败变未处理异步错误。**已修复。**

**生命周期/async gap**（模式统一修）：
- TapGestureRecognizer 在 build 中创建不释放：H-003 / H-012 / F-035（三处同模式，统一改 WidgetSpan+GestureDetector）。**已修复。**
- TextEditingController 泄漏：H-025 / F-039。**已修复。**
- H-011：图片 errorBuilder post-frame 回调 dispose 后 setState；F-038：await 后 setState 无 mounted；F-030：bottom sheet pop 后继续用弹层 context。**已修复。**
- G-010：存储页加载无 catch/finally，异常即永久 loading。**已修复：首帧后加载、catch/finally、可重试错误态。**

**误操作防护（已修复）**：G-012 书签清空/删除、G-013 弹幕源删除、G-027 登录历史清空/删除均已接入统一确认弹窗，取消时不触发存储变更。

## 5. 批次 M —— 多后端抽象收口（约 60 条，工作量最大）

与 `docs/multi-backend-abstraction-plan.md` 是同一件事的两面，建议合并执行。按层推进：

**已修复（2026-07-09，本次提交）**：
- A-032 / A-039：单条目与整季播放 launcher 不再按 `FeiniuPlaybackContext` / `EmbyPlaybackContext` 下钻分发桥接器；新增中立 `MediaPlaybackSourceBridge`，由各后端通过 `MediaBackend.playbackSourceBridge` 自供装配器，调用方只消费中立 bridge 结果。
- B-010 / B-012：`EmbyNativePickerSupport`、`EmbyPlaybackReporter` 改为服务器族命名（`ServerNativePickerSupport`、`ServerPlaybackReporter`），原生反向通道飞牛分支改走 `usesLegacyFeiniuFlow` 语义能力位。
- 5.1 部分基础扩展点：新增 `MediaBackendKind.isServerFamily`、`MediaBackendCapabilities.usesLegacyFeiniuFlow`、`MediaBackendCapabilities.server()` 与 `supportsServerTranscodeSession`，`main.dart` / `MediaBackendProvider` 的 Emby-only gate 收口为服务器族语义。
- 新增架构回归测试 `test/media_backend/multi_backend_abstraction_boundary_test.dart`，防止播放 launcher 重新认识具体后端 context / bridge。

**已修复（2026-07-09，本次提交补充）**：
- A-002 / A-029：`MediaBackendRegistry` / `MediaBackendDescriptor` 作为服务器族唯一描述符入口，`MediaBackendProvider` 以及遗留飞牛临时工厂均通过注册表边界创建后端，不再散落具体工厂。
- 5.1 分支收口补充：`media_list_screen.dart` 与 `media_list_screen_widgets.dart` 的首页配置 gate / loadKey / 登出分支改用 `MediaBackendKind.isServerFamily`，不再写死 `MediaBackendKind.emby`。
- 登录历史展示收口：`login_history_screen.dart` 的服务器族显示名与角标改从注册表描述符读取，保留飞牛本地化 fallback，为后续 Jellyfin 等服务器族后端复用同一列表入口。
- 架构回归测试扩展：`multi_backend_abstraction_boundary_test.dart` 增加公共层禁止 Emby-only 判断与注册表描述符存在性的断言。

**5.1 核心扩展点（已清零）**
- A-024/A-029/A-002：后端 kind 保持显式枚举扩展点，服务器族由 `MediaBackendRegistry` 描述符统一登记，遗留飞牛工厂也收口到注册表。
- A-033：`resolveForNative` 改为接收当前后端，缺省遗留路径通过注册表工厂创建，不再直接构造具体适配器。
- A-020/A-014：飞牛适配器补齐收藏、人物作品、源信息和版本映射，`MediaSourceInfo`/`MediaSourceVersion` 由飞牛与服务器族共同使用。
- A-012：公共操作目标的已看状态改为布尔值，去除飞牛 `1/0` 语义泄漏。

**5.2 API/服务层**
- A-006 已修复（`035e1f1`）：普通接口 401 不再由 FeiniuApi 网络层直接 `logout()`，错误仍向调用方透传；A-007/A-010 FeiniuApi 上帝类拆分（auth/catalog/playback/download/subtitle/prefs）；A-005 FN Connect entry-token 逻辑抽出 EmbyApi 到 transport 层；A-004 EmbyApi 默认 Dio 无超时；
- B-004 DownloadTaskService 上帝服务 + 绑定 FeiniuApi/弹幕/存储；B-015 play_stats 回填绑 FeiniuApi；
- B-021 ApiUrlHelper 写死飞牛路径；B-024 登录错误 resolver 依赖飞牛异常；B-026 nasImageHeaders 混 FN/Emby 规则；
- A-030 NasProvider 承担会话横切副作用；B-019 存储服务反向依赖 provider；B-020 存储统计漏算 scoped 统计库；A-034~A-038 下载/详情 controller 直连 FeiniuApi。

**5.3 页面层直连 FeiniuApi / kind 分流**（详情/浏览/登录/统计）
- 详情：F-001、F-005、F-007、F-010、F-015、F-003；
- 浏览：F-019、F-021、F-023、F-025、F-026、F-027、F-029、F-031、F-032、F-034、F-037；
- 登录：G-024（连接页直持两后端 API）、G-028、G-033（配合批次 S 的 WebView 改造与 G-034 共享注入模板）；
- 统计：G-018、G-023。

**5.4 公共组件图片鉴权泄漏**（H 的最大簇，一个方案通杀）
H-004/005/010/017/018/019/020/021/023/024/030 + F-031/F-034：全部是「组件内判断 NAS token / `api_key=` 自鉴权 / 调 nasImageHeaders」。
方案：定义中立 `MediaImageRequest {urls, headers}`（或直接 ImageProvider），由 media_backend 的 artwork presenter 统一产出；组件只渲染。做完这一个抽象，13 条一起消。
配套：H-007（/vol 路径语义）、H-015（fromFeiniu 工厂出 UI 文件）。

## 6. 批次 P —— 性能（约 25 条）

**已修复（2026-07-09，本次提交）**：
- B-022：新增本地字幕异步扫描入口，下载/原生起播路径先异步解析 sidecar 字幕，再构造 `MpvMediaSource`，避免起播链路同步扫目录。
- F-008：详情页本地下载文件信息改为下载记录变化时异步刷新快照，`build()` 不再执行 `existsSync/statSync`。
- G-007：已修复回归（`aaea330`）。下载列表页/下载详情页保留行级局部监听，并按任务 ID 读取当前记录，避免闭包持有旧 `DownloadTaskRecord` 导致进度停止刷新。
- G-015：截图库缩略图按卡片尺寸传入目标解码宽高，全屏预览仍走原图。
- G-016：分辨率排序 metadata 预热改为小批量加载，避免一次性并发解码全部截图。
- G-017：截图库可见项过滤/排序只计算一次，并按分组使用懒构建 `SliverGrid`，避免 `Wrap` 一次性构建全部卡片。

**主线程同步 IO**：
- B-022（起播路径同步扫字幕目录——在原生起播链上，优先）；F-008（详情页 build 内 existsSync/statSync）；B-001（日志导出 getter 同步读 256KB journal）；B-005（下载总量 getter 遍历 lengthSync）；B-008（离线封面同步扫目录）。

**高频重建**：G-007 已修复回归（下载速度 900ms 全页重建 PageView+列表——改行级局部监听，并按任务 ID 读取当前记录）。

**截图库**：G-015（缩略图按原图解码）、G-016（分辨率排序并发解码全部截图）、G-017（build 双重全量排序 + Wrap 全量构建）均已处理；G-011 存储明细分页已在 `e67bafe` 完成。

**数据聚合**：B-017（报表 all 范围全量加载 + Dart 多轮聚合→SQL 聚合/后台 isolate）；B-016（每视频重建全部聚合表→批次末尾一次）；A-017（Emby 系列起播按季串行扫描→NextUp 查询）。

**模糊残留清剿**：H-001（bottom_glass_panel 真模糊路径）、H-028（LiquidGlassLevel.liquid 死配置入口）已清理；H-009（沉浸背景 ImageFiltered+BackdropFilter）、H-027（死 token）仍属于沉浸详情背景的后续清理。

**图片解码尺寸**：H-006、H-016、F-036（统一并入 5.4 的 MediaImageRequest 改造，presenter 顺带带上 cacheWidth）。

**弹幕（原生链路）**：E-004 已通过 `DanmakuImportParser` 的 isolate 入口处理；B-013 已增加评论缓存与 payload 临时文件 TTL 清理。

**缓存泄漏**：A-011 已修复（FeiniuApi 静态缓存登出时清理）。

## 7. 批次 R —— 结构：拆分与去重（约 18 条）

**已修复（2026-07-09，commit `abb06d4`）**：
- G-002：mpv 设置标题/副标题映射双份已收敛到 `MpvSettingsL10n.definitionByKey`。
- G-034：`FnConnectWebLoginPage` / `EmbyFnEntryLoginPage` 的 Web 登录注入脚本已抽为共享 `FnWebLoginBridgeScript`，保留 FN OAuth 探测与 entry-token 阻断页检测差异配置。
- H-013：`TvSeasonDetailPanel` 已引入 `TvSeasonPanelHeader/Layout/Actions/Content` 配置对象，现有调用走 `legacy` 过渡工厂。
- 死代码/死契约：F-011、F-013、F-020、G-026 已删除不可达或未调用旧代码；C-001 已在 `FlutterHostActivity` 补齐 `getGpuProfile` 原生实现。

- **详情页三兄弟**：F-006/F-014/F-016（3.5k+2.1k+3.3k 行）——按 F-014 建议抽 `DetailScaffold/DetailHeroChrome/DetailActionRow` 公共件；注意与批次 M 的 5.3 同文件，**建议先做 M 的数据层收口再拆 UI**，避免拆两次。
- 超大文件：G-001（mpv 设置页 3.2k）、G-006（下载页 2.4k）、G-009（存储页 2.9k）、G-014（截图预览 2.5k）、G-019/G-021（统计报表）、G-025（连接页）。
- 重复合并：G-002（mpv 设置标题映射双份）、G-034（两个 Web 登录页重复注入脚本）。
- 组件 API：H-013、H-022（参数 30+/超阈值→配置对象）。
- 死代码：F-011、F-013、F-020、G-026、C-001（getGpuProfile 孤儿契约：补 Kotlin 实现或删桥）、D-027 已随废弃区。

## 8. 批次 I —— i18n / 模型层文案（约 22 条，机械性高）

**已修复（2026-07-09，commit `840a7c0`）**：
- 模型/DTO 层不再产出 `Unknown`、`未知版本`、`饰` 等用户可见 fallback；空值保持空或结构化 token，由 UI 层负责本地化展示。
- `StreamListOption` 移除对 UI mapper 的反向依赖；语言映射、音轨/字幕显示名、人物演职员展示等 fallback 改为后端中立输出。
- `AppThemeProvider` 不再提供英文主题展示文案，主题预设名与自定义名称建议改由 `AppThemeL10n`/`AppLocalizations` 生成。
- 路由错误页、FN Connect Web 登录页、媒体信息页、mpv 缓存滑杆端点、详情简介/链接/下载角标等页面硬编码文案已接入 l10n。
- `TvEpisodeCardData` 的状态颜色从模型层 `Color` 改为语义 tone，组件层再映射主题色。

统一模式：**模型/store/provider 层不产出用户可见文案**，只出结构化状态，由 UI presenter 走 AppLocalizations。
- 模型层英文/中文 fallback：A-013、A-023、A-041、A-042、A-043、A-045（同时是 models→ui 反向依赖，优先）、A-046、A-047、B-025（语言映射表）；
- provider/theme：A-026、H-026、A-003；
- 页面硬编码：F-004、F-022、F-040、F-042、F-044（随批次 X 的路由错误页一起）、G-003、G-022、G-031、H-002、H-008、H-014。

## 9. 批次 O —— 错误处理与可观测性（约 30 条，可穿插执行）

全项目空 `catch (_)` 统一策略：**允许降级，禁止无迹**。建议先落一个轻量 helper（`logSwallowed(action, id, error)` 走 AppLogService），然后机械替换：
- A-009、A-015、A-016、A-021、A-027；B-002、B-003（用 `Error.throwWithStackTrace` 保留堆栈）、B-009；
- E-001（DanDanPlay 业务错误被吞——**偏 Bug，提级处理**：`on DanDanPlayApiException rethrow`）、E-007；
- F-002、F-009、F-012、F-017、F-018、F-024、F-028、F-033、F-041；
- G-005、G-008、G-020、G-030；H-029、H-031。

**已修复（2026-07-09，本次提交）**：
- 新增 `logSwallowedError()` 统一记录允许降级的异常，写入 `AppLogService` warning，并在 action/id/details 中保留业务上下文；新增回归测试覆盖 warning 记录与堆栈保留。
- A-009、A-015、A-016、A-021、A-027、B-009、E-007、F-002/F-009/F-012/F-017/F-018/F-024/F-028/F-033/F-041、G-005/G-008/G-020/G-030、H-029/H-031：点名 best-effort 降级路径不再无声吞异常，保留原降级/用户反馈语义并补日志。
- B-002：`AppLogService._persist()` 失败不再空吞，改写入 runtime crash journal 并 `debugPrint`，避免递归调用日志服务。
- B-003：`DetailRuntimeCache` loader 失败改用 `Error.throwWithStackTrace` 保留原始堆栈，并新增回归测试。
- E-001：DanDanPlay 评论接口 JSON 业务错误改为 `on DanDanPlayApiException rethrow`，不再被 payload 探测兜底吞掉。

## 10. 建议执行顺序

1. **S 安全**（半天量级，风险最高）
2. **X 崩溃/数据丢失**（多为局部小修）
3. **废弃区删除立项**（先做 2 节的三项确认；删完再动 M 能少改很多死代码）
4. **M 多后端收口**（配合 multi-backend-abstraction-plan.md，5.1→5.4 顺序推进；5.4 图片抽象一个方案消 13 条）
5. **P 性能**（G-007、G-015~017、B-022、F-008 优先，体感最明显）
6. **R 结构拆分**（在 M 完成后做，避免重复动同一批文件）
7. **I / O**（机械性批量清理，可随时穿插或交给低成本窗口）
