# B-FLY：L0 资料助手与已发布 OP/ED 消费接线

日期：2026-09-13。本交付来自 `codex/b-client-oped-20260913`，基线 `dbd21129c252a993cc33668d4cf6337304b2f6be`。只在 `E:\fly_play_recovere\.worktrees\fly-player-b-oped` 修改。原 `fly_player` 的未提交账号、绑定、历史及并行 i18n 等改动没有被本任务覆盖；原工作树在其他任务中仍有变化，不能声称其文件散列整体不变。

## 实际改动

- `fly_oped.dart` / `FlyOpedPlayback.kt` 消费现有 A `SourceRef` 和服务返回的 `FileContext`。不从标题、URL、时长或 LLM 输出另建文件身份。拒绝未核验文件、过时上下文、过时 seek、错来源、错版本、越界、重叠、保护段冲突及无效整套发布。
- Android 内置播放器沿用 `loadNonce`、`seekWithEpoch` 与 `completedSeekEpoch`；Windows 沿用当前来源代次、`_danmakuSeekRevision` 和真实 mpv 状态。未接入第三方外部播放器。
- 点击前重新 resolve，固定整套 `set_revision`、文件坐标和目标；撤销、修订或身份失效后不执行旧目标。有人暂停、切源、seek、启用 A-B 或进入缓冲时，迟到的自动跳过不会继续执行。
- ED 跳到核验后的 `end_ms`，不以“下一集”替代。seek 落入区间只提示，区间首次正常连续跨入才可自动；已进入区间不会反复自动回环，跳过 OP 后仍可正常进入 ED。
- `intent` 与唯一终态按 action 排序发送，只有真实落点距离目标不超过 500 ms 才记 settled。Android 要求实际 seek epoch 完成；Windows 读取 `seeking` 和 `time-pos`，即使暂停且没有后续播放 tick 也会独立采样。命令 Future 成功本身不算 settled。
- 原 Emby/飞牛单集播放资料页增加“资料助手 · 当前节目”，飞翔同步资料页及 Windows 播放菜单也可打开。面板带当前精确来源，可创建、轮询、取消、重试读取任务，展示文本答案、候选、证据和预算；账号变化后丢弃旧回调。输入上限与服务一致为 1000 字符，模型预算沿用管理员配置。
- 助手不渲染模型 HTML、不执行模型命令、不直接控制播放器、不直接发布候选。Android 原生播放画面内没有另建助手抽屉，入口位于原 Flutter 资料页。
- 新增可选 `FLY_PLAYER_DATA_HOME`，在 Windows 首次读取 prefs/SQLite 前安装目录覆盖。SQLite、SharedPreferences/现有 DPAPI 密文、应用缓存、临时目录和弹幕保存源使用指定目录。无此变量时保持原位置；不复制、迁移、删除旧账号或历史。四项 Windows 平台包从已有传递依赖改为同版本直接声明，无版本升级。

## 契约与迁移

沿用现有飞翔登录会话和鉴权客户端：`POST /assistant/context`、`POST /assistant/runs`、任务读取/取消、`POST /oped/resolve`、`POST /oped/actions`。准确 wire 以服务分支 `docs/LLM_BASELINE.md` 为准。来源绑定与 `remote_media_source_id` 原样携带，不能通过丢弃媒体版本来绕过文件身份。

客户端没有数据库 schema 迁移。未更改 A 的 BIF/遮罩采样、模型或产物；`NativePlayerSurface.seek` 只向调用方返回已有控制器产生的 seek epoch。

## 真实 Windows 证据

证据目录：`E:\fly_play_recovere\.tmp\llm-b-fly-ui`。截图与对应 UIA 文本是实际窗口采集，未生成模拟界面。首次实测使用本分支的 `llm-b-fly-windows-delivery-build.log` 对应构建，后续异步审查修复及目录覆盖又完成最终构建，因此不能把早先视频截图宣称为最终版本全部行为的验收。

