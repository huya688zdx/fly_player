# A5 外部播放修复记录

基线为 `a5acbc3df8af601e654d4839c16d8d4583a43192`，修复目录为 `<REPAIR_WORKTREE>`（下称 W）。命令和原始输出保存在 `<REPAIR_EVIDENCE>/logs`（下称 E/logs）。本批没有提交、集成、安装或运行实际播放器，没有修改 audit 快照或主工程。

## 适用性与重叠

2026-09-12 读取交接书、FINDINGS、REVIEW_REPORT、REMEDIATION_PLAN、TEST_RESULTS、EVIDENCE_INDEX，以及 external/repro_tests 的两个原症状探针。三个问题在 a5 基线均成立，非 ALREADY_FIXED。

只读检查主工程对应 git diff：`external_playback_host.dart` 的已有变更在 `_prepareSubtitle` 中向弹幕预取补充 statsScope/isCurrent；`play_detail_page.dart` 的已有变更增加统计作用域捕获及传递；`potplayer_session.dart` 没有相应未提交修复。这些属于并行 fly_data 工作，不解决本批问题，也未复制到 W。Host、详情页存在文件重叠；尤其详情 getter 与 `_openPlayer` 的统计作用域新增相邻，集成时须按当前目标内容保留双方改动。

## 逐项结果

| ID | 状态 | 实际修复及主要位置 | 验证边界 |
| --- | --- | --- | --- |
| A5-E02 | FIXED；Dart 契约 VERIFIED | `potplayer_session.dart` 的 `sendCommand`/`requireCommand` 要求 native bool=true；启动、列表续播、resume、Host pause/seek/step、close 均处理 false。定位使用 focus=false，窗口前台激活独立调用；焦点失败单独提示，媒体控制失败不返回 resume 成功。resume 的最终结果还检查真实返回的匹配文件、播放状态与定位样本。close 失败不阻止本地清理。 | 生产 Dart + mock MethodChannel，true/false/PlatformException、命令后窗口退出；未运行真实 Win32/PotPlayer。原生 PID/file 身份校验完全保留，C++ 无变更。 |
| A5-UI-02 | FIXED；Host 查询 VERIFIED | Host 新增 `positionForLaunch(itemGuid)`，核验 mounted、当前 scope、未结束且仍被持有的 Session、媒体 ID 与 ready 状态。详情页三个原消费点通过同一 getter 查询；历史 ended 状态仍可展示。 | 假飞牛账号与假 Emby 连接；下载来源标记、同媒体 ID 的账号/服务器切换、ready/preparing/disconnected/ended、已结束后 B 的解析进度、切回内置后的空查询；同会话保留位置和显式字幕关闭不变。不是点击完整详情页后真实起播的集成测试。 |
| A5-E01 | FIXED；Session/公开 Host 取消 VERIFIED | Session 在 snapshot/configure/seek/延时及接受采样后复核 finished/current，防止重装 Timer/observer。Host 从首个 await 前捕获 scope 和启动 owner，公开 stop 立即作废 owner，内部替换旧 Session 不误取消自己的新启动。每个准备边界、PID 返回、start 与字幕应用之后核验身份；取消统一走收尾并返回 false。尚未 ready 的 stop 不再先等待额外 poll。 | 公开 Host 的 launch、launch 返回无 PID、snapshot、configure、initial seek、subtitle 六个等待点 × stop/账号切换，共12例。stop 是 DesktopPlaybackHost 切内置所调用的同一公开接口，未启动 mpv。 |

取消收尾保留 proxy 关闭、reporter flush/dispose、字幕目录清理；同作用域的飞牛后端会话释放改为等待完成，并按 playLink 防止重复释放。获得 PID 前失败也释放已准备的源；预取晚返回发现 disposed 时自行回收已取得的后端源。账号已切换时仍保留原 scope 护栏：不会用当前 NasProvider 向新账号发送旧进度或退出命令；失效 scope 的远端会话仍依赖服务端超时，不声称已在旧服务器执行退出。没有用零位伪造中立后端的已播放/结束回报。

## RED → GREEN 与命令证据

所有 Flutter 命令使用固定 Flutter 3.41.9 / Dart 3.11.5，并经 E/run_check.py 记录实际工作目录、命令、隔离 TEMP/TMP、起止时间和退出码。测试使用内存 SharedPreferences、假账号/连接、单字节假 exe（只作路径校验）、合成媒体与本机 HTTP 服务，不启动该 exe。

