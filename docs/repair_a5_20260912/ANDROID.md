# A5 Android 有界整改：A5-R01 / A5-R02

基线为 `a5acbc3df8af601e654d4839c16d8d4583a43192`，比较目录为 `<REPAIR_EVIDENCE>/baseline`。生产只修改 `repair-a5-handoff-20260912` 隔离工作树。原工程 Android 未提交差异只包含三行 `statsScope`，不能修复本两项；本批未继承这些无关统计改动。

已读交接、REVIEW_REPORT、FINDINGS、TEST_RESULTS、EVIDENCE_INDEX、整改计划与工作树 AGENTS。仅覆盖 Android 来源镜像并发删除和保留目录归属；不修改 Dart、解码、弹幕渲染、轨道/画质解析策略或后端。

## A5-R01：删除成功时修改当前来源列表

**适用性：确认。** 原 `removeDanmakuSource` 在反向通道请求之前计算 `kept`，等待成功后整表覆盖。Flutter 的写队列不能保护 Kotlin 的旧数组。

**修复：** 新 `NativeDanmakuSourceStore` 的删除完成闭包仅捕获 `mediaKey + source identity`；收到严格布尔 `true` 后，在 `NativePlayerSettingsStore.updateString` 的进程共享锁内读取最新偏好、只移除该身份、再写入。保存/去重添加走同一事务。保留现有 `dandan:episodeId` 与本地导入文件路径身份，不按展示名称删除。重复成功幂等；失败/异常不改镜像；解析损坏数据时保留原值，不把它覆盖为空数组。

Activity 捕获删除时的媒体加载代次。切媒体后的成功仍处理原目标持久记录，但不会清空新媒体 Flutter 列表或重绘新页；错误提示也限定在原媒体。列表查询增加独立代次，删除/切媒体使旧查询失效，避免晚到的列表再次显示已删除行。

**测试：** `NativeDanmakuSourceStoreTest` 5 项：双删正/逆序并在等待中新增；false/null/非布尔成功不写；切媒体晚成功只删除旧目标、同名源不误删、重复成功幂等；两个存储实例并发删除/新增 40 次；本地来源身份和损坏数据保护。使用生产存储与生产完成闭包，Android SharedPreferences 接口的测试适配器读写真实临时文件，再新建存储读取落盘结果。没有使用 Python 状态模型，也未触碰真实用户数据。

**影响/限制：** 保留现有 SharedPreferences `apply()` 的异步磁盘语义，锁保护进程内读改写及提交顺序。临时文件测试覆盖序列化结果；不声称验证了真实设备进程被杀时的磁盘行为或 Flutter/Android 双存储跨进程事务。

**回退：** 撤回来源存储 helper、SettingsStore 事务与 Activity 对应调用/列表回包守卫即可；不涉及格式迁移或不可逆数据变换。回退将恢复旧并发风险。

## A5-R02：scope 与剧/季共同限定目录复用

**适用性：确认。** 原 Activity 先替换 `playbackSessionScope`，后续 `applyLoadArgs` 只按 series/season GUID 判断保留目录，同 GUID 的不同服务器/账号会复用旧数据。

**修复：** `NativeEpisodeCatalog` 独立保存上一目录的 scope/series/season。`onNewIntent` 在替换 Activity scope、读取异步弹幕文件之前调用目录选择；只有非空同 scope 且相同已知 series 才可跨季复用；没有完整 series 信息时允许同已知 season 回退。两个不同已知 series 不因 season 碰撞而复用。未知 scope 不继承目录。

归属变化立即增加目录 generation、清除季缓存/请求等待者/旧面板目录与预取；旧季回包必须通过 generation 才能写缓存。另用媒体加载代次拒绝过期的 Intent 弹幕解析、播放解析、版本/重载和预取回包。加载尚未应用期间暂停从旧媒体上下文发起相关操作。同 item 的免重载快捷路径独立检查相同 scope/item/media；仅在双方明确提供的剧/季字段冲突时拒绝，不要求电影拥有剧集目录。未知目录仍不可继承缓存。

反向播放解析返回的 source DTO 不含宿主 `playbackSessionScope`，只有在已通过请求代次守卫的回包中补回当前捕获归属；显式不同 scope 拒绝，不会把旧回包自动改成新归属。同账号跨季保留已访问季缓存及同季等待者。首次异步加载被新 Intent 覆盖时，Activity 返回键回调仍会注册。

