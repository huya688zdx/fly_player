<!-- CHECKPOINT
已审文件数: 19 / 19
最后完成: 第二轮自复核与总结
下一个: 无
阶段: 已完成
更新时间: 2026-07-03 03:02
-->

# TASK F Findings

### [F-001] 媒体合集详情页直接绑定 FeiniuApi
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2)
- 位置: lib/pages/media_collection_detail_page.dart:6
- 问题: 页面层直接导入并实例化具体飞牛 API，详情、列表、排序设置、兜底播放信息都绕过 `lib/media_backend/` 抽象，非飞牛后端无法复用这条详情页路径。关键代码摘录：
  ```dart
  import '../api/feiniu_api.dart';
  ...
  final api = FeiniuApi(context.read<NasProvider>());
  final detail =
      widget.initialItemDetail ?? await api.getItemDetail(widget.itemGuid);
  final setting = settingsMdbGuid.isNotEmpty
      ? await api.getUserListSetting(settingsMdbGuid)
      : null;
  ```
- 建议方向: 将合集详情、合集条目分页、用户列表设置与播放信息兜底收敛到 `MediaBackend`/service 层；页面只消费中立 detail/view model 和 action 接口。
- 状态: 已确认

### [F-002] 合集兜底加载失败被空 catch 静默吞掉
- 级别: P2
- 分类: 可维护性 / Bug / 错误处理(M4)
- 位置: lib/pages/media_collection_detail_page.dart:208
- 问题: 播放信息兜底和码流列表兜底都用 `catch (_)` 直接返回空列表，网络、解析或后端字段异常都会被表现为“合集无条目”，没有日志或错误提示，排查困难。关键代码摘录：
  ```dart
  } catch (_) {
    return const <MediaLibraryItem>[];
  }
  ...
  } catch (_) {
    return const <MediaLibraryItem>[];
  }
  ```
- 建议方向: 至少记录异常上下文；如该兜底失败会影响页面主体数据，应把错误合并到页面错误态或顶部提示，而不是静默降级为空内容。
- 状态: 已确认

### [F-003] 媒体明细弹层的公共变体模型暴露 Feiniu 构造入口
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/pages/media_detail_overlay_page.dart:39
- 问题: `MediaDetailVariant` 是同一个 overlay 的公共输入模型，但公开 factory 命名为 `fromFeiniu`，并直接接收飞牛 DTO，公共 UI 层接口出现后端专名和后端数据格式。关键代码摘录：
  ```dart
  factory MediaDetailVariant.fromFeiniu({
    required String key,
    required String title,
    required AppLocalizations l10n,
    VideoStreamInfo? video,
    List<AudioTrackOption> audios = const <AudioTrackOption>[],
    List<SubtitleTrackOption> subtitles = const <SubtitleTrackOption>[],
  }) {
  ```
- 建议方向: 将飞牛轨道 DTO 到 `MediaInfoCard` 的映射移到飞牛 backend/presenter 层；overlay 只暴露 `fromCards`/普通构造等后端中立入口。
- 状态: 已确认

### [F-004] 媒体明细弹层 barrierLabel 写死英文 key
- 级别: P3
- 分类: 可维护性 / i18n(M3)
- 位置: lib/pages/media_detail_overlay_page.dart:113
- 问题: 底部弹层的无障碍标签使用硬编码英文 key，没有走 `AppLocalizations`，读屏场景会暴露内部标识。关键代码摘录：
  ```dart
  return AppSheetTransitions.showBottomSurface<void>(
    context,
    barrierDismissible: true,
    barrierLabel: 'media_detail_overlay',
    barrierColor: const Color(0xBF020812),
    builder: (_) => page,
  );
  ```
- 建议方向: 使用已有的本地化标题（如 `mediaDetailsTitle`）或新增专用 l10n getter，避免 UI/无障碍文案硬编码。
- 状态: 已确认

### [F-005] 详情入口页用飞牛详情和飞牛 type schema 决定路由
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/pages/play_detail_entry_page.dart:66
- 问题: 入口页直接创建 `FeiniuApi` 拉详情，并用 `movie/tv/mediadb/directory` 等具体后端字段决定落到哪个详情页。非飞牛后端如果要复用入口路由，就必须返回飞牛兼容字段。关键代码摘录：
  ```dart
  final api = FeiniuApi(context.read<NasProvider>());
  final detail = await api.getItemDetail(widget.itemGuid);
  ...
  final directType = (detail['type'] ?? '').toString().trim().toLowerCase();
  if (directType == 'tv') return DetailPageMode.tv;
  if (directType == 'mediadb' || directType == 'directory') {
    return DetailPageMode.library;
  }
  ```
- 建议方向: 由 `MediaBackend.getItemDetail` 返回中立 detail kind/route target，或在 backend presenter 层完成路由决策；入口页只消费中立枚举。
- 状态: 已确认

### [F-006] PlayDetailPage 超大且混合过多职责
- 级别: P2
- 分类: 可维护性 / 超大文件(M1)
- 位置: lib/pages/play_detail_page.dart:86
- 问题: 单个 UI 文件约 3300 行，`_PlayDetailPageState` 同时管理飞牛/中立后端数据、动画、下载状态、本地文件、播放启动、主题取色、演职员/文件/视频信息等逻辑，已超过 M1 的 1500 行拆分阈值。关键代码摘录：
  ```dart
  class _PlayDetailPageState extends State<PlayDetailPage>
      with TickerProviderStateMixin, WidgetsBindingObserver {
    ...
    final DownloadTaskService _downloadTaskService = DownloadTaskService.instance;
    MediaDetail? _detail;
    MediaSourceInfo? _sourceInfo;
    List<MediaSourceVersion> _neutralVersions = const <MediaSourceVersion>[];
    StreamTrackData? _streamTrackData;
  ```
