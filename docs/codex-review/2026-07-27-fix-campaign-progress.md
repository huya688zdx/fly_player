# 2026-07-27 活代码修复战役 —— 进度与续作报告

> 本轮以子代理双评审流程（实现 → 规格评审 → 质量评审）推进 FIX-PLAN 剩余活代码问题。
> 本文档是**断点续作的唯一入口**：记录已完成、在途尾巴、未开工任务的完整上下文与执行顺序约束。
> 已完成项的登记以 `FIX-PLAN.md` 1.2 登记表为准（本轮已同步更新）。

## 一、本轮完成（T1~T8，均已提交并过规格评审）

| 任务 | Finding | 提交 | 评审状态 |
|---|---|---|---|
| T1 登记表审计更正 | A-019 回退标注、G-010/H-009 补行、H-013/G-027 降级、5 条补证据 | `f777b41` | — |
| T2 I 批残留 | SSL 文案 l10n（key 已归 common 前缀）、'未知'哨兵、H-027 死 token、G-027 失败反馈+失败路径测试 | `8d0b142` `1a8f47e` `90004dc` | 规格✅ 质量✅ 已收口 |
| T3 B-025 | 音频语言标签出模型层 → lib/ui helper + l10n（key 归 track 前缀） | `4eb47a7` `0f74f51` | 规格✅ 质量✅ 已收口 |
| T4 B-001/B-005/B-008 | 日志导出/下载体积/本地封面 同步 IO 异步化 | `f9b5b83` `12326e2` | 规格✅ 质量✅（1 条 Important 跟进，见下） |
| T5 B-016/B-017 | 回填批末一次重建聚合表；报表快照映射+聚合移入 Isolate.run，season_stats SQL 预过滤 | `830d6a5` | **实现完成含对拍测试 17/17 绿；双评审未做** |
| T6 A-017 | Emby 起播 Resume→NextUp→逐季即停 | `f58c9a1` `ac54bad` | 规格✅ 质量✅ 已收口 |
| T7 H-006/H-016/F-036 | 图片按显示尺寸解码（H-016 防压扁修正） | `4ae56ac` `6f3ea6b` | 规格✅ 质量✅（Minor 搁置） |
| T8 A-004/A-005 | EmbyApi 默认超时；entry-token 抽 transport 层 | `8763634` | 规格✅（逐字节等价核验）；质量评审未做 |

**遗留跟进（续作时处理）**：
- **T4 Important**：`downloadedBytes()` 链路仍残留同步 `existsSync`——构建 futures 时逐条调 `_isDownloadedRecordAvailable`（download_task_service.dart:5772，`File(path).existsSync()`），`downloadedRecordForItem`（:458）同。需异步化 exists 判定并保持语义分野：**文件缺失计 0，不可读计 totalBytes**。可并入 T9/T14 触碰该文件时顺手做。
- **T5 双评审未做**：830d6a5 自带对拍测试（新旧链路快照逐字段一致 ×2 范围 + 季表预过滤等价），风险中低，但按流程欠一轮规格+质量评审。
- **T8 质量评审未做** + fnos 中转 Emby 登录/播放建议实机过一次（entry-token 纯搬迁+单测覆盖，未实机验证）。
- **T2 收口时发现的测试技巧**（已解决，记录备用）：弹窗退出动画的 ticker 在下一帧才建立起点，widget 测试需"空 pump 启动 + 按时长推进"两步；`_reportPersistFailure` 的日志写入改为 `unawaited`（AppLogService 在测试环境异步链不回来会卡住用户提示）——**日志 best-effort 不得阻塞用户反馈**，这个模式后续 O 批清剿时同样适用。

## 二、审计基线（2026-07-27 全量代码审计结论，续作前提）

