<!-- CHECKPOINT
已审文件数: 47 / 47
最后完成: lib/player/widgets/player_system_controls.dart
下一个: 无
阶段: 已完成
更新时间: 2026-07-02 16:05
-->

# TASK E findings

### [E-001] 评论接口的业务错误会被解析兜底吞掉
- 级别: P1
- 分类: Bug / 可维护性
- 位置: lib/danmaku/api/dandanplay_api.dart:242
- 问题: `fetchComments()` 用 `_throwIfCommentPayloadError()` 识别服务端返回的 JSON 错误，但 `_throwIfBusinessError(payload)` 抛出的 `DanDanPlayApiException` 会被同一层 `catch (_)` 捕获并直接 `return`，导致鉴权/限流/业务错误被当作正常评论内容返回，调用方无法展示失败原因。
  ```dart
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return;
    final payload = Map<String, dynamic>.from(decoded);
    _throwIfBusinessError(payload);
  } catch (_) {
    return;
  }
  ```
- 建议方向: 只捕获 `jsonDecode`/类型转换失败，或单独 `on DanDanPlayApiException { rethrow; }`，确保业务错误沿调用链抛给 UI 反馈层。
- 状态: 已确认

### [E-002] DanDanPlay 配置类直接创建平台通道
- 级别: P2
- 分类: 约束违规(C5) / 耦合
- 位置: lib/danmaku/api/dandanplay_config.dart:62
- 问题: 弹幕 API 配置类直接持有 `MethodChannel` 并散落平台方法名，违反平台通道应收敛在明确桥接文件/服务/store 中的约束；后续 DanDanPlay 凭据来源或通道契约调整时，API 层会继续耦合平台实现。
  ```dart
  static const MethodChannel _channel = MethodChannel(
    'fly_player/secret_store',
  );
  ...
  await _channel.invokeMethod<void>('clearDanDanPlayConfig');
  ...
  'getDanDanPlayConfig',
  ```
- 建议方向: 将通道名与方法名迁移到专职 bridge/service，`DanDanPlayConfig` 只依赖抽象后的配置加载接口或纯数据结果。
- 状态: 已确认

### [E-003] 弹幕状态摘要绕过 AppLocalizations 直接硬编码英文
- 级别: P2
- 分类: 约束违规(M3) / 可维护性
- 位置: lib/danmaku/controller/danmaku_controller.dart:35
- 问题: `statusLabel` / `summaryText` 拼接英文 UI 文案，播放器设置页又直接读取这些 getter 展示，违反 UI 展示文案必须走 `AppLocalizations` getter 的约束。
  ```dart
  String get statusLabel {
    if (!_settings.enabled) return 'Off';
    return switch (_loadedSourceType) {
      DanmakuLoadedSourceType.local => 'Local',
      DanmakuLoadedSourceType.network => 'DanDanPlay',
      DanmakuLoadedSourceType.none => 'Not loaded',
    };
  }
  ```
  ```dart
  String _danmakuStatusLabel() => _danmakuController.statusLabel;
  String _danmakuSummaryText() => _danmakuController.summaryText;
  ```
- 建议方向: 控制器只暴露状态枚举和数量等结构化数据，由 UI 层使用 `AppLocalizations` 生成最终展示文案。
- 状态: 已确认

### [E-004] 网络弹幕内容在 UI isolate 同步解析
- 级别: P1
- 分类: 性能
- 位置: lib/danmaku/api/dandanplay_resolver.dart:170
- 问题: DanDanPlay 网络弹幕拉取后直接调用同步的 `parseContentString()`，该路径会在当前 isolate 内 `jsonDecode` 或用正则遍历整包 XML。弹幕包通常可能达到数千条，播放器中自动匹配/手动搜索后导入会阻塞 UI isolate，和 README“解析、排序、时间索引建立不要放 UI isolate”的热路径原则冲突。
  ```dart
  final commentsResponse = await _api.fetchComments(item.episodeId);
  final content = commentsResponse.data?.trim() ?? '';
  if (content.isEmpty) return null;
  final result = DanmakuImportParser.parseContentString(
    content,
    sourceLabel: 'DanDanPlay · ${item.displaySubtitle}',
  );
  ```
  ```dart
  static DanmakuImportResult parseContentString(String content, {
    String sourceLabel = 'Network Danmaku',
  }) {
    final comments = _parseContentComments(content);
  ```
