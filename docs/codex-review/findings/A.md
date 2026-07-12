<!-- CHECKPOINT
已审文件数: 64 / 64
最后完成: lib/models/tv_episode_picker_mode.dart
下一个: 无
阶段: 已完成
更新时间: 2026-07-02 17:46
-->

# TASK A findings

### [A-001] 路由 JSON 参数未防护，非法深链会直接抛异常
- 级别: P1
- 分类: Bug
- 位置: lib/main.dart:445
- 问题: `_buildRoute()` 对 query 中的 JSON 直接 `jsonDecode` 和强转，没有 `try/catch` 或降级到 `_RouteErrorScreen`。外部/原生传入损坏的 `/detail/item`、`/detail/season`、`/screen/category` 参数时，`onGenerateRoute` 会抛 `FormatException`/`TypeError`，而不是展示缺参错误页。
  ```dart
  final decodedInitialItemDetail = rawInitialItemDetail.isEmpty
      ? null
      : (jsonDecode(rawInitialItemDetail) as Map).cast<String, dynamic>();
  ...
  final decodedCategory = rawCategory.isEmpty
      ? const <String, dynamic>{}
      : (jsonDecode(rawCategory) as Map).cast<String, dynamic>();
  ```
- 建议方向: 给路由 payload 解析增加统一的安全解析函数，解析失败时返回对应 `_RouteErrorScreen` 或忽略初始快照并依赖 guid 拉取详情；不要让异常逃出 `onGenerateRoute`。
- 状态: 已确认

### [A-002] 主入口 ProviderGate 写死飞牛/Emby 登录规则，新增后端必须改公共入口
- 级别: P1
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/main.dart:624
- 问题: `_ProviderGate` 在公共路由入口直接判断 `provider.isConfigured` 和 `session.currentKind == MediaBackendKind.emby`，把飞牛与 Emby 的认证差异泄漏到 `main.dart`。新增 Jellyfin 等后端时必须继续修改这个公共 gate，不符合后端差异收敛在 `lib/media_backend/` 或会话抽象内的要求。
  ```dart
  // 飞牛已配置，或当前后端会话为 Emby 且已认证，均可进入主导航；否则回登录页。
  final embyReady =
      session.currentKind == MediaBackendKind.emby && session.isConfigured;
  if (requireConfigured && !provider.isConfigured && !embyReady) {
    return const ConnectionScreen();
  }
  ```
- 建议方向: 将“当前后端是否已配置/可进入主界面”的判断收敛到 `BackendSessionProvider`/`MediaBackendProvider` 或后端 capability，`main.dart` 只依赖抽象布尔值。
- 状态: 已确认

### [A-003] 全局错误页和路由错误页仍保留英文硬编码 fallback
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/main.dart:339
- 问题: UI 可见错误文案在取不到 `AppLocalizations` 时回退到英文硬编码，违反“UI 展示文案一律走 AppLocalizations getter”的硬约束。该路径会在全局错误 fallback 或本地化上下文不可用时展示给用户。
  ```dart
  Text(
    _maybeAppLocalizations(context)?.globalLoadFailed ??
        'Load failed',
  ...
  l10n?.routeErrorMissingDetail ?? 'Missing detail parameters',
  ```
- 建议方向: 避免在 UI 层写英文 fallback；若确实需要本地化初始化失败兜底，应集中到本地化/错误展示基础设施中，并确保默认 locale 文案来自同一来源。
- 状态: 已确认

### [A-004] EmbyApi 默认使用裸 Dio，生产请求没有统一超时边界
- 级别: P2
- 分类: 可维护性 / Bug
- 位置: lib/api/emby_api.dart:31
- 问题: `EmbyApi` 在未注入 `Dio` 时直接创建 `Dio()`，没有 `connectTimeout`、`receiveTimeout`、`sendTimeout` 等统一边界；生产路径 `MediaBackendProvider` 和连接页均使用默认构造。Emby 服务器不可达或网络半开时，登录、首页列表、详情、播放进度上报等请求可能长时间挂起，错误也难以统一归因。
  ```dart
  EmbyApi({
    Dio? dio,
    this.clientName = 'Fly Player',
    ...
  }) : _dio = dio ?? Dio(),
       _entryTokenProvider = entryTokenProvider {
    _installEntryTokenInterceptor();
  }
  ```
- 建议方向: 为默认 Dio 配置统一 BaseOptions 超时，并把需要的重试/错误归一策略集中在 API 客户端或共享网络层；测试注入 Dio 的能力可以保留。
- 状态: 已确认

### [A-005] EmbyApi 内嵌 FN Connect 入口令牌逻辑，跨后端中转能力没有抽象
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/api/emby_api.dart:49
- 问题: Emby API 客户端直接知道 `*.fnos.net`、`entry-token`、FN Connect/飞牛边缘闸，并在请求拦截器里拼 Cookie。该逻辑属于传输/入口中转能力，不是 Emby 协议本身；未来 Jellyfin 或其他后端经同一入口中转时，需要在各自 API 客户端重复接入同一套飞牛特化逻辑。
  ```dart
  /// FN Connect 入口令牌（cookie `entry-token` 的值）的动态取值器。
  /// 当 Emby 服务器是 `*.fnos.net` 中转域名（藏在飞牛反向代理后面）时，请求必须携带
  /// `Cookie: entry-token=<值>` 才能过云端 FN Connect 边缘闸
  final String Function()? _entryTokenProvider;
  ...
  if (usesFnConnectRelayCookie(options.uri.toString())) {
  ```
- 建议方向: 将 FN Connect relay cookie 注入抽到共享 transport/connection 层，由后端连接配置声明是否需要入口令牌；EmbyApi 只保留 Emby 协议请求。
- 状态: 已确认

### [A-006] API 层反向依赖 NasProvider，鉴权和登出副作用耦合到状态层
- 级别: P1
- 分类: 耦合 / 约束违规(C1)
- 位置: lib/api/feiniu_api.dart:27
- 问题: `lib/api/feiniu_api.dart` 直接 import 并持有 `NasProvider`，在请求拦截器中读取 token/baseUrl，401 时还直接调用 `nasProvider.logout()`。这让 API 层反向依赖状态层，违反 UI→状态→服务→API 的单向依赖；同时网络层会直接改变全局登录状态，调用方无法按场景决定 401 的处理策略。
  ```dart
  import '../providers/nas_provider.dart';
  ...
  final NasProvider nasProvider;
  final Dio _dio = Dio();
  ...
  if (e.response?.statusCode == 401) {
    nasProvider.logout();
  }
  ```