| 记录（E/logs 下同名 .json/.log） | 结果与解释 |
| --- | --- |
| external_session_red | 环境阻断：缺 package_graph.json；尚未执行用例。 |
| external_red_ready | 环境阻断：锁定 sqlite3 native asset 下载失败；尚未执行用例。根代理随后从同 a5 构建缓存补齐元数据和已锁定 DLL。 |
| external_red_assertions | 正确断言 RED：原 Session 将 false 返回为 true、取消后 start 正常返回；UI 原 getter 语义将 ended 的45秒作为起播位置。UI getter 先等价迁入 Host 再加 guards，以避免仅把“新增API不存在”的编译错误算成 RED。该轮 Host HTTP fixture 尚受 Flutter HTTP mock 干扰，不计为 Host 产品缺陷证据。 |
| external_host_red_loopback | 测试夹具编译错误：HttpOverrides 不接收 null；保留日志，随后改用只在测试 zone 内创建真实 DIRECT HttpClient 的 overrides。 |
| external_host_red_boundary | Host 正确断言 RED；真实生产 Host+Session、mock native 和实际 loopback 进入取消边界，旧 Host 仍返回成功或抛出取消异常。 |
| external_session_scope_green | 初始 Session/作用域/原正常路径通过，exit0。 |
| external_host_green | 同 W 并行 Flutter 编译缓存发生 PathExistsException，主动中断；只有原始日志，无完整 runner JSON，不计测试结论。根代理随后为 run_check 加 cwd 锁。 |
| external_host_green_locked | 初版10个取消用例通过，包含 socket 拒连和临时目录清空；exit0。 |
| external_replay_guard_red → external_replay_guard_green | 自审新增“列表待续播期间显式从头播放”断言，先失败后修复通过。显式定位在 await 前覆盖旧目标，失败时恢复；不会被并发 poll 重新定位回旧进度。 |
| external_release_red → external_release_green | 同 scope 的合成 `media.quit` 请求在旧 launch 返回前尚未完成，正确断言 RED；改为等待收尾后通过。 |
| external_frozen_tests / external_frozen_analyze | 复核前版本：8个文件44例通过；本批8个变更Dart文件分析无issues。不是复核后的最终数量。 |
| external_delayed_control_red → external_delayed_control_green | 根复核指出 PostMessage 与同步 Query 不能保证首次样本已生效。两个第三次snapshot才应用的正常resume/seek用例先失败后通过；Host pause/seek也复用新的有界确认。 |
| external_unchanged_seek_red → external_review_final_tests | 独立复核指出按最大12倍速随等待扩宽定位上界会把始终不变的旧30秒位置当作seek0成功；正确断言复现后改为固定±3秒容差。等待仅增加采样机会，不把墙钟当作定位已经生效。 |
| external_confirmed_final_tests | 中间验证有1个fixture失败：并发测试共用runner TEMP，全目录枚举误计入另一Host测试的有效临时目录。改为IOOverrides只将本fixture系统临时目录指向自己的目录后复验；不是生产清理失败。 |
| external_review_final_tests | **最终8个测试文件、49例通过、0失败、0跳过，exit0，18.534秒。** |
| external_review_final_analyze_clean / external_review_final_format_clean | 复核后本批8个Dart文件的分析与格式记录。此前 external_review_final_analyze 的唯一测试if-braces提示已补齐，external_review_final_format 随后提示该测试需要重新格式化；已格式化，原日志均保留。 |

49例构成：新增 Session 生命周期/命令25例，新增 Host 取消12例，新增起播位置2例；原 Session 2例、Host 1例、控制页1例、列表2例、字幕4例。Host 原测试补充 false/PlatformException 的 pause/seek/resume 分支，以及第三次采样才生效的pause/seek。stepPlaylist 的三种返回值覆盖集中在生产命令封装，实际 PotPlayer 列表切集仍未运行。

每个 Host 取消用例都实际读取三字节合成媒体，确认旧 launch=false、取消之后不再发 configure/seek/subtitle、无活动1秒周期 Timer、关闭端口拒连、fly_potplayer 临时目录为空，并再次正常 launch/stop。Session 取消用例还确认 binding 中没有遗留 observer，重复 finish 只执行一次 onFinished。合成 HTTP 客户端仅在测试 zone 直连，未修改生产全局代理策略，也未修改 E03 的测试文件。

## 播放影响与未运行项

正常起播、暂停保持、恢复、定位、显式字幕关闭、动态弹幕与字幕更新、列表媒体身份切换及原字幕匹配测试通过。详情画质重开仍可取得同一活跃会话的位置；ended/preparing/disconnected 不再提供起播覆盖值。控制 false 会让调用方继续正常启动或展示错误，避免提前中止起播；前台激活失败不会被误判为已确认播放的媒体失败。

resume 与 Host pause/seek 使用同一 `confirmPlayback`：100毫秒重试、3秒确认窗口（单次IPC仍受原生自身超时约束），始终检查同一PID/媒体及当前会话；退出、切媒体或取消立即失败。定位容差固定为±3秒，始终不变的旧位置不会因等待变长而变成成功。超过窗口仍未生效返回false，不承诺极慢的真实原盘定位在此窗口内完成。

真实 PotPlayer 启动、Win32 消息投递/前台策略、真实 NAS/Emby、真实下载媒体、完整详情页起播操作、mpv 与 PotPlayer 实际互切、系统退出和长时播放：**NOT_RUN**。没有用 mock 输出冒充原生验证，亦没有测量 FPS/长期内存。新增等待后端退出会使网络慢时的取消完成时间包含原释放请求耗时；仍沿用现有 API 的异常处理/超时机制。

## 文件与回退

生产：`lib/desktop/playback/external_playback_host.dart`、`lib/desktop/playback/potplayer_session.dart`、`lib/pages/play_detail_page.dart`。

变更测试：`test/desktop/external_playback_host_test.dart`、`test/desktop/potplayer_session_test.dart`；新增测试：`test/desktop/external_playback_lifecycle_test.dart`、`test/desktop/potplayer_session_lifecycle_test.dart`、`test/desktop/external_playback_position_test.dart`。本批不包含 external_player_media_proxy_test.dart 或任何 C++ 改动。

E02 与 E01 在 Session/Host 中共享检查边界，建议将这3个生产文件及5个变更/新增测试作为一批集成或回退；回退只反向应用本批补丁，不 reset 主工程、不覆盖并行 fly_data 工作。整仓分析、全套测试及独立复核由根代理统一记录；本说明的49例不能替代整仓最终结果。**尚未应用到主工程。**
