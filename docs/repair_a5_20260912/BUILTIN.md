# Windows 内置播放器修复交付（A5-N01 / A5-N02）

## 基线、隔离与适用性

- 基线：`a5acbc3df8af601e654d4839c16d8d4583a43192`，从已提交版本开始，未继承原工程脏改动。
- 修复工作区：`<REPAIR_WORKTREE>`。
- 证据目录：`<REPAIR_EVIDENCE>`，下文日志简称均位于其 `logs/` 子目录；每次正常结束的命令有同名 `.log` 原始输出及 `.json` 命令、环境、时间、退出码。
- 已读交接书、FINDINGS 的 N01/N02、REVIEW_REPORT、REMEDIATION_PLAN、TEST_RESULTS、EVIDENCE_INDEX，以及原 N01 症状探针。原症状 PASS 不作为正确行为 PASS。
- 两项均适用。只读比较原工程的三个相关文件：Host / Session 没有已有修复；Screen 的已有改动是弹幕请求绑定 scope/来源/代次，与 N01/N02 不同。没有复制这些改动或其他 fly_data 内容。只读差异另存 `builtin_main_overlap.diff`。
- 本次仅修改下列五份源码、三份测试及一个方法夹具生成器；未提交、推送、合并、安装或替换原工程、旧 worktree、审查快照和正在使用的播放器。原工程可能继续受到其他窗口的合法修改。

## A5-N01：片尾提示与自动切集

状态：**CODE_FIXED / METHOD_REGRESSION_PASS**。实际 mpv/Windows 播放结果由主任务另行记录，不能从方法夹具推导。

生产位置：`lib/desktop/playback/desktop_playback_screen.dart`。

- 最后 5 秒媒体时间内只更新预提示，数字按剩余媒体时间和当前倍速计算；此时没有触发切集的墙钟 Timer。
- 只有 completed/EOF 才建立真正的连播倒计时。已经展示过片尾预提示时保留最后 1 秒；没有预提示的 EOF 保持原 5 秒取消窗口。这是与旧逻辑明确不同的行为：不再提前跳过尚未播放的片尾。
- EOF Timer 复核来源代次、completed、自动播放开关、下一集/解析入口、A-B、加载和错误状态。用户暂停意图和缓冲时暂停推进；恢复后继续。
- 用户取消仍保留本集 `_autoNextSuppressed`；普通 seek 不清除该取消。主动 seek 撤销旧 Timer 并清理旧 completed 展示标记，防止 EOF 后回拖到最后 5 秒时拦截新的 EOF。设置 A 点也撤销预提示。
- 切集/重播原有 overlay reset 继续重置新播放的取消状态；没有改变解码、画质、音轨或字幕选择策略。

修复证据：

| 命令记录 | 结果 | 断言与边界 |
| --- | --- | --- |
| `builtin_n01_red_isolated` | 17 例，13 失败 / 4 通过，exit 1 | 从 a5 原样提取方法，以正确行为断言重现暂停/缓冲/未 EOF 提前切集、Timer 失效检查缺失 |
| `builtin_n01_green` | 17/17，exit 0 | 首次修复后同场景通过 |
| `builtin_seek_tail_red` | 19 例，2 失败，exit 1 | 独立审查补充：EOF → seek 98/100 秒，完成标记仍为 true；分别覆盖本集已取消与未取消 |
| `builtin_seek_tail_green` | 19/19，exit 0 | 主动 seek 清旧 completed，取消状态仍保留 |
| `builtin_review_final_tests` | 69/69，exit 0 | 含最终 N01 19 例方法夹具、Host 14 例、Session 4 例、原 runtime 32 例 |

19 例覆盖：最后 5 秒暂停/缓冲/无位置推进各 10 秒；0.5/1/2 倍速等待 EOF；seek 离开片尾再回来；取消后 seek/EOF；EOF 等待时暂停、缓冲、错误、加载、关闭自动播放、A-B、退出、代次变化；EOF 后回拖片尾；无预提示 EOF 的原 5 秒窗口。

可重复生成器已经进入补丁：`tool/desktop_auto_next_probe.py`。它每次读取待验证源码并原样提取 `_onPositionChanged`、播放/缓冲/完成回调、倒计时/取消及 `_seekTo`；输出 `.binding.json` 绑定整文件与方法 SHA256。UI、上报、内核和下一集解析是惰性桩，**不是完整 Screen widget，也不是解码测试**。没有把生产方法的固定旧副本当作永久回归。

复现方式（从已配置 Flutter 依赖的修复工程运行；输出放入独立临时目录）：

```text
python tool/desktop_auto_next_probe.py . <临时目录>/desktop_auto_next_test.dart
flutter test --no-pub <临时目录>/desktop_auto_next_test.dart
```

最初 `builtin_n01_red` 被 package_graph 缺失阻断；`builtin_n01_red_ready` 被锁定 sqlite3 DLL 下载超时阻断，均没有执行行为断言。为先取得 N01 RED，曾在证据目录创建只依赖 flutter_test 的独立方法夹具包，`builtin_fixture_pub` 离线解析成功。最终测试已回到完整修复工作区运行。