- 建议方向: FeiniuApi 改为依赖不可变连接配置和 token 读取回调，401 通过异常/事件返回到 provider 或 session 层处理，避免 API 层 import provider。
- 状态: 已确认

### [A-007] FeiniuApi 聚合网络、登录发现、播放、下载、字幕、偏好持久化等多职责
- 级别: P2
- 分类: 可维护性 / 约束违规(C6)
- 位置: lib/api/feiniu_api.dart:343
- 问题: 单个 `FeiniuApi` 文件约 2874 行，类内同时包含 FN Connect 登录/发现/OAuth、NAS 业务接口、播放流与播放记录、下载任务、字幕搜索/下载、图片下载、共享缓存、SharedPreferences 本地偏好等职责。新增或排查任何后端能力都要修改同一个核心 API 类，回归面过大。
  ```dart
  class FeiniuApi {
    static const String _loginPath = '$_apiPrefix/login';
    static const String _downloadTaskPath = '$_apiPrefix/download/task';
    static const String _subtitleSearchPath = '$_apiPrefix/subtitle/search';
    static final Map<String, Object?> _sharedResourceCache = <String, Object?>{};
    ...
    Future<String?> getPlaylistViewType() async {
  ```
- 建议方向: 按能力拆成 auth/FN Connect、catalog、playback、download、subtitle、user preference 等小型 API 或 service；保留一个轻量 facade 兼容调用方。
- 状态: 已确认

### [A-008] 播放记录上报只看 HTTP 成功，不校验后端业务 code
- 级别: P1
- 分类: Bug
- 位置: lib/api/feiniu_api.dart:2010
- 问题: `recordPlayback()` 只 `await _dio.post`，没有调用 `_requireSuccessPayload()`。飞牛接口若返回 HTTP 200 但业务 `code != 0`，方法仍被视为成功，播放器侧会误以为播放进度已经保存，导致续播位/播放历史丢失且难以触发重试。
  ```dart
  try {
    await _dio.post(
      _playRecordPath,
      data: <String, dynamic>{
        'item_guid': itemGuid,
        ...
      },
    );
  } catch (e) {
  ```
- 建议方向: 与收藏、下载、播放配置等写接口保持一致，对响应调用 `_requireSuccessPayload(response.data, 'playback record')`，让业务失败进入统一异常路径。
- 状态: 已确认

### [A-009] 服务端下载任务删除失败被完全吞掉，可能造成远端任务继续运行
- 级别: P2
- 分类: 错误处理 / 约束违规(M4)
- 位置: lib/api/feiniu_api.dart:2414
- 问题: `deleteDownloadTask()` 在删除服务端任务失败时空 `catch`，既不记录也不上抛。调用方会继续执行本地取消/暂停 UX，但 NAS 侧下载任务可能仍在运行，占用带宽和存储，后续状态也难以追踪。
  ```dart
  try {
    await _dio.delete(
      '$_downloadTaskPath/$normalizedTaskId',
      data: <String, dynamic>{'lan': lan.trim()},
    );
  } catch (_) {
    // Best-effort: server-side cleanup should not block the local UX.
  }
  ```
- 建议方向: 至少记录失败并返回可区分的结果；若 UX 需要 best-effort，可由调用方决定是否忽略，而不是 API 层静默吞掉。
- 状态: 已确认

### [A-010] API 客户端直接读写 SharedPreferences，网络层混入本地持久化职责
- 级别: P2
- 分类: 可维护性 / 约束违规(C6)
- 位置: lib/api/feiniu_api.dart:1541
- 问题: `FeiniuApi` 直接 import `shared_preferences` 并维护播放列表视图类型、播放 client id 等本地持久化状态。API 客户端因此同时承担网络通信和本地状态存储，测试与多后端复用都要绕过这些本地副作用。
  ```dart
  import 'package:shared_preferences/shared_preferences.dart';
  ...
  static const String _playlistViewTypePrefKey = 'playlist_view_type';
  ...
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_playlistViewTypePrefKey, viewType);
  ```
- 建议方向: 将本地偏好和播放 client id 下沉到专职 store/service，由调用层组合 API 读写与本地缓存；FeiniuApi 只负责远端请求。
- 状态: 已确认

### [A-011] 静态共享缓存以 token 作为 key 且没有登出清理，旧会话数据会常驻进程
- 级别: P2
- 分类: 资源泄漏 / 可维护性
- 位置: lib/api/feiniu_api.dart:406
- 问题: `_sharedResourceCache`、`_sharedResourceInflight`、`_sharedResourceCacheTimes` 是静态 Map，key 由 `baseUrl|token|suffix` 拼出。登出或切换账号时没有清理旧 token 对应的缓存项，旧用户的首页/详情等数据和 token 字符串会一直留在进程内，直到再次命中同 key 才可能按 TTL 被动失效。
  ```dart
  static final Map<String, Object?> _sharedResourceCache = <String, Object?>{};
  static final Map<String, Future<Object?>> _sharedResourceInflight =
      <String, Future<Object?>>{};
  ...
  return '$baseUrl|${nasProvider.token}|$suffix';
  ```
- 建议方向: 不把原始 token 放入缓存 key；在登出/切换连接时提供显式清理入口，或把缓存生命周期绑定到后端实例而不是静态全局 Map。
- 状态: 已确认

### [A-012] 公共操作 target 继续暴露飞牛式 watched=1/0 语义
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/media_backend/action/media_item_action_target.dart:19
- 问题: `MediaItemActionTarget` 是后端中立公共入参，但已看状态仍用 `int watched` 和 `watched == 1` 表示，并在注释中说明“沿用飞牛语义”。这要求 Emby/Jellyfin 等后端适配时也转换成飞牛式 1/0，而不是公共布尔语义，公共模型仍受单一后端历史字段约束。
  ```dart
  /// 已看态：1=已看，0=未看（沿用飞牛语义便于过渡）。
  final int watched;
  ...
  bool get isWatched => watched == 1;
  ```
- 建议方向: 公共 target 改为 `bool watched` 或三态枚举（未知/已看/未看），飞牛的 1/0 只在 `feiniu` mapper/适配层转换。
- 状态: 已确认

