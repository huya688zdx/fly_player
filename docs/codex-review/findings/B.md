<!-- CHECKPOINT
已审文件数: 55 / 55
最后完成: lib/utils/tv_hero_adaptive.dart
下一个: 无
阶段: 已完成
更新时间: 2026-07-02 20:27
-->

# TASK B findings

### [B-001] 日志导出入口会在 UI 查询中同步读取 crash journal
- 级别: P1
- 分类: 性能
- 位置: lib/services/app_log_service.dart:132
- 问题: `hasExportableLogs` 是给导出按钮放行的 getter，但会同步检查并读取 crash journal；journal 上限为 256KB，设置页刷新或按钮状态计算时会在主 isolate 触发磁盘 IO。
  ```dart
  bool get hasExportableLogs {
    if (_entries.isNotEmpty) return true;
    return _crashJournalHasContent(_runtimeCrashJournalFile()) ||
        _crashJournalHasContent(_nativeCrashJournalFile());
  }

  bool _crashJournalHasContent(File file) {
    try {
      return file.existsSync() && file.readAsStringSync().trim().isNotEmpty;
  ```
- 建议方向: 初始化或 journal 写入后维护异步缓存状态，UI getter 只读内存；确需读取文件时改为显式 async 方法并避免在 build/按钮状态计算链路中调用。
- 状态: 已确认

### [B-002] 日志持久化失败被空 catch 完全吞掉
- 级别: P2
- 分类: 可维护性 / 错误处理
- 位置: lib/services/app_log_service.dart:462
- 问题: `_persist()` 负责把内存日志落盘，但任意编码、写临时文件、rename 失败都会被空 `catch` 吞掉；用户只能看到日志消失，后续也没有可追踪线索。
  ```dart
  Future<void> _persist() async {
    try {
      final list = _entries
          .map((entry) => entry.toJson())
          .toList(growable: false);
      final encoded = await compute(_encodeLogEntries, list);
      final file = _logsFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  ```
- 建议方向: 至少写入 crash journal / debugPrint / 内存故障标记中的一种，避免递归调用 `record()` 即可；导出界面可暴露最近一次持久化失败。
- 状态: 已确认

### [B-003] 运行时缓存转发 loader 异常时丢失原始堆栈
- 级别: P2
- 分类: 可维护性 / 错误处理
- 位置: lib/services/detail_runtime_cache.dart:54
- 问题: `onError` 收到了 `StackTrace` 却直接 `throw error`，Dart 会把重新抛出点作为新的堆栈来源，导致真正的加载失败位置在上层日志中丢失。
  ```dart
  final future = loader().then<Object?>(
    (value) {
      bucketCache.remove(normalizedKey);
      bucketCache[normalizedKey] = value;
      while (bucketCache.length > _maxEntriesPerBucket) {
        bucketCache.remove(bucketCache.keys.first);
      }
      _inflight.remove(inflightKey);
      return value;
    },
    onError: (Object error, StackTrace stackTrace) {
      _inflight.remove(inflightKey);
      throw error;
  ```
- 建议方向: 使用 `Error.throwWithStackTrace(error, stackTrace)` 或改为 `try/finally` 清理 `_inflight`，保留原始故障现场。
- 状态: 已确认

### [B-004] 下载服务把飞牛后端、文件恢复、封面缓存和弹幕预取揉成一个上帝服务
- 级别: P1
- 分类: 约束违规(C3) / 单一职责(C6) / 可扩展性
- 位置: lib/services/download_task_service.dart:13
- 问题: `DownloadTaskService` 位于通用 services 层，却直接依赖 `FeiniuApi`、`NasProvider`、弹幕 API 与存储服务；尾部恢复查找类也把 `NasProvider` 固定包装成 `FeiniuApi`。下载、后端元数据搜索、封面缓存、字幕物化、弹幕预取、本地持久化都集中在一个 5k+ 行类里，新增 Emby/Jellyfin 下载或恢复逻辑时必须继续改这个公共服务。
  ```dart
  import '../api/feiniu_api.dart';
  import '../danmaku/api/dandanplay_api.dart';
  import '../danmaku/api/dandanplay_config.dart';
  import '../danmaku/api/dandanplay_resolver.dart';
  import '../providers/nas_provider.dart';
  ...
  class _RecoveredBackendLookup {
    final NasProvider provider;
    final FeiniuApi api;
  ```
