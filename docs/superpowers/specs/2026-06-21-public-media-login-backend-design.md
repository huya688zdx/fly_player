# 登录页后端选择与 Emby 入口设计

日期：2026-06-21

前置文档：
- `docs/superpowers/public-media-frontend-status.md`
- `docs/superpowers/specs/2026-06-20-public-media-frontend-design.md`
- `docs/superpowers/specs/2026-06-21-public-media-detail-design.md`
- `docs/superpowers/specs/2026-06-21-public-media-playback-design.md`
- `docs/superpowers/specs/2026-06-21-public-media-playback-reverse-reload-design.md`
- `docs/superpowers/research/2026-06-21-emby-api-shape.md`

## 目标

把当前“飞牛 NAS 登录页”设计成“媒体后端选择 + 后端登录/连接配置”入口，让 Feiniu 与 Emby 都能作为媒体后端配置目标，同时保持现有飞牛登录、首页、详情和播放体验默认不变。

本阶段只设计入口和配置层，不接入 Emby 媒体列表、详情、播放、字幕、播放器反向通道、播放进度 check-in 或下载能力。后续若加入 Emby，只允许先做认证/服务器信息的只读连接验证，严禁提交真实 server、token、userId、password 等敏感信息。

## 登录页面兼容优先级

本轮改造的主目标是**登录页面兼容**，不是 Emby 功能接入。任何实现必须先锁住当前飞牛登录页行为，再加入后端选择能力。

必须保持的飞牛登录页行为：

- 默认进入登录页时仍选中飞牛，旧用户不需要知道“后端选择”存在。
- `NasProvider` 预填的服务器地址、用户名、已记住密码和 HTTPS 开关语义不变。
- 普通直连登录仍调用 `FeiniuApi.loginWithBaseUrl()`。
- FN Connect 输入、直连探测、网页兜底和“重新登录 FN Connect”入口不变。
- 登录成功后仍写旧飞牛 prefs key，保证现有主导航、分屏副引擎、播放统计 owner、`FeiniuApi` 鉴权和下载/播放链路不回归。
- 记住密码、登录历史、打开已下载内容、错误提示、提交防抖行为不回归。
- Emby 表单或入口不得影响飞牛表单校验、历史回填、登出和重登。

因此实施顺序必须是：先补登录页兼容性 characterization tests，再拆 Feiniu handler，然后才添加 selector 和 Emby 入口。Emby 只读连接验证排在飞牛兼容性验证之后。

## 当前事实审计

### 启动与登录门禁

- `lib/main.dart:358` 的 `FlyPlayerApp.build()` 用 `MultiProvider` 注入顶层 provider。
- `lib/main.dart:360` 创建 `NasProvider`。
- `lib/main.dart:361` 创建 `ChangeNotifierProxyProvider<NasProvider, MediaBackendProvider>`，当前 `MediaBackendProvider` 只从 `NasProvider` 派生。
- `lib/main.dart:598` 的 `_ProviderGate` 读取 `NasProvider`。
- `lib/main.dart:614` 判断 `requireConfigured && !provider.isConfigured`。
- `lib/main.dart:615` 未配置时返回 `ConnectionScreen`。
- `lib/main.dart:621` 的 `AppEntry` 把主导航包在 `_ProviderGate` 内，因此首次启动、登出、token 清空后都会回到登录页。

结论：当前“是否进入业务页面”的唯一门禁是 `NasProvider.isConfigured`，而 `isConfigured` 只懂飞牛字段。

### 飞牛账号配置保存与初始化

- `lib/providers/nas_provider.dart:13` 定义 `NasProvider`。
- `lib/providers/nas_provider.dart:28` 的 `baseUrl` 优先返回 `_resolvedBaseUrl`，为空时返回 `_baseUrl`。
- `lib/providers/nas_provider.dart:38` 的 `isConfigured` 要求 `_baseUrl.isNotEmpty && _token.isNotEmpty`。
- `lib/providers/nas_provider.dart:40` 构造函数注册生命周期监听、恢复 `_bootstrapSnapshot`，然后调用 `_loadSettings()`。
- `lib/providers/nas_provider.dart:81` 的 `_loadSettings()` 从 `SharedPreferences` 读取：
  - `base_url`
  - `resolved_base_url`
  - `user_name`
  - `password`
  - `token`
  - `remember_password`
