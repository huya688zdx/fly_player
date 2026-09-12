# 飞翔统一账号与媒体绑定：客户端 P2

最终工作目录：`E:/fly_play_recovere/fly_player`。协议见相邻服务仓库的 `docs/P2_BINDING_CONTRACT.md`、`docs/DATA_FLOW.md`、`docs/P2_SCHEMA.md`。

## 实际用户入口

AppEntry 首次进入飞翔账号登录页。登录成功后读取 NAS 的媒体绑定清单；选择绑定后进入 NAS 媒体目录。Windows 与 Android 共用这些 Flutter 页面和现有平台播放宿主，没有新增播放器或海报渲染器。

- `lib/main.dart`：账号恢复、登录/绑定入口门控、主导航注册。
- `lib/screens/fly_account_screen.dart`：飞翔登录、服务地址切换、媒体服务器登记、创建绑定、重新授权、选择媒体地址、解绑、触发 NAS 目录任务，以及原本地连接的过渡入口。
- `lib/screens/fly_catalog_screen.dart`：NAS 目录搜索/分页、番剧→季→集详情、元数据、来源及文件版本、鉴权图片。播放按钮进入现有媒体后端详情和起播流程；也可直接浏览已选择的媒体服务。
- 设置 → 数据与下载 → 飞翔账号：回到账号与媒体绑定管理。旧历史关联与统计同步详情保留 P1 的明确归属确认流程。

网页新增的绑定经刷新即可在 App 选择；App 新增/重新授权/解绑使用相同服务 API。绑定的普通列表、缓存和配置不含媒体 token。选用绑定时仅通过 Fly 原生设备会话调用 `POST /bindings/{id}/device-access`，安全存储按 `accountKey + binding_id` 分开保存，可保存多个同类型连接。

飞牛仍需要 NasProvider 供原播放链路使用；兼容 token 副本带归属标记，切换到其他后端、绑定失效、注销或离开统一绑定模式时清除，不能通过过渡入口复用已解绑的副本。旧的独立本地连接记录保留，可能需要重新登录本地媒体账号。

## 两类地址与凭据边界

飞翔服务地址和媒体地址独立。Fly 会话身份是 `service_instance_id | user_id`，地址不是账号键。服务可保存 HTTPS、LAN、VPN 根地址；切换前先无认证访问 `/system/identity`，实例吻合后才用 token 验证 `/me` 的账号。旧 P1 的 URL 账号键只在原入口身份验证后迁移，原数据集、序号和 pending JSON 字节保持不变；先退出旧 P1 再重新登录同一账号也覆盖在回归中。

媒体服务器配置包含 `nas_api` 与 `client_lan/client_remote/vpn` 地址；NAS 扫描使用前者，App 只允许选用已登记的客户端地址。第一次激活或更换媒体地址前，Emby/Jellyfin 用 `/System/Info/Public`、飞牛用不含用户 secret 的公开 Authx `/v/api/v1/server/info` 核对 `remote_server_id`，失败不应用连接，也不把媒体 token 发给该地址。

新增 Fly API 和媒体身份探测使用独立严格 TLS HttpClient，不继承旧媒体请求的宽松证书 override，不跟随重定向。自签证书真实测试验证了密码、Fly bearer 和身份探测均在 TLS 层被拒绝。媒体播放继续使用现有网络实现。实际媒体 token 权限来自原媒体账号；不宣称 Fly 可以独立撤销已经下发到某台设备的远端 token。

Fly 会话/安装身份与媒体 token 使用现有 Windows DPAPI / Android Keystore 安全存储。普通配置只保存地址、账号/绑定 ID、显示名、版本及当前选择。离线恢复仅应用本账号选中的、缓存状态/版本匹配且有可用凭据的绑定；缺失凭据时清除全局活跃连接并显示绑定入口，不能落到其他账号的旧连接。

## 本地事实与自动补传

统计物理范围由完整 `accountKey + binding_id` 的 SHA256 派生，不随 LAN/HTTPS/VPN 地址变化。绑定切换先完成旧本地会话及已有元数据写入，再切换范围。统一绑定下新写入来源自动继承已验证账号归属；旧导入历史仍需 P1 明确关联，不按标题猜测，也不因升级自动认领。

新事实在同一 SQLite 事务内保存记录/版本/来源以及 `source_ref`：`binding_id`、`backend_kind`、`remote_item_id`，存在真实远端标识时再附 `remote_series_id` 和 `remote_season_id`。派生标题身份不会假装成远端 series ID。Emby 的统计元数据不会发送到飞牛回填接口。

起播源携带 `statsScope`，Android 进度和桌面本地统计事件透传该捕获值。迟到的同 ID 进度、起播、旧播放器退出不能作用于另一个绑定；统一绑定的无范围孤儿进度被拒绝。原生选集/重解析/转码重载也验证并保留起播范围。媒体服务自身的播放进度协议与心跳频率没有改动。