- 建议方向: 把下载任务编排、后端下载/元数据能力、文件恢复、封面/字幕/弹幕副作用拆成独立协作者；后端差异收敛到 `media_backend` 或专门的下载 backend adapter。
- 状态: 已确认

### [B-005] 下载总量 getter 会同步遍历本地文件长度
- 级别: P1
- 分类: 性能
- 位置: lib/services/download_task_service.dart:250
- 问题: `downloadedBytes` 是同步 getter，会遍历所有记录并对每个已下载文件执行 `lengthSync()`。下载页、设置页统计或 Provider rebuild 读取该值时，记录越多越容易在主 isolate 上触发磁盘 IO 卡顿。
  ```dart
  int get downloadedBytes {
    var total = 0;
    for (final record in _records) {
      if (!_isDownloadedRecordAvailable(record)) continue;
      try {
        total += File(record.filePath).lengthSync();
      } catch (_) {
        total += record.totalBytes;
      }
  ```
- 建议方向: 在下载完成、恢复扫描、删除记录时异步维护已下载字节缓存；UI getter 只读内存，必要时提供显式刷新接口。
- 状态: 已确认

### [B-006] “立即持久化”没有等待落盘且多个写入共用同一个 tmp 文件
- 级别: P0
- 分类: Bug / 持久化一致性 / 错误处理
- 位置: lib/services/download_task_service.dart:1847
- 问题: `_upsertRecord(... persistImmediately: true)` 实际只是 `unawaited(_persist())`，调用方即使 `await` 下载完成/删除流程也不能保证记录已落盘；下载流每 512KB、完成、弹幕元数据更新等路径还可能并发进入 `_persist()`，共用同一个 `.tmp` 文件，任一写入/rename 失败又被空 `catch` 吞掉，可能丢失最新下载状态。
  ```dart
  if (persistImmediately) {
    unawaited(_persist());
    _persistTimer?.cancel();
    _persistTimer = null;
  }
  ...
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(encoded, flush: true);
  await tmp.rename(file.path);
  } catch (_) {}
  ```
- 建议方向: 串行化持久化队列，`persistImmediately` 返回可等待的 Future；使用唯一临时文件或写入锁，并记录持久化失败。
- 状态: 已确认

### [B-007] 下载转码进度轮询可能重入并发请求
- 级别: P1
- 分类: 性能 / Bug
- 位置: lib/services/download_task_service.dart:4293
- 问题: `Timer.periodic` 每 2 秒 `unawaited(pollOnce())`，但 `pollOnce` 内部会等待网络请求；如果 `getDownloadTaskProgress` 超过一个周期，下一轮会并发发起，后返回的旧请求仍可能覆盖 `_downloadTaskProgress` 并触发 `notifyListeners()`，造成重复网络压力和进度抖动。
  ```dart
  Future<void> pollOnce() async {
    ...
    final progress = await api.getDownloadTaskProgress(
      activeRecord.remoteTaskId,
    );
    ...
    _downloadTaskProgress[record.id] = normalized;
    notifyListeners();
  }

  _downloadTaskProgressPollers[record.id] = Timer.periodic(
    _taskProgressPollInterval,
    (_) => unawaited(pollOnce()),
  );
  ```
- 建议方向: 为每个 record 增加 in-flight 标记或改成 await 完成后再 delay 的循环，确保同一任务同一时间只有一个进度请求。
- 状态: 已确认

### [B-008] 离线封面解析入口同步扫目录和读取文件长度
- 级别: P1
- 分类: 性能
- 位置: lib/services/download_task_service.dart:4594
- 问题: `resolveExistingLocalCover()` 是同步方法，先查记录中的本地 URL，再调用 `_probeDownloadedCoverFiles()`；后者同步 `existsSync()`、`listSync()`、`lengthSync()` 扫视频目录、`_artwork` 和分组目录。离线选集面板或列表批量解析封面时会在主 isolate 上按记录数做目录扫描。
  ```dart
  String resolveExistingLocalCover(DownloadTaskRecord record) {
    final fromRecord = _existingLocalArtworkUrls(<String>[
      ...record.posterUrls,
      ...record.groupPosterUrls,
    ]);
    if (fromRecord.isNotEmpty) return fromRecord.first;
    final probed = _probeDownloadedCoverFiles(record.filePath);
  ...
  if (!dir.existsSync()) continue;
  for (final entity in dir.listSync(followLinks: false)) {
    ...
    if (entity.lengthSync() <= 0) continue;
  ```