- 建议方向: 给网络内容增加和 `parseFile`/`parseBytes` 一致的 isolate 解析入口，并在解析完成后再回到 UI 层更新控制器。
- 状态: 已确认

### [E-005] 存在未接入的平行弹幕 overlay 实现
- 级别: P2
- 分类: 可维护性 / 死代码
- 位置: lib/danmaku/render/canvas_danmaku_overlay.dart:11
- 问题: `canvas_danmaku_overlay.dart` 定义了另一个同名 `DanmakuOverlay`，`flutter_danmaku_overlay.dart` 又定义了一套完整 `FlutterDanmakuOverlay`/engine，但仓库内播放器只 import `lib/danmaku/render/danmaku_overlay.dart`，没有任何地方导入这两套替代实现。这会形成未运行、未验证的平行渲染实现，后续排查弹幕渲染问题时容易改错文件。
  ```dart
  class DanmakuOverlay extends StatefulWidget {
    final DanmakuController controller;
    final Duration position;
    final bool paused;
    ...
  }
  ```
  ```dart
  class FlutterDanmakuOverlay extends StatefulWidget {
    final DanmakuController controller;
    final int positionMs;
    ...
  }
  ```
  ```text
  lib/player/mpv_player_page.dart:25:import '../danmaku/render/danmaku_overlay.dart';
  ```
- 建议方向: 删除未接入实现，或改成明确的可切换 renderer 并通过单一入口选择，避免多套 overlay 分叉维护。
- 状态: 已确认

### [E-006] 滚动弹幕入场按轨道重复扫描 active 列表
- 级别: P1
- 分类: 性能
- 位置: lib/danmaku/render/danmaku_overlay.dart:1586
- 问题: 每条滚动弹幕准入都会通过 `_findTrack()` 遍历候选轨道；每个轨道又先 `_visibleScrollItemCountOnTrack()` 全量扫描 `_scrollItems`，再按轨道过滤并构造 `DanmakuScrollTrackItemSnapshot` 列表。当前只缓存“最后一个 trackY”的快照，候选轨道连续 miss 时会重复扫描 active 列表并分配快照列表。高密度弹幕入场或 pending 队列 drain 时，这段会在调度热路径上放大为 `待入场弹幕数 × 轨道数 × active滚动弹幕数`。
  ```dart
  for (var offset = 0; offset < tracks.length; offset += 1) {
    final track = tracks[(startIndex + offset) % tracks.length];
    if (canUse(track)) {
      return track;
    }
  }
  ```
  ```dart
  final visibleOnTrack = _visibleScrollItemCountOnTrack(trackY, _timelineMs, viewportSize);
  ...
  trackSnapshots = _scrollItems
      .where((item) => item.trackPosition == trackY)
      .map((item) => DanmakuScrollTrackItemSnapshot(...))
      .toList(growable: false);
  ```
- 建议方向: 按帧/调度批次预聚合 `trackY -> active items/snapshots/count`，或把轨道状态维护在专门 allocator 中，避免每条弹幕重复过滤全量 active 列表。
- 状态: 已确认

### [E-007] 弹幕源持久化失败被吞掉且坏 JSON 未兜底
- 级别: P2
- 分类: 可维护性 / Bug / 约束违规(M4)
- 位置: lib/danmaku/settings/danmaku_saved_source_store.dart:234
- 问题: `_loadPayload()` 直接 `jsonDecode(raw)`，文件内容损坏时异常会冒泡到加载弹幕源的播放器路径；另一方面 `_readRaw()`、`clearAll()`、`_purgeLegacyPref()` 用空 `catch` 吞掉文件/SharedPreferences 失败，没有日志也没有降级状态，导致迁移失败、清空失败或读源失败都不可追踪。
  ```dart
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return _emptyPayload();
  ```
  ```dart
  try {
    final file = await _file();
    if (await file.exists()) await file.delete();
  } catch (_) {}
  ...
  } catch (_) {
    return null;
  }
  ```
- 建议方向: 对 JSON 损坏做显式捕获并备份/重置坏文件；所有持久化异常至少 debug 记录或返回可展示的失败结果，避免静默丢失用户弹幕源状态。
- 状态: 已确认

