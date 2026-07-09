# FIX-PLAN —— 全项目评审修复计划

> 汇总自 8 个评审窗口共 **264 条已确认 finding**（findings/A~H.md），已按主题去重归批。
> **范围调整（用户决策 2026-07-03）**：Flutter 层播放链路已废弃（实际播放走原生壳 NativePlayerActivity），
> 该区域的问题**不修复**，归入「废弃区」，建议以删除代替修复（见第 2 节）。

## 1. 总览

| 分类 | 条数 | 处理 |
|---|---|---|
| 废弃区（Flutter 播放器及其专属附件） | 74 | 不修，随删除计划一次性消灭 |
| 活代码待修 | 190 | 按下方批次 S/X/M/P/R/I/O 执行 |

活代码问题的四大主题：**多后端抽象泄漏**（约 60 条，最大主题）、**错误处理空 catch**（约 35 条）、
**性能/主线程 IO/图片解码**（约 25 条）、**i18n 模型层文案**（约 22 条）；另有安全 5 条、崩溃/数据丢失约 25 条、结构拆分约 18 条。

## 2. 废弃区（74 条，不修）

**清单**：
- **D 全部 44 条**（lib/player 页面宿主、core/view mixin、controllers、stores、player services）
- **E 中 22 条**：E-003（danmaku controller）、E-005/E-006（Flutter 弹幕渲染层）、E-008 ~ E-026（播放器 danmaku/settings mixin、panels、player widgets）
- **C 中 4 条**：C-002/C-003（lib/player/services 两个死桥）、C-006/C-007（播放器页面/widget 直建 system channel）
- **B 中 2 条**：B-028/B-029（mpv_proxy_server，D-035 已证实 registerStream 无调用方，本就是死路径）
- **G 中 2 条**：G-035/G-036（player_host_screen，Flutter 播放宿主）

**E 中仍是活代码、不在废弃区**（原生壳弹幕链路仍在用）：E-001/E-002/E-004（`lib/danmaku/api/` DanDanPlay API/config/resolver）、E-007（弹幕保存源 store）。

**建议：立项「删除 Flutter 播放链路」**，收益比逐条修大得多——约 4 万行 lib/player + danmaku render/controller 层 + 死桥，74 条问题一次清零，也是对"低耦合易维护"目标的最大单笔回报。删除前需确认三件事：
1. `player_host_screen` / PlayerActivity 仍注册在 `main.dart` 路由与原生侧——确认外部本地视频（ExternalLocalVideoActivity）等所有入口都已走原生壳后再删；
2. `MpvMediaSource`（mpv_player_controller.dart 内）目前被原生起播装配路径复用——删除前先把该模型抽离到独立文件（顺带解决 D-044 的反向依赖）；
3. `lib/danmaku/api/`、`danmaku_saved_source_store`、`DanmakuImportParser` 被原生弹幕链路使用，**保留**。

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
- A-028：保存主题整包 try/catch，一条损坏清空全部——改 item 级隔离 + 备份。
- B-018：play_stats 数据库并发 open 无去重；B-007：下载转码进度轮询重入。**B-007 已修复；B-018 未修。**
- A-008：`recordPlayback` 不校验业务 code，续播位假保存。**已修复。**
- A-022：`MediaBackend` 默认收藏/已看实现返回入参 = 假成功——改抛 UnsupportedError + capability 门控。
- A-025：未知后端 kind 反序列化静默回退飞牛。**已修复。**
- G-004 / A-031：设置先改内存后落盘、失败无回滚。
- B-014：Emby 原生进度上报失败静默丢失（可复用离线进度队列）。
- B-023：AsyncActionGuard 旁路 Future 把失败变未处理异步错误。**已修复。**

**生命周期/async gap**（模式统一修）：
- TapGestureRecognizer 在 build 中创建不释放：H-003 / H-012 / F-035（三处同模式，统一改 WidgetSpan+GestureDetector）。**已修复。**
- TextEditingController 泄漏：H-025 / F-039。
- H-011：图片 errorBuilder post-frame 回调 dispose 后 setState；F-038：await 后 setState 无 mounted；F-030：bottom sheet pop 后继续用弹层 context。
- G-010：存储页加载无 catch/finally，异常即永久 loading。

**误操作防护**：G-012 (P0) 书签清空/删除、G-013 弹幕源删除、G-027 登录历史清空——均无确认/撤销，统一加确认弹窗模式。

## 5. 批次 M —— 多后端抽象收口（约 60 条，工作量最大）

与 `docs/multi-backend-abstraction-plan.md` 是同一件事的两面，建议合并执行。按层推进：