- 建议方向: 下载/恢复时把本地封面候选异步写回记录，展示路径只读记录字段；兜底目录扫描改成异步并缓存结果。
- 状态: 已确认

### [B-009] 缓存导入失败被静默降级，用户和日志都看不到原因
- 级别: P2
- 分类: 错误处理 / 可维护性
- 位置: lib/services/download_task_service.dart:1347
- 问题: 缓存导入前置检查、缓存提升和整体导入过程多处 `catch (_) { return null; }`，调用方会把它当作“无可导入缓存”继续创建下载任务；真实的存储权限、文件移动或缓存服务异常没有日志，容易造成重复下载或缓存残留。
  ```dart
  try {
    downloadability = await storageService.canPromoteCachedMedia(identity);
  } catch (_) {
    return null;
  }
  ...
  try {
    promoteResult = await storageService.promoteCachedMedia(
      identity,
      targetMode: 'appExternalMovies',
    );
  } catch (_) {
    return null;
  }
  ```
- 建议方向: 对缓存服务异常至少记录 `AppLogService` warning，并区分“确实不可导入”和“导入过程失败”；必要时向启动下载结果暴露失败原因。
- 状态: 已确认

### [B-010] Emby 原生选集适配泄漏在通用 services 层
- 级别: P2
- 分类: 约束违规(C3) / 可扩展性
- 位置: lib/services/emby_native_picker_support.dart:10
- 问题: 文件名、类名和注释都直接绑定 Emby，并放在通用 `lib/services/`；虽然数据读取使用了 `MediaBackend`，但“某后端如何适配原生壳选集”的差异仍泄漏到公共服务层。后续 Jellyfin 或其它后端如果也需要类似原生壳补齐，容易继续新增并列 `*_native_picker_support.dart`。
  ```dart
  /// Emby 原生壳「选集」反向通道支持。
  ///
  /// 对位飞牛 [NativeReentrySupport] 的选集三方法（loadEpisodePickerData /
  /// loadSeasonEpisodes / setEpisodePickerViewType），但数据源是**后端中立** [MediaBackend]
  ...
  class EmbyNativePickerSupport {
  ```
- 建议方向: 抽成后端中立的 native picker adapter 接口/实现，或收敛到 `media_backend` 的后端能力扩展中，避免通用 service 以后端专名扩张。
- 状态: 已确认

### [B-011] 登录历史和后端连接把密码/token 明文写入 SharedPreferences
- 级别: P1
- 分类: Bug / 持久化一致性
- 位置: lib/services/login_history_store.dart:47
- 问题: 登录历史序列化始终包含 `password` 字段，后端连接存储也把 access token 写入 SharedPreferences JSON；SharedPreferences 不是安全凭据存储，设备备份、root/调试导出或日志抓取时会扩大账号凭据暴露面。
  ```dart
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': kind.name,
      'baseUrl': baseUrl,
      'userName': userName,
      'password': password,
      'rememberPassword': rememberPassword,
  ```
- 建议方向: 密码和 token 使用平台安全存储；历史记录只保留后端、地址、用户名和 remember 标志，未勾选记住密码时确保落盘值为空并可迁移清除旧明文。
- 状态: 已确认

### [B-012] 原生播放反向通道在 service 层按后端类型分支
- 级别: P1
- 分类: 约束违规(C3) / 可扩展性
- 位置: lib/services/native_playback_reentry.dart:53
- 问题: `NativePlaybackReentry.bind()` 直接判断 `backend.capabilities.kind == MediaBackendKind.feiniu`，飞牛分支绑定 `NativeReentrySupport`，其它后端默认走 Emby 逻辑和 `EmbyNativePickerSupport`。这把后端差异泄漏到通用 service，第三个后端接入时必须继续修改这个分支。
  ```dart
  if (backend.capabilities.kind == MediaBackendKind.feiniu) {
    return NativePlayerBridge.bindReentry(
      onResolvePlayback: onResolvePlayback,
      onRecordProgress: (progress) =>
          NativeReentrySupport.recordProgress(nas, progress),
      ...
    );
  }
  ...
  final reporter = EmbyPlaybackReporter(backend);
  ```
- 建议方向: 让 `MediaBackend` 暴露原生重入能力对象，或用 registry/factory 按 backend adapter 提供回调集；通用绑定层只消费接口，不写具体后端分支。
- 状态: 已确认

