# Windows 实机连接验证（2026-09-12）

构建项目：`E:\fly_play_recovere\fly_player`，当前工作区含 P2 飞翔账号与媒体绑定改动。未提交或推送代码。

## 启动

双击 `E:\fly_play_recovere\启动飞翔播放器.cmd`。

程序及资源必须一起保留：`E:\fly_play_recovere\fly_player\build\windows\x64-portable\bundle`。

本机重建脚本：`E:\fly_play_recovere\.tools\portable-build\build-player-release.ps1`。运行重建前应关闭播放器。使用便携 MSVC + Windows SDK + Ninja，不依赖 Visual Studio 安装注册；常规 `flutter run -d windows` 的 VS 探测没有修改。

## 新增工具和缓存

- Flutter 3.41.9：`E:\fly_play_recovere\.tools\flutter-3.41.9`
- MSVC 14.44.35207：`.tools\portable-build\msvc`
- Windows SDK 官方 NuGet 10.0.26100.9169（SDK内部版本10.0.26100.0）：`.tools\portable-build\sdk-common`、`sdk-x64`
- CMake/Ninja：`.tools\portable-build\cmake`，由已有 Android SDK 中的工具复制至 E 盘
- NuGet、libmpv、ANGLE、WebView2 SDK/WIL：E盘工具/项目build目录
- Pub、NuGet、Python、Node等缓存：`E:\fly_play_recovere\.cache`
- TEMP/TMP：`E:\fly_play_recovere\.tmp`
- 通过启动脚本设置 WebView2 用户缓存：`E:\fly_play_recovere\.cache\fly-player-webview`

没有运行 Visual Studio/MSI 安装器，没有安装新的 C 盘依赖或开启 Windows 开发者模式。系统已有 WebView2 Runtime 被复用。播放器自己的安全凭据、设置仍采用原项目的 Windows 用户目录/DPAPI 机制；它们不是SDK或依赖安装。

MSVC VSIX按微软manifest SHA256核验；Windows SDK两包按官方NuGet catalog SHA512核验，rc/mt/ucrtbased为有效微软签名；NuGet与媒体原生包按插件固定hash核验。插件目录使用E盘junction。WebView2的MSBuild targets在外层CMake中等价替换为headers和官方静态loader，原插件源码未改。

## 已完成的实机操作

- Release播放器真实窗口启动，登录 NAS 飞翔数据服务 `http://192.168.6.120:8787`。
- App中显示与NAS后台一致的飞牛/Emby绑定，媒体用户名均为`geqian688`。
- 选用飞牛`http://192.168.6.120:5666`，打开NAS同步目录与《3月的狮子》同步详情，再打开原始媒体详情；原始详情的背景、简介、两季列表正常。
- 切换Emby`http://192.168.6.120:8096`，打开NAS同步目录与原始媒体详情；同步海报、简介及来源信息正常。
- 独立API冒烟确认：飞牛5库、Emby3库，用户ID与当前绑定一致。
- 未导入WIN01旧统计，未主动播放影片或修改媒体内容。

## 最终版复查

2026-09-12 03:17 完成 Release 重建，构建进程退出码 0；通过根目录的 `启动飞翔播放器.cmd` 启动，进程正常响应。

- 保存的飞翔登录和飞牛选用状态在重启后恢复；NAS同步目录中的飞牛海报实际显示。
- 切换到 Emby 后，侧栏从飞牛5库更新为 Emby 的动漫TV、影片、合集3库，分类与收藏计数同步更新。
- Emby同步目录的海报实际显示；从新侧栏打开动漫TV，成功显示44个条目及海报。
- 修复 `DesktopShell` 仅首次加载侧栏的问题。会话/绑定变化触发清空并重载，旧请求返回不会覆盖新连接结果。
- 修复同地址、同实例、同账号验证刷新无谓替换会话对象的问题，避免正在加载的详情/图片被误判为跨会话响应；真实地址或身份变化的隔离检查保留。
- 桌面测试136项通过；会话刷新及账号/补传相关测试19项通过；完整静态分析无问题，`git diff --check` 通过。独立代码审阅无阻塞问题。