- `lib/providers/nas_provider.dart:127` 的 `updateSettings()` 写回同一组键。
- `lib/providers/nas_provider.dart:155` 的 `updateToken()` 只更新 `token`。
- `lib/providers/nas_provider.dart:163` 的 `_applyLoggedOutState()` 清空 `token` 和 `resolved_base_url`，保留服务器地址、用户名和已记住密码。
- `lib/providers/nas_provider.dart:177` 的 `logout()` 在清本地状态后调用 `SessionExitBridge.logoutAndResetParallelUi()`。
- `lib/providers/nas_provider.dart:203` 的 `_currentPlayStatsOwnerKey()` 以 `baseUrl|userName` 绑定播放统计 owner。

结论：飞牛会话状态、登录表单预填、播放统计 owner、分屏 isolate 同步都耦合在 `NasProvider`。直接把 Emby 字段塞进这些旧 key 会污染现有语义。

### 登录页链路

- `lib/screens/connection_screen.dart:32` 定义 `ConnectionScreen`。
- `lib/screens/connection_screen.dart:55` 的 `initState()` 从 `NasProvider` 预填服务器、用户名、密码、记住密码和 HTTPS 开关。
- `lib/screens/connection_screen.dart:109` 的 `_submitWithUnifiedErrors()` 只执行飞牛登录：
  - 标准化服务器输入；
  - 校验 server/user/password；
  - 调 `FeiniuApi.loginWithBaseUrl()`；
  - FN Connect 失败时尝试网页兜底；
  - 成功后进入 `_applyLoginResult()`。
- `lib/screens/connection_screen.dart:202` 的 `_applyLoginResult()` 写 `NasProvider.updateSettings()`，并写 `LoginHistoryStore.save()`。
- `lib/screens/connection_screen.dart:21` 的 `effectivePersistedBaseUrlForLogin()` 保证 FN Connect 登录成功后保存可用地址。
- `lib/screens/connection_screen.dart:237` 的 `_showLoginHistorySheet()` 展示登录历史。
- `lib/screens/connection_screen.dart:281` 的 `_resetFnConnectWebLoginState()` 清 FN Connect 网页态并登出。
- `lib/screens/connection_screen.dart:482` 的 `build()` 是当前登录 UI，字段均为飞牛/飞牛 NAS 语义。

结论：登录页 UI、校验、提交和历史记录均是单后端实现。可以在登录页显式选择后端类型，但提交逻辑必须拆成 backend-specific handler，不能让业务页面到处判断 `isEmby`。

### 登录历史与存储清理

- `lib/services/login_history_store.dart:49` 使用 `login_history_v1`。
- `lib/services/login_history_store.dart:6` 的 `LoginHistoryEntry` 只包含 `baseUrl`、`userName`、`password`、`rememberPassword`、`updatedAtMillis`，没有后端类型。
- `lib/services/storage_management_service.dart:300` 也把 `login_history_v1` 作为可清理项。
- `lib/services/storage_management_service.dart:311` 的 `_nasConfigKeys` 包含 `base_url`、`resolved_base_url`、`user_name`、`password`、`token`、`remember_password`。

结论：如果登录历史支持 Emby，必须升级为带 `backendKind` 的新版本，或保留旧历史只作为 Feiniu 历史读入，避免 Emby 历史误回填到飞牛表单。

### API 注入与公共后端