### [E-008] 自动匹配失败分支缺少切集后的上下文校验
- 级别: P1
- 分类: Bug / async gap 安全
- 位置: lib/player/page_parts/danmaku/mpv_player_danmaku_mixin.dart:662
- 问题: `_tryLoadDanDanPlayComments()` 在 `resolveForPlayback()` 之后，只有成功命中分支检查 `requestToken`；`resolved == null` 和 `catch` 分支会直接写入 blocked reason 并用当前 `context` 弹 toast。若用户在网络请求期间切集，旧请求可能在新集页面显示“无结果/失败”提示，catch 分支还用新的 `_currentSeriesTitle/_currentEpisodeNumber` 记录旧错误，形成串台。
  ```dart
  final resolved = await _danDanPlayResolver.resolveForPlayback(...);
  if (resolved == null) {
    await _danmakuSavedSourceStore.saveAutoMatchBlockedReason(
      mediaKey: mediaKey,
      reason: _danmakuAutoBlockNoResult,
    );
    if (mounted) {
      _showTopTip(...);
    }
    return false;
  }
  if (requestToken != null &&
      !_isActiveDanmakuContext(requestToken, mediaKey)) {
    return false;
  }
  ```
- 建议方向: 在 `resolved == null` 和 `catch` 分支写 store/显示 UI 前同样校验 `requestToken + mediaKey`，并捕获请求开始时的标题/季集信息用于日志。
- 状态: 已确认

### [E-009] 手动导入完成后用当前媒体写保存源，切集时会串台
- 级别: P1
- 分类: Bug / async gap 安全
- 位置: lib/player/page_parts/danmaku/mpv_player_danmaku_sources_mixin.dart:113
- 问题: `_importDanmakuSearchResult()` 和 `_importLocalDanmakuFile()` 在网络/文件解析 await 之后，直接读取 `_currentDanmakuMediaKey()`、`_currentTitle`、`_currentEpisodeNumber` 等当前字段来保存源并应用弹幕。用户在导入期间切到另一集时，旧导入结果会被保存到新媒体 key，甚至应用到新集，破坏“按集保存源”的边界。
  ```dart
  final result = await _danDanPlayResolver.importEpisodeById(item);
  ...
  final savedSource = DanmakuSavedSource(
    type: DanmakuSavedSourceType.danDanPlay,
    mediaKey: _currentDanmakuMediaKey(),
    sourceKey: item.episodeId.toString(),
    label: item.displayTitle,
  ```
  ```dart
  final result = StorageAccessService.isScopedIdentifier(sourceKey)
      ? await (() async { ... })()
      : await DanmakuImportParser.parseFile(sourceKey);
  ...
  mediaKey: _currentDanmakuMediaKey(),
  ```
- 建议方向: 在导入开始时捕获 mediaKey 与媒体元数据，await 后确认仍是同一上下文；保存源时使用捕获的元数据，过期结果直接丢弃。
- 状态: 已确认

### [E-010] 弹幕搜索当前匹配文案会显示问号占位
- 级别: P2
- 分类: Bug / 约束违规(M3)
- 位置: lib/player/page_parts/danmaku/mpv_player_danmaku_mixin.dart:812
- 问题: `_danmakuSearchContextText()` 把季/集拼成 `?1?` 这类问号占位，搜索页直接把该字符串传给 `l10n.danmakuCurrentMatch()` 展示。该文案既绕过本地化 getter，也会让用户看到损坏的季集格式。
  ```dart
  final parts = <String>[
    if (title.isNotEmpty) title,
    if (_currentSeasonNumber > 0) '?$_currentSeasonNumber?',
    if (_currentEpisodeNumber > 0) '?$_currentEpisodeNumber?',
  ];
  ```
  ```dart
  Text(
    l10n.danmakuCurrentMatch(_danmakuSearchContextText()),
  ```
- 建议方向: 用 `AppLocalizations` 提供“第 N 季/第 N 集”或等价格式化 getter，并修复当前问号占位。
- 状态: 已确认