**测试：** `NativeEpisodeCatalogTest` 6 项，覆盖换账号/服务器而 GUID 相同、旧回包晚于新回包、同账号跨季保留及完成在途请求、series 缺失的同季回退、series 冲突、未知 scope/目录不继承。`NativePlayerActivityCatalogOwnershipTest` 2 项直接创建生产 Activity，反射调用其实际目录迁移方法，验证请求等待者/缓存/面板 token 的失效和同账号跨季保留。Android API 来自 mockable SDK，不是完整 Activity 生命周期或真机测试。

**影响/回退：** 变化限定目录状态及异步回包归属；沿用宿主已有 scope 协议，不引入数据迁移。撤回 helper 和 Activity 对应目录/代次接线可回退。真实 singleTop 设备重入、系统多窗口、真实 NAS 两账号与实际播放仍需设备验收。

## 验证账本与工具边界

所有命令由新证据目录 `run_check.py` 记录 cwd、命令、时间、退出码及固定缓存/临时目录环境。下面日志基名均位于 `<REPAIR_EVIDENCE>/logs/`，同名 `.json` 保存命令元数据。

| 检查 | 状态 | 证据及边界 |
| --- | --- | --- |
| 抽取旧行为后的 Kotlin 回归 RED | FAIL，预期症状 | `android_r01_r02_red_json_fixed.log`：9 项运行、6 失败，复现复活删除目标、丢新增/新媒体源及跨 scope 复用。首次 `android_r01_r02_red.log` 有诊断 classpath 的 mockable JSON 抢先问题；已纠正顺序且保留原失败。 |
| 组件首次 GREEN | PASS | `android_r01_r02_green.log`，9 项通过；随后增加 2 个边界用例及 2 个实际 Activity 方法用例。 |
| 完整真实 Gradle full/lite compile/unit/lint 请求 | BLOCKED | `android_gradle_full_lite_offline.log`：Gradle 启动，Flutter SQLite 3.5.2 ARM Android native asset GitHub 下载失败，56 秒退出。没有进入 app Kotlin、JUnit 或 lint。 |
| 新工作树 full/lite 资源符号生成 | PASS，仅诊断资源任务 | `android_gradle_resources_offline.log`：跳过 Flutter 构建/资产复制，生成各自 flavor 的 R.jar 和 BuildConfig；当时尚未接入插件 metadata，不作为整包构建证据。 |
| Android 插件 metadata/registrant | 有界生成完成 | `android_plugin_metadata.log`：使用当前 Flutter 工具自己的 refreshPluginsList/injectPlugins；metadata 写出后 Windows symlink 权限报错被单独记录，Android registrant 继续生成。不标 pub get 或跨平台插件构建 PASS。 |
| 插件完整接线后的诊断 Gradle compile/unit/lint | BLOCKED | `android_gradle_wired_diagnostic_v2.log`：离线缺 file_picker 构建所需 Kotlin compiler 1.8.22 及 Netty 4.1.93 五个 jar，13 秒退出。未下载或升级这些依赖。v1 PowerShell 将未引号的 `-Drepair.verifiedMavenMirror` 拆开，已修正命令并保留失败日志。 |
| main + full Kotlin 全源诊断编译 | PASS | `android_full_source_final.log`，固定 Kotlin 2.2.20，真实 SDK 36 API、新工作树 full R/BuildConfig。不是 APK、插件打包或 Gradle compile PASS。首次 v1 缺闭合括号导致编译失败，已修复；v2 与 final 均通过。 |
| main + lite Kotlin 全源诊断编译 | PASS | `android_lite_source_final.log`，使用 lite 自己的 R/BuildConfig；相同编译边界。 |
| full 全部原生宿主 JVM 测试 | PASS | `android_full_jvm_final.log`：29 个测试类、208 项、0 失败。含本批 13 项用例。 |
| lite 全部原生宿主 JVM 测试 | PASS | `android_lite_jvm_final.log`：29 个测试类、208 项、0 失败。含本批 13 项用例。 |
| 真机/实播/Android SharedPreferences 进程死亡/完整 APK | NOT_RUN | 未安装、替换、启动或发布应用，未接触真实账号/NAS/媒体。 |

诊断 Python 只负责调用 Kotlin 编译器/JUnit，不复制生产逻辑。脚本先阅读旧整改的 `compile_android_sources.py`、`run_android_host_jvm.py`、`GenerateMockableAndroid.java`，复制到新证据目录 `tools/` 后适配；修正原脚本 lite 使用 full R.jar 的问题。旧脚本和旧日志未修改。