- `lib/api/feiniu_api.dart:421` 的 `FeiniuApi(this.nasProvider)` 在构造时把 `nasProvider.baseUrl` 写入 Dio baseUrl。
- `lib/api/feiniu_api.dart:435` 每次请求动态读取 `nasProvider.token`，写入 `Authorization` 和 `Trim-MC-token`。
- `lib/api/feiniu_api.dart:468` 遇到会话失效会调用 `nasProvider.logout()`。
- `lib/api/feiniu_api.dart:529` 的 `loginWithBaseUrl()` 是飞牛用户名密码登录入口，并处理 FN Connect 输入。
- `lib/api/feiniu_api.dart:1239` 的 `getServerInfo()` 可作为飞牛已登录后的服务器信息读取。
- `lib/providers/media_backend_provider.dart:18` 定义 `MediaBackendProvider`。
- `lib/providers/media_backend_provider.dart:26` 的 `backend` 按 `nasProvider.baseUrl` 缓存。
- `lib/providers/media_backend_provider.dart:32` 固定创建 `FeiniuMediaBackend(FeiniuApi(nasProvider))`。
- `lib/media_backend/media_backend_kind.dart` 已有 `MediaBackendKind { feiniu, emby }`，但 `emby` 只是占位。
- `lib/media_backend/media_backend.dart` 已定义后端中立接口，页面迁移目标是依赖 `MediaBackend` 而不是 `FeiniuApi`。

结论：`MediaBackendProvider` 已经是避免 UI 分支的正确汇聚点，但它现在没有“当前后端配置/会话”输入，只能固定飞牛。

### 设置页相关入口

- `lib/screens/app_settings_screen.dart:128` 的 `_resetFnConnectWebLoginState()` 清飞牛网页态并调用 `NasProvider.logout()`。
- `lib/screens/app_settings_screen.dart:298` 在设置搜索中注册 `fn_connect_relogin`。
- `lib/screens/app_settings_screen.dart:757` 在设置页展示“重新登录 FN Connect”入口。

结论：当前设置页没有“切换媒体后端/管理后端连接”入口。后续应新增中立“媒体服务器连接”入口，FN Connect 重登保留为飞牛专属操作。

## 设计原则

1. 现有飞牛默认路径不变：未迁移前，旧 `base_url` / `token` 配置仍可直接进入 App。
2. UI 允许在登录页显式选择“飞牛 / Emby”，但登录后的业务页面只依赖 provider、capabilities 和 `MediaBackend`，不散落 `if (isEmby)`。
3. 新增公共配置模型使用中立命名：`backendKind`、`serverUrl`、`displayName`、`accessToken`、`userId`、`userName`、`rememberSecret` 等。
4. Feiniu 私有字段留在飞牛登录 handler / `NasProvider` 兼容层 / `FeiniuApi` 内部；Emby 私有字段留在 Emby 配置 store / verifier / 未来 `EmbyApi` 内部。
5. Emby 第一阶段只做只读连接验证，不进入媒体浏览和播放。
6. 不提交真实连接信息；测试使用 mock prefs、fake client 或脱敏 fixture。

## 方案取舍

### 方案 A：新增中立 BackendSession 层，保留 NasProvider 作为 Feiniu 兼容壳（推荐）

新增 `MediaBackendConnection` / `MediaBackendSession` / `MediaBackendConnectionStore`，保存当前选择的后端类型和会话信息。`NasProvider` 暂时继续服务飞牛旧路径，并作为 Feiniu session 的兼容 facade。`MediaBackendProvider` 改为读取中立 session，再通过 factory 创建具体后端。

优点：
- 最大限度保持飞牛行为不变；
- 可以小步迁移：先模型和 store，再登录页，再 provider factory；
- 后续 Emby 不需要污染 `NasProvider` 的飞牛命名；
- 业务页面继续只读 `MediaBackendProvider.backend`。

代价：
- 短期会有 `NasProvider` 与中立 session 的双层状态，需要明确同步边界；
- 存储需要兼容旧 key，测试要覆盖旧配置启动。

### 方案 B：直接把 NasProvider 改名/扩展成多后端 Provider（不推荐）

把 `NasProvider` 扩展成 `MediaBackendSessionProvider`，所有字段改为中立命名，并同时兼容飞牛。

问题：
- 改动面大，容易影响分屏、播放统计 owner、登出桥、FeiniuApi token 读取；
- 很容易把 Emby 字段塞入旧 key；
- 对现有飞牛登录回归风险高。