### [E-011] 音频抽屉仍大量硬编码中文/英文 UI 文案
- 级别: P2
- 分类: 约束违规(M3) / 可维护性
- 位置: lib/player/page_parts/settings/mpv_player_audio_drawer_mixin.dart:40
- 问题: 音频抽屉的标题、按钮、空状态、提示和错误信息直接写在 Dart 字符串里，`PlayerNestedSheet.show` 的 `barrierLabel` 也使用英文裸字符串，未通过 `AppLocalizations` getter。播放器设置是多语言重灾区，这类文案会绕过 arb 生成与翻译检查。
  ```dart
  await PlayerNestedSheet.show<void>(
    context,
    initialPageId: _audioMainPageId,
    barrierLabel: 'audio drawer',
  ```
  ```dart
  title: '\u97f3\u9891',
  label: '\u8c03\u8282',
  ...
  child: Text('\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u97f3\u8f68',
  ```
  ```dart
  return '\u97f3\u9891\u5ef6\u8fdf\u8bbe\u7f6e\u5931\u8d25';
  ```
- 建议方向: 为音频抽屉所有展示文案补齐 arb getter，Dart 层只引用 `AppLocalizations`；barrierLabel 也应使用可本地化的语义标签。
- 状态: 已确认

### [E-012] mpv 缓存大小页在确认弹窗返回后直接更新局部状态
- 级别: P1
- 分类: Bug / 性能安全(P7)
- 位置: lib/player/page_parts/settings/mpv_player_settings_mpv_mixin.dart:806
- 问题: 缓存大小设置页使用 `StatefulBuilder` 保存局部状态，但在性能确认弹窗 `await` 返回后没有确认抽屉页仍存在，就直接调用 `setLocalState`。用户在确认弹窗期间关闭设置抽屉或切换页面时，这个局部 `StateSetter` 可能已经失效，属于文档要求逐条上报的 async gap。
  ```dart
  final confirmed = await _confirmMpvPerformanceSelection(
    context,
    _MpvPlayerPageState._mpvSettingCacheSizeMb,
    selectedMb.toString(),
  );
  if (!confirmed) {
    setLocalState(() {
      auto = true;
  ```
- 建议方向: 将缓存大小页提取为独立 `StatefulWidget` 以便使用 `mounted` 防护，或让抽屉控制器提供仍在当前页的校验后再更新局部状态。
- 状态: 已确认

### [E-013] mpv 缓存滑杆端点直接硬编码英文标签
- 级别: P2
- 分类: 约束违规(M3) / 可维护性
- 位置: lib/player/page_parts/settings/mpv_player_settings_mpv_mixin.dart:950
- 问题: 缓存大小滑杆底部端点用硬编码英文 `MIN` / `MAX` 拼接显示，绕过 `AppLocalizations`，在中文界面或其他语言下会残留英文 UI 文案。
  ```dart
  Text(
    'MIN ${_formatMpvCachePercentLabel(_mpvCachePercentSliderMin)}',
  ...
  Text(
    'MAX ${_formatMpvCachePercentLabel(_mpvCachePercentSliderMax)}',
  ```
- 建议方向: 增加 `AppLocalizations` getter 或参数化文案，例如“最小/最大”标签由 arb 生成。
- 状态: 已确认

### [E-014] 播放诊断页仍直接拼接英文诊断标签
- 级别: P2
- 分类: 约束违规(M3) / 可维护性
- 位置: lib/player/page_parts/settings/mpv_player_settings_video_info_mixin.dart:112
- 问题: 播放诊断页多个展示项没有走 `AppLocalizations`，包括 Dolby Vision 的条目名、Profile/Level 值和系统音频 buffer 文案；这些字符串会直接出现在播放器诊断 UI，绕过 arb 翻译与统一术语维护。
  ```dart
  PlaybackDetailItem(
    'DV Profile / Level',
    _dolbyVisionProfileLevelLabel(mpv),
  );
  ...
  return 'Profile $profile / Level $level';
  ...
  'buffer $framesPerBuffer',
  ```
- 建议方向: 将诊断条目名和值模板补到 `AppLocalizations`，技术缩写如 DV 可保留为参数或本地化模板的一部分。
- 状态: 已确认

### [E-015] 已废弃的片头片尾设置组件仍留在 settings widgets 中
- 级别: P2
- 分类: 可维护性 / 死代码(M5)
- 位置: lib/player/page_parts/settings/mpv_player_settings_widgets.dart:321
- 问题: `PlaybackSettingsIntroOutroView` 是公开组件，包含开关、章节加载和时长调整 UI，但全仓搜索只有定义没有调用点；当前片头片尾设置已经由 `mpv_player_settings_intro_outro_mixin.dart` 内的页面实现承载。保留这段未接入组件会让后续维护者误判真实 UI 入口，还可能继续在无用代码上修 bug。
  ```dart
  class PlaybackSettingsIntroOutroView extends StatelessWidget {
    final bool enabled;
    final String mode;
    final int introDurationSeconds;
    final int outroDurationSeconds;
    final Future<List<MpvChapterItem>> Function() chapterLoader;
  ```