- 建议方向: 参考 player 的 part/mixin 模式，至少拆出数据加载/后端适配、播放启动、下载与本地文件状态、弹层选择器、主体分区构建几个切面；保留主页面只做组合。
- 状态: 已确认

### [F-007] PlayDetailPage 在 UI 层按后端类型分流并直接调用 FeiniuApi
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/pages/play_detail_page.dart:1306
- 问题: 页面加载逻辑直接读取 `MediaBackendKind.feiniu` 做后端分流，非飞牛走 `MediaBackend`，飞牛分支仍创建 `FeiniuApi` 拉取播放详情和后续数据。后端差异泄漏在页面层，新增后端时容易继续扩展页面 if/else。关键代码摘录：
  ```dart
  final backend = context.read<MediaBackendProvider>().backend;
  if (backend.capabilities.kind != MediaBackendKind.feiniu) {
    _neutralDisplayOnly = true;
    final detail = await backend.getItemDetail(_currentItemGuid);
    ...
  }
  ...
  final api = FeiniuApi(context.read<NasProvider>());
  final info = await _loadPlayInfo(api, _currentItemGuid);
  ```
- 建议方向: 将飞牛播放详情、轨道、字典、延迟区块加载统一包装到 `MediaBackend` 能力接口或专用 detail loader；页面只按能力字段渲染，不直接判断具体 backend kind。
- 状态: 已确认

### [F-008] 详情页 build 路径同步访问本地文件系统
- 级别: P1
- 分类: 性能 / 约束违规(P5)
- 位置: lib/pages/play_detail_page.dart:3103
- 问题: `build()` 中计算当前文件信息时调用 `_localDownloadedFileInfo()`，该方法内部执行 `File.existsSync()` 和 `file.statSync()`。下载任务变化、主题变化、滚动相关状态或播放返回都可能触发页面重建，从而在主线程同步访问文件系统，造成详情页卡顿。关键代码摘录：
  ```dart
  final localDownloadRecord = _downloadedRecordForCurrentItem();
  final localDownloadedFile = _localDownloadedFileInfo(
    localDownloadRecord,
  );
  ...
  if (!file.existsSync()) return null;
  final stat = file.statSync();
  ```
- 建议方向: 将本地文件存在性与 stat 结果放到下载服务或异步缓存中，在下载完成/记录变化时更新状态；build 只读取已准备好的快照。
- 状态: 已确认

### [F-009] PlayDetailPage 多个延迟加载失败被空 catch 静默吞掉
- 级别: P2
- 分类: 可维护性 / 错误处理(M4)
- 位置: lib/pages/play_detail_page.dart:1551
- 问题: 演职员、授权目录、外部链接补全以及原生壳季集列表预取等路径存在空 `catch (_) {}`，失败后页面只表现为区块缺失或原生壳选集缺失，没有日志、错误态或可追踪上下文。关键代码摘录：
  ```dart
  try {
    final people = await _loadPersonCredits(api, _currentItemGuid)
        .then<List<PersonCredit>>((v) => v)
        .catchError((_) => const <PersonCredit>[]);
    ...
  } catch (_) {}
  ...
  } catch (_) {}
  ```
- 建议方向: 对 best-effort 区块至少用 `AppErrorReporter.report` 记录 action、itemGuid 和阶段；对影响播放/选集的失败应给出降级提示或显式状态。
- 状态: 已确认

### [F-010] TvDetailPage 在 UI 层按后端类型分流并直接调用 FeiniuApi
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/pages/tv_detail_page.dart:260
- 问题: TV 详情页直接判断 `MediaBackendKind.feiniu`，非飞牛走中立路径，飞牛分支在页面内创建 `FeiniuApi` 拉详情与延迟数据。后端差异没有收敛在 `media_backend` 层。关键代码摘录：
  ```dart
  final backend = context.read<MediaBackendProvider>().backend;
  if (backend.capabilities.kind != MediaBackendKind.feiniu) {
    await _loadNeutral();
    return;
  }
  try {
    final api = FeiniuApi(context.read<NasProvider>());
    ...
    final detail = await _loadItemDetail(api, widget.itemGuid);
  ```
- 建议方向: 将 TV 详情、季列表、续看目标和飞牛字段映射统一放入 backend/presenter 层；页面只消费中立 detail、season summary 和 action 接口。
- 状态: 已确认

### [F-011] TvDetailPage 保留被 ignore 掩盖的未用主按钮文案方法
- 级别: P2
- 分类: 可维护性 / 死代码(M5)
- 位置: lib/pages/tv_detail_page.dart:567
- 问题: `_tvPrimaryText` 被 `// ignore: unused_element` 保留但未被调用，且方法内部还重复判断 `seasonNumber == 0` 两次。该逻辑与实际使用的 `_tvPrimaryLabel` 平行存在，容易让后续维护者改错入口。关键代码摘录：
  ```dart
  // ignore: unused_element
  String _tvPrimaryText(Map<String, dynamic> item) {
    final fromPlayInfo = _playInfo?.item;
    final seasonNumber = _asInt(item['season_number']);
    ...
    if (seasonNumber == 0) {
      ...
    }
    if (seasonNumber == 0) {
  ```