### [B-013] 原生弹幕预取缓存和 payload 文件没有上限或清理
- 级别: P2
- 分类: 资源泄漏(P6)
- 位置: lib/services/native_danmaku_prefetch.dart:479
- 问题: 评论缓存按 `sourceKey.hashCode` 写入 `Directory.systemTemp`，payload 又按毫秒时间戳每次生成新 JSON；代码没有 TTL、数量/大小上限或清理旧文件。长时间切集、搜索、导入弹幕会持续在 app cache 目录累积文件。
  ```dart
  static File _commentCacheFile(String sourceKey) {
    final safeKey = sourceKey.hashCode.toUnsigned(32).toRadixString(16);
    return File(
      '${Directory.systemTemp.path}/native_danmaku_cache_$safeKey.json',
    );
  }
  ...
  final file = File(
    '${Directory.systemTemp.path}/native_danmaku_'
    '${DateTime.now().millisecondsSinceEpoch}.json',
  );
  ```
- 建议方向: 给缓存目录建立统一前缀清理策略，按最近访问时间/总大小淘汰；payload 文件可复用固定 mediaKey 路径或在原生读取完成后清理。
- 状态: 已确认

### [B-014] Emby 原生进度上报失败会静默丢失
- 级别: P2
- 分类: 错误处理 / Bug
- 位置: lib/services/native_playback_reentry.dart:127
- 问题: `EmbyPlaybackReporter.report()` 首次进度会先 `reportPlaybackStart`，切集会先 `reportPlaybackStopped`，随后 `reportPlaybackProgress`；任一步失败都被空 `catch` 吞掉。飞牛分支至少会把 transient 进度写入 `PlaybackProgressOfflineQueue`，Emby 分支断网/超时会直接丢续播位且无日志。
  ```dart
  try {
    if (itemGuid != _itemId) {
      if (_itemId.isNotEmpty) {
        await backend.reportPlaybackStopped(
          itemId: _itemId,
          mediaSourceId: _mediaId,
          positionSeconds: _lastTs,
        );
      }
      _itemId = itemGuid;
      await backend.reportPlaybackStart(
  ...
  } catch (_) {}
  ```
- 建议方向: 至少记录 warning；可复用离线进度队列的抽象，让后端 reporter 区分可恢复网络错误和不可恢复错误。
- 状态: 已确认

### [B-015] play_stats 元数据回填直接绑定飞牛 API
- 级别: P1
- 分类: 约束违规(C3) / 可扩展性
- 位置: lib/services/play_stats/play_stats_backfill_service.dart:6
- 问题: 播放统计模块本应服务于多媒体后端的统一统计，但元数据回填服务直接依赖 `FeiniuApi` 和 `NasProvider`，并在 `_run()` 内按飞牛接口拉详情、人物列表。Emby/Jellyfin 的统计元数据补全无法复用该服务，只能继续在 play_stats 内加后端分支或另起平行实现。
  ```dart
  import '../../api/feiniu_api.dart';
  import '../../api/person_list_request.dart';
  import '../../providers/nas_provider.dart';
  ...
  Future<void> _run({required NasProvider provider, required int limit}) async {
    _scheduledTimer?.cancel();
    final api = FeiniuApi(provider);
  ```
- 建议方向: 定义播放统计元数据 provider/adapter，由各 `MediaBackend` 实现详情、季、人物等查询；play_stats 只消费中立接口。
- 状态: 已确认

### [B-016] 每补全一个视频都会删除并重建全部聚合表
- 级别: P1
- 分类: 性能
- 位置: lib/services/play_stats/play_stats_backfill_service.dart:279
- 问题: `_backfillSingleVideo()` 在单个视频的事务里更新 `video_stats` 后立即调用 `_rebuildAggregateTables(txn)`；该方法删除整张 `season_stats`、`anime_stats`，再从 `video_stats`/`play_history` 全表聚合并逐行 insert。一次回填批次最多 8 个视频，会重复执行 8 次全表重建。
  ```dart
  await _database.transaction<void>((txn) async {
    await txn.update(
      'video_stats',
      <String, Object?>{
        'anime_id': effectiveAnimeId,
        ...
      },
      where: 'video_id = ?',
      whereArgs: <Object?>[normalizedVideoId],
    );
    ...
    await _rebuildAggregateTables(txn);
  });
  ```
- 建议方向: 批次内先更新所有视频和演职员，最后重建一次聚合表；更好是按受影响的 season/anime 增量重算，避免全表 delete/insert。
- 状态: 已确认