- 建议方向: 删除未使用组件，或若仍计划复用，改为私有并由当前片头片尾 mixin 实际接入；避免保留平行 UI 实现。
- 状态: 已确认

### [E-016] 字幕抽屉大量硬编码中文/英文 UI 文案
- 级别: P2
- 分类: 约束违规(M3) / 可维护性
- 位置: lib/player/page_parts/settings/mpv_player_subtitle_drawer_mixin.dart:37
- 问题: 字幕抽屉的 barrierLabel、标题、按钮、空状态、错误提示和滑杆端点大量写死在 Dart 字符串里，没有通过 `AppLocalizations`。这会让字幕设置页绕过 arb 生成与翻译检查，和同一播放器设置体系里其它已本地化页面不一致。
  ```dart
  barrierLabel: 'subtitle drawer',
  ...
  title: '\u5b57\u5e55',
  label: '\u8c03\u6574',
  ...
  const Text('\u672a\u627e\u5230\u53ef\u4e0b\u8f7d\u5b57\u5e55',
  ...
  _showTransientMessage('\u641c\u7d22\u5b57\u5e55\u5931\u8d25: $error');
  ```
- 建议方向: 为字幕抽屉所有展示文案补齐 arb getter；错误提示使用本地化模板，barrierLabel 也使用本地化语义标签。
- 状态: 已确认

### [E-017] 字幕抽屉 UI 直接创建 FeiniuApi，绕过多后端抽象
- 级别: P1
- 分类: 约束违规(C2/C3) / 可扩展性
- 位置: lib/player/page_parts/settings/mpv_player_subtitle_drawer_mixin.dart:80
- 问题: 播放器 UI 的字幕抽屉直接读取 `NasProvider` 并创建 `FeiniuApi`，用于语言映射、远程字幕搜索/下载和删除字幕。字幕 UI 因此绑定飞牛 API，未来接入 Emby/Jellyfin 时必须改播放器 UI 代码，违反“UI 不得直接依赖具体后端 API”和后端差异应收敛在抽象层的约束。
  ```dart
  final languageMap = await FeiniuApi(
    nasProvider,
  ).getTagIso6392Map(lan: 'zh-CN');
  ...
  final api = FeiniuApi(context.read<NasProvider>());
  final results = await _subtitleService.searchRemoteSubtitles(
    api: api,
  ```
- 建议方向: 将字幕搜索、下载、删除和语言映射能力收敛到 media backend/service 抽象；UI 只依赖播放器字幕服务的后端无关接口。
- 状态: 已确认

### [E-018] 远程字幕下载完成后未校验媒体上下文，可能把旧结果应用到新视频
- 级别: P1
- 分类: Bug / async gap 安全
- 位置: lib/player/page_parts/settings/mpv_player_subtitle_drawer_mixin.dart:620
- 问题: `_downloadRemoteSubtitle()` 在发起下载前捕获 `mediaGuid`，但 `await downloadRemoteSubtitleTrack()` 返回后只检查 `mounted`，随后直接把 track 插入当前 `_subtitleTracks` 并调用 `_selectSubtitleFromDrawer()`。如果下载期间播放器切换到下一集/其它媒体，旧媒体的字幕会被插入并选中到当前视频，造成字幕串台。
  ```dart
  final track = await _subtitleService.downloadRemoteSubtitleTrack(
    api: api,
    mediaGuid: mediaGuid,
    trimId: item.trimId,
  );
  if (!mounted) return;
  _upsertSubtitleTrack(track, insertAtFront: true);
  await _selectSubtitleFromDrawer(track.guid, drawer);
  ```
- 建议方向: 下载开始时记录媒体上下文 token/mediaGuid，await 后确认仍匹配当前媒体；过期下载结果只清理 loading 状态，不写当前字幕列表、不自动选择。
- 状态: 已确认