### 方案 C：登录页直接写 `if (isEmby)`，业务页慢慢接（否决）

登录后根据后端类型在首页、详情、播放入口里分别分支。

问题：
- 与公共媒体前端抽象方向冲突；
- Emby 会把列表、详情、播放和字幕差异扩散到 UI；
- 后续很难验证 Feiniu 不回归。

## 推荐架构

```text
登录页 / 设置页
  -> MediaBackendConnectionController
     -> FeiniuLoginAdapter -> NasProvider.updateSettings -> FeiniuApi.loginWithBaseUrl
     -> EmbyConnectionVerifier -> Emby connection store（只读验证阶段）

启动门禁
  -> BackendSessionProvider.isReady
  -> BackendSessionProvider.isConfiguredForCurrentKind
  -> 未配置：ConnectionScreen
  -> Feiniu 已配置：MainNavigation（现状）
  -> Emby 仅验证阶段：ConnectedBackendPlaceholder / 后续 Emby 首页

业务页面
  -> MediaBackendProvider.backend
     -> FeiniuMediaBackend(FeiniuApi(NasProvider))
     -> 未来 EmbyMediaBackend(EmbyApi(EmbySession))
```

### 配置模型

建议新增 `lib/media_backend/session/media_backend_connection.dart`：

```dart
class MediaBackendConnection {
  const MediaBackendConnection({
    required this.kind,
    required this.serverUrl,
    this.displayName = '',
    this.userName = '',
    this.userId = '',
    this.accessToken = '',
    this.rememberSecret = true,
    this.updatedAtMillis = 0,
  });

  final MediaBackendKind kind;
  final String serverUrl;
  final String displayName;
  final String userName;
  final String userId;
  final String accessToken;
  final bool rememberSecret;
  final int updatedAtMillis;

  bool get isAuthenticated => serverUrl.trim().isNotEmpty && accessToken.trim().isNotEmpty;
}
```

注意：
- 公共模型不命名 `baseUrl`、`token`、`nas`、`embyToken`。
- `userId` 对飞牛可为空，对 Emby 后续保存真实用户 id。
- 密码不进入 session；只在登录表单和历史记录中按 `rememberSecret` 受控保存。

### 存储策略

短期采用兼容读写：

- 旧飞牛 key 保持不变：`base_url`、`resolved_base_url`、`user_name`、`password`、`token`、`remember_password`。
- 新增当前后端选择 key：`media_backend_active_kind_v1`，默认 `feiniu`。
- 新增中立连接列表 key：`media_backend_connections_v1`，用于后续 Emby 和多连接管理。
- 首次读取时，如果新 key 不存在但旧飞牛 key 已配置，则合成一个 `kind=feiniu` 的连接快照。
- 飞牛登录成功时继续写旧 key，另行镜像写中立连接快照。
- Emby 连接验证成功时只写新 key，不写旧飞牛 key。
- 登出当前飞牛时沿用 `NasProvider.logout()`；登出 Emby 时清对应中立 session，不触碰飞牛旧 key。

这样旧用户升级后默认仍走飞牛；新增 Emby 不会破坏飞牛保存态。

### 登录页 UX

登录页顶部增加后端类型 segmented control：

- `飞牛 NAS`：默认选中，当前表单和行为保持现状，包括 FN Connect、HTTPS 开关、登录历史、记住密码、打开已下载内容、重新登录 FN Connect。
- `Emby`：展示 Emby server、用户名、密码字段，以及“验证连接”按钮；第一阶段验证成功后只显示“已连接，媒体浏览接入将在后续阶段开放”的状态，不进入播放器深层能力。

登录历史升级：

- 新增 `login_history_v2`，每条记录带 `backendKind`。
- 读取历史时可把 `login_history_v1` 当作 Feiniu 历史导入显示，但保存新记录只写 v2。
- 历史 sheet 只展示当前选中后端的记录，避免 Emby 地址误填飞牛表单。

### Provider 分层