这组136/19项是本轮修复回归；此前P2完整测试1218项的结果属于修复前基线，本轮没有将其计作重新全量运行。最终播放器保持打开，可继续人工操作。

最终引擎DLL SHA256：`92E7AA320AFE026E90780E4049DC6F6A480696400A269C179B1CCA0EF751D175`，与Flutter Release引擎一致。

最终构建日志：`E:\fly_play_recovere\.tools\portable-build\native-release-final.log`。
本轮脱敏API冒烟记录：`E:\fly_play_recovere\fly-data-service\runtime\win01-verification\nas-connection-smoke-20260912-024623\nas-connection-smoke.json`。

## 构建问题记录

Windows CMake编译参数`/wd"4100"`在Ninja中保留字面引号，改为`/wd4100`后编译通过。Debug/Release共享安装目录时，CMake可能按时间戳保留旧模式的Flutter引擎DLL；构建脚本在安装后强制复制当前模式的引擎DLL。

自动化工具注入的键盘事件曾在Flutter Debug中触发物理键状态断言。Release测试通过鼠标与英文逐键输入完成登录；没有修改应用快捷键逻辑。

本轮范围为局域网实机连接。HTTPS域名与VPN入口支持仍需使用真实外网地址进行端到端验证。

## 后续黑屏排查与显卡恢复复测（2026-09-12）

以下是上文连接验证之后新增的实际播放测试，会推进飞牛续播位置并产生正常观看统计。

此前实际截图复现了《3月的狮子》S02E02只有字幕和进度、视频区域纯黑。Windows 当时报告 AMD Radeon RX 6750 GRE 12GB 状态 Error、设备错误码 43。切换硬件解码时日志两次出现 `Failed to allocate AVHWDeviceContext`。软件解码曾让《中二病也要谈恋爱！》S01E01正常显示，但全新进程下《3月的狮子》仍然黑屏，所以当时没有将软件解码判定为完整解决方案。

用户恢复显卡后，本轮在 12:32 之后重新验证：

- CIM 查询显示 AMD 显卡 Status 为 OK、ConfigManagerErrorCode 为 0；虚拟显示适配器也为 OK。
- 启动新的 Release 播放器进程，从飞牛首页继续播放同一部《3月的狮子》S02E02，软件解码下已经出现完整彩色画面。
- 在播放页“设置 → 高级设置”将解码方式从软件切回硬件，确认硬件选项选中；比例保持“适应”，清晰度保持“原画”。
- 恢复播放后，进度从 09:58 推进至 10:21，多次截图可见不同的完整视频帧，没有再次黑屏。最后暂停于 10:21，保留窗口供用户继续观看。
- 本轮日志中硬件设备分配错误为 0、`desktop-playback` 播放器错误为 0；stderr 仍有 `Cannot load nvcuda.dll`，而画面正常，不能将该提示单独当作故障原因。

本次没有修改播放源码、驱动或安装依赖。结果支持本次黑屏与显卡故障有关；这里只验证了上述影片的短时播放，不代表全部编码格式或长时间播放均已验证。界面的“硬件解码”表示已选择硬件优先策略，未单独采集 mpv 实际所用解码器属性。日志中的 `H/W rendering` 指硬件纹理输出，不能用它代替硬件解码生效的证据。

截图：`design/data_service/evidence/gpu-restored-playback-20260912.png`。

本轮日志：`E:\fly_play_recovere\fly-data-service\.private\gpu-restored-20260912.stdout.log`、同名前缀的 `stderr.log`。此前对照日志为 `.private\black-screen-20260912.stdout.log` 和 `.private\black-screen-soft-final-20260912.stdout.log`；原始日志仅保存在本机，未作为可公开附件复制。