- 建议方向: 删除未用方法，或将 `_tvPrimaryLabel` 与需要的命名集数文案合并为唯一实现，并移除 lint ignore。
- 状态: 已确认

### [F-012] TV 详情延迟区块异常被统一吞成 null
- 级别: P2
- 分类: 可维护性 / 错误处理(M4)
- 位置: lib/pages/tv_detail_page.dart:483
- 问题: `_guardSection` 捕获任何异常后直接返回 null，调用方无法区分“成功但为空”和“请求/解析失败”。季列表、题材/地区字典、播放信息失败都会静默表现为缺区块或缺元信息。关键代码摘录：
  ```dart
  Future<T?> _guardSection<T>(Future<T> Function() task) async {
    try {
      return await task();
    } catch (_) {
      return null;
    }
  }
  ...
  final seasonItemsFuture = _guardSection<List<MediaLibraryItem>>(
    () => _loadSeasonItems(api, widget.itemGuid),
  );
  ```
- 建议方向: 给 `_guardSection` 增加 action/source 参数并记录异常；调用方可继续降级为空，但日志中要保留 itemGuid 和失败区块。
- 状态: 已确认

### [F-013] TV 详情保留未用的旧播放入口和 TODO
- 级别: P2
- 分类: 可维护性 / 死代码(M5)
- 位置: lib/pages/tv_detail_page.dart:1286
- 问题: `_onPrimaryPlayTap` 被 `// ignore: unused_element` 保留，内部仍直接创建 `FeiniuApi`，最后只显示占位提示并留下 TODO。实际主按钮使用 `_launchPrimaryPlayback`，这段旧入口容易和真实播放链路混淆。关键代码摘录：
  ```dart
  // ignore: unused_element
  Future<void> _onPrimaryPlayTap() async {
    ...
    final api = FeiniuApi(context.read<NasProvider>());
    final info = await _loadPlayInfo(api, widget.itemGuid);
    ...
    // TODO: hook real player launch here with `info`.
  ```
- 建议方向: 删除旧 handler；如果仍需保留调试路径，应移到专用调试工具并避免页面层直接 Feiniu 调用。
- 状态: 已确认

### [F-014] TV 详情页超大且重复电影详情页主体结构
- 级别: P2
- 分类: 可维护性 / 重复代码(M1/M2)
- 位置: lib/pages/tv_detail_page.dart:75
- 问题: `TvDetailPage` 超过 2000 行，并在本页重复实现了电影详情页已有的动态主题、沉浸背景、hero、meta、描述弹层、播放动作行、链接区和折叠顶栏结构。后续改动这些通用详情体验时需要在多页同步修改。关键代码摘录：
  ```dart
  class _TvDetailPageState extends State<TvDetailPage>
      with TickerProviderStateMixin, WidgetsBindingObserver {
    ...
    Widget _buildNeutralBody(AppThemeColors colors, Color? ambientTint) {
      ...
      return Scaffold(
        backgroundColor: colors.backgroundBase,
        body: Stack(
  ```
- 建议方向: 抽取通用 `DetailScaffold`/`DetailHeroChrome`/`DetailActionAndDescription` 等组件，TV 页只提供季列表和播放目标解析；与 `PlayDetailPage` 共享顶栏、hero、描述、链接和动态主题宿主。
- 状态: 已确认

### [F-015] TvSeasonDetailPage 在页面层直接调用 FeiniuApi 并维护双后端路径
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/pages/tv_season_detail_page.dart:7
- 问题: 季详情页直接导入 `FeiniuApi`，页面 helper 内拉取集列表、季列表、详情、播放信息、播放列表视图设置等；同时文件还维护中立后端路径和飞牛路径，后端差异泄漏到 UI 层。关键代码摘录：
  ```dart
  import '../api/feiniu_api.dart';
  ...
  final future = FeiniuApi(context.read<NasProvider>())
      .getEpisodeList(seasonGuid)
      .catchError((error) {
  ...
  final viewType = await FeiniuApi(
    context.read<NasProvider>(),
  ).getPlaylistViewType();
  ```
- 建议方向: 将季详情、集分页、播放列表视图设置、播放信息和飞牛字段映射收敛到 `MediaBackend`/service；页面只接收中立 season/episode view model 和用户动作接口。
- 状态: 已确认

### [F-016] TvSeasonDetailPage 超大且承担季详情全链路职责
- 级别: P2
- 分类: 可维护性 / 超大文件(M1)
- 位置: lib/pages/tv_season_detail_page.dart:83
- 问题: 单个季详情 UI 文件超过 3000 行，`_TvSeasonDetailPageState` 同时承担后端分流、分页/缓存、播放 reentry、下载状态、动态主题、图片缓存、选集 UI、季切换、收藏/已看等职责，远超 M1 拆分阈值。关键代码摘录：
  ```dart
  class _TvSeasonDetailPageState extends State<TvSeasonDetailPage>
      with TickerProviderStateMixin, WidgetsBindingObserver {
    static const int _episodePageSize = 30;
    ...
    final DownloadTaskService _downloadTaskService = DownloadTaskService.instance;
    final Map<String, List<MediaLibraryItem>> _episodeCache =
        <String, List<MediaLibraryItem>>{};
    final Map<String, Future<List<MediaLibraryItem>>> _episodeInflight =
        <String, Future<List<MediaLibraryItem>>>{};
  ```