### [B-017] 报表详情页按范围全量加载历史并在 Dart 内多轮聚合
- 级别: P1
- 分类: 性能
- 位置: lib/services/play_stats/play_stats_summary_repository.dart:55
- 问题: `loadReportSnapshot()` 查询指定范围内所有 `play_history`，`all` 范围没有 limit；随后取关联视频和所有 season，再交给 `PlayStatsReportAggregator` 在 Dart 内排序、分桶、排行、热力图、人物亲和等多轮遍历。历史越多，打开统计报表越容易出现大内存分配和主 isolate 聚合卡顿。
  ```dart
  final historyRows = await db.query(
    'play_history',
    where: _rangeWhereClause(range),
    whereArgs: _rangeWhereArgs(range),
    orderBy: 'started_at_ms DESC',
  );
  final histories = historyRows
      .map((row) => PlayStatsSqlMapper.playHistoryFromMap(row))
      .toList(growable: false);
  ```
- 建议方向: 对趋势、热力、分布、top 榜使用 SQL 聚合和分页；`all` 范围也应有可控上限或后台 isolate 聚合。
- 状态: 已确认

### [B-018] SQLite 数据库打开缺少并发保护，可能重复 open 同一作用域
- 级别: P2
- 分类: 资源泄漏(P6) / 持久化一致性
- 位置: lib/services/play_stats/play_stats_database.dart:53
- 问题: `rawDatabase` 只检查 `_database`，没有 `_openingFuture`。多个统计入口冷启动并发调用时，都可能在 `_database` 仍为 null 时执行 `openDatabase()`，后完成者覆盖 `_database`，先打开的连接没有被关闭。
  ```dart
  Future<Database> get rawDatabase async {
    final existing = _database;
    if (existing != null) return existing;
    final databasesPath = await getDatabasesPath();
    final databasePath = p.join(databasesPath, _databaseFileNameForScope());
    final database = await openDatabase(
      databasePath,
      version: databaseVersion,
  ```
- 建议方向: 增加 `_openingDatabase` Future 去重，并在 `bindOwnerScope()` 中等待或取消旧打开流程后再切换作用域。
- 状态: 已确认

### [B-019] 存储管理 service 反向依赖 Provider 和主题运行时
- 级别: P2
- 分类: 耦合 / 约束违规(C1)
- 位置: lib/services/storage_management_service.dart:13
- 问题: `StorageManagementService` 位于 services 层，却直接 import `AppThemeProvider`、`ParallelWindowSettingsProvider` 以及主题 runtime，并在 `clearSavedThemes/resetSettings` 中要求传入 provider 后调用 `load()`。这让服务层反向依赖状态层/主题层，违反 UI/状态 → service 的单向依赖。
  ```dart
  import '../providers/app_theme_provider.dart';
  import '../providers/parallel_window_settings_provider.dart';
  import '../theme/app_theme.dart';
  import '../theme/dynamic_theme_runtime_controller.dart';
  import '../theme/dynamic_theme_seed_extractor.dart';
  ...
  Future<void> clearSavedThemes(AppThemeProvider themeProvider) async {
  ```
- 建议方向: service 只执行存储清理并返回结果；provider 自己在上层响应结果后刷新状态，主题 cache 清理可抽到不依赖 provider 的专用 store。
- 状态: 已确认

### [B-020] 存储统计漏算按账号作用域拆分的 play_stats 数据库
- 级别: P2
- 分类: Bug / 持久化一致性
- 位置: lib/services/storage_management_service.dart:890
- 问题: 播放统计数据库支持 `bindOwnerScope()` 后改用 `play_stats_<scope>.db` 文件名，但存储概览只统计固定的 `play_stats.db/-wal/-shm`，多账号/多后端切换后实际统计数据库占用不会显示在 AppData 的 playStatsBytes 中。
  ```dart
  final basePath = p.join(
    databasesPath,
    SqflitePlayStatsDatabase.databaseName,
  );
  var total = 0;
  for (final path in <String>[basePath, '$basePath-wal', '$basePath-shm']) {
    final file = File(path);
    if (await file.exists()) {
      total += await file.length();
    }
  }
  ```
- 建议方向: 复用 `SqflitePlayStatsDatabase` 的作用域命名规则或扫描 `play_stats*.db` 及其 wal/shm；清理/展示也应按当前 owner scope 或全部 scope 明确区分。
- 状态: 已确认