### [A-013] 详情展示模型内置英文 Unknown，占位文案绕过本地化
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/media_backend/detail/media_detail.dart:106
- 问题: `MediaDetail.displayTitle` 是展示用 getter，但当标题为空时直接返回英文硬编码 `Unknown`。该值会被 UI 直接消费时绕过 `AppLocalizations`，也让模型层混入展示文案决策。
  ```dart
  String get displayTitle {
    final secondary = secondaryTitle.trim();
    if (secondary.isNotEmpty) {
      return secondary;
    }
    final value = title.trim();
    return value.isEmpty ? 'Unknown' : value;
  }
  ```
- 建议方向: 模型层返回空字符串或状态，由 UI/presenter 通过 `AppLocalizations` 决定占位文案；避免模型内写用户可见英文。
- 状态: 已确认

### [A-014] 公共媒体源模型只覆盖 Emby 路径，飞牛仍走独立详情/轨道路径
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/media_backend/detail/media_source_info.dart:7
- 问题: `MediaSourceInfo` / `MediaSourceVersion` 位于公共 `media_backend/detail` 抽象目录，但注释明确说明“飞牛有自己的文件信息 / 视频信息渲染路径”“本模型只服务 Emby 等公共后端”。这意味着详情页文件信息、版本、音轨、字幕选择并未形成真正的公共模型；新增 Jellyfin 时容易继续复制一套“公共后端”路径，而飞牛路径保持平行分叉。
  ```dart
  /// 飞牛有自己的文件信息 / 视频信息渲染路径，本模型只服务 Emby 等公共后端的中立详情页。
  class MediaSourceInfo {
  ...
  /// 飞牛有自己的版本 / 轨道选择路径（深绑 `MpvMediaSource`），本模型只服务 Emby 等公共后端
  /// 的中立详情页。
  class MediaSourceVersion {
  ```
- 建议方向: 将详情页文件信息、版本、音轨、字幕选择统一成所有后端都能产出的公共 contract；飞牛的 `MpvMediaSource` 等私有句柄只留在播放解析层。
- 状态: 已确认

### [A-015] Emby 题材筛选加载失败被静默吞掉，列表筛选能力会无诊断降级
- 级别: P2
- 分类: 错误处理 / 约束违规(M4)
- 位置: lib/media_backend/emby/emby_media_backend.dart:187
- 问题: `getCatalogFilterSchema()` 拉取 Emby genres 失败时空 `catch`，直接返回不含题材维度的 schema。用户只会看到筛选项消失，日志和上层错误链都没有信息，旧服务器兼容问题或鉴权问题很难定位。
  ```dart
  var genreOptions = const <MediaFilterOption>[];
  try {
    final genres = await api.getGenres(
      ...
    );
    genreOptions = genres ...;
  } catch (_) {}
  ```
- 建议方向: 至少记录后端、catalogId 和异常；若要降级，返回 schema 时保留可观测诊断或由调用层决定是否提示/重试。
- 状态: 已确认

### [A-016] Emby 外挂字幕下载或写临时文件失败被静默吞掉
- 级别: P2
- 分类: 错误处理 / 约束违规(M4)
- 位置: lib/media_backend/emby/emby_media_backend.dart:764
- 问题: `resolveExternalSubtitleFile()` 同时负责下载字幕文本和写入系统临时文件，但任何下载、解码、文件写入异常都会直接返回 `null`，没有日志。播放器只会表现为外挂字幕不可用，无法区分服务端取流失败、entry-token 失效还是本地文件系统失败。
  ```dart
  try {
    final text = await api.downloadSubtitleText(...);
    ...
    await file.writeAsString(text, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
  ```
- 建议方向: 保持可降级返回 `null` 也应记录异常和 trackId/format；文件写入可拆到专职 subtitle cache/service，便于测试和清理。
- 状态: 已确认

### [A-017] 系列播放目标解析会按季串行拉取全部集，播放入口可能出现网络瀑布
- 级别: P2
- 分类: 性能
- 位置: lib/media_backend/emby/emby_media_backend.dart:524
- 问题: 当系列没有继续观看记录时，`resolveSeriesNextUpEpisode()` 先拉季列表，再按季 `await getSeasonEpisodes(season.id)` 串行扫描首个未看集。长剧/多季剧从系列播放按钮进入时会产生 N 次顺序网络请求，首播入口延迟随季数线性增长。
  ```dart
  final seasons = await getItemSeasons(target);
  ...
  for (final season in sorted) {
    final episodes = await getSeasonEpisodes(season.id);
    if (episodes.isEmpty) continue;
    firstEpisode ??= episodes.first;
    for (final episode in episodes) {
  ```
- 建议方向: 使用 Emby 支持的 NextUp/Resume/Items 查询一次性取目标集，或并行/分页限制拉取；至少先请求第一季首集，避免播放入口为完整扫描付费。
- 状态: 已确认

### [A-018] Emby 视频信息的 interlaced 字段取反，隔行扫描状态显示相反
- 级别: P2
- 分类: Bug
- 位置: lib/media_backend/emby/emby_media_mappers.dart:404
- 问题: `_videoStream()` 从 `IsInterlaced` 得到 `interlaced`，但写入 `MediaInfoFieldKey.interlaced` 时传了 `_yesNoRaw(!interlaced)`。如果视频确实是隔行扫描，详情明细会显示“否”；如果不是隔行扫描则显示“是”，技术信息与实际相反。
  ```dart
  final interlaced = stream['IsInterlaced'] == true;
  ...
  MediaInfoField(MediaInfoFieldKey.interlaced, _yesNoRaw(!interlaced)),
  ```
- 建议方向: 对 `interlaced` 字段直接使用 `_yesNoRaw(interlaced)`；若 UI 标签实际表示“逐行扫描”，应改名为对应的字段 key，避免语义反转。
- 状态: 已确认

### [A-019] Emby 图片 URL 将 access token 拼进 query，令牌容易进入缓存和日志
- 级别: P2
- 分类: Bug / 可维护性
- 位置: lib/media_backend/emby/emby_media_mappers.dart:646
- 问题: Emby 图片映射把 `_token` 直接拼到 `api_key` query 中，生成的 URL 会被 `MediaImageRef`、图片缓存 key、调试日志或错误上报携带。access token 因此从鉴权头扩散到可见字符串，且多处图片 URL 都重复这一模式。
  ```dart
  return MediaImageRef(
    url: '$serverUrl/Items/$id/Images/Primary?tag=$tag&api_key=$token',
  );
  ...
  url: '$serverUrl/Items/$id/Images/Backdrop?tag=$tag&api_key=$token',
  ```