- 批次 S/X/O/I 基本落实；**A-019 已被 `98c2e1c` 有意回退**（Emby 图片必须 URL 带 api_key，因旧 UI 图片管线只传 URL 丢 headers、组件靠 `api_key=` 子串判定自鉴权），根治依赖 T10。
- **批次 M 仅 5.1 骨架完成（约 19%）**：5.2 API/服务层 17 条、5.3 页面层 20 条、5.4 图片抽象 9 条未开工。pages/screens 下仍有 14 个文件 import feiniu_api、24 处 `MediaBackendKind.feiniu` 硬分支。
- **批次 O 剩约 76 处空吞 catch**，`download_task_service.dart` 独占 23 处（全文件仅 2 处接了 logSwallowedError）；B-009 第二调用点 :5719/:5730 未修。
- **批次 R 十个超大文件一个没拆**：play_detail_page 3520 行、tv_season_detail_page 3398、mpv_player_settings_screen 3056、storage_management_screen 2950、play_stats_report_widgets 2841（零改动）、screenshot_preview_screen 2555、download_list_screen 2522、tv_detail_page 2042、connection_screen 1634、play_stats_report_screen 1536。`DetailScaffold/DetailHeroChrome/DetailActionRow` 不存在；H-022 `MediaPosterCard` 仍 18 参；H-013 调用方仍走 30 参 legacy 工厂。
- T4 范围外剩余同步 IO：`app_log_service.dart` 6 行（:228-229/:626/:670-671/:680）、`download_task_service.dart` 39 行（含 `_isDownloadedRecordAvailable` :5772，被 10+ 同步 getter 调用，改造连锁大）。

## 三、未开工任务（T9~T21，按序执行）

### T9 O 批空吞 catch 清剿（~76 处）
统一策略"允许降级，禁止无迹"：接 `logSwallowedError`（lib/utils/swallowed_error_logger.dart）或注明有意降级。重点 `download_task_service.dart` 23 处（样例行号 :720/:875/:915/:1518/:1767/:1809/:2054/:3466/:3622/:3783/:3872/:3908/:4608/:4738/:4753/:5072/:5080/:5097/:5130/:5138/:5732）；B-009 第二调用点 :5719-5724/:5730-5732；`on PlatformException {}` 空块 6 处（runtime_theme_sync_bridge/embedded_detail_launcher/player_system_session_bridge/session_exit_bridge）多为平台能力缺失兜底，补日志即可。分布清单见审计（25 文件）。**依赖：等 T5 落地（play_stats_backfill_service 有 4 处）。**

### T10 M-5.4 MediaImageRequest 图片抽象（一次消 13 条，最高优先）
中立 `{urls, headers, decodeWidth}` 由各后端 artwork presenter 产出，组件只渲染。消 H-004/005/010/017/018/023/024/030 + F-031/F-034，收尾 H-019/020/021/H-007/H-015，并正确根治 A-019。
**硬约束（实机踩过坑）**：
- 保留 Emby api_key-in-URL 决策（`98c2e1c`）语义或以显式 `hasAuth` 标志替代 `url.contains('api_key=')` 门控（7 处组件判定点）；不能回到"仅 headers"方案除非同时改掉全部只传 URL 字符串的管线（`MediaLibraryItem` 链路）。
- fnos 中转 Emby 需 entry-token cookie（nas_image_headers.usesFnConnectRelayCookie）。
- 详情页封面跳闪修复规则不可破坏（垫底图必须与主图同源，宁可空底色——见 memory detail-artwork-flash-fix）。
- `nasImageHeaders` UI 层 14 处调用、`media_list_screen_widgets.dart:877-878/:904` 同模式未立 finding 也一并收。
- H-030 动态取色 `dynamic_theme_seed_extractor.dart:219` 同链路。

### T11 M-5.2 utils 中立化
B-021 `api_url_helper.dart:4-6` 飞牛路径前缀下沉后端；B-024 `login_error_resolver.dart` 去 feiniu_api import；B-026 `nas_image_headers.dart` 拆飞牛头/fnos cookie 规则。**顺序：在 T10 之后做**（T10 决定图片鉴权逻辑归属，避免二次动同文件）。