**已修复（2026-07-09，本次提交）**：
- A-032 / A-039：单条目与整季播放 launcher 不再按 `FeiniuPlaybackContext` / `EmbyPlaybackContext` 下钻分发桥接器；新增中立 `MediaPlaybackSourceBridge`，由各后端通过 `MediaBackend.playbackSourceBridge` 自供装配器，调用方只消费中立 bridge 结果。
- B-010 / B-012：`EmbyNativePickerSupport`、`EmbyPlaybackReporter` 改为服务器族命名（`ServerNativePickerSupport`、`ServerPlaybackReporter`），原生反向通道飞牛分支改走 `usesLegacyFeiniuFlow` 语义能力位。
- 5.1 部分基础扩展点：新增 `MediaBackendKind.isServerFamily`、`MediaBackendCapabilities.usesLegacyFeiniuFlow`、`MediaBackendCapabilities.server()` 与 `supportsServerTranscodeSession`，`main.dart` / `MediaBackendProvider` 的 Emby-only gate 收口为服务器族语义。
- 新增架构回归测试 `test/media_backend/multi_backend_abstraction_boundary_test.dart`，防止播放 launcher 重新认识具体后端 context / bridge。

**5.1 核心扩展点（新增后端必改的公共代码，最优先）**
- A-024 后端 kind 写死 enum；A-029 backend 工厂 else=飞牛；A-002 main.dart 登录 gate 写死 Emby/飞牛；
- A-032 / A-039：单条目与整季播放 launcher 拿到抽象 `getPlayback()` 后又 downcast `FeiniuPlaybackContext/EmbyPlaybackContext` 选装配器——改注册式 playback assembler 或由后端返回装配结果（**这是原生起播路径，活代码核心**）；
- A-033 `resolveForNative` 直接 new `FeiniuMediaBackend(FeiniuApi(nas))`；B-012 原生重入按 kind 分支；B-010 `EmbyNativePickerSupport` 后端专名泄漏在 services；
- A-020 FeiniuMediaBackend 公共接口返空数据；A-014 MediaSourceInfo 只服务 Emby；A-012 公共 target 用飞牛 watched=1/0。

**5.2 API/服务层**
- A-006 FeiniuApi 反向依赖 NasProvider 并在 401 直接 logout；A-007/A-010 FeiniuApi 上帝类拆分（auth/catalog/playback/download/subtitle/prefs）；A-005 FN Connect entry-token 逻辑抽出 EmbyApi 到 transport 层；A-004 EmbyApi 默认 Dio 无超时；
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
- G-007：下载列表页/下载详情页移除包住整页的高频 service `AnimatedBuilder`，列表结构按签名变化刷新，下载速度/转码进度改为行级局部监听。
- G-015：截图库缩略图按卡片尺寸传入目标解码宽高，全屏预览仍走原图。
- G-016：分辨率排序 metadata 预热改为小批量加载，避免一次性并发解码全部截图。
- G-017（部分）：`build()` 内可见项过滤/排序只计算一次并复用到 section；section 内 `Wrap` 全量构建仍保留，后续需要改 SliverGrid/分页才能完全关闭。

**主线程同步 IO**：
- B-022（起播路径同步扫字幕目录——在原生起播链上，优先）；F-008（详情页 build 内 existsSync/statSync）；B-001（日志导出 getter 同步读 256KB journal）；B-005（下载总量 getter 遍历 lengthSync）；B-008（离线封面同步扫目录）。

**高频重建**：G-007（下载速度 900ms 全页重建 PageView+列表——改行级局部监听）。

**截图库**：G-015（缩略图按原图解码）、G-016（分辨率排序并发解码全部截图）、G-017（build 双重全量排序 + Wrap 全量构建）；G-011（存储明细 Column 全量渲染）。

**数据聚合**：B-017（报表 all 范围全量加载 + Dart 多轮聚合→SQL 聚合/后台 isolate）；B-016（每视频重建全部聚合表→批次末尾一次）；A-017（Emby 系列起播按季串行扫描→NextUp 查询）。

**模糊残留清剿**（回归纯色决策的收尾）：H-001（bottom_glass_panel 真模糊路径）、H-009（沉浸背景 ImageFiltered+BackdropFilter）、H-028（LiquidGlassLevel.liquid 死配置入口）、H-027（死 token）。

**图片解码尺寸**：H-006、H-016、F-036（统一并入 5.4 的 MediaImageRequest 改造，presenter 顺带带上 cacheWidth）。

**弹幕（原生链路）**：E-004（网络弹幕 UI isolate 同步解析→isolate 入口）；B-013（native_danmaku_prefetch 缓存/payload 文件无 TTL 清理）。

**缓存泄漏**：A-011（FeiniuApi 静态缓存以 token 为 key、登出不清理）。

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

## 10. 建议执行顺序

1. **S 安全**（半天量级，风险最高）
2. **X 崩溃/数据丢失**（多为局部小修）
3. **废弃区删除立项**（先做 2 节的三项确认；删完再动 M 能少改很多死代码）
4. **M 多后端收口**（配合 multi-backend-abstraction-plan.md，5.1→5.4 顺序推进；5.4 图片抽象一个方案消 13 条）
5. **P 性能**（G-007、G-015~017、B-022、F-008 优先，体感最明显）
6. **R 结构拆分**（在 M 完成后做，避免重复动同一批文件）
7. **I / O**（机械性批量清理，可随时穿插或交给低成本窗口）