| 项目 | 实际结果与证据 |
| --- | --- |
| 飞翔账号连接 | PASS：真实登录隔离服务 `http://127.0.0.1:18789`，显示已绑定的飞牛与 Emby；`01-login-bindings.png` |
| 已绑定媒体库 | PASS：选择 Emby 局域网连接，真实媒体库显示 78 个影视项目；`02-real-emby-library.png` |
| 当前对象助手 | PASS：从《花开伊吕波》S01E01 原资料页打开助手，服务返回真实单集标题和“当前文件尚未核验”状态；`03-episode-assistant-entry.png`、`04-real-context-unresolved.png/.txt` |
| 普通视频播放 | PASS（旧实测构建）：内置 Windows 播放器获取 NAS 视频画面并运行至 00:23 / 24:12，Space 可暂停；`05-real-windows-playback.png`、`06-real-windows-paused-23s.png/.txt` |
| 最终目录覆盖构建 | PASS：以 `.runtime\llm-b-final-20260913` 新 E profile 启动，真实显示未登录的独立页面，实际 prefs 文件写入 E 的 `support`；`07-final-e-profile-startup.png/.txt`、`runtime-profile.json`。这次只核对启动与写入，没有再次登录或播放 |
| 助手完整任务在 Windows | NOT_RUN：本次桌面实测只打开真实上下文，没有从桌面再调用模型或发起任务；创建/轮询/取消已有自动化 fixture 测试，真实模型和网页证据另见服务交付 |
| 已发布 OP/ED 实际跳过（首次构建） | 当时 BLOCKED：A 文件 resolver 尚未提供核验身份。下方“真实文件发布后复验”记录后续真实 A 身份、人工确认及最终构建实播，替代这个历史阻塞结论 |
| Android 实机 | NOT_RUN：初查 D 盘已有 adb 无设备，根任务最终使用复制到 `E:\fly_play_recovere\.tools\platform-tools-llm\adb.exe devices -l` 复验仍无设备；没有 APK 安装或实播证据 |

首次通过 `sky.launch_app` 实测时，运行期继承了 Windows 默认 AppData。已确认 `C:\Users\25131\AppData\Roaming\com.geqian.flyplayer\fly_player` 中 prefs/数据库有本次写入。开发依赖、编译缓存、脚本临时与构建全在 E；首次运行期写入 C 是实际限制，不能隐瞒。随后增加了独立目录入口，后续验证使用全新的 E profile；原 C 数据保持原位，没有迁移或删除。

## 测试与构建

命令均在 B 工作树运行，先加载 `E:\fly_play_recovere\fly-data-service\scripts\enter-env.ps1`。

- Flutter 79 项相关测试 PASS：OPED 整套校验/500 ms 落点/代次取消/seek 策略、助手上下文/文本显示/取消/账号隔离、原播放来源/历史/目录/prefetch，以及目录覆盖与弹幕存储回归。日志：`E:\fly_play_recovere\.tmp\llm-b-fly-tests-profile-final.log`。新增目录测试确实写入临时 E 文件，并证明旧 sentinel 文件未被移动删除。
- Kotlin 3 项纯逻辑测试 PASS：实际 epoch 与 completed 必須匹配、真实终态位置、500 ms 边界、干预 seek 取消、首次连续进入与回环保护。命令：`E:\fly_play_recovere\.tmp\llm-b-fly-kotlin\run.ps1 -RunName delivery-final`。测试数据为明确 fixture，不是 NAS 核验产物。
- 修改的 10 个 Dart 目标静态分析 PASS。`git diff --check` PASS（仅 Windows CRLF 提示）。
- Android 生产 Kotlin/Java 源码诊断编译 PASS：`E:\fly_play_recovere\repair_a5acbc3_20260912\tools\compile_android_sources.py`，使用 E 盘 JDK、Maven mirror、Gradle cache 与 mockable Android API jar；日志 `E:\fly_play_recovere\.tmp\llm-b-fly-android-review-final.log`。沿用既有生成 R.jar，本次无资源变化；生成 BuildConfig 的第三方 key 字段为空。此检查不等于完整 Gradle APK 打包、JNI 链接、设备安装或运行。
- Windows 完整 Release portable build PASS：`E:\fly_play_recovere\.tools\portable-build\build-mask-p0-integrated.ps1 -ProjectDir E:\fly_play_recovere\.worktrees\fly-player-b-oped`；最终日志 `E:\fly_play_recovere\.tmp\llm-b-fly-windows-final.log`。产物在 `build\windows\x64-mask-p0-integrated\bundle`，没有替换原目录程序。
- `dart pub get --offline` 仅把四个现有锁定包标为直接依赖，没有下载或升级版本。常规 `flutter pub get` 在此 Windows 环境的符号链接权限处失败，沿用已存在的 E 盘 portable junction 构建方案。