### [B-021] 全局 URL 工具写死飞牛媒体接口路径
- 级别: P1
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/utils/api_url_helper.dart:4
- 问题: `ApiUrlHelper` 是被 pages/controllers/api/player 复用的全局工具，但内部常量和拼接逻辑硬编码飞牛图片、流媒体接口，公共层调用它时默认继承单一后端 URL 规则，后续接 Jellyfin/其他后端需要继续改公共工具。
  ```dart
  static const String _apiImagePrefix = '/v/api/v1/sys/img';
  static const String _directImagePrefix = '/sys/img';
  static const String _vImagePrefix = '/v/sys/img';
  ...
  final uri = Uri.parse('$origin/v/api/v1/media/range/$guid');
  ```
- 建议方向: 将飞牛 URL 候选和 stream URL 拼接下沉到 `FeiniuMediaBackend`/飞牛 API 适配层；全局工具只保留通用 URI normalization。
- 状态: 已确认

### [B-022] 播放源创建时同步扫描本地字幕目录
- 级别: P1
- 分类: 性能
- 位置: lib/utils/local_subtitle_bundle.dart:24
- 问题: `discoverLocalSubtitleBundle()` 使用 `existsSync()` 和 `directory.listSync()` 扫描视频所在目录；调用点在 `MpvMediaSource` 构造路径中，播放启动或切源时会在主 isolate 同步扫目录，目录中文件多或外置存储较慢时会阻塞起播。
  ```dart
  final videoFile = File(normalizedVideoPath);
  if (!videoFile.existsSync()) return LocalSubtitleBundle.empty;
  ...
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! File) continue;
  ```
- 建议方向: 改为异步发现并缓存结果，播放启动只接收已解析的字幕 bundle；必要时把目录扫描放到后台 isolate 或限制扫描范围。
- 状态: 已确认

### [B-023] AsyncActionGuard 的清理 Future 会把失败重新变成未处理异步错误
- 级别: P2
- 分类: Bug / 错误处理
- 位置: lib/utils/async_action_guard.dart:36
- 问题: `sharedFuture.whenComplete()` 的返回 Future 被 `unawaited` 丢弃；当 `actionFuture` 失败时，`whenComplete` 返回的 Future 也会以同一错误完成，即使调用方处理了 `actionFuture`，这个旁路 Future 仍可能触发未处理异步错误。
  ```dart
  final actionFuture = Future<T>.sync(action);
  final sharedFuture = actionFuture.then<Object?>((value) => value);
  _inFlight[normalizedKey] = sharedFuture;

  unawaited(
    sharedFuture.whenComplete(() async {
  ```
- 建议方向: 清理链路使用 `then(..., onError: ...)` 或在 unawaited 分支显式吞掉/记录错误，确保错误只沿调用方返回的 Future 传播。
- 状态: 已确认

### [B-024] 登录错误解析器在全局 utils 中依赖飞牛异常类型
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/utils/login_error_resolver.dart:3
- 问题: `LoginErrorResolver` 位于全局 utils，却直接 import `feiniu_api.dart` 并识别 `FnConnectLoginException`、`fn connect` 等飞牛专名；连接页和 Web 登录页复用该 resolver 时，公共登录错误通道被飞牛语义污染。
  ```dart
  import '../api/feiniu_api.dart';
  ...
  if (error is FnConnectLoginException) {
    return error.error;
  }
  ```
- 建议方向: 定义后端中立的登录异常/错误码模型；飞牛 Fn Connect 文案映射留在飞牛登录适配层，公共 resolver 只处理通用网络、证书、鉴权分类。
- 状态: 已确认

### [B-025] 语言标签工具硬编码中文 UI 文案
- 级别: P1
- 分类: i18n / 约束违规(M3)
- 位置: lib/utils/media_language_mapper.dart:4
- 问题: `MediaLanguageMapper` 直接保存并返回中文语言名、未知音频/未知语言等展示文案；这些值会被音轨/字幕列表和详情信息 UI 直接展示，绕过 `AppLocalizations`。
  ```dart
  static final Map<String, String> _languageNameMap = {
    'ara': '\u963f\u62c9\u4f2f\u8bed',
    'ar': '\u963f\u62c9\u4f2f\u8bed',
  ...
  if (name == '\u672a\u77e5') return '\u672a\u77e5\u97f3\u9891';
  ```