- 建议方向: 拆出 season data controller、episode pagination/cache、playback/reentry、download state、theme/artwork resolver 和纯 UI section；主页面只协调状态快照与路由。
- 状态: 已确认

### [F-017] 季详情中立路径多处 best-effort 失败静默降级
- 级别: P2
- 分类: 可维护性 / 错误处理(M4)
- 位置: lib/pages/tv_season_detail_page.dart:1036
- 问题: 中立后端加载季列表、系列详情兜底、选集列表、续看目标和收藏动作时多处 `catch (_) {}` 或吞成空列表，失败后只表现为缺季、缺集、播放目标不更新或收藏无反馈，日志中没有上下文。关键代码摘录：
  ```dart
  try {
    seasons = await backend.getItemSeasons(widget.parentGuid);
    ...
  } catch (_) {
    seasons = const <MediaSeasonSummary>[];
  }
  ...
  } catch (_) {}
  List<MediaEpisodeSummary> episodes;
  try {
    episodes = await backend.getSeasonEpisodes(target);
  } catch (_) {
  ```
- 建议方向: 对每个降级点记录 action、backend kind、series/season guid；用户动作类失败至少给顶部提示，数据补充类可继续降级但要可追踪。
- 状态: 已确认

### [F-018] 季详情飞牛路径多处失败被静默吞掉
- 级别: P2
- 分类: 可维护性 / 错误处理(M4)
- 位置: lib/pages/tv_season_detail_page.dart:2034
- 问题: 飞牛季详情的集列表解析、演职员延迟加载、播放后刷新、单集详情预取等失败路径都用空 catch 或直接置空，用户只看到空选集/缺演职员/进度不刷新，日志无根因。关键代码摘录：
  ```dart
  try {
    final episodes = await episodesFuture;
    ...
  } catch (_) {
    setState(() {
      _episodeItems = const <MediaLibraryItem>[];
      _episodeItemsResolved = true;
    });
  }
  ...
  } catch (_) {}
  ```
- 建议方向: 至少通过统一错误上报记录 seasonGuid、episodeGuid 和阶段；播放后刷新失败应保留 warning 日志，避免进度/已看状态不更新时无法定位。
- 状态: 已确认

### [F-019] 首页媒体浏览在页面层分流 FeiniuApi 与 MediaBackend
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/screens/media_list_screen.dart:255
- 问题: 首页列表页直接导入 `FeiniuApi`，并在 `_loadContinueWatching`、`_loadCategoryItems`、缓存写入等核心数据路径里判断 `MediaBackendKind.feiniu`。新增后端时首页数据差异仍需要改 UI 层。关键代码摘录：
  ```dart
  Future<List<MediaLibraryItem>> _loadContinueWatching(
    MediaBackend backend,
    FeiniuApi api, {
    bool forceRefresh = false,
  }) async {
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      return api.getPlayList(forceRefresh: forceRefresh);
    }
  ```
- 建议方向: 将继续观看、分类预览、首页缓存策略下沉到 backend/service 层，页面只请求中立 HomeViewData；飞牛保留 `ts` 等特殊字段也应由 mapper 适配。
- 状态: 已确认

### [F-020] 首页保留多段 return 后不可达导航代码
- 级别: P2
- 分类: 可维护性 / 死代码(M5)
- 位置: lib/screens/media_list_screen.dart:627
- 问题: `_openAllItems`、`_openAllItemsByType`、`_openFavorites` 在调用异步新路径后立即 `return`，后面仍保留旧 `Navigator.push` 代码并用 `// ignore: dead_code` 压制 lint。后续维护容易误以为两个路径都有效。关键代码摘录：
  ```dart
  void _openAllItems() {
    unawaited(
      _openCategoryAsync(
        MediaItem(
          id: '',
          name: AppLocalizations.of(context).mediaAllItemsTitle,
        ),
      ),
    );
    return;
    // ignore: dead_code
    Navigator.of(context).push(
  ```
- 建议方向: 删除不可达旧路径；如需保留 fallback，应把 fallback 合并进 `_openCategoryAsync`/`_openFavoritesAsync` 的正常控制流。
- 状态: 已确认

### [F-021] 继续观看删除动作直接调用 FeiniuApi
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2)
- 位置: lib/screens/media_list_screen_actions.dart:102
- 问题: 首页继续观看 action sheet 中，已看/收藏动作已走 `MediaBackend`，但“移除继续观看”仍直接创建 `FeiniuApi` 并调用 `deletePlaybackRecord`。非飞牛后端无法提供等价删除能力，页面层也需要知道飞牛 API。关键代码摘录：
  ```dart
  final api = FeiniuApi(context.read<NasProvider>());
  final backend = context.read<MediaBackendProvider>().backend;
  ...
  case _ContinueWatchingAction.remove:
    await api.deletePlaybackRecord(itemGuid: item.guid);
    if (!mounted) return;
    _applyState(() {
  ```
- 建议方向: 在 `MediaBackend` 增加可选的 continue-watching remove 能力，或由 action controller/service 封装；页面按能力启用/禁用该项。
- 状态: 已确认

### [F-022] 首页下载角标硬编码中文文案
- 级别: P2
- 分类: 可维护性 / i18n(M3)
- 位置: lib/screens/media_list_screen_widgets.dart:826
- 问题: 继续观看卡片右上角下载状态直接写中文 `已下载`，没有走 `AppLocalizations`。切换语言时该角标不会本地化。关键代码摘录：
  ```dart
  child: const Text(
    '已下载',
    style: TextStyle(
      color: _textColor,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  ```