## 性能、预算与已知限制

本分支实测没有增加收费模型调用（0 次）；服务团队的真实模型预算另行列示。客户端不持有模型密钥。OPED resolve 最多等待 2 秒，事件请求最多 4 秒；Windows 单次引擎观测 1 秒超时，250 ms 重试，整个跳转最多等待 12 秒后记 failed。助手轮询间隔 2 秒。79 项 Flutter 相关回归约 9 秒；Kotlin 单测约 0.1 秒，这些不是视频性能指标。

未测量真实 OPED 跳转端到端延迟、丢帧、GPU/功耗、倍速/旋转/切镜下的两端遮罩效果。没有因构建通过而宣称这些已通过。记录上传目前没有新增持久化离线队列；HTTP 失败时不阻塞播放，但该 action 的服务统计可能缺失。Android 身份保鲜检查为约 5 秒一次，执行前仍会重新 resolve；没有后台实时推送撤销。

## 使用及回滚

E 盘隔离开发启动：`scripts\run-windows-isolated.ps1 -DataHome E:\fly_play_recovere\.worktrees\fly-player-b-oped\.runtime\llm-b-test -ShowWindow`。脚本默认隐藏启动，需要交互时显式加 `-ShowWindow`；本机隐藏启动不暴露可控制窗口，最终截图使用此显式参数。脚本只设置被启动子进程的 `FLY_PLAYER_DATA_HOME/TEMP/TMP/APPDATA/LOCALAPPDATA`，验证程序和测试目录均是绝对 E 盘路径，之后还原调用 shell 环境。仅设置 `FLY_PLAYER_DATA_HOME` 不会改变现有 `Directory.systemTemp` 使用者，因此隔离测试必须通过脚本同时设置 `TEMP/TMP`；不能声称单个变量覆盖了所有运行缓存。下载视频的用户目录仍按原“更改目录”配置单独管理，本次没有下载媒体。新 profile 需要重新登录；不要通过复制已有明文 token 来跳过验证。`.runtime` 已加入 Git 忽略。

首次目录覆盖交付 `app.so` SHA256：`69BE4B4AE95ADC8CC93A805638CAAEAB3D6C86C4723AA5451455928DC15DEF34`。可执行文件 SHA256：`39EBAFBDE8B607A92C6406508C2EA78934713962404A1F6571C202FD40761F0E`。二者散列和新 profile 文件的存在性、大小、时间均记录在 `runtime-profile.json`，不含 prefs 正文、密码或 token。后续实播构建散列见下节。

回滚本分支提交即可撤销消费和助手入口；不需要回滚用户数据库。正式服务也可停止提供 published OPED 集合，普通播放继续沿用原服务链路。目录覆盖可通过取消 `FLY_PLAYER_DATA_HOME` 回到旧 profile；E 中新数据仍保留，旧 C 数据没有被替换。不要 reset/clean 原工作树，也不要把原账号和历史数据库覆盖成测试 profile。