- 建议方向: 让 `MediaImageRef` 支持鉴权 headers 或统一图片加载器注入 Emby token；URL 只保留资源路径和非敏感参数。
- 状态: 已确认

### [A-020] FeiniuMediaBackend 的公共查询接口仍返回空结果，通用页面一旦切到 backend 会丢数据
- 级别: P1
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/media_backend/feiniu/feiniu_media_backend.dart:103
- 问题: `FeiniuMediaBackend` 实现了公共 `MediaBackend`，但多个接口仍以“页面走自有路径”为由返回空值，包括收藏分页、人物作品、媒体源信息/版本等。这样公共页面无法真正只依赖 `MediaBackend`；迁移某个入口到通用后端接口时，飞牛会直接显示空数据，而 Emby 走另一套实现。
  ```dart
  Future<MediaItemCardPage> queryFavoriteItems(MediaCatalogQuery query) async =>
      // 飞牛收藏页走自有 `getFavoritePage` ... 不经本接口。
      const MediaItemCardPage();
  ...
  Future<List<MediaItemCard>> getPersonItems(String personId) async {
    // 飞牛走自有的按职务分页 getPersonItemList 路径 ... 不经本接口。
    return const <MediaItemCard>[];
  }
  ```
- 建议方向: 要么补齐 FeiniuMediaBackend 对这些公共接口的真实实现，要么把暂不支持能力显式建模在 capability/接口返回中，避免通用调用方把空列表误认为真实无数据。
- 状态: 已确认

### [A-021] Feiniu 详情与播放轨道降级吞异常，缺失演职员/字典/轨道时无诊断
- 级别: P2
- 分类: 错误处理 / 约束违规(M4)
- 位置: lib/media_backend/feiniu/feiniu_media_backend.dart:120
- 问题: `getItemDetail()` 获取演职员失败时空 `catch`，题材/地区字典用 `catchError` 静默回空 map；`getPlayback()` 获取流轨道字典失败也直接置空。用户会看到演职员缺失、题材退化为 id、音轨/字幕补充信息缺失，但日志没有后端错误上下文。
  ```dart
  try {
    credits = await api.getPersonList(itemId, request: _creditsRequest);
  } catch (_) {
    // 演职员失败不阻断详情展示
  }
  final genresMap = await api
      .getTagGenresMap(lan: 'zh-CN')
      .catchError((_) => const <int, String>{});
  ...
  try {
    trackData = await api.getStreamTrackData(request.itemId);
  } catch (_) {
    trackData = null;
  }
  ```
- 建议方向: 保留 best-effort 降级，但记录 action、itemId 和异常；对可恢复的字典/轨道缺失可通过诊断状态返回给页面或开发日志。
- 状态: 已确认

### [A-022] MediaBackend 默认收藏/已看实现返回请求态，未支持后端会被误判为操作成功
- 级别: P1
- 分类: Bug / 可扩展性
- 位置: lib/media_backend/media_backend.dart:136
- 问题: 公共接口给 `setItemFavorite` / `setItemWatched` 提供默认实现，并直接返回入参。新增后端若声明或误用这些通道但忘记 override，UI 会把“想要设置的状态”当成后端最终状态，导致收藏/已看按钮显示成功但服务端没有任何写入。
  ```dart
  Future<bool> setItemFavorite(String itemId, {required bool favorite}) async =>
      favorite;
  ...
  Future<bool> setItemWatched(String itemId, {required bool watched}) async =>
      watched;
  ```
- 建议方向: 默认实现应抛 `UnsupportedError` 或返回显式 unsupported 结果；调用方依据 `capabilities` 决定是否开放入口，避免静默假成功。
- 状态: 已确认

### [A-023] MediaItemCard 展示标题内置英文 Unknown，占位文案绕过本地化
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/media_backend/media_item_card.dart:90
- 问题: 公共卡片模型的 `displayTitle` 在标题为空时直接返回英文 `Unknown`。这是 UI 可见标题 fallback，但模型层没有 l10n context，导致卡片/列表/搜索结果在异常数据下绕过 `AppLocalizations`。
  ```dart
  String get displayTitle {
    final secondary = secondaryTitle.trim();
    if (secondary.isNotEmpty) {
      return secondary;
    }
    final value = title.trim();
    return value.isEmpty ? 'Unknown' : value;
  }
  ```
- 建议方向: 模型层只返回空值或提供 `hasDisplayTitle`；由 UI/presenter 层通过本地化文案决定占位。
- 状态: 已确认

### [A-024] 后端类型写死为 enum，新增 Jellyfin 必须修改公共 media_backend 文件
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/media_backend/media_backend_kind.dart:1
- 问题: 公共后端类型用 `enum MediaBackendKind { feiniu, emby }` 写死。TASK A 要求新增后端尽量不改公共代码，但接入 Jellyfin 时必须先修改该公共 enum，并同步所有 switch/序列化点；这会把后端注册扩展点变成公共代码变更。
  ```dart
  /// 公共媒体前端支持的后端类型。
  ...
  enum MediaBackendKind { feiniu, emby }
  ```
- 建议方向: 将后端 kind 抽为注册式字符串/id 或集中在 session/registry 层，公共 capability 只暴露稳定 id；新增后端时避免修改通用模型文件。
- 状态: 已确认

### [A-025] 未识别的后端连接 kind 会被反序列化成飞牛连接
- 级别: P1
- 分类: Bug / 可扩展性
- 位置: lib/media_backend/session/media_backend_connection.dart:51
- 问题: `MediaBackendConnection.fromJson()` 遇到未知 `kind` 时默认回退 `MediaBackendKind.feiniu`。如果未来版本写入 `jellyfin`，或本地存储损坏/降级，连接会被误当飞牛会话继续使用，后续 provider 可能拿飞牛 API 处理非飞牛 serverUrl/token，产生错误登录态或错误请求。
  ```dart
  final kind = MediaBackendKind.values.firstWhere(
    (value) => value.name == kindName,
    orElse: () => MediaBackendKind.feiniu,
  );
  ```