- 建议方向: 新增或复用下载完成状态的 l10n getter，并从 `build` 中读取本地化文案。
- 状态: 已确认

### [F-023] 分类列表页仍直接使用 FeiniuApi 读取设置和预取详情
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/screens/category_items_screen.dart:131
- 问题: 分类列表主体查询已走 `MediaBackend.queryCatalogItems`，但页面仍直接创建 `FeiniuApi` 读取/保存列表偏好，并在打开详情前直接 `getItemDetail` 预取飞牛 detail。该页面仍需要知道飞牛设置端点和 detail map。关键代码摘录：
  ```dart
  final provider = context.read<NasProvider>();
  final api = FeiniuApi(provider);
  final backend = context.read<MediaBackendProvider>().backend;
  final isFeiniu = backend.capabilities.kind == MediaBackendKind.feiniu;
  ...
  setting = await api.getUserListSetting(widget.category.id);
  ...
  initialDetail = await FeiniuApi(
    context.read<NasProvider>(),
  ).getItemDetail(item.id).timeout(const Duration(milliseconds: 240));
  ```
- 建议方向: 将列表偏好读写纳入 backend 能力或浏览设置 service；详情预取应走中立 detail summary 或交给详情页按 backend 自行加载。
- 状态: 已确认

### [F-024] 分类列表设置和详情预取失败被空 catch 吞掉
- 级别: P2
- 分类: 可维护性 / 错误处理(M4)
- 位置: lib/screens/category_items_screen.dart:141
- 问题: 用户列表设置读取、筛选 schema 读取、详情预取等失败都用空 `catch (_) {}` 静默降级，导致排序/视图偏好丢失或详情首屏预取失效时没有任何可追踪信息。关键代码摘录：
  ```dart
  if (hasAncestor && isFeiniu) {
    try {
      setting = await api.getUserListSetting(widget.category.id);
    } catch (_) {}
  }
  var schema = const MediaCatalogFilterSchema();
  try {
    schema = await backend.getCatalogFilterSchema(widget.category.id);
  } catch (_) {}
  ```
- 建议方向: 为这些 best-effort 分支增加统一 warning 日志或错误上报，至少包含 catalogId、backend kind 和失败阶段。
- 状态: 已确认

### [F-025] 搜索历史 key 仍绑定 NasProvider.baseUrl
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/screens/search_screen.dart:88
- 问题: 搜索历史持久化 key 只使用 `NasProvider.baseUrl`。非飞牛后端（如 Emby）不一定维护 NAS baseUrl，多个后端/服务器可能共用空 key 或飞牛 key，导致搜索历史串库。关键代码摘录：
  ```dart
  String _historyKey() {
    final baseUrl = context.read<NasProvider>().baseUrl;
    return '$_historyKeyPrefix::$baseUrl';
  }
  ```
- 建议方向: 改用 `BackendSessionProvider.currentConnection` 或 backend capability 暴露的稳定 storage namespace；飞牛也通过同一中立 namespace 生成 key。
- 状态: 已确认

### [F-026] 搜索结果打开详情时直接 FeiniuApi 预取 detail
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2)
- 位置: lib/screens/search_screen.dart:236
- 问题: 搜索本身走 `MediaBackend.searchItems`，但打开非人物结果时仍直接创建 `FeiniuApi` 预取 `getItemDetail`，并把飞牛 detail map 传给详情页；非飞牛搜索结果无法提供等价预取。关键代码摘录：
  ```dart
  final provider = context.read<NasProvider>();
  Map<String, dynamic>? initialDetail;
  try {
    initialDetail = await FeiniuApi(
      provider,
    ).getItemDetail(item.id).timeout(const Duration(milliseconds: 240));
  } catch (_) {}
  ```
- 建议方向: 使用 backend 中立 detail preview，或取消页面层预取让详情页按当前 backend 加载；失败应记录为 best-effort 预取失败。
- 状态: 已确认

### [F-027] 收藏页主文件在页面层维护飞牛收藏分页和设置路径
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/screens/favorite_items_screen.dart:141
- 问题: 收藏页直接导入 `FeiniuApi`，并在初始化、布局设置、分页、剧集父海报补全、详情预取等路径中判断 `MediaBackendKind.feiniu` 或直接调用飞牛 API。非飞牛路径被临时映射为 `MediaLibraryItem` 以复用 UI，后端差异仍集中在页面层。关键代码摘录：
  ```dart
  if (context.read<MediaBackendProvider>().backend.capabilities.kind !=
      MediaBackendKind.feiniu) {
    await _fetch(tab: _selectedTab, reset: true);
    return;
  }
  final api = FeiniuApi(context.read<NasProvider>());
  final genresMap = await api.getTagGenresMap(lan: 'zh-CN');
  ...
  final page = await FeiniuApi(context.read<NasProvider>())
      .getFavoritePage(
  ```
- 建议方向: 将收藏分页、标签筛选、列表偏好、剧集父海报补全和详情预取下沉到 `MediaBackend`/service；页面只消费中立 favorite query 和 card/detail preview。
- 状态: 已确认