## 真实文件发布后复验（2026-09-13）

复验仍在同一 B 工作树（修改前 HEAD `260e17f8422fa2b9b3796e03b80f6d9c0537778f`），服务为 `http://127.0.0.1:18789`。实际播放《紫罗兰永恒花园》S01E07，Emby item `2538` / source `mediasource_2538`，时长 `1421005 ms`。A 对原 NAS 文件提供 verified 身份，文件 SHA256 `4d7fe0c1ab63d555e0e2d5b76c184c9f46df9f610dfa96a720eaf586c778fa85`，坐标 `33f4be04242c11a50b23aa624dcc606111001f8a6ae4c91f3ecf4a37df0d4d1d`。用户查看真实边界取证后明确确认以“仅提示”发布；客户端验收脚本不写人工核验或发布记录。

正式集合 `c1601f298174596c9181d974a20ae9807c20d9bdd3d6ea3e4ab393de83b5b999` 包含 OP `79876–164876 ms`、ED `1330000–1420000 ms`，均为 `prompt_only`。该结果只覆盖此文件及本次原画质来源，不能推广为其他文件已核验。

本轮增加两处保守门禁：两端仅在当前来源明确为 `originalQuality` 且不是下载/外部本地文件时消费原文件坐标；转码、直链派生画质或缺少这些来源事实时拒绝消费。服务 ED 点击授权通过后取消已有自动连播倒计时，并保护剩余尾段；暂停 seek 不再因原有“剩余小于五秒”规则直接进入下一集，真实 EOF 且非用户暂停时仍使用原连播入口。普通手动 seek 不设置此保护。

最终 Windows Release 的真实运行 PID 为 `34860`，隔离数据及以下截图/SMTC 日志均位于 `E:\fly_play_recovere\.worktrees\fly-player-b-oped\.runtime\oped-real-validation`。其他用户原播放器 PID `37980` 未操作。截图来自真实窗口 `PrintWindow`，未生成或替换视频画面。

| 项目 | 实际证据与结果 |
| --- | --- |
| 正式 OP 提示及真实点击 | `final-op-prompt.png` 显示 01:30 的“片头·飞翔已核验 / 跳到 02:44”。实际点击提示的 TextButton 后，客户端 action `1789293453520738-320725335`：intent `90006 → 164876`，settled 实测 `164873 ms`，误差 `−3 ms`，generation `1` |
| OP 稳定画面 | `final-op-after-correct-click.png`（18:00:40 +08:00）为 02:44 的 Violet Evergarden 标题卡；SMTC 保持 `164000 ms` / paused。点击后瞬时截图不是稳定落点的依据 |
| 正式 ED 提示及真实点击 | `final-ed-prompt.png` 显示 22:20 的“片尾·飞翔已核验 / 跳到 23:40”。action `1789293733824141-2038597703`：intent `1340005 → 1420000`，settled 实测 `1420002 ms`，误差 `+2 ms`，generation `3` |
| 暂停 ED 尾段 | `final-ed-settled.png`、`final-ed-tail-paused-11s.png` 及对应 SMTC 日志：仍为 S01E07，23:40 / 23:41，paused，等待超过 11 秒没有倒计时或自动切至 E08 |
| 回看不循环 | `final-op-rewatch-paused.png`、`final-ed-rewatch-paused.png`：分别回看 100→104 秒、1340→1344 秒，只显示正式提示，没有自动跳转；对应 `*-before-smtc.jsonl`、`*-after-smtc.jsonl` 记录真实状态 |
| 发布关闭时拒绝旧提示 | 根任务仅暂关 `oped_publish_enabled`，服务返回 `OPED_PUBLICATION_DISABLED`。18:05:48 点击缓存 ED 提示后仍暂停于 1344 秒，提示消失；`final-disabled-old-prompt-result.png`。服务 action 表没有增加 intent |
| 发布关闭时普通播放 | 关闭期间重开同集，100→104 秒正常播放且没有正式提示；`final-disabled-ordinary-paused.png`。恢复 true 后再次重开，`final-restored-op-prompt.png`（18:12:12）在 90 秒重新显示正式 OP 提示，倍速为 1.0x |
| seek 到零点与短段倍速 | `final-seek-zero.png` / 对应 SMTC 显示 0 ms；通过原 UI 选择 2.0x，约 4.56 秒墙钟内进度到 8000 ms，真实画面更新，`final-speed-two-paused.png`。随后恢复 1.0x；此观察不等于全部倍速/OPED/性能场景通过 |