- 建议方向: 未识别 kind 应返回无效连接/抛解析错误/保留 unknown 状态，由 session 层提示重新登录；不要静默降级到某个具体后端。
- 状态: 已确认

### [A-026] 主题 Provider 暴露给 UI 的标题/副标题仍是英文硬编码
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/providers/app_theme_provider.dart:183
- 问题: `AppThemeProvider` 直接提供 UI 可见的英文标题、副标题和默认保存主题名，调用方如果展示这些 getter 会绕过 `AppLocalizations`。这违反“UI 展示文案一律走 AppLocalizations getter”的约束，也让主题名称在中文界面中无法本地化。
  ```dart
  String get currentThemeTitle => switch (_themeSourceType) {
    AppThemeSourceType.preset => _preset.title,
    AppThemeSourceType.currentCustom => 'Current custom',
    AppThemeSourceType.savedCustomTheme =>
      activeSavedTheme?.name ?? 'Current custom',
  };
  String get currentThemeSubtitle => switch (_themeSourceType) {
    AppThemeSourceType.preset => 'Preset theme',
    AppThemeSourceType.currentCustom => 'Manual recipe',
  ```
- 建议方向: Provider 只暴露结构化状态或本地化 key，由 UI 层通过 `AppLocalizations` 生成展示文案；默认保存主题名也应由调用处传入本地化后的 base name。
- 状态: 已确认

### [A-027] 跨窗口主题同步模式探测失败被静默吞掉
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/providers/app_theme_provider.dart:125
- 问题: `_refreshPrefsSharingMode()` 查询宿主上下文失败时 `catch (_)` 只保留旧值/默认值且没有日志或降级标记。该值决定是否在并行窗口下 `prefs.reload()`，一旦平台通道异常，主题跨引擎同步可能失效，但线上没有任何可追踪诊断。
  ```dart
  Future<void> _refreshPrefsSharingMode() async {
    try {
      final context = await ParallelHostBridge.getHostContext();
      if (_disposed) return;
      _prefsSharedAcrossEngines = context.parallelEngineActive;
      _hostRoleResolved = true;
    } catch (_) {
      // Leave the previous value; default false means "skip reload".
    }
  }
  ```
- 建议方向: 至少在 debug/诊断日志中记录异常，并考虑失败时使用保守同步策略或暴露状态，避免跨窗口主题不同步时完全无迹可查。
- 状态: 已确认

### [A-028] 保存主题 JSON 解析失败会静默丢弃全部保存主题
- 级别: P1
- 分类: Bug / 约束违规(M4)
- 位置: lib/providers/app_theme_provider.dart:1007
- 问题: `_decodeSavedThemes()` 对保存主题列表做整包 `try/catch`，任意一条损坏或字段类型异常都会落到 `catch (_)` 并返回空列表；随后 `_applyStoredValues()` 会把 active saved theme 降级为 current custom。用户保存过的主题会从 UI 中全部消失，且没有日志、备份或部分恢复。
  ```dart
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <SavedCustomTheme>[];
    }
    final result = <SavedCustomTheme>[];
    ...
    return result;
  } catch (_) {
    return const <SavedCustomTheme>[];
  }
  ```
- 建议方向: 将单条主题解析失败隔离到 item 级别并记录诊断；整包损坏时保留原始 payload/备份，避免一次异常导致所有保存主题不可见。
- 状态: 已确认

### [A-029] 当前后端工厂写死 Emby/飞牛分支，未就绪或新增后端都会落回飞牛
- 级别: P1
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/providers/media_backend_provider.dart:35
- 问题: `MediaBackendProvider.backend` 在公共 provider 中直接判断 `MediaBackendKind.emby`，其余情况统一构造 `FeiniuMediaBackend`。这同时把新增后端扩展点写死在公共层，并让 session 未就绪、未知 kind 或未来 Jellyfin 连接都可能被错误地按飞牛 API 处理。
  ```dart
  if (session != null &&
      session.currentKind == MediaBackendKind.emby &&
      connection != null &&
      connection.isAuthenticated) {
    final key = 'emby:${connection.serverUrl}:${connection.accessToken}';
    ...
  }

  final key = 'feiniu:${nasProvider.baseUrl}';
  final created = FeiniuMediaBackend(FeiniuApi(nasProvider));
  ```
- 建议方向: 用 registry/factory 按后端 kind 显式创建实例，session 未就绪或 kind 未注册时返回加载/错误状态；不要在公共 provider 的 `else` 中把所有非 Emby 情况都解释为飞牛。
- 状态: 已确认

### [A-030] NasProvider 同时承担登录态、统计作用域、缓存清理和播放进度队列调度
- 级别: P2
- 分类: 可维护性 / 约束违规(C6)
- 位置: lib/providers/nas_provider.dart:7
- 问题: `NasProvider` 不只是 NAS 登录态 provider，还直接依赖详情缓存、播放统计、离线进度队列、会话退出桥和动态主题写入器。登录态读取/退出会顺手改统计 owner、清缓存、触发离线队列 flush 和并行 UI 重置，导致认证状态变化的副作用分散在 provider 内，后续多后端会话接入时也难以复用这些横切逻辑。
  ```dart
  import '../services/detail_runtime_cache.dart';
  import '../services/play_stats/play_stats.dart';
  import '../services/playback_progress_offline_queue.dart';
  import '../services/session_exit_bridge.dart';
  import '../theme/dynamic_theme_seed_extractor.dart';
  ...
  unawaited(PlaybackProgressOfflineQueue.flush(this));
  ```
- 建议方向: 将“当前账号/后端 owner”抽成独立 session scope 服务，播放统计绑定、离线进度 flush、详情缓存清理和平台退出分别订阅会话事件；`NasProvider` 只维护飞牛登录态与持久化。
- 状态: 已确认

### [A-031] 并行窗口设置保存失败会留下已通知但未持久化的 UI 状态
- 级别: P2
- 分类: Bug / 约束违规(M4)
- 位置: lib/providers/parallel_window_settings_provider.dart:42
- 问题: 各个 setter 都先修改内存并 `notifyListeners()`，随后才调用 `ParallelWindowSettingsBridge.save()`；如果平台通道或原生持久化抛错，异常会继续向外抛，但 provider 已经通知 UI 使用新值，且没有回滚到桥接层返回的真实设置。重启或下次 load 后状态会跳回旧值。
  ```dart
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final settings = await ParallelWindowSettingsBridge.save(
      enabled: _enabled,
      preferredPrimaryPaneSide: _preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide: _preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: _splitRatioPreset,
  ```