### [F-028] 收藏页多处飞牛辅助请求失败静默吞掉
- 级别: P2
- 分类: 可维护性 / 错误处理(M4)
- 位置: lib/screens/favorite_items_screen.dart:157
- 问题: 标签列表、剧集父海报补全、详情预取等辅助请求失败时使用空 `catch (_) {}` 或只保留当前 UI，没有日志；筛选缺项、横版剧集海报不替换、详情预取失效时难以排查。关键代码摘录：
  ```dart
  Map<String, List<dynamic>> tags = const <String, List<dynamic>>{};
  try {
    tags = await api.getTagList(isFavorite: 1);
  } catch (_) {}
  ...
  } catch (_) {
    // Keep the current episode still if parent poster lookup fails.
  }
  ```
- 建议方向: 记录 action、parentGuid/itemGuid 和失败阶段；可继续保留降级 UI，但不要完全静默。
- 状态: 已确认

### [F-029] 收藏排序弹层直接持久化飞牛列表设置
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/screens/favorite_items_screen_sheets.dart:63
- 问题: 收藏排序弹层属于页面 UI part，却在点击排序项时判断飞牛后端并直接调用 `FeiniuApi.setUserListSetting`。这让列表偏好持久化继续绑定飞牛 setting key，非飞牛后端无法通过统一抽象复用排序偏好能力。关键代码摘录：
  ```dart
  if (_isFeiniuBackend) {
    await FeiniuApi(
      context.read<NasProvider>(),
    ).setUserListSetting(
      '',
      sortField: _sortColumn,
  ```
- 建议方向: 将收藏列表偏好读写封装到 backend/service 的中立接口；弹层只提交排序状态，由页面状态层或后端能力决定是否持久化。
- 状态: 已确认

### [F-030] 排序弹层关闭后继续使用弹层 context 读取 Provider
- 级别: P1
- 分类: Bug / async gap 安全(P7)
- 位置: lib/screens/favorite_items_screen_sheets.dart:62
- 问题: `onTap` 先 `Navigator.of(context).pop()` 关闭 bottom sheet，随后继续用同一个 builder 传入的弹层 `context` 执行 `context.read<NasProvider>()`。弹层 context 在路由关闭后可能已失效，Provider 查找存在 “deactivated widget ancestor” 风险。关键代码摘录：
  ```dart
  Navigator.of(context).pop();
  if (_isFeiniuBackend) {
    await FeiniuApi(
      context.read<NasProvider>(),
    ).setUserListSetting(
  ```
- 建议方向: 在关闭弹层前捕获需要的 service/provider，或使用 State 自身仍挂载的上下文并在 await 前后检查 `mounted`；避免在 pop 后继续访问弹层 context。
- 状态: 已确认

### [F-031] 收藏卡片构建仍透传 NAS baseUrl/token 拼图片 URL
- 级别: P2
- 分类: 耦合 / 可扩展性 / 约束违规(C3)
- 位置: lib/screens/favorite_items_screen_widgets.dart:51
- 问题: 收藏列表 UI 从 `NasProvider` 取 `baseUrl/token` 传入 `_buildGrid`，再用 `_posterCandidates(baseUrl, item, ...)` 为卡片生成图片 URL，并把 NAS token 传给通用卡片组件。图片 URL 拼接和鉴权形态仍由页面层处理，后端差异没有收敛到 media backend 的图片 presenter。关键代码摘录：
  ```dart
  child: _buildGrid(
    tab: tab,
    baseUrl: provider.baseUrl,
    token: provider.token,
  ...
  urls: _posterCandidates(baseUrl, item, width: 280),
  token: token,
  ```
- 建议方向: 让 `MediaLibraryItem`/card presenter 提供已解析的图片候选与鉴权信息，页面组件只渲染 `ImageSource`/view model，避免直接接触 NAS baseUrl/token。
- 状态: 已确认

### [F-032] 人物详情页直接维护飞牛人物详情和作品分页路径
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/screens/person_detail_screen.dart:180
- 问题: 页面层直接导入 `FeiniuApi`，按 `MediaBackendKind.feiniu` 分流，飞牛人物详情、按职务作品分页、详情预取仍由页面直接调用具体 API；非飞牛路径则另走 `_loadNeutral`，后端差异泄漏到 UI 状态机。关键代码摘录：
  ```dart
  if (backend.capabilities.kind != MediaBackendKind.feiniu) {
    await _loadNeutral(backend);
    return;
  }

  final api = FeiniuApi(context.read<NasProvider>());
  ...
  await _loadNextPendingJob(
    FeiniuApi(context.read<NasProvider>()),
  ```
- 建议方向: 将人物详情、人物作品分页与详情预取统一收敛到 `MediaBackend` 或专职 detail service；页面只消费中立人物 profile、作品分组和打开详情所需 preview。
- 状态: 已确认

### [F-033] 人物作品和详情预取失败被静默降级
- 级别: P2
- 分类: 可维护性 / 错误处理(M4)
- 位置: lib/screens/person_detail_screen.dart:311
- 问题: 按职务加载作品失败时直接把该职务写成空列表，打开作品详情前的飞牛 detail 预取失败也空 `catch`；网络、权限或字段解析问题会表现为“没有作品”或“没有预填详情”，没有日志和阶段信息。关键代码摘录：
  ```dart
  } catch (_) {
    if (!mounted || loadVersion != _jobLoadVersion) return false;
    setState(() {
      _jobPages[job] = const ItemListPage(
        total: 0,
        items: <MediaLibraryItem>[],
  ...
  } catch (_) {}
  ```