两次 action 的 context 均为 `desktop-1349889724-1789293315403122-898619117`，使用同一设备、文件、坐标和集合。精确 settled 数据由根任务只读真实服务 action 表取得，记录于服务树 `runtime/real-evidence/windows-published-actions.json`；脚本没有调用 `/oped/actions` 伪造事件。SMTC 是现有播放器暴露的整秒进度，日志明确 `position_precision_ms: 1000`，定位命令明确 `settled_observation: false`；它只能辅助画面定位，不能替代 mpv 实际落点验收。

新脚本 `scripts/observe-windows-oped.ps1` 校验目标 PID 的可执行路径必须为本工作树，定位该 PID 的 FLUTTERVIEW 后发送实际窗口点击/按键并采集截图；文本输入不进入 JSON 元数据，登录凭据仅在本机私有文件读取。`scripts/windows-media-observation.cpp` 读取现有 Windows 媒体会话，只有唯一会话且应用名与目标单集副标题严格匹配时才可暂停/定位；不打开文件、不解码、不代理媒体。点击提示使用原客户端 UI，定位辅助不能算 OPED action。

复现窗口观察：先用前述隔离启动脚本启动 B bundle，再执行 `scripts/observe-windows-oped.ps1 -TargetProcessId <实际B进程ID> -Action Capture -Name observation`。仅在读取实际截图后按该窗口尺寸传入 `Click -X <x> -Y <y>`；Flutter UIA 在本机仅暴露 FLUTTERVIEW，不能把坐标流程宣称为跨布局控件自动识别。SMTC 辅助器可加载 `E:\fly_play_recovere\.tools\portable-build\enter-portable-env.ps1` 后，用 `cl.exe /nologo /EHsc /std:c++17 /O1 scripts/windows-media-observation.cpp /FoE:\fly_play_recovere\.tmp\oped-smtc-read.obj /FeE:\fly_play_recovere\.tmp\oped-smtc-read.exe /link windowsapp.lib runtimeobject.lib` 编译；无参数只读，`--seek-ms 90000 '紫罗兰永恒花园 · S01E07'` 暂停并定位现有唯一媒体会话。使用前必须确认该会话属于本轮 B 播放窗口。

最终构建日志 `E:\fly_play_recovere\.tmp\oped-real-windows-tail-final-build.log`，bundle 路径不变。`fly_player.exe` SHA256 `BD8AF9C97A72A49DC231F6AA3C088AAB1F56D134FE30C38579D285C105506CA0`；`data/app.so` SHA256 `BDA80AD96B88763EFA6BBF876FD5759A8FD4A9FF338568EA0FBC565B7B593BAC`，记录为 `final-binary-hashes.json`。

本轮验证：`flutter test --no-pub test/services/fly_oped_source_delivery_test.dart` 三项 PASS；修改的三个 Dart 源文件与该测试 `dart analyze` 无问题；完整 Windows Release PASS。Android 生产源码诊断编译 PASS，日志 `E:\fly_play_recovere\.tmp\oped-real-android-diagnostic.log`；仍无 adb 设备，也未进行 APK 打包、安装、实机消费或 ED 尾段实播。原画质之外的来源拒绝以测试及代码门禁验证，没有把它记为转码实播通过。本轮客户端未调用收费模型（0 次）。