- 建议方向: 把“待保存中”和“已持久化状态”分开，保存失败时记录/回滚并通知 UI；重复的 save/apply 返回逻辑也可抽成一个私有 helper，统一错误处理。
- 状态: 已确认

### [A-032] 播放启动器拿到抽象 MediaPlayback 后又按具体后端上下文分发
- 级别: P1
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/controllers/item_playback_launcher.dart:368
- 问题: `_resolve()` 调用抽象 `backend.getPlayback()` 后，立即对 `resolution.backendContext` 做 `is FeiniuPlaybackContext` / `is EmbyPlaybackContext` 判断并选择具体 bridge。新增 Jellyfin 后端即使实现了 `MediaBackend.getPlayback()`，仍必须修改这个公共 controller 才能起播，说明后端差异没有收敛在 `lib/media_backend/` 或统一播放装配抽象内。
  ```dart
  final resolution = await backend.getPlayback(request);
  final context = resolution.backendContext;
  if (context is FeiniuPlaybackContext) {
    final source = await const FeiniuPlaybackSourceBridge().assemble(
  ...
  if (context is EmbyPlaybackContext) {
    final source = await const EmbyPlaybackSourceBridge().assemble(
  ```
- 建议方向: 让 `MediaBackend` 或 `MediaPlaybackResolution` 返回已装配好的公共 `MpvMediaSource`/native load args，或注册 backend-specific playback assembler，controller 只消费抽象结果。
- 状态: 已确认

### [A-033] 原生反向解析路径绕过当前后端抽象重新构造 FeiniuApi
- 级别: P1
- 分类: 耦合 / 约束违规(C3)
- 位置: lib/controllers/item_playback_launcher.dart:296
- 问题: `resolveForNative()` 是公共播放启动器的一部分，但签名直接接收 `NasProvider`，并在反向通道里构造 `FeiniuMediaBackend(FeiniuApi(nas))`。这条路径无法复用 `MediaBackendProvider` 的当前后端实例，也把本地下载、弹幕、画质切换与飞牛 API 绑死；新增后端要支持原生壳画质/切源回调时必须继续改 controller。
  ```dart
  // 原生壳画质切换反向通道目前仅飞牛走（Emby 用最小反向通道 _resolveEmbyForNative）。
  final resolved = await _resolve(
    FeiniuMediaBackend(FeiniuApi(nas)),
    itemGuid: itemGuid,
    fallbackTitle: fallbackTitle,
    qualityIndex: qualityIndex,
  ```
- 建议方向: 将 native reentry 的重解析能力挂到当前 `MediaBackend` 或 backend capability 上，由每个后端实现自己的重解析；controller 不应直接创建飞牛 API/backend。
- 状态: 已确认

### [A-034] 本地下载播放解析器直接依赖飞牛 API 并吞掉所有元数据失败
- 级别: P2
- 分类: 耦合 / 约束违规(C3, M4)
- 位置: lib/controllers/local_download_source_resolver.dart:32
- 问题: `resolveLocalDownloadSource()` 是播放 controller 复用的本地下载解析入口，但它固定接收 `NasProvider`、构造 `FeiniuApi`，并连续空 `catch` 拉取飞牛 `getPlayInfo/getStreamTrackData/getPlaybackStream`。这使本地下载播放元数据只能从飞牛补齐，未来 Emby/Jellyfin 下载记录无法接入同一解析路径；飞牛元数据失败时也没有 itemGuid/action 诊断。
  ```dart
  /// 从下载记录解析本地播放 source。NAS 连接时合并 getPlayInfo/StreamTrack/PlaybackStream
  ...
  final api = FeiniuApi(nas);
  ...
  try {
    initialPlayInfo = await api.getPlayInfo(normalizedItemGuid);
  } catch (_) {}
  ```
- 建议方向: 将下载记录的后端 kind/source metadata 写入模型，并把“补齐播放元数据”交给对应 `MediaBackend` 或下载服务策略；best-effort 降级时至少记录失败的接口和 itemGuid。
- 状态: 已确认

### [A-035] 通用命名的播放详情数据加载器固定依赖 FeiniuApi 和飞牛模型
- 级别: P2
- 分类: 可扩展性 / 耦合
- 位置: lib/controllers/play_detail_data_loader.dart:121
- 问题: `PlayDetailDataLoader`、`PlayDetailInitialData`、`PlayDetailRefreshData` 都是通用命名，但加载器构造函数固定接收 `FeiniuApi`，返回值也绑定 `PlayInfoData`、`StreamTrackData`、`StreamListOption` 等飞牛模型。详情页如果要复用这套加载/刷新流程到 Emby/Jellyfin，必须新增平行 controller 或改动公共类型。
  ```dart
  class PlayDetailInitialData {
    final PlayInfoData info;
    final StreamTrackData streamTrackData;
    final List<StreamListOption> streamOptions;
  ...
  final FeiniuApi api;
  const PlayDetailDataLoader(this.api);
  ```
- 建议方向: 若该 loader 只服务飞牛旧详情页，应在命名/目录上显式标记为 Feiniu；否则改为依赖 `MediaBackend` 的详情/播放抽象，并返回后端中立的 view data。
- 状态: 已确认

### [A-036] 单条目下载面板 controller 直接构造 FeiniuApi，下载能力没有后端抽象
- 级别: P2
- 分类: 耦合 / 约束违规(C3, M4)
- 位置: lib/controllers/play_detail_download_sheet_controller.dart:89
- 问题: `PlayDetailDownloadSheetController.show()` 从 `NasProvider` 直接构造 `FeiniuApi`，后续清晰度、详情、分组信息都调用飞牛接口；预取和后台解析失败处多次空 `catch`，只把面板置为 loadingError 或静默放弃缓存。新增 Emby/Jellyfin 下载能力时无法复用该下载面板 controller，也难以诊断下载面板为什么缺清晰度/分组信息。
  ```dart
  final provider = context.read<NasProvider>();
  final api = FeiniuApi(provider);
  ...
  static Future<void> prefetchQualities(FeiniuApi api, String itemGuid) async {
    ...
    } catch (_) {}
  ```