### [E-019] 视频调整保存完成后会刷新可能已销毁的抽屉控制器
- 级别: P1
- 分类: Bug / async gap 安全
- 位置: lib/player/page_parts/settings/mpv_player_video_adjust_mixin.dart:142
- 问题: 快速调整页在滑杆释放或重置时异步保存设置，`await _mpvSettingsStore.saveVideoAdjustments()` 返回后直接 `drawer?.refresh()`。`PlayerNestedSheetController` 在抽屉关闭时会 `dispose()`，而 `refresh()` 是裸 `notifyListeners()`；用户拖动滑杆后立刻关闭抽屉，就可能在已 dispose 的 controller 上通知监听器。
  ```dart
  await _mpvSettingsStore.saveVideoAdjustments(normalized);
  _updatePlayerState(() => _videoAdjustments = normalized);
  drawer?.refresh();
  await _controller.setVideoAdjustments(normalized);
  ```
  ```dart
  void refresh() {
    notifyListeners();
  }
  ```
- 建议方向: 异步提交前后校验抽屉仍处于当前页面，或让 `PlayerNestedSheetController` 暴露 `isDisposed`/安全刷新方法；关闭后的提交只更新持久化和播放器状态，不再触发抽屉刷新。
- 状态: 已确认

### [E-020] 季选择 OverlayEntry 没有在面板销毁时清理
- 级别: P1
- 分类: Bug / 资源泄漏(P6)
- 位置: lib/player/panels/episode_picker_sheet.dart:463
- 问题: `_showSeasonMenu()` 把季选择菜单插入 root overlay，只有 `closeMenu()` 会 remove entry；但 entry 是方法局部变量，`dispose()` 只释放 `_scrollController`。如果用户打开季菜单后通过系统返回/外层 barrier 关闭剧集面板，`OverlayEntry` 没有生命周期归属，会残留在 root overlay，`completer.future` 也不会完成。
  ```dart
  final completer = Completer<String?>();
  OverlayEntry? entry;
  ...
  overlay.insert(entry!);
  final selection = await completer.future;
  ```
  ```dart
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  ```
- 建议方向: 将当前菜单 entry/completer 提升为 State 字段，在 `dispose()` 中统一 remove/complete；或改用 Flutter 自带 route/menu API，让菜单随面板 route 生命周期释放。
- 状态: 已确认

### [E-021] episode_picker_sheet.dart 单个 UI 文件超过 1500 行
- 级别: P2
- 分类: 可维护性(M1)
- 位置: lib/player/panels/episode_picker_sheet.dart:1
- 问题: `episode_picker_sheet.dart` 约 1626 行，同时包含数据模型、弹层状态机、季菜单、列表/宫格、海报加载、播放中动画和多个小组件，超过总纲中 UI 文件 >1500 行应拆分的阈值。后续调整剧集面板交互、图片加载或动画时都要在同一大文件内移动，维护成本偏高。
  ```dart
  class EpisodePickerSheetItem { ... }
  ...
  class _EpisodePickerDialogState extends State<_EpisodePickerDialog> { ... }
  ...
  class _EpisodePosterImageState extends State<_EpisodePosterImage> { ... }
  ```
- 建议方向: 按职责拆成 `episode_picker_sheet.dart`、`episode_picker_models.dart`、`episode_picker_season_menu.dart`、`episode_picker_list_grid.dart`、`episode_poster_image.dart` 等小文件。
- 状态: 已确认

### [E-022] 剧集面板 warmup 失败被空 catch 静默吞掉
- 级别: P2
- 分类: 可维护性(M4) / Bug
- 位置: lib/player/panels/episode_picker_sheet.dart:252
- 问题: `_warmupInitialData()` 加载预热数据失败时使用 `catch (_)`，只把 `_warmupLoading` 置回 false，不记录错误也不提示。预热 loader 涉及季列表/初始季数据，失败会导致面板停留在旧数据或少季状态，但排查时没有任何错误来源。
  ```dart
  } catch (_) {
    if (!mounted) return;
    setState(() => _warmupLoading = false);
  }
  ```
- 建议方向: 至少接收 `error, trace` 并上报到 `AppErrorReporter`；必要时提供轻量 UI 状态让用户知道季数据刷新失败。
- 状态: 已确认