## A5-N02：Host 请求、会话和已接受来源的所有权

状态：**CODE_FIXED / HOST_SESSION_REGRESSION_PASS**，会话内核为惰性注入，出流释放使用合成本机 HTTP；真实双媒体路由/纹理/音频验收由主任务另记。

生产位置：`desktop_playback_host.dart`、`desktop_playback_screen.dart`、`desktop_playback_session.dart`。

- Host 的 launch/resume 在任何 await 之前取得请求代次与 scope。设置、旧路由退出、旧会话释放、季列表、暂停及 seek 返回后重新核验；最新请求取代旧请求。
- 撤销旧会话时先清除其槽位和认领，再移除旧活跃路由并等待释放；后续清理只持有捕获的旧对象。路由 completed 回调也只清除仍属于该路由的槽位。
- 新会话建立后由 Host 显式认领。Screen dispose 仅在会话仍被认领、未 disposed 且原有 ready/错误/完成/加载条件允许时暂停保留，否则释放。
- Session 的重复 dispose 共享同一个 Future，所有调用都等待同一条释放链；暂停、播放器或来源释放异常时，其余清理仍在 finally 中执行。`releaseSource` 支持并等待 `FutureOr<void>`，兼容 Screen Reporter 的原有 void 回调。
- 独立审查发现的两个来源缺口也已修复：已传入 Host、尚在等待季列表的 source，以及创建后在首帧前被替换的 session，均在 Host 就具有释放回调。未转交请求由 finally 收尾；挂载后仍通过 Reporter 的原有上报队列调用同一释放闭包。
- 出流句柄按当前请求 scope 及归属判断并去重；旧请求不会 quit 新请求复用的同一 playLink。页面 unmounted 后仍可通过捕获的 provider 身份清理本请求。scope 已变化时不向失效账号发 quit，旧远端会话保留服务端超时回收语义。
- Host 注入参数仅用于测试会话；Session 可注入 Player/VideoController 以运行真实 Session 的清理代码。默认仍创建 `PlayerConfiguration(libass: true)` 和原 VideoController，未改变正式内核设置。

修复证据：

| 命令记录 | 结果 | 断言与边界 |
| --- | --- | --- |
| `builtin_n02_red_bounded_v2` | 1 失败，exit 1 | a5 Host 仅以注入替代原生构造：旧 A 晚返回仍 true，正确断言要求 false；方法/来源见 `fixtures/n02_baseline_binding.json` |
| `builtin_n02_expanded_v2` | 7/7，exit 0 | 首批公开 Host + Navigator 交错/恢复回归 |
| `builtin_session_red` | 4 失败，exit 1 | a5 Session 仅加入构造注入；重复 dispose 提前完成，异常导致后续资源未清理 |
| `builtin_session_green` | 4/4，exit 0 | 实际修复后的 Session，惰性 Player/VideoController |
| `builtin_source_release_red` | 3 失败 / 1 通过，exit 1 | 新来源回归先证明 metadata 与首帧前缺少 media.quit；scope 已变化不释放的反证通过 |
| `builtin_source_release_green` | 4/4，exit 0 | 不同句柄各释放一次、相同句柄不提前释放、scope 失效不发送 |
| `builtin_review_final_tests` | 69/69，exit 0 | 最终 Host 14 例包含增加的 unmounted 来源释放 |

Host 测试文件：`test/desktop/desktop_playback_host_ownership_test.dart`。9 例验证真正的 Host/导航入口、假后端和惰性会话：两种请求完成顺序、未挂载、设置 await、账号切换、3 轮保留恢复、等待 pause/seek 的恢复被新 launch 取代、旧路由/会话清理期间新请求持有槽位。视频路由在构建正式 Screen 前移除，不能当成 Screen 生命周期或纹理测试。

另 5 例通过真实 Feiniu HTTP 调用、合成本机服务记录 `media.quit` 的 playLink 和次数：metadata 晚回包、首帧前替换、共用 playLink、scope 变化及入口 unmounted。季列表返回受控 500 是预期夹具故障路径；所有账号、token、媒体 ID 和出流句柄均为合成数据。测试只在自己的 HttpOverrides 中将 loopback 设为 DIRECT，没有改变产品全局代理策略。

Session 测试文件：`test/desktop/desktop_playback_session_test.dart`，直接运行正式 Session 的 dispose 方法，检查资源释放次数与 Future 等待语义。

早期 `builtin_n02_red` 至 `builtin_n02_red_v6` 有夹具 runAsync/fake-zone 等待及 teardown 停滞，曾有界中断；保留原始日志，但不把它们当作播放器挂死或完整测试 PASS。修订后 `builtin_n02_red_bounded_v2` 得到可正常结束的真实失败断言。最终测试用 tester.idle 驱动无视频的 Host 交错，HTTP 仅在 runAsync 内执行。

## N02 追加闭环：释放 API 内部等待期间的归属变化

主任务追加授权修改 `lib/services/native_reentry_support.dart` 和 `lib/api/feiniu_api.dart`。原工程这两文件只读差异为空；未把其他窗口改动带入。

