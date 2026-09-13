# OP/ED 设置与飞翔登录

本次增量在 B 客户端 `0ff973b` 上继续实现，入口沿用播放器的“设置 → 跳过 OP/ED”。Windows 与 Android 都增加“飞翔已核验区间”开关，复用同一个 `player_fly_oped_enabled` 偏好，默认开启。是否显示和执行还必须通过当前飞翔登录及原文件播放来源检查；登录状态不会保存成偏好，也不从调用参数中推定权限。

未登录时隐藏飞翔服务开关、服务区间状态和飞翔跳过提示；原有章节识别与固定时长功能继续使用各自设置。飞翔服务开关独立于旧章节/本地跳过开关，关闭它会停止取用服务区间。当前文件有发布集合时，设置显示实际范围与策略；Windows 显示毫秒，ED 目标为核验结束点，保留其后内容。只有 OP 的服务集合不会让设置误报 ED 会走章节回退。

Windows 通过不含 token 的账号变更通知立即重建设置和提示。Android 在打开设置、恢复前台及约 5 秒周期刷新真实账号，反向桥再次核验当前会话、来源作用域和保存的偏好；全局 MPV 设置回包不再覆写账号状态，防止迟到响应恢复已隐藏的控件。令牌更新本身不重置当前跳转。退出账号、换账号或关闭服务会作废缓存区间及待执行动作，但保留本集已经触发的 ED 尾段保护。

没有 SQL 迁移，没有修改服务发布内容或模型配置，没有更改 A 遮罩/BIF 渲染。此设置使用设备上的既有播放器偏好管理与备份分类。本次新增模型收费调用为 0，播放开销及功耗未做净增量测量。

传统 NAS 登录会保留已保存的飞翔会话，所以显隐还检查当前播放的活动绑定是否属于该账号与当前统计作用域。切入传统模式后，即使保存的 session 仍存在，服务项也会隐藏，反向桥拒绝写入服务开关；没有通过清除用户账号来实现显隐。

## 定向验证

- Flutter 相关联合测试 19 项通过，包含会话刷新、原生重入、设置与初始 6 项窗口组件检查；窗口组件文件追加仅 OP 集合后单独 7 项通过。另有原生桥真实会话/来源/偏好检查 1 项通过。集合存在重叠，不累加为覆盖率。
- 修改 Dart 目标分析无问题。Kotlin 6 项纯逻辑测试通过；Android 生产源码诊断编译通过。审查后移除了一处缺少序号保护的账号状态套用，最终完整 APK 构建负责覆盖这处编译。
- Windows Release 构建完成，日志 `E:\fly_play_recovere\.tmp\oped-settings-windows-build.log`。真实窗口与最终 APK 结果另在下方记录，构建不作为实播证据。

测试日志：`E:\fly_play_recovere\.tmp\oped-settings-targeted-tests.log`、`oped-native-settings-test.log`、`oped-settings-analysis.log`、`oped-settings-android-diagnostic.log`，以及 `.tmp\llm-b-fly-kotlin\settings-account-20260913\junit.log`。

最终绑定检查的回归为 4 项通过（原生桥 1 项及原文件来源/尾段保护 3 项），日志 `E:\fly_play_recovere\.tmp\oped-settings-binding-tests-final.log`；对应 Dart 分析无问题，日志 `oped-settings-binding-analysis.log`。一次误用旧 Flutter SDK 的测试在原生依赖 hook 处以 `Invalid SDK hash` 失败，切回当前一致的 Flutter 3.41.9 后完成上述验证；未改依赖版本来掩盖失败。

## Windows 启动复核记录

首次新设置构建的真实启动没有通过：19:06 在既有 E 验收 profile 连续两张窗口截图为白屏，随后新 E 空 profile 同样白屏。证据 `settings-01-startup.png`、`settings-02-library-ready.png`、`settings-03-fresh-profile-startup.png` 保留在 `.runtime/oped-real-validation`，文件名不表示页面检查成功。这些不算设置或播放验收。新 profile 的 stdout 只有媒体插件注册信息，stderr 为空。正在定位启动链，最终结果另行补充；没有清除或覆盖原账号数据库。

## Android 包

完整 `fullProfile` APK 构建通过，127.7 秒，产物 `build/app/outputs/flutter-apk/app-full-profile.apk`，179,710,368 字节，SHA256 `27318cbde9141acafded64b63b680184a7cafbcf44d625341e9208ad8b879f7b`。交付副本为 `E:\fly_play_recovere\deliverables\Fly_Player_B_OPED_20260913_arm64_profile.apk`。包名 `com.geqian.flyplayer.fly_player.profile`，Android API 24 起，使用 E 盘独立测试签名，可与原正式包共存；没有复制用户原签名。v2 签名校验通过。完整播放器、Flutter/AOT、MPV、SQLite、MNN 和 full 模型均在包内；这些核心组件仅支持 arm64。AndroidX 附带少量其他 ABI 的计数库，本包不因此成为通用 ABI 包。

构建命令为 `flutter build apk --flavor full --profile --target-platform android-arm64 --no-pub`，E 盘复现入口 `.runtime/android-build/build-profile.ps1`，最终日志 `flutter-full-profile-20260913-190611.log`。`apk-verification.json` 记录签名、包名、库清单及散列；`final-source-baseline.json` 核对 644 个源码文件在最终构建期间没有变化。

构建复用已有 E 盘 Flutter 3.41.9、JDK 21、Gradle 与 SDK/许可，并在 E SDK 安装 CMake 3.22.1。首次 sqlite3 hook 下载超时后复用 E 上同版本缓存，其 SHA256 与包自带资产清单完全一致；没有改依赖版本。尝试单 ABI split 与项目已有 `ndk.abiFilters` 冲突失败，随后使用项目原本支持的非 split 配置打出上述最终包，没有修改构建配置来规避检查。

ADB 仍没有连接设备，安装、实际播放、OP/ED 点击及尾段验证均为 **NOT_RUN**，APK 不能代替 Android 实播。没有安装、卸载或替换任何设备上的原应用。

## 使用与回滚

本机服务为 `http://127.0.0.1:18789`。在 B 播放器登录飞翔账号并使用已绑定的 Emby 来源，打开《紫罗兰永恒花园》S01E07 原画质播放，再进入原“跳过 OP/ED”设置。正式区间仍为 OP 01:19.876–02:44.876、ED 22:10–23:40，均由用户确认后以“仅提示”发布；本次客户端设置不会自动更改发布策略。

客户端停用只需关闭“飞翔已核验区间”；退出飞翔账号也会隐藏并停用服务能力。服务侧可以关闭 `oped_publish_enabled` 或撤回指定发布。保留历史、账号与新偏好，不覆盖用户原播放器目录。NAS 生产实例尚未启用本机的共享身份证明，此设置不能让 NAS 自动获得已核验区间。