### [E-023] 播放器背景/封面图未限制解码尺寸
- 级别: P1
- 分类: 性能(P3)
- 位置: lib/player/widgets/player_backdrop_image.dart:78
- 问题: `PlayerArtworkImage` / `PlayerBackdropImage` 直接用 `Image.network` 和 `Image.file` 渲染播放器背景/封面，但没有传 `cacheWidth/cacheHeight` 或其它受控解码尺寸。NAS 返回的海报/背景可能是高分辨率原图，进入播放器首屏时会按原图解码，占用内存并增加栅格压力，违反网络大图必须限制解码尺寸的约束。
  ```dart
  return Image.network(
    currentUrl,
    fit: widget.fit,
    alignment: widget.alignment,
    filterQuality: widget.filterQuality,
    headers: _networkHeaders(currentUrl),
  ```
- 建议方向: 让组件接收目标显示尺寸或在 `LayoutBuilder` 中按 `MediaQuery.devicePixelRatio` 计算 `cacheWidth/cacheHeight`，本地文件图同样传入受控解码尺寸。
- 状态: 已确认

### [E-024] 弱网建议浮层按钮硬编码中文
- 级别: P2
- 分类: 约束违规(M3) / 可维护性
- 位置: lib/player/widgets/player_gesture_overlay.dart:738
- 问题: `_PlayerWeakNetworkSuggestionCard` 的操作按钮直接写死“暂不”和“切换”，没有走 `AppLocalizations`。该浮层属于播放器可见 UI，当前其它标题/副标题由上层传入，本地化边界在按钮处断开。
  ```dart
  child: Text(
    '\u6682\u4e0d',
  ...
  child: Text(
    '\u5207\u6362',
  ```
- 建议方向: 给弱网建议浮层增加本地化按钮文案，或从上层传入已本地化的 dismiss/switch label。
- 状态: 已确认

### [E-025] 听视频页面使用全屏 ImageFilter.blur
- 级别: P1
- 分类: 性能(P1)
- 位置: lib/player/widgets/player_listen_video_presentation.dart:38
- 问题: 听视频模式把整屏背景图放大后套 `ImageFiltered(ImageFilter.blur(sigmaX: 28, sigmaY: 28))`。总纲明确要求禁止大面积 `ImageFilter.blur`/模糊玻璃回潮；该层覆盖播放器主视觉区域，会在进入听视频模式和背景变化时增加离屏渲染与栅格压力。
  ```dart
  child: ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
    child: PlayerBackdropImage(
      urls: artworkUrls,
      token: token,
  ```
- 建议方向: 改为预生成/低分辨率模糊位图、纯色/渐变遮罩，或复用已缓存的低清背景，避免运行时对全屏图层做 blur。
- 状态: 已确认

### [E-026] 播放完成海报网络图未限制解码尺寸
- 级别: P1
- 分类: 性能(P3)
- 位置: lib/player/widgets/player_overlay_sections.dart:1005
- 问题: `_PlayerCompletionPoster` 在播放完成面板中直接使用 `Image.network` 加载海报，没有设置 `cacheWidth/cacheHeight`。该控件实际显示尺寸只有约 220x124 或 280x158，但 NAS 图片可能按原始大图解码，增加完成页弹出时的内存和解码开销。
  ```dart
  : Image.network(
      widget.urls[_urlIndex],
      fit: BoxFit.cover,
      headers: nasImageHeaders(widget.token, url: widget.urls[_urlIndex]),
      errorBuilder: (context, error, stackTrace) {
  ```
- 建议方向: 按 `posterWidth/posterHeight * devicePixelRatio` 计算并传入 `cacheWidth/cacheHeight`，或复用已有的受控海报组件。
- 状态: 已确认

## 总结

- 本轮 TASK E 共审 47 个文件，记录 26 条 findings，第二轮全部复核为已确认，无撤回。
- 最高优先级集中在弹幕与播放器热路径：DanDanPlay 错误吞掉、网络弹幕 UI isolate 解析、弹幕轨道扫描复杂度、图片原图解码、大面积 blur。
- 多后端扩展风险主要是字幕抽屉直接创建 `FeiniuApi`，会把字幕搜索/下载/删除绑定飞牛实现。
- async gap/串台问题主要出现在弹幕自动匹配、手动导入、远程字幕下载和抽屉控制器异步刷新。
- i18n 回潮集中在音频/字幕抽屉、弹幕状态摘要、诊断页、弱网建议浮层。
- 最建议优先处理：E-001、E-004、E-006、E-017、E-018、E-020、E-023、E-025。