`releaseServerSession` 增加可选 `isCurrent`，在进度队列 flush 前后复核，并传至 `quitServerPlaySession` / `_controlServerSession`。后者在 clientId 读取/写入前后复核，还将该回调仅放在本次请求的 `Options.extra`，由已有 Dio onRequest 在读取动态 NAS 鉴权前再检查。失效请求停止，已进入 Dio 的失效请求以取消结束并由原 best-effort helper 收尾。默认不传回调的调用保留旧行为；未更改离线队列的全局 scope 业务模型。

内置 Host 传入的闭包同时核验捕获的账号/后端 scope 与最新同 playLink 请求/会话归属，不使用 context.mounted，所以页面退出后仍能释放自己的来源。外部 Host 由主线程接入同一可选参数，未由本子任务编辑。

| 命令记录 | 结果 | 断言与边界 |
| --- | --- | --- |
| `builtin_release_guard_red_v2` | 6 例，4 失败 / 2 通过，exit 1 | 实际 Host + API + HTTP 回环；flush 或 clientId 持久化等待期间改账号/同 link 新 owner，原逻辑误发退出；同 owner 各释放一次 |
| `builtin_release_guard_green` | 6/6，exit 0 | guard 链补齐后同场景通过 |
| `builtin_release_queue_green` | 5/5，exit 0 | Dio 排队后、已有 access-code 拦截器与 auth 拦截器之间用微任务使账号/owner 变化；无旧 quit；正常/默认各一次；入口失效连 flush 都不执行 |
| `builtin_release_queue_mutant_red_v3` | 5 例，2 失败 / 3 通过，exit 1 | 补充变异检查：仅移除最终 onRequest guard，即重新误发两次 quit；不是 a5 历史基线 RED |
| `builtin_release_final_tests` | 124/124，exit 0 | 最终 Host 20、Session 4、N01 方法 19、runtime 32，及新 API 5 与既有 helper/access-code 回归 |
| `builtin_release_guard_analyze` | 8 个 Dart 文件，无 issues，exit 0 | 五份生产与三份测试 |
| `builtin_release_final_format` | 8 个文件，0 changed，exit 0 | 格式检查 |

新增 API 回归位于 `test/api/feiniu_session_release_guard_test.dart`。Host 测试通过测试端 SharedPreferences 内存平台存储暂停真实 clientId 的 setString，使用已锁定的间接测试包，不增加生产依赖；同 link 新 launch 先登记请求，再放开旧释放，最后等待新 launch，避免测试依赖提前结束的 dispose。所有网络只访问合成本机回环服务，依然没有真实 NAS 或媒体内核。

`builtin_release_guard_red` 因外部调用先接入新参数而编译失败；当时仅补可选签名后才运行可信 red_v2。队列补充变异检查初轮与 v2 分别因夹具导入身份及方法提取错误而未执行断言，只有 v3 是有效行为证据；该检查是在新增队列测试通过之后运行，明确不充作先写测试的历史 RED。变异副本/删除 hunk/SHA 记录在证据目录 `fixtures/n02_release_queue_mutant_v3_binding.json`，未改生产以运行变异。

追加改动仍沿用原 best-effort 释放和超时回收；对于已经发送到网络的请求，新的 guard 不撤回请求。回退时 API/helper 的可选参数及两个 Host 的调用接线需要成组处理，不能只删除签名。最终文件绑定见证据目录 `builtin_release_guard_freeze.json`，测试摘要见 `builtin_release_guard_test_summary.json`。

## 验证边界、风险与集成

- `builtin_review_analyze_clean`：五个变更 Dart 文件静态分析无 issues，exit 0。最终格式检查与文件 SHA 见证据目录后续 `builtin_final_*` 记录。
- 本子任务未运行真实 mpv、双媒体 Windows 视频路由、真实 NAS、真实账号数据库、PotPlayer、Android 或长期播放。正常选集解析失败后的完整 Screen UI、服务端字幕和音轨/画质的实播回归不能用这些夹具签署通过。主任务另有实际 Windows 合成素材探针与全套回归。
- 主要可见变化是 EOF 后的 1 秒/5 秒切集窗口，以及交错启动时拒绝旧请求。集成后重点复查暂停返回/恢复、片尾 seek、A-B、首帧前替换、内外切换。
- 首帧前已接受的出流句柄现在随 Session dispose 等待 best-effort quit，失败沿用 Feiniu 客户端超时及服务端回收；极端网络下这条清理可能增加该次替换等待。已挂载 Screen 继续通过原 Reporter 的队列顺序释放。
- 未改原工程。同一 Screen 文件还承载其他窗口的弹幕 scope 改动，集成时须保留其不同 hunk 并复验；不应整体覆盖该文件，也不要夹带 fly_data 内容。
- 回退：N01 回退 Screen 的片尾/seek/A-B hunk及方法生成器；N02 将 Host、Session 及 Screen retain hunk作为一组回退，并移除新增 Host/Session 测试。不要仅回退 Host 认领而保留 Screen 的认领条件。
- 未创建 Git 提交；最终补丁由主任务统一导出，**尚未应用到主工程**。