- 建议方向: 对可降级请求记录 job/personGuid/itemGuid、action 和错误；UI 可继续空态，但排障信息不能丢。
- 状态: 已确认

### [F-034] 人物页图片 URL 拼接继续依赖 NAS baseUrl/token
- 级别: P2
- 分类: 耦合 / 可扩展性 / 约束违规(C3)
- 位置: lib/screens/person_detail_screen.dart:736
- 问题: 人物页 build 中直接读取 `NasProvider`，用 `ApiUrlHelper.personImageCandidates(provider.baseUrl, ...)` 构造动态取色、头像和作品海报 URL，并把 `provider.token` 传入图片组件。图片 URL 与鉴权策略仍散在页面层，且代码注释中显式区分 “Emby 完整直链 / 飞牛相对路径”。关键代码摘录：
  ```dart
  final provider = context.read<NasProvider>();
  ...
  _imageCandidates(
    provider.baseUrl,
    _person!.profilePath,
    width: 240,
  )
  ...
  token: provider.token,
  ```
- 建议方向: 由后端 presenter 输出人物头像、取色图源、作品海报的中立图片候选和鉴权描述；页面不要接触 NAS baseUrl/token 或按后端注释区分图片形态。
- 状态: 已确认

### [F-035] 简介“详情”链接的 TapGestureRecognizer 未释放
- 级别: P1
- 分类: 性能 / 资源泄漏(P6)
- 位置: lib/screens/person_detail_screen.dart:1111
- 问题: `_buildBiographyPreviewRaw` 在 `build` 路径里内联创建 `TapGestureRecognizer()` 并挂到 `TextSpan`，但 State 没有保存和 dispose。Flutter 的 recognizer 生命周期需要创建方管理；页面重建会持续产生未释放 recognizer。关键代码摘录：
  ```dart
  TextSpan(
    text: moreText,
    style: moreStyle,
    recognizer: TapGestureRecognizer()
      ..onTap = () => LongTextOverlayPage.show(
        context,
  ```
- 建议方向: 改成 `GestureDetector`/`InkWell` 包裹可点击文本，或把 recognizer 作为 State 字段并在 `dispose` 释放。
- 状态: 已确认

### [F-036] 中立人物头像网络图未限制解码尺寸
- 级别: P2
- 分类: 性能 / 图片解码尺寸(P3)
- 位置: lib/screens/person_detail_screen.dart:538
- 问题: `_buildNeutralProfileImage` 直接用 Emby 人物图片完整 URL `Image.network`，头像实际渲染在固定尺寸容器中，但没有 `cacheWidth/cacheHeight`；大头像原图会按原尺寸解码，进入人物详情首屏时可能增加内存和解码耗时。关键代码摘录：
  ```dart
  return Image.network(
    url,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.low,
    errorBuilder: (_, error, __) {
  ```
- 建议方向: 参考 `_PersonProfileImage` 用 `LayoutBuilder` + DPR 计算稳定 `cacheWidth/cacheHeight`，或让图片 presenter 提供受控尺寸 URL。
- 状态: 已确认

### [F-037] 媒体信息页直接调用 FeiniuApi 获取流元数据和 URL
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2)
- 位置: lib/screens/media_info_screen.dart:33
- 问题: 页面层直接导入 `FeiniuApi`，用手输 GUID 调 `getStreamMetadata`，并在 build helper 里实例化 API 生成播放流 URL。这个诊断页完全绕过 `media_backend`/service，无法支持 Emby/Jellyfin 等后端的媒体信息查看。关键代码摘录：
  ```dart
  final api = FeiniuApi(context.read<NasProvider>());
  final info = await api.getStreamMetadata(guid);
  ...
  final api = FeiniuApi(context.read<NasProvider>());
  final streamUrl = api.getStreamUrl(_guidController.text.trim());
  ```
- 建议方向: 把流元数据查询和播放 URL 生成放到后端抽象或专职诊断 service；页面只提交 media id 并显示中立 `MediaInfo`。
- 状态: 已确认

### [F-038] 媒体信息页 await 后 setState 未检查 mounted
- 级别: P1
- 分类: Bug / async gap 安全(P7)
- 位置: lib/screens/media_info_screen.dart:34
- 问题: `_fetchMetadata` 在 `await api.getStreamMetadata(guid)` 后直接 `setState`，异常路径同样直接 `setState`；用户在请求期间退出页面会触发 disposed State 更新。关键代码摘录：
  ```dart
  final info = await api.getStreamMetadata(guid);
  setState(() {
    _mediaInfo = info;
    _isLoading = false;
  });
  ...
  } catch (e) {
    setState(() {
  ```
- 建议方向: await 后先检查 `if (!mounted) return;`，并确保 success/catch 两条路径都不更新已卸载的 State。
- 状态: 已确认

### [F-039] 媒体信息页 TextEditingController 未 dispose
- 级别: P1
- 分类: 性能 / 资源泄漏(P6)
- 位置: lib/screens/media_info_screen.dart:17
- 问题: State 持有 `_guidController = TextEditingController()`，但类中没有 `dispose()` 释放 controller；反复进入该页面会泄漏监听资源。关键代码摘录：
  ```dart
  class _MediaInfoScreenState extends State<MediaInfoScreen> {
    final _guidController = TextEditingController();
    MediaInfo? _mediaInfo;
  ```
- 建议方向: 增加 `dispose`，调用 `_guidController.dispose()` 后再 `super.dispose()`。
- 状态: 已确认