启动恢复、回前台及本地播放结束会调度低频补传；成功尝试间隔至少 30 秒，失败按 60/120/240/480/960 秒退避，播放结束不会取消或提前穿过已有退避。网络失败只影响上传，本地播放与事实落盘不等待云端。

后台补传先处理当前范围，再枚举当前 Fly 账号曾实际选用且仍在服务本人绑定清单中的范围。旧范围使用独立数据库句柄，不切换活跃播放范围，也不新建写入 epoch。仅已有且明确归属该账号的数据可导出。本人已解绑来源仍能补传离线事实，不重新取得媒体 token。空范围不会阻塞其他范围；某范围失败会保留其错误与原待重试包，继续其他范围。退出/切账号请求会终止后续范围上传，已在途的回执只写回其原范围。

P1 的完整逻辑快照、同事务记录版本、水位、导入认领、墓碑、删除屏障与不可变 pending 协议保留：排空本地写入后生成快照，读事务结束后才发送 HTTP；只有 `applied` 回执推进序号。失败重发相同 JSON 字节。历史数/数据源数/包体仍受已实现的 P1 上限约束，超限报错而不截断。

## 精选迁移与依赖

主目录以 `main e2c478f` 为起点。原 P1 参考工作树 `fly_player_p1` 基于 `b2eb238`，两者有 210 个基线文件差异，因此没有整体合并或覆盖。P1 自身补丁与新增文件白名单已备份至 E 盘 ignored runtime：`E:/fly_play_recovere/.tmp/p2-client-p1-backup`，再选择性应用数据同步、统计迁移/排空/范围守卫及其测试。原 P1 工作树保留不变。

main 已有完整 Emby/Jellyfin 媒体 backend、鉴权、目录、播放桥和宿主，必要核心文件与 P1 基线一致，无需带入海报或外部播放分支。P1 的外部播放器代理测试没有搬入 main；main 不含那个功能。`P1_CLIENT.md` 中原 P1 工作树测试数字只属于历史记录，不是本次主目录验证结果。

Flutter 3.41.9 / Dart 3.11.5，全缓存/TEMP/GRADLE/PUB 路径位于 E 盘。保留原 `pubspec.lock` 每个依赖的版本、校验值和规范源地址；无新增 Dart 依赖。镜像拉取时仅临时改写源 URL，随后恢复原锁文件。

## 验证

```powershell
. E:/fly_play_recovere/fly-data-service/scripts/enter-env.ps1
$env:FLY_TEST_PYTHON = 'E:/fly_play_recovere/fly-data-service/.venv/Scripts/python.exe'
$env:FLY_TEST_BACKEND = 'E:/fly_play_recovere/fly-data-service'
flutter --no-version-check test --no-pub --reporter expanded
flutter --no-version-check analyze --no-pub
& $env:FLY_TEST_PYTHON test/services/check_sync_schema.py
git diff --check
```

2026-09-12 主目录最终结果：

- 完整 Flutter 测试 **1218 项通过**，退出码 0；`.dart_tool/p2-full-final.log`。其中真实 P2 后端集成已启用并通过，没有沿用 P1 工作树数字。
- 完整静态分析 **No issues found**，退出码 0；`.dart_tool/p2-analyze-final.log`。
- 直接执行生产迁移 SQL 的 Python 回归 **2 项通过**，退出码 0。
- `git diff --check` 通过；`pubspec.lock` 无差异。

已逐项观察必要行为红灯后验证修复；独立审计重跑了统计/账号隔离 8 项及多范围补传/取消/退避 4 项。原启动冒烟和三项凭据失败重试测试增加“原本地配置过渡”步骤后保留各自原语义；没有为了通过测试改动媒体重试实现。

真实 API 集成用当前 `backend/` 源码启动隔离的本机服务，使用合成账号、历史、Emby 服务和临时数据库。覆盖绑定创建、native device-access、身份探测、NAS 完整扫描、详情/版本、绑定 source_ref 上传，以及 P1 导入关联、修订、重复阻止、墓碑和本地删除语义。不会读取实际 NAS 凭据、ZIP 或历史样本。TLS 测试证书和私钥仅为自签测试 fixture。

上述基线验证时未执行 Android APK、Windows 安装包或实机播放/安全存储迁移验证。完整应用备份复制凭据到另一安装的恢复行为没有实机证据，不能将其声称为已验证。新安装写入身份与旧记录来源分离；BIF、精确 OP/ED 和其他未约定功能没有包含在本次修改中。

2026-09-12 后续 Windows 实机验证：使用全部位于 E 盘的便携编译工具和插件目录 junction，已构建并启动主项目 Release，无需修改开发者模式。飞翔登录、保存登录后的重启、飞牛/Emby绑定选用、NAS同步目录及原媒体详情已实测，并修复侧栏切换缓存和同地址刷新导致进行中图片请求失效的问题。新增回归结果、启动方式和边界见 [WINDOWS_RUNTIME_VERIFICATION.md](WINDOWS_RUNTIME_VERIFICATION.md)。本轮未验证实际影片播放、Android APK或Windows安装包。