工具链沿用独立 JDK 21.0.12.1、项目固定 Kotlin 2.2.20、Gradle 8.14、现有 SDK36 与既有校验 Maven mirror。mockable SDK jar 来自既有 AGP8.11.1 工具生成，运行 Android stub 时返回默认值，与当前项目 `unitTests.isReturnDefaultValues=true` 一致。没有升级依赖、修改系统代理/系统配置或下载新工具；仅新工作树被忽略的 `local.properties` 写入既有工具路径，证据/临时制品均在新 E。

首批生产改动共 4 个 Kotlin 文件（Activity、SettingsStore、2 个 helper），对应 3 个 Kotlin 测试文件；首批 SHA 与基线差异保存于 `<REPAIR_EVIDENCE>/android_frozen_files.json`，未覆盖该历史冻结记录。

## 独立审查 IR-02 / IR-03 回归修正

2026-09-12 第一轮独立审查确认首批改动引入两项回归。本轮只修改 Activity 并新增 `NativePlayerActivityReentryRequestTest`，保留来源持久化与目录 helper 的首批实现。

**IR-02：** 初版同项快捷判断额外要求 `episodeCatalog.canReuse`，使没有 series/season 的电影恒为 false。现在把实际 Activity 判断提取为私有 `canKeepCurrentPlayback`：相同有效 item/media、相同 scope、当前未停放且没有在途媒体加载时可以保持播放；双方都有的 series 或 season 字段明确冲突时才重载。目录 helper 的未知归属不继承规则没有放宽。

**IR-03：** 初版三个用户解析请求只捕获媒体加载代次，直到第一份成功回包应用才增加该代次，导致连续 A/B 选择时 A 先回便压掉 B。现在 `requestEpisode`、`requestVersion`、`requestServerReload` 在有效请求发起时统一取得新的 `PlaybackResolveRequest` owner；成功和错误回包必须同时满足最新请求 owner 与原媒体加载代次。只是发起请求不改变媒体加载代次/目录 generation，不会作废仍在播放媒体的有效预取或列表回包。收到新的有效 Intent 时立即作废旧用户解析 owner，走同项免重载也适用；真正换媒体时继续沿用原媒体加载代次守卫。

**正确断言 RED→GREEN：** 先将首批实际 Activity 判断/守卫作等价提取并接入原调用点，尚保留首批错误行为，运行新增正确行为断言。`android_ir0203_red_compile` 编译通过，`android_ir0203_red_jvm` 全套 216 项中 5 项失败，实际复现电影误重载、缺省目录误重载、明确季冲突未拒绝、A 先回只接受 A、旧错误仍可通过。RED 时的 Activity 与新增测试源码另外保存在 `temp/android_ir0203_red_sources/`。随后修复生产判断与发起时 owner，完成下表复验。

| 本轮检查 | 状态 | 证据 |
| --- | --- | --- |
| main + full 全源 Kotlin 诊断编译 | PASS | `logs/android_ir0203_full_compile.json/.log`，exit 0 |
| main + lite 全源 Kotlin 诊断编译 | PASS | `logs/android_ir0203_lite_compile.json/.log`，exit 0 |
| full 全部原生宿主 JVM | PASS | `logs/android_ir0203_full_jvm.json/.log`，30 类、216 项、0 失败 |
| lite 全部原生宿主 JVM | PASS | `logs/android_ir0203_lite_jvm.json/.log`，30 类、216 项、0 失败 |

新增 8 项测试直接创建生产 Activity，并调用其实际私有 shortcut / 请求 owner 方法：电影同项复用；不同 scope/item/media、parked/pending 拒绝；剧/季冲突拒绝；缺省目录不打断同项；A/B 正反回包顺序均最新 B 生效；旧错误拒绝、最新失败不复活旧成功；请求发起不作废当前媒体预取/目录；新 Intent 和新媒体加载仍使旧 owner 失效。测试没有运行真实播放器或完整 MethodChannel/Activity 生命周期；两种回包顺序测试在接受成功时显式推进生产媒体代次字段，以保持 `applyEpisodeResult` 的提交边界，不调用解码器。

本轮没有改变工具链、依赖或构建环境，因此没有重复已确定受依赖阻挡的完整 Gradle/设备验证；上文 BLOCKED/NOT_RUN 边界继续成立。回退本轮仅涉及 Activity 新增请求 owner/同项判断接线及新增测试；会恢复独立审查指出的两项回归，不建议独立回退。

修正后总计 4 个生产 Kotlin 文件、4 个 Kotlin 测试文件及本说明。最新冻结 SHA 为 `<REPAIR_EVIDENCE>/android_frozen_files_ir0203.json`，新基线补丁为 `android_baseline_review_ir0203.patch`；首批冻结、失败/通过日志均保留。