### T12 M-5.2 服务层解耦
B-015 play_stats 回填去 FeiniuApi 直连（backfill_service :6/:99/:136/:504，等 T5 落地）；B-019 storage_management_service 去 provider 反向依赖（:13-14/:21）；B-020 补算 scoped 统计库（`play_stats_$truncated.db`，play_stats_database.dart:212 vs storage :890-902）；A-030 NasProvider 横切副作用收敛（:87/:194/:336/:346/:360-367）。

### T13 M-5.2 controllers 解耦（A-034~A-038 + F-003）
local_download_source_resolver :3/:46、play_detail_data_loader :121、play_detail_download_sheet_controller :90 等、play_detail_sheet_controller :93（fromFeiniu）、tv_season_download_sheet_controller :137 等；`MediaDetailVariant.fromFeiniu` 工厂在 media_detail_overlay_page.dart:40。

### T14 M-5.2 上帝类拆分
A-007 FeiniuApi 2890 行拆 auth/catalog/playback/download/subtitle/prefs；A-010 SharedPreferences 出 API 层（:1596/:1606/:2818/:2826）；B-004 DownloadTaskService 6017 行依赖解耦。**建议拆成 2-3 个子任务，先 A-010（小）再拆类。**

### T15~T17 M-5.3 页面层收口
- T15 登录+统计组：G-024 connection_screen（:76/:380-381/:475/:677/:801/:855）、G-028 fn_connect_web_login_page（:218/:322/:440）、G-033 emby_fn_entry_login_page（:163/:193-200 协议出 screen）、G-018 play_stats_report_screen:237、G-023 play_stats_debug_screen:91。
- T16 浏览组 11 条：F-019（media_list_screen :266/:279/:360/:391/:484/:569/:745 硬分支）、F-021（actions:102）、F-023（category :88/:136/:138/:331/:505/:587）、F-025/F-026（search :88-91/:239）、F-027/F-029/F-031（favorite 系列）、F-032/F-034（person_detail）、F-037（media_info :40/:102）。
- T17 详情组（体量最大，须 T13/T14 先行）：F-001（media_collection_detail 10 处）、F-005（play_detail_entry :66/:88/:97 飞牛 schema 路由）、F-007（play_detail_page 双路径）、F-010（tv_detail "飞牛分支整段保持原样"）、F-015（tv_season_detail 同）。

### T18 边界测试白名单断言（可提前，防回流）
`test/media_backend/multi_backend_abstraction_boundary_test.dart` 补两条清单式断言：pages/screens 禁止 import feiniu_api（白名单=当前 14 文件，随修复缩短）；公共层禁止 `MediaBackendKind.feiniu` 硬分支（白名单=当前 24 处）。**建议续作时最先做这条，锁住现状。**

### T19/T20 R 批拆分（必须在 M 完成后）
T19 详情三兄弟抽 DetailScaffold/DetailHeroChrome/DetailActionRow；T20 其余超大文件 part 化/组件抽离 + H-022 MediaPosterCard 18 参→配置对象 + H-013 legacy 工厂迁移删除。行数基线见第二节。

### T21 终验
`flutter analyze` + `flutter test --concurrency=1` 全量 + `cd android && .\gradlew.bat :app:compileFullDebugKotlin && .\gradlew.bat :app:testFullDebugUnitTest`；登记表全面收口；实机烟测（播放/切集/下载播放/fnos Emby）。

## 四、执行方法备忘

- 子代理双评审流程有效：本轮拦下 dispose 后 setState、竖版海报双维解码压扁、G-027 缺失败路径测试等实机才会暴露的问题。
- 并行约束：文件集不相交的任务可并行（各自只 `git add` 自己的文件，index.lock 冲突等待重试）；本机 7 个并发 Flutter 进程会打爆内存（analyze VirtualAlloc 失败），**并发别超 5**，评审代理避免跑全量测试。
- pre-commit dart format 钩子会顺手格式化工作区文件，并行时可能拦下别人未暂存文件的格式问题，重试即可；勿动他人文件。
- 每任务独立提交便于回滚；FIX-PLAN 登记表由监督者统一更新，实现代理不碰。