- 建议方向: mapper 只归一化语言代码；展示层用 `AppLocalizations` 或 locale-aware language display provider 生成标签，未知/默认后缀也走 arb。
- 状态: 已确认

### [B-026] NAS 图片 header 工具混入 FN Connect/Emby 中转 Cookie 规则
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/utils/nas_image_headers.dart:10
- 问题: 全局 `nasImageHeaders()` 同时写入飞牛 `Trim-MC-token`、判断 `fnos.net`、并在注释中声明 Emby 直链需要 `entry-token`；这些后端差异散落在公共 utils，新增后端或调整中转规则时仍要改公共函数。
  ```dart
  headers['Trim-MC-token'] = trimmedToken;
  if (usesFnConnectRelayCookie(url)) {
    headers['Cookie'] = 'mode=relay';
  }
  ...
  return host == 'fnos.net' || host.endsWith('.fnos.net');
  ```
- 建议方向: 图片/播放 headers 由各 `MediaBackend` 或其 artwork resolver 生成；公共 UI 只接收已解析好的 URL 与 headers。
- 状态: 已确认

### [B-027] 全局 HttpOverrides 对任意 IP 主机跳过证书校验
- 级别: P1
- 分类: Bug / 安全风险
- 位置: lib/utils/private_network_http_overrides.dart:19
- 问题: `PrivateNetworkHttpOverrides` 是全局 `Image.network` 证书策略，但 `_isPrivateHost()` 对任何能解析为 IP 的 host 都返回 true，不区分 RFC1918/localhost/link-local；外部公网 IP 的 HTTPS 图片也会绕过证书校验。
  ```dart
  client.badCertificateCallback = (cert, host, port) {
    return _isPrivateHost(host);
  };
  ...
  if (address != null) {
    return true;
  }
  ```
- 建议方向: 只允许已注册 NAS host 或明确私网/loopback/link-local 地址跳过校验；公网 IP 必须走正常证书校验。
- 状态: 已确认

### [B-028] mpv 本地代理直接绑定 FeiniuApi，播放通道无法后端中立
- 级别: P1
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/player/services/mpv_proxy_server.dart:7
- 问题: TASK B 点名的播放代理位于 player 服务层，但 `registerStream()` 强制要求 `FeiniuApi` 并调用飞牛签名 header；代理能力因此不能被 Emby/Jellyfin 等后端复用，公共播放器服务继续依赖具体后端 API。
  ```dart
  import '../../api/feiniu_api.dart';
  ...
  Future<MpvProxyRegistration> registerStream({
    required FeiniuApi api,
    required String remoteUrl,
  }) async {
  ```
- 建议方向: 抽出后端中立的代理签名/headers provider 接口，由各 media backend 提供实现；mpv 代理只处理本地 HTTP 转发、Range 和连接生命周期。
- 状态: 已确认

### [B-029] mpv 代理 session 没有超时回收机制
- 级别: P2
- 分类: 资源泄漏(P6)
- 位置: lib/player/services/mpv_proxy_server.dart:22
- 问题: `_sessions` 只在显式 `unregister()` 时删除，`createdAt` 写入后没有使用；如果页面异常退出、原生侧未回调或注册后起播失败，session 会一直留在单例代理里并持有 `FeiniuApi`/URL。
  ```dart
  final Map<String, _ProxySession> _sessions = <String, _ProxySession>{};
  ...
  _sessions[sessionId] = _ProxySession(
    api: api,
    remoteUri: remoteUri,
    createdAt: DateTime.now(),
  );
  ```
- 建议方向: 加 idle TTL/最大 session 数清理，并在每次 register/request 时清扫过期项；异常起播路径也应确保 unregister。
- 状态: 已确认

## 总结

TASK B 第一轮 55/55 文件已完成，第二轮自复核 29 条 findings 均已确认，无撤回项。

问题主要集中在三类：服务层和工具层泄漏飞牛/Emby/FN Connect 后端语义；下载、播放统计、字幕发现等播放链路存在主 isolate 同步 IO 或全量聚合；若干持久化/缓存路径错误被吞掉或缺少并发保护。

优先建议处理：B-006 下载记录持久化竞态和潜在状态丢失；B-028 mpv 代理绑定 FeiniuApi；B-021/B-026 公共 URL/header 工具后端耦合；B-022 本地字幕同步扫目录阻塞起播；B-017/B-016 播放统计全量加载/重建聚合表性能问题。