- 建议方向: 下载入口应通过 `MediaBackend` capability 或下载服务抽象获取可下载版本/分组元数据；飞牛专用预取失败要记录 itemGuid/action，非飞牛后端由 capability 决定是否展示入口。
- 状态: 已确认

### [A-037] 通用媒体信息面板入口仍通过 fromFeiniu 构造变体
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/controllers/play_detail_sheet_controller.dart:80
- 问题: `showMediaInfoDetail()` 是通用命名的媒体信息面板入口，但参数和构造路径都绑定飞牛 `StreamListOption/StreamTrackData`，并调用 `MediaDetailVariant.fromFeiniu()`。Emby 已有公共 `MediaSourceInfo`，但这里无法消费后端中立的媒体源信息，新增后端仍需要新增平行入口或继续扩大 `fromFeiniu` 特例。
  ```dart
  static Future<void> showMediaInfoDetail(
    BuildContext context, {
    required List<StreamListOption> streamOptions,
    required StreamTrackData? streamTrackData,
  ...
      variants.add(
        MediaDetailVariant.fromFeiniu(
  ```
- 建议方向: 让媒体信息面板入口接收公共 `MediaSourceInfo/MediaSourceVersion` 或已转换好的 `MediaDetailVariant`；飞牛模型到公共变体的映射应留在飞牛 adapter 内。
- 状态: 已确认

### [A-038] 整季下载面板 controller 固定使用 FeiniuApi，批量下载能力无法扩展到其他后端
- 级别: P2
- 分类: 耦合 / 约束违规(C3, M4)
- 位置: lib/controllers/tv_season_download_sheet_controller.dart:43
- 问题: `TvSeasonDownloadSheetController` 的预取、展示和后台加载都固定接收/构造 `FeiniuApi`，并依赖飞牛 `getItemDetail/getDownloadResolutionOptions` 的字段形状来解析 playItemGuid、分组和清晰度。失败路径多处 `catch (_)` 或只设置 `loadingError`，没有记录候选 guid 和接口名。整季下载如果要支持 Emby/Jellyfin，必须新增平行 controller 或重写该文件。
  ```dart
  static Future<void> prefetchSeasonDownloadData(
    FeiniuApi api, {
    required List<String> candidateItemGuids,
  }) async {
    ...
      } catch (_) {
        // Try next candidate.
      }
  }
  ```
- 建议方向: 将“可下载条目解析、质量列表、分组元数据”抽为下载后端能力；controller 只渲染 payload 并调用下载服务，失败时记录 backend、guid 和接口阶段。
- 状态: 已确认

### [A-039] 整季播放启动器也按具体后端 PlaybackContext 分发 source bridge
- 级别: P1
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/controllers/tv_season_playback_launcher.dart:324
- 问题: `_resolveWithProvider()` 调用抽象 `backend.getPlayback()` 后，再用 `is FeiniuPlaybackContext` / `is EmbyPlaybackContext` 选择具体装配器。该文件负责季度详情起播和原生壳切集，新增 Jellyfin 后端即使实现了公共 `MediaBackend`，仍需要修改这里才能播放剧集/切集。
  ```dart
  final resolution = await backend.getPlayback(request);
  final context = resolution.backendContext;
  if (context is FeiniuPlaybackContext) {
    final source = await const FeiniuPlaybackSourceBridge().assemble(
  ...
  if (context is EmbyPlaybackContext) {
    final source = await const EmbyPlaybackSourceBridge().assemble(
  ```
- 建议方向: 与单条目 launcher 一样，把 source/native load args 装配迁回后端实现或注册式 playback assembler；TV controller 只处理剧集上下文和导航。
- 状态: 已确认

### [A-040] MediaInfo 嵌套 JSON 未做类型防护，服务端字段异常会抛 TypeError
- 级别: P1
- 分类: Bug
- 位置: lib/models/media_info.dart:16
- 问题: `MediaInfo.fromJson()` 对 `file_stream/video_stream` 以及列表元素直接调用子模型 `fromJson`，没有确认嵌套值是 `Map<String, dynamic>`。一旦 Feiniu 返回空字符串、`List` 元素为非 Map，或 map 泛型不是预期类型，解析会在模型层抛 `TypeError`，导致媒体信息页/调用方加载失败。
  ```dart
  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    return MediaInfo(
      fileStream: json['file_stream'] != null ? FileStream.fromJson(json['file_stream']) : null,
      videoStream: json['video_stream'] != null ? VideoStream.fromJson(json['video_stream']) : null,
      audioStreams: (json['audio_streams'] as List?)?.map((e) => AudioStream.fromJson(e)).toList() ?? [],
      subtitleStreams: (json['subtitle_streams'] as List?)?.map((e) => SubtitleStream.fromJson(e)).toList() ?? [],
  ```
- 建议方向: 对每个嵌套对象使用 `if (raw is Map)` + `Map<String, dynamic>.from(raw)`，列表元素跳过非法项并记录上层接口上下文；数字字段也用统一 `_asInt`。
- 状态: 已确认

### [A-041] MediaItem 模型内置英文 Unknown 作为标题 fallback
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/models/media_item.dart:24
- 问题: `MediaItem.fromJson()` 在 `title/name` 缺失时写入英文 `Unknown`。`MediaItem` 被首页分类、路由 category payload 和缓存复用，模型层没有 l10n context，后续 UI 看到的是已污染的英文标题，无法再按 locale 决定占位文案。
  ```dart
  return MediaItem(
    id: (json['guid'] ?? json['id'] ?? '').toString(),
    name: (json['title'] ?? json['name'] ?? 'Unknown').toString(),
    type: (json['category'] ?? json['type'])?.toString(),
    path: (json['poster'] ?? json['path'])?.toString(),
  ```
- 建议方向: 模型层保留空字符串或增加 `hasName`；由 UI/presenter 层使用 `AppLocalizations` 生成“未知”占位。
- 状态: 已确认

### [A-042] MediaLibraryItem 模型内置英文 Unknown 作为列表标题 fallback
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/models/media_library_item.dart:80
- 问题: `MediaLibraryItem.fromJson()` 在 `title` 缺失时直接写入英文 `Unknown`。该模型用于媒体列表、季度/剧集、下载与播放入口，模型层没有本地化上下文，后续 UI 只能展示英文 fallback，无法按当前 locale 输出占位文案。
  ```dart
  return MediaLibraryItem(
    guid: (json['guid'] ?? '').toString(),
    title: (json['title'] ?? 'Unknown').toString(),
    tvTitle: (json['tv_title'] ?? '').toString(),
    type: (json['type'] ?? '').toString(),
    poster: resolvedPoster,
  ```