### [F-040] 媒体信息页 UI 文案全部硬编码英文
- 级别: P2
- 分类: 可维护性 / i18n(M3)
- 位置: lib/screens/media_info_screen.dart:53
- 问题: 页面标题、输入提示、列表字段、空值、流信息等展示文本都写死英文，未走 `AppLocalizations`。关键代码摘录：
  ```dart
  appBar: AppBar(title: const Text('Media Info Viewer')),
  ...
  labelText: 'Media GUID',
  hintText: 'Enter media_guid',
  ...
  title: const Text('Filename'),
  subtitle: Text(info.fileStream?.filename ?? 'Unknown'),
  ```
- 建议方向: 为这些诊断展示文案补充 arb getter；如果该页仅供内部调试，也应明确隔离在调试入口，避免用户可见页面绕过 i18n。
- 状态: 已确认

### [F-041] 详情路由 payload 读取错误被当作空 payload 处理
- 级别: P2
- 分类: 可维护性 / 错误处理(M4)
- 位置: lib/screens/detail_route_bodies.dart:65
- 问题: `FutureBuilder` 只判断 `connectionState`，完成后直接读取 `snapshot.data`，没有处理 `snapshot.hasError`。`DetailRoutePayloadStore.readPayload` 失败时会静默降级为 `widget.initialItemDetail`/`seasonItem`，可能让详情页以缺失初始数据继续渲染且没有日志。关键代码摘录：
  ```dart
  return FutureBuilder<Map<String, dynamic>?>(
    future: payloadFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return DetailLoadingSkeleton(presentation: widget.presentation);
      }
      final payload = snapshot.data;
  ```
- 建议方向: 显式处理 `snapshot.hasError`，至少记录 payloadToken 和错误；必要时展示状态页或带 retry 的错误态。
- 状态: 已确认

### [F-042] 详情路由状态页错误文案硬编码英文
- 级别: P2
- 分类: 可维护性 / i18n(M3)
- 位置: lib/screens/detail_route_bodies.dart:50
- 问题: 缺少 item/season 参数时传给 `_DetailRouteStatusScreen` 的用户可见消息写死英文，未走 `AppLocalizations`。关键代码摘录：
  ```dart
  return const _DetailRouteStatusScreen(
    message: 'Missing detail route params',
  );
  ...
  return const _DetailRouteStatusScreen(
    message: 'Missing season detail params',
  );
  ```
- 建议方向: 为路由参数缺失状态补充本地化 getter，或让状态页接收语义枚举后在 build 中读取 `AppLocalizations`。
- 状态: 已确认

### [F-043] 副栏路由参数 JSON 在 build 中无保护解析
- 级别: P1
- 分类: Bug / 错误处理(M4)
- 位置: lib/screens/detail_host_screen.dart:452
- 问题: `_buildRouteChild` 在构建路由页时直接 `jsonDecode` query 参数中的 `initialItemDetail`、`seasonItem`、`category`、`types`，没有 try/catch。平台或深链传入畸形 JSON 时会在 build 阶段抛异常，导致副栏详情 host 崩溃，而不是显示路由错误页。关键代码摘录：
  ```dart
  final decodedInitialItemDetail = rawInitialItemDetail.isEmpty
      ? null
      : (jsonDecode(rawInitialItemDetail) as Map).cast<String, dynamic>();
  ...
  final decodedCategory = rawCategory.isEmpty
      ? const <String, dynamic>{}
      : (jsonDecode(rawCategory) as Map).cast<String, dynamic>();
  ```
- 建议方向: 把 query JSON 解析收敛成安全 helper，捕获 `FormatException`/类型转换错误并返回 `_DetailHostRouteError`，同时记录原始 route 便于排查。
- 状态: 已确认

### [F-044] 副栏路由错误页文案硬编码英文
- 级别: P2
- 分类: 可维护性 / i18n(M3)
- 位置: lib/screens/detail_host_screen.dart:443
- 问题: `_DetailHostRouteError` 的所有消息都由调用点写死英文，包括参数缺失和未找到页面，用户可见但未走 `AppLocalizations`。关键代码摘录：
  ```dart
  return const _DetailHostRouteError(message: 'Invalid route format');
  ...
  return const _DetailHostRouteError(
    message: 'Missing person detail parameters',
  );
  ...
  return const _DetailHostRouteError(message: 'Page not found');
  ```
- 建议方向: 让错误页接收错误类型枚举，在 build 中读取本地化文案；或为各路由错误补充 arb getter。
- 状态: 已确认

## 总结

- 本任务完成 19 个详情/浏览相关文件的第一轮逐文件评审与第二轮自复核，共确认 44 条 findings，无撤回项。
- 问题分布以多后端迁移耦合为主：详情页、收藏页、分类页、人物页仍有大量 UI 层直接调用 `FeiniuApi` 或按 `MediaBackendKind.feiniu` 分流。
- 可维护性重点是三个详情页超大且重复、空 `catch` 静默降级、路由/诊断页硬编码英文文案。
- 性能与稳定性重点包括 build 路径同步文件检查、未限制头像解码尺寸、`TapGestureRecognizer`/`TextEditingController` 生命周期问题、await 后缺少 `mounted`。
- 优先建议处理 F-007/F-010/F-015/F-032 的后端抽象泄漏，F-035/F-039 的资源释放，F-043 的副栏路由崩溃风险，以及 F-006/F-014/F-016 的详情页拆分。