建议新增一个中立 provider，而不是立刻删除 `NasProvider`：

- `BackendSessionProvider`：负责 active kind、连接快照、是否已配置、Emby 连接状态。
- `NasProvider`：保留飞牛兼容职责，继续供 `FeiniuApi` 使用。
- `MediaBackendProvider`：改为读取 `BackendSessionProvider.activeKind` 和会话。Feiniu 分支仍创建 `FeiniuMediaBackend(FeiniuApi(nasProvider))`；Emby 分支在未实现媒体能力前不返回可浏览 backend，或返回受限 placeholder backend 并由入口 gate 拦截。

重要边界：provider/factory 可以按后端类型分支，业务页面不可以。

### Emby 只读连接验证

后续可新增 `EmbyConnectionVerifier`，只做：

1. 标准化 serverUrl。
2. 调官方用户认证接口，获取 access token 与 user id。
3. 可选读取服务器信息或当前用户信息，用于显示 displayName。
4. 保存脱敏后的 session 到新 store。

不做：
- `/Users/{UserId}/Items`
- 详情
- PlaybackInfo
- HLS
- subtitle
- playback check-in
- 下载

测试必须用 fake HTTP client 或脱敏 fixture，不提交真实 token/server/userId/password。

## 实施阶段边界

### 阶段 1：配置模型与兼容 store

先补当前登录页兼容性测试，再新增中立模型、store 和单测。Feiniu 旧 key 能被识别为默认后端。无 UI 行为改动。

### 阶段 2：登录页拆 handler，但 Feiniu 体验不变

把 `ConnectionScreen` 的 Feiniu 提交逻辑包成 `FeiniuLoginAdapter` 或私有 handler，UI 暂时仍默认飞牛。单测覆盖 `effectivePersistedBaseUrlForLogin`、历史记录版本升级、记住密码、FN Connect 重登入口和 HTTPS 开关。

### 阶段 3：后端选择 UI

加入后端类型选择。Feiniu 选中时渲染当前表单；Emby 选中时先显示验证入口/占位说明。设置页新增“媒体服务器连接”入口，FN Connect 重登保留为飞牛专属入口。

### 阶段 4：Emby 只读验证

实现 Emby 认证 verifier 和 store 写入。验证成功不进入媒体页面深层；如果还没有 Emby backend，则显示受限已连接页或停留在连接页展示成功态。

### 阶段 5：后续另立设计

只有在用户确认后，才进入 Emby 首页/列表 mapper、详情 mapper、播放 mapper 或播放器能力阶段。每个阶段单独设计、单独计划、单独验证。

## 测试与验收

- `flutter test test/connection_login_persistence_test.dart`
- 新增 `test/media_backend/media_backend_connection_test.dart`
- 新增 `test/services/media_backend_connection_store_test.dart`
- 新增 `test/screens/connection_backend_selection_test.dart` 或等价 widget test，覆盖：
  - 默认选中 Feiniu；
  - 旧 prefs 配置可直接通过 gate；
  - Feiniu 登录仍写旧 key；
  - Emby 记录不写旧飞牛 key；
  - 登录历史按 backendKind 过滤。
- 改 provider 后跑 `flutter analyze lib/providers lib/screens/connection_screen.dart lib/media_backend test/media_backend test/services test/providers test/screens`。
- 涉及真实登录页 UI 时，用 `flutter run` 人工验证飞牛登录、FN Connect、登出、重新登录、已有下载入口均不回归。

## 明确不做

- 不接入 Emby 媒体列表、搜索、分类、详情、播放、字幕、下载。
- 不修改 `MpvPlayerPage`、`ItemPlaybackLauncher`、`TvSeasonPlaybackLauncher` 或 Android mpv 控制器。
- 不改 `FeiniuApi` 的请求鉴权语义，除非后续发现明确 bug 并单独说明。
- 不把 Emby 字段写入 `NasProvider` 的旧飞牛 key。
- 不在业务页面散落 `if (isEmby)`。
- 不提交任何真实 server/token/userId/password。