- 建议方向: 模型层保留空标题或暴露结构化状态，UI/presenter 负责本地化占位；同时统一清理 `MediaItem/MediaLibraryItem/MediaItemCard` 的英文 fallback。
- 状态: 已确认

### [A-043] 人物模型 getter 直接生成中文展示文案，绕过 AppLocalizations
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/models/person_credit.dart:35
- 问题: `PersonCredit.displayName/displaySubTitle` 在模型层返回 `未知`、`饰`、`导演/演员/编剧` 等中文文案；`PersonDetailProfile.displayName` 也内置 `未知`。这些都是 UI 展示文本，但模型无法访问 `AppLocalizations`，会让英文/系统语言界面仍显示中文 fallback。
  ```dart
  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    final o = originalName.trim();
    if (o.isNotEmpty) return o;
    return '未知';
  }
  ```
- 建议方向: 模型只暴露原始字段和枚举/角色 code；由 UI/presenter 使用 `AppLocalizations` 组装姓名 fallback、饰演关系和职业翻译。
- 状态: 已确认

### [A-044] PlaybackStreamData 对 header 字段使用强转，异常响应会中断播放流解析
- 级别: P1
- 分类: Bug
- 位置: lib/models/playback_stream.dart:190
- 问题: `PlaybackStreamData.fromJson()` 大多数嵌套字段都先判断类型，但 `header` 直接 `as Map<String, dynamic>?`。如果后端返回空字符串、列表、`Map<dynamic,dynamic>` 或其他异常结构，播放流解析会在这里抛 `TypeError`，后续 qualities/directLink 等已解析数据也会全部丢失。
  ```dart
  final responseHeaders = PlaybackResponseHeaders.fromJson(
    json['header'] as Map<String, dynamic>?,
  );
  PlaybackCloudStorageInfo? cloudStorageInfo;
  final rawCloudStorageInfo = json['cloud_storage_info'];
  if (rawCloudStorageInfo is Map<String, dynamic>) {
  ```
- 建议方向: 与其他嵌套字段一致，先 `final rawHeader = json['header']; if (rawHeader is Map) ...`，非法 header 降级为空 headers 并在 API 层记录原始响应形状。
- 状态: 已确认

### [A-045] StreamListOption 位于 models 层却反向依赖 ui mapper 并生成展示标签
- 级别: P1
- 分类: 耦合 / 约束违规(C1, M3)
- 位置: lib/models/stream_list_option.dart:1
- 问题: `lib/models/stream_list_option.dart` 直接 import `../ui/capability_badge_mapper.dart`，并在模型 getter 中生成 `未知版本`、`1080P/720P` 和语言展示标签。按分层约束，模型层不应反向依赖 UI 层；这些展示文案也无法走 `AppLocalizations`。
  ```dart
  import '../ui/capability_badge_mapper.dart';
  import 'package:fly_player/utils/media_language_mapper.dart';

  class StreamListOption {
    static const String unknownVersionLabel = '未知版本';
  ...
    String get label {
  ```
- 建议方向: 将 badge/语言/未知版本文案移动到 presenter 或 UI helper；模型只保留原始 resolution/color/audio language 字段，避免 `models -> ui` 的反向依赖。
- 状态: 已确认

### [A-046] StreamTrackData 轨道模型内置中文/英文展示文案
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/models/stream_track_data.dart:301
- 问题: `AudioTrackOption` 和 `SubtitleTrackOption` 在模型层提供 `displayLabel/detailLabel`，直接返回 `未知音频`、`字幕`、`中文`、`Traditional/Simplified` 等 UI 文案。该模型被播放页、下载、本地解析复用，文案一旦从模型返回，UI 层无法再按 locale 或页面语境本地化。
  ```dart
  String get detailLabel {
    final parts = <String>[
      if (codecName.trim().isNotEmpty) codecName.trim().toLowerCase(),
  ...
    if (audioType.trim().isNotEmpty) return audioType.trim();
    return '未知音频';
  }
  ```
- 建议方向: 保留原始 codec/language/title/style 字段，展示标签交给使用 `AppLocalizations` 的 UI/presenter；语言映射也应返回结构化 code 或由本地化层处理。
- 状态: 已确认

### [A-047] TV 剧集浏览模型直接依赖 Flutter Color，模型层承载 UI 状态
- 级别: P2
- 分类: 耦合 / 可维护性
- 位置: lib/models/tv_episode_browser_models.dart:1
- 问题: `TvEpisodeCardData` 位于 `lib/models/`，但直接 import `package:flutter/material.dart` 并把 `Color statusColor` 存进数据模型。这样领域/数据模型依赖 Flutter UI 类型，状态颜色策略无法由主题或本地化 UI 层统一控制，测试和后续后端复用也会被 Flutter 依赖污染。
  ```dart
  import 'package:flutter/material.dart';

  class TvEpisodeCardData {
    final String statusLabel;
    final Color statusColor;
    final List<String> imageUrls;
  ```
- 建议方向: 模型层改为状态枚举/语义 token（如 playing/completed/progress），由 widget/presenter 根据主题映射到颜色与状态文案。
- 状态: 已确认

## 总结

- 本轮 TASK A 共审 64 个文件，记录 47 条 finding，第二轮复核后 47 条均为已确认，0 条撤回。
- 最高优先级集中在多后端抽象泄漏：`main.dart`、`MediaBackendProvider`、播放 launcher、下载 controller、`MediaBackendKind` 多处仍需新增后端时改公共代码。
- 飞牛旧路径仍大量直连 `FeiniuApi`，尤其播放详情、下载、原生反向解析和本地下载解析，建议优先统一到 `MediaBackend`/下载 capability。
- 错误处理问题主要是 best-effort 空 catch 和模型 JSON 强转，优先处理会造成数据丢失/崩溃的 A-028、A-040、A-044。
- i18n 与分层问题集中在模型/provider 层生成展示文案、models 反向依赖 UI，建议作为清理面统一收敛到 presenter/UI。
- 最值得优先处理：A-001、A-002、A-029、A-032/A-039、A-028、A-040/A-044。
