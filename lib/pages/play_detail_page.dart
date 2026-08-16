import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../api/feiniu_api.dart';
import '../controllers/play_detail_data_loader.dart';
import '../controllers/play_detail_download_sheet_controller.dart';
import '../controllers/play_detail_sheet_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/authorized_dir_entry.dart';
import '../models/download_task_record.dart';
import '../models/playback_stream.dart';
import '../models/play_info.dart';
import '../models/person_credit.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import '../media_backend/detail/media_detail.dart';
import '../media_backend/detail/media_detail_variant.dart';
import '../media_backend/detail/media_source_info.dart';
import '../media_backend/detail/media_source_version.dart';
import '../media_backend/feiniu/feiniu_detail_data_gateway.dart';
import '../media_backend/feiniu/feiniu_detail_mappers.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_image_ref.dart';
import '../providers/backend_session_provider.dart';
import '../providers/media_backend_provider.dart';
import 'long_text_overlay_page.dart';
import '../playback/native_playback_host.dart';
import '../playback/playback_source.dart';
import '../playback/player_source_controller.dart';
import '../providers/app_theme_provider.dart';
import '../providers/nas_provider.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../controllers/item_playback_launcher.dart';
import '../services/app_log_service.dart';
import '../services/detail_runtime_cache.dart';
import '../services/manual_subtitle_store.dart';
import '../services/native_danmaku_prefetch.dart';
import '../services/native_playback_reentry.dart';
import '../services/native_player_bridge.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/app_transitions.dart';
import '../ui/capability_badge_mapper.dart';
import '../ui/credit_person_presenter.dart';
import '../ui/detail_artwork_resolver.dart';
import '../ui/feiniu_video_info_lines.dart';
import '../ui/detail_presentation.dart';
import '../ui/player_pane_host_scope.dart';
import '../ui/region_name_localizer.dart';
import '../ui/route_transition_gate.dart';
import '../utils/api_url_helper.dart';
import '../utils/async_action_guard.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/detail_layout_solver.dart';
import '../utils/detail_top_tip.dart';
import '../utils/imdb_launcher.dart';
import '../utils/local_subtitle_bundle.dart';
import '../utils/manual_subtitle_tracks.dart';
import '../utils/media_language_mapper.dart';
import '../utils/player_artwork_path_resolver.dart';
import '../utils/playback_resume_position_resolver.dart';
import '../utils/player_title_formatter.dart';
import '../utils/play_detail_formatters.dart';
import '../utils/play_detail_track_selector.dart';
import '../utils/swallowed_error_logger.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/track_option_sheet.dart';
import '../widgets/detail/credits_section.dart';
import '../widgets/detail/detail_description_section.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/detail_hero_overlay.dart';
import '../widgets/detail/detail_loading_skeleton.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/detail/detail_meta_lines.dart';
import '../widgets/detail/detail_selector_row.dart';
import '../widgets/detail/detail_resolution_section.dart';
import '../widgets/detail/dynamic_page_theme_scope.dart';
import '../widgets/detail/file_info_section.dart';
import '../widgets/detail/immersive_detail_background.dart';
import '../widgets/detail/link_section.dart';
import '../widgets/detail/play_action_bar.dart';
import '../widgets/detail/theme_save_name_helper.dart';
import 'media_detail_overlay_page.dart';
import '../widgets/detail/video_info_section.dart';

class PlayDetailPage extends StatefulWidget {
  final String itemGuid;
  final String seriesGuid;
  final String? heroTag;
  final Map<String, dynamic>? initialItemDetail;
  final DetailPresentation presentation;

  const PlayDetailPage({
    super.key,
    required this.itemGuid,
    this.seriesGuid = '',
    this.heroTag,
    this.initialItemDetail,
    this.presentation = DetailPresentation.page,
  });

  @override
  State<PlayDetailPage> createState() => _PlayDetailPageState();
}

class _PlayDetailPageState extends State<PlayDetailPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _headerFadeDuration = Duration(milliseconds: 360);
  static const Duration _actionsPopDuration = Duration(milliseconds: 300);
  static const Duration _descriptionPopDuration = Duration(milliseconds: 320);
  static const Duration _asyncContentFadeDuration = Duration(milliseconds: 120);
  // Entrance pacing. Tightened so the page feels responsive: the description
  // and deferred sections (credits/file/video/links) appear noticeably sooner
  // and step in closer together, instead of trickling in over ~1s.
  static const Duration _deferredSectionStartDelay = Duration(
    milliseconds: 320,
  );
  static const Duration _deferredSectionStepDelay = Duration(milliseconds: 110);
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);
  final PlayDetailDownloadSheetController _downloadSheetController =
      const PlayDetailDownloadSheetController();
  final DownloadTaskService _downloadTaskService = DownloadTaskService.instance;
  // 当前 item 已下载记录的签名，用于在下载任务变化时跳过无关的全页重建（P7）。
  String? _downloadedRecordSignatureForCurrentItem;
  StreamFileInfo? _localDownloadedFileInfoSnapshot;
  int _localDownloadedFileInfoRequestId = 0;
  static const Duration _favoriteTapCooldown = Duration(milliseconds: 900);
  static const Duration _watchedTapCooldown = Duration(milliseconds: 900);

  bool get _isPane => widget.presentation == DetailPresentation.pane;
  bool get _useRuntimeCache => _isPane;

  PlayInfoData? _data;

  /// 公共详情展示快照（Phase 5 详情页迁移）：由页面已加载的 [_data] / 题材·地区字典 /
  /// 演职员 / imdb 在进程内构造，零额外网络。渐进加载下随各阶段重建（见 [_rebuildDetail]）。
  ///
  MediaDetail? _detail;

  /// 中立态(Emby)的媒体源信息(文件/视频信息)。派生自选中版本 [_neutralSelectedVersion];
  /// 飞牛态恒为 null(飞牛走自有 FileInfoSection/VideoInfoSection 路径)。
  MediaSourceInfo? _sourceInfo;

  /// 中立态(Emby)的可选播放版本列表(每版本含其音轨/字幕轨),由
  /// [MediaBackend.getItemSourceVersions] 取。飞牛态恒空(走自有版本/轨道选择路径)。
  List<MediaSourceVersion> _neutralVersions = const <MediaSourceVersion>[];
  int _neutralSelectedVersionIndex = 0;

  /// 中立态选中的音轨/字幕轨 id(stream Index 串)。本轮仅记录选中态、为日后 Emby
  /// 播放预留;无播放消费。字幕空串=关闭。
  String? _neutralSelectedAudioId;
  String? _neutralSelectedSubtitleId;
  bool _neutralAudioSelectorExpanded = false;
  bool _neutralSubtitleSelectorExpanded = false;

  MediaSourceVersion? get _neutralSelectedVersion {
    if (_neutralVersions.isEmpty) return null;
    final index = _neutralSelectedVersionIndex.clamp(
      0,
      _neutralVersions.length - 1,
    );
    return _neutralVersions[index];
  }

  /// 中立展示态:当前后端非飞牛(如 Emby)时,本页只读 [MediaBackend.getItemDetail] 的中立
  /// [_detail] 渲染展示半身,**不加载飞牛播放数据**([_data] 保持 null),播放入口为占位。
  /// 飞牛态恒为 false、原构建路径完全不变。
  bool _neutralDisplayOnly = false;

  late String _currentItemGuid;
  List<PersonCredit> _personCredits = const [];
  List<StreamListOption> _streamOptions = const [];
  StreamTrackData? _streamTrackData;
  bool _loading = true;
  AppException? _error;
  int? _selectedStreamIndex;
  String? _selectedSubtitleGuid;
  String? _selectedAudioGuid;
  // 当前媒体的手动导入本地字幕元数据缓存（详情页面板展示 + 合并播放轨用）。
  List<ManualSubtitleEntry> _manualSubtitleEntries =
      const <ManualSubtitleEntry>[];
  VoidCallback? _manualSubtitleRevisionListener;
  String _imdbId = '';
  String _trimId = '';
  bool _liked = false;
  bool _favoriteUpdating = false;
  DateTime _lastFavoriteTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _watched = false;
  bool _watchedUpdating = false;
  DateTime _lastWatchedTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  final DetailTopTip _topTip = DetailTopTip();
  final Map<String, dynamic> _localeMap = const <String, dynamic>{};
  Map<int, String> _genresMapZhCn = const <int, String>{};
  Map<String, String> _locateMapZhCn = const <String, String>{};
  List<AuthorizedDirEntry> _authorizedDirs = const <AuthorizedDirEntry>[];
  bool _descriptionVisible = false;
  bool _creditsVisible = false;
  bool _fileInfoVisible = false;
  bool _videoInfoVisible = false;
  bool _linkVisible = false;
  bool _heroAsyncSectionsResolved = false;
  bool _subtitleSelectorExpanded = false;
  bool _audioSelectorExpanded = false;
  bool _deferredSectionLoadStarted = false;
  final bool _playerRouteActive = false;
  // 原生播放壳是独立 Android Activity,退出无 Navigator.push 返回点,详情页收不到刷新信号。
  // 故启动原生壳时置位,并记录其最后播放的条目(切集时更新);回前台一次性刷新进度/跟到新集。
  bool _nativePlayerLaunched = false;
  String _lastNativePlayedItemGuid = '';
  Timer? _entryActionTimer;
  Timer? _deferredSectionTimer;
  late final AnimationController _headerFadeController;
  late final AnimationController _actionsPopController;
  late final AnimationController _descriptionPopController;
  late final Animation<double> _headerTitleOpacity;
  late final Animation<double> _headerMetaOpacity;
  late final Animation<double> _headerSelectorOpacity;
  late final Animation<double> _actionsOpacity;
  late final Animation<double> _actionsScale;
  late final Animation<double> _actionsTranslateY;

  double _backdropHeroHeight(Size screenSize) {
    final isLandscape = screenSize.width > screenSize.height;
    if (isLandscape) {
      return screenSize.height * 0.50;
    }
    final byHeight = screenSize.height * 0.38;
    final byWidth = screenSize.width / 1.36;
    return math.min(byHeight, byWidth).clamp(300.0, 560.0).toDouble();
  }

  bool _isPhonePortrait(Size screenSize) {
    return screenSize.width < screenSize.height &&
        screenSize.shortestSide < 600.0;
  }

  Alignment _backdropImageAlignment(Size screenSize) {
    if (_isPhonePortrait(screenSize)) {
      return const Alignment(0.0, -0.22);
    }
    return Alignment.topCenter;
  }

  double _backdropImageScale(Size screenSize) {
    if (_isPhonePortrait(screenSize)) {
      return 1.05;
    }
    return 1.0;
  }

  double _heroInfoBlockReservedHeight(
    Size screenSize, {
    required bool canPlay,
  }) {
    if (!canPlay) {
      return _isPhonePortrait(screenSize) ? 110.0 : 100.0;
    }
    if (_isPhonePortrait(screenSize)) {
      return 180.0;
    }
    return screenSize.width > screenSize.height ? 150.0 : 160.0;
  }

  // Unified one-shot entrance animation for deferred detail sections (credits,
  // file info, video info, links). Mirrors the description block's pop (fade +
  // slide-up + subtle scale) so every section reveals consistently instead of
  // snapping in. Driven by TweenAnimationBuilder so each section animates once
  // on first build without needing its own AnimationController.
  Widget _sectionReveal({required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: _descriptionPopDuration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: Transform.scale(
              scale: 0.97 + (0.03 * t),
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }

  Widget _asyncFadeSwitcher(Widget child, {required Object switchKey}) {
    return AnimatedSwitcher(
      duration: _asyncContentFadeDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(key: ValueKey<Object>(switchKey), child: child),
    );
  }

  late final Animation<double> _resolutionOpacity;
  late final Animation<double> _resolutionScale;
  late final Animation<double> _resolutionTranslateY;
  late final Animation<double> _descriptionOpacity;
  late final Animation<double> _descriptionScale;
  late final Animation<double> _descriptionTranslateY;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentItemGuid = widget.itemGuid;
    _headerFadeController = AnimationController(
      vsync: this,
      duration: _headerFadeDuration,
    );
    _actionsPopController = AnimationController(
      vsync: this,
      duration: _actionsPopDuration,
    );
    _descriptionPopController = AnimationController(
      vsync: this,
      duration: _descriptionPopDuration,
    );
    _headerTitleOpacity = CurvedAnimation(
      parent: _headerFadeController,
      curve: const Interval(0.0, 0.45, curve: Curves.linear),
    );
    _headerMetaOpacity = CurvedAnimation(
      parent: _headerFadeController,
      curve: const Interval(0.24, 0.78, curve: Curves.linear),
    );
    _headerSelectorOpacity = CurvedAnimation(
      parent: _headerFadeController,
      curve: const Interval(0.52, 1.0, curve: Curves.linear),
    );
    _actionsOpacity = CurvedAnimation(
      parent: _actionsPopController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    );
    final actionsCurve = CurvedAnimation(
      parent: _actionsPopController,
      curve: Curves.easeOutCubic,
    );
    _actionsScale = Tween<double>(begin: 0.96, end: 1.0).animate(actionsCurve);
    _actionsTranslateY = Tween<double>(begin: 10, end: 0).animate(actionsCurve);
    _resolutionOpacity = CurvedAnimation(
      parent: _actionsPopController,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
    );
    _resolutionScale = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(
        parent: _actionsPopController,
        curve: const Interval(0.25, 1.0, curve: Curves.linear),
      ),
    );
    _resolutionTranslateY = Tween<double>(begin: 8, end: 0).animate(
      CurvedAnimation(
        parent: _actionsPopController,
        curve: const Interval(0.25, 1.0, curve: Curves.linear),
      ),
    );
    final descriptionCurve = CurvedAnimation(
      parent: _descriptionPopController,
      curve: Curves.easeOutCubic,
    );
    _descriptionOpacity = CurvedAnimation(
      parent: _descriptionPopController,
      curve: const Interval(0.0, 1.0, curve: Curves.linear),
    );
    _descriptionScale = Tween<double>(
      begin: 0.97,
      end: 1.0,
    ).animate(descriptionCurve);
    _descriptionTranslateY = Tween<double>(
      begin: 10,
      end: 0,
    ).animate(descriptionCurve);
    _scrollController.addListener(_onScroll);
    _downloadTaskService.addListener(_handleDownloadTasksChanged);
    _manualSubtitleRevisionListener = () {
      unawaited(_refreshManualSubtitleEntries());
    };
    const ManualSubtitleStore().revision.addListener(
      _manualSubtitleRevisionListener!,
    );
    unawaited(_downloadTaskService.initialize());
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _topTip.dispose();
    _entryActionTimer?.cancel();
    _deferredSectionTimer?.cancel();
    _headerFadeController.dispose();
    _actionsPopController.dispose();
    _descriptionPopController.dispose();
    _scrollController.removeListener(_onScroll);
    _downloadTaskService.removeListener(_handleDownloadTasksChanged);
    final subtitleRevisionListener = _manualSubtitleRevisionListener;
    if (subtitleRevisionListener != null) {
      const ManualSubtitleStore().revision.removeListener(
        subtitleRevisionListener,
      );
      _manualSubtitleRevisionListener = null;
    }
    _scrollController.dispose();
    _scrollOffsetNotifier.dispose();
    PlayDetailDownloadSheetController.clearCache();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 原生播放壳退出后回前台:一次性刷新本详情(进度;若壳内切了集则跟到新集)。性能:仅在
    // 确实启动过原生壳后触发一次,不做实时刷新。Flutter 全屏播放器走 Navigator.push 返回刷新,
    // 不在此路径。
    if (state != AppLifecycleState.resumed) return;
    if (!_nativePlayerLaunched || _playerRouteActive) return;
    _nativePlayerLaunched = false;
    final playedGuid = _lastNativePlayedItemGuid.trim();
    if (playedGuid.isNotEmpty && playedGuid != _currentItemGuid) {
      setState(() {
        _currentItemGuid = playedGuid;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshAfterItemStateChange());
      // 原生播放器内可能导入了本地字幕，回前台时刷新本地字幕轨（配合 store reload）。
      unawaited(_refreshManualSubtitleEntries());
    });
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if ((offset - _scrollOffsetNotifier.value).abs() > 0.5) {
      _scrollOffsetNotifier.value = offset;
    }
  }

  void _handleDownloadTasksChanged() {
    if (!mounted) return;
    // 下载服务在任意任务的每个进度 tick 都 notifyListeners；但本页只关心“当前 item 是否有
    // 已下载可用记录”（PlayActionBar 的已下载角标 + FileInfoSection 切到本地文件）。该记录
    // 只在下载完成/消失/换文件时变化，不随进度变。故仅在签名变化时才整页 setState，避免
    // 详情页可见期间被无关下载进度的每帧重建打满（PlayActionBar 另有局部 AnimatedBuilder 兜底）。
    final record = _downloadedRecordForCurrentItem();
    final signature = record == null
        ? null
        : '${record.id}|${record.filePath}|${record.status}';
    if (signature == _downloadedRecordSignatureForCurrentItem) return;
    _downloadedRecordSignatureForCurrentItem = signature;
    setState(() {});
    unawaited(_refreshLocalDownloadedFileInfo(record));
  }

  DownloadTaskRecord? _downloadedRecordForCurrentItem() {
    return _downloadTaskService.downloadedRecordForItem(
      _currentItemGuid,
      mediaGuid: _currentStreamOption()?.mediaGuid ?? '',
    );
  }

  Future<void> _refreshLocalDownloadedFileInfo(
    DownloadTaskRecord? record,
  ) async {
    final requestId = ++_localDownloadedFileInfoRequestId;
    if (record == null) {
      if (!mounted) return;
      setState(() => _localDownloadedFileInfoSnapshot = null);
      return;
    }
    final path = record.filePath.trim();
    if (path.isEmpty) {
      if (!mounted || requestId != _localDownloadedFileInfoRequestId) return;
      setState(() => _localDownloadedFileInfoSnapshot = null);
      return;
    }

    StreamFileInfo? info;
    final file = File(path);
    try {
      if (await file.exists()) {
        final stat = await file.stat();
        final modifiedAt = stat.modified.millisecondsSinceEpoch;
        info = StreamFileInfo(
          mediaGuid: record.mediaGuid,
          path: path,
          fileName: record.fileName.trim().isEmpty
              ? file.uri.pathSegments.isEmpty
                    ? ''
                    : file.uri.pathSegments.last
              : record.fileName.trim(),
          size: stat.size,
          fileBirthTime: record.createdAtMs > 0
              ? record.createdAtMs
              : modifiedAt,
          createTime: record.createdAtMs > 0 ? record.createdAtMs : modifiedAt,
          updateTime: record.updatedAtMs > 0 ? record.updatedAtMs : modifiedAt,
        );
      }
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'refresh local downloaded file info',
        id: record.itemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'play_detail_page',
      );
      info = null;
    }
    if (!mounted || requestId != _localDownloadedFileInfoRequestId) return;
    setState(() => _localDownloadedFileInfoSnapshot = info);
  }

  int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  String _heroPathForPlayItem(PlayItem item) {
    return resolvePlayerArtworkPathForPlayItem(item);
  }

  // Unified hero artwork path used by the persistent background layer (the one
  // that lives outside the loading↔ready crossFade). Prefers loaded data, then
  // the initial detail map passed in on navigation, so the backdrop is known on
  // the very first frame and never has to reload when _loading flips to false.
  String _persistentHeroPath() {
    // Only use the loaded data's artwork, via the SAME resolver the ready
    // branch uses. We deliberately do NOT fall back to initialItemDetail here:
    // its artwork resolver can disagree with the loaded item (e.g. a movie
    // showing an episode-style still), which produced a visible "wrong image
    // then correct image" flash on open. While loading we return '' (base color
    // only); when data arrives the backdrop loads once (empty → correct = a
    // single fade-in, not a swap), so there's no flash and the layer still
    // persists across loading→ready without rebuilding.
    final data = _data;
    if (data == null) {
      return '';
    }
    return _heroPathForPlayItem(data.item);
  }

  /// 中立后端(Emby)展示体:与飞牛页同一批组件(背景在页级已铺、此处为 hero + 信息块 +
  /// 描述 + 演职员),数据全来自中立 [_detail]。播放入口为占位(能力门控,本切片不做 Emby
  /// 播放);演职员点击在中立态暂不跳转(Emby 人物详情后续切片)。
  /// 选中版本的默认音轨 id:有 `defaultAudioId` 用之,否则首条音轨,无音轨空。
  String _defaultAudioIdFor(MediaSourceVersion? version) {
    if (version == null) return '';
    if (version.defaultAudioId.isNotEmpty) return version.defaultAudioId;
    return version.audioTracks.isNotEmpty ? version.audioTracks.first.id : '';
  }

  List<MediaSourceVersion> _localizeNeutralSourceVersions(
    List<MediaSourceVersion> versions,
    AppLocalizations l10n,
  ) {
    return <MediaSourceVersion>[
      for (var index = 0; index < versions.length; index++)
        _localizeNeutralSourceVersion(versions[index], index, l10n),
    ];
  }

  MediaSourceVersion _localizeNeutralSourceVersion(
    MediaSourceVersion version,
    int index,
    AppLocalizations l10n,
  ) {
    return MediaSourceVersion(
      id: version.id,
      label: _localizeNeutralVersionLabel(version.label, index, l10n),
      badges: version.badges,
      info: _localizeNeutralSourceInfo(version.info, l10n),
      audioTracks: _localizeNeutralTrackOptions(version.audioTracks, l10n),
      subtitleTracks: _localizeNeutralTrackOptions(
        version.subtitleTracks,
        l10n,
      ),
      defaultAudioId: version.defaultAudioId,
      defaultSubtitleId: version.defaultSubtitleId,
      durationSeconds: version.durationSeconds,
    );
  }

  String _localizeNeutralVersionLabel(
    String label,
    int index,
    AppLocalizations l10n,
  ) {
    final raw = label.trim();
    if (raw.startsWith(mediaSourceFallbackLabelPrefix)) {
      final numberText = raw.substring(mediaSourceFallbackLabelPrefix.length);
      final number = int.tryParse(numberText) ?? (index + 1);
      return l10n.detailSourceFallbackLabel(number);
    }
    return label;
  }

  List<MediaTrackOption> _localizeNeutralTrackOptions(
    List<MediaTrackOption> tracks,
    AppLocalizations l10n,
  ) {
    return <MediaTrackOption>[
      for (final track in tracks)
        MediaTrackOption(
          id: track.id,
          label: track.label,
          summary: _localizeNeutralSummary(track.summary, l10n),
          isExternal: track.isExternal,
        ),
    ];
  }

  MediaSourceInfo _localizeNeutralSourceInfo(
    MediaSourceInfo info,
    AppLocalizations l10n,
  ) {
    return MediaSourceInfo(
      path: info.path,
      container: info.container,
      sizeBytes: info.sizeBytes,
      addedDate: info.addedDate,
      streams: <MediaSourceStream>[
        for (final stream in info.streams)
          MediaSourceStream(
            type: stream.type,
            label: stream.label,
            summary: _localizeNeutralSummary(stream.summary, l10n),
            fields: stream.fields,
          ),
      ],
    );
  }

  String _localizeNeutralSummary(String summary, AppLocalizations l10n) {
    return summary.trim() == mediaExternalSubtitleSummaryToken
        ? l10n.playerSubtitleExternal
        : summary;
  }

  void _selectNeutralVersion(int index) {
    if (index == _neutralSelectedVersionIndex ||
        index < 0 ||
        index >= _neutralVersions.length) {
      return;
    }
    setState(() {
      _neutralSelectedVersionIndex = index;
      final version = _neutralVersions[index];
      // 切版本:音轨/字幕回到新版本默认,文件/视频信息同步换成该版本。
      _neutralSelectedAudioId = _defaultAudioIdFor(version);
      _neutralSelectedSubtitleId = version.defaultSubtitleId;
      _sourceInfo = version.info;
    });
  }

  /// 中立(Emby)起播:走 [ItemPlaybackLauncher]（与飞牛同入口、原生壳），带详情页已选的
  /// 版本(=MediaSourceId)/音轨/字幕。字幕 id 为空串=显式关闭，与 launcher 三态一致。
  Future<void> _startNeutralPlayback() async {
    final detail = _detail;
    if (detail == null) return;
    final version = _neutralSelectedVersion;
    await const ItemPlaybackLauncher().open(
      context,
      itemGuid: detail.id,
      fallbackTitle: detail.title,
      qualityMediaGuid: version?.id,
      audioTrackId: _neutralSelectedAudioId,
      subtitleTrackId: _neutralSelectedSubtitleId,
    );
  }

  String _neutralAudioLabel() {
    final l10n = AppLocalizations.of(context);
    final tracks =
        _neutralSelectedVersion?.audioTracks ?? const <MediaTrackOption>[];
    if (tracks.isEmpty) return l10n.trackAudioNone;
    for (final track in tracks) {
      if (track.id == _neutralSelectedAudioId) return track.label;
    }
    return tracks.first.label;
  }

  String _neutralSubtitleLabel() {
    final l10n = AppLocalizations.of(context);
    final tracks =
        _neutralSelectedVersion?.subtitleTracks ?? const <MediaTrackOption>[];
    final id = _neutralSelectedSubtitleId ?? '';
    if (id.isEmpty) return l10n.trackSubtitleOff;
    for (final track in tracks) {
      if (track.id == id) return track.label;
    }
    return tracks.isNotEmpty ? tracks.first.label : l10n.trackSubtitleOff;
  }

  /// 中立态音轨选择 sheet（复用中立 [TrackOptionSheet]）。本轮仅记录选中态,无播放消费。
  Future<void> _showNeutralAudioSheet() async {
    final tracks =
        _neutralSelectedVersion?.audioTracks ?? const <MediaTrackOption>[];
    if (tracks.length <= 1) return;
    setState(() => _neutralAudioSelectorExpanded = true);
    final items = tracks
        .map(
          (t) => TrackOptionSheetItem(
            id: t.id,
            title: t.label,
            subtitle: t.summary,
          ),
        )
        .toList();
    final current = _neutralSelectedAudioId ?? '';
    final result = await TrackOptionSheet.show(
      context,
      title: AppLocalizations.of(context).playerAudioSelectTitle,
      items: items,
      selectedId: current.isEmpty ? items.first.id : current,
    );
    if (!mounted) return;
    setState(() {
      _neutralAudioSelectorExpanded = false;
      if (result != null) _neutralSelectedAudioId = result;
    });
  }

  /// 中立态字幕选择 sheet（含「字幕关」项）。本轮仅记录选中态,无播放消费。
  Future<void> _showNeutralSubtitleSheet() async {
    final tracks =
        _neutralSelectedVersion?.subtitleTracks ?? const <MediaTrackOption>[];
    if (tracks.isEmpty) return;
    setState(() => _neutralSubtitleSelectorExpanded = true);
    final l10n = AppLocalizations.of(context);
    const offId = '__subtitle_off__';
    final items = <TrackOptionSheetItem>[
      TrackOptionSheetItem(id: offId, title: l10n.playerSubtitleOffAction),
      ...tracks.map(
        (t) =>
            TrackOptionSheetItem(id: t.id, title: t.label, subtitle: t.summary),
      ),
    ];
    final current = _neutralSelectedSubtitleId ?? '';
    final result = await TrackOptionSheet.show(
      context,
      title: l10n.playerSubtitleSelectTitle,
      items: items,
      selectedId: current.isEmpty ? offId : current,
    );
    if (!mounted) return;
    setState(() {
      _neutralSubtitleSelectorExpanded = false;
      if (result != null) {
        _neutralSelectedSubtitleId = result == offId ? '' : result;
      }
    });
  }

  Widget _buildNeutralBody(AppThemeColors colors) {
    final detail = _detail!;
    final capabilities = context
        .read<MediaBackendProvider>()
        .backend
        .capabilities;
    // 与飞牛分支同一图源入口:Emby 引用是完整 api_key 直链,resolveRef 直接透传
    // (baseUrl/token 仅对飞牛相对路径生效,此处不影响 Emby)。
    const artworkResolver = DetailArtworkResolver(
      baseUrl: '',
      token: '',
      accessCode: '',
    );
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final posterHeight = _backdropHeroHeight(screenSize);
    final layout = DetailLayoutSolver.solve(
      screenSize: screenSize,
      safePadding: media.padding,
      posterHeight: posterHeight,
    );

    final title = detail.title.trim().isNotEmpty
        ? detail.title.trim()
        : detail.displayTitle;
    final logoImages = artworkResolver.resolveRef(detail.logoImage);
    final logoChild = logoImages.isNotEmpty
        ? DetailHeroLogoTitle(
            images: logoImages,
            fallbackTitle: title,
            maxHeight: 112,
            maxWidth:
                screenSize.width - (DetailTokens.screenHorizontalPadding * 2),
            fallbackFontSize: 28,
          )
        : null;

    // 时长随选中版本走（同片不同剪辑版本时长可不同）：版本时长优先，缺则回退条目级时长。
    final selectedVersionDuration =
        _neutralSelectedVersion?.durationSeconds ?? 0;
    final effectiveDuration = selectedVersionDuration > 0
        ? selectedVersionDuration
        : detail.durationSeconds;
    // 元信息与飞牛同结构同顺序（共享 PlayDetailFormatters）：A=年份/题材/地区，B=时长。
    final metaLineA = PlayDetailFormatters.metaLineAFromDetail(detail);
    final metaLineB = PlayDetailFormatters.metaLineBFromDetail(
      detail,
      effectiveDurationSeconds: effectiveDuration,
      l10n: AppLocalizations.of(context),
    );
    final isEpisode = detail.type.trim().toLowerCase() == 'episode';
    final episodeHeroSubtitle = _neutralEpisodeHeroSubtitle(detail);

    // 续看进度（与飞牛同口径）：续看位 / 剩余 / 完成态 → 进度条 + 主按钮文案。
    final resumeTs = detail.resumePositionSeconds.clamp(0, effectiveDuration);
    final remainSeconds = (effectiveDuration - resumeTs).clamp(
      0,
      effectiveDuration,
    );
    final playbackCompleted =
        effectiveDuration > 0 && (remainSeconds <= 0 || _watched);
    final showResumeProgress = resumeTs > 0 && remainSeconds > 0;
    final resolvedPlayText = playbackCompleted
        ? AppLocalizations.of(context).playerReplayAction
        : resumeTs > 0
        ? AppLocalizations.of(context).detailContinuePlay
        : AppLocalizations.of(context).detailPlay;

    final creditItems = detail.people
        .map(
          (p) => CreditPersonItem(
            personGuid: p.id,
            name: CreditPersonPresenter.displayName(
              p,
              AppLocalizations.of(context),
            ),
            subtitle: CreditPersonPresenter.displaySubTitle(
              p,
              AppLocalizations.of(context),
            ),
            images: artworkResolver.resolveRef(p.avatar, width: 180),
          ),
        )
        .toList();

    // 版本 / 音轨 / 字幕选择器数据（本轮仅展示 + 记录选中态,无播放消费）。
    final versions = _neutralVersions;
    final selectedVersion = _neutralSelectedVersion;
    final versionLabels = versions.map((v) => v.label).toList();
    final showVersionSelector = versions.length > 1;
    final versionSelectedKey =
        (showVersionSelector &&
            _neutralSelectedVersionIndex < versionLabels.length)
        ? '$_neutralSelectedVersionIndex:${versionLabels[_neutralSelectedVersionIndex]}'
        : null;
    final audioTracks =
        selectedVersion?.audioTracks ?? const <MediaTrackOption>[];
    final subtitleTracks =
        selectedVersion?.subtitleTracks ?? const <MediaTrackOption>[];
    final showSelectorRow = audioTracks.isNotEmpty || subtitleTracks.isNotEmpty;
    final capabilityLabels = (selectedVersion?.badges ?? const <String>[])
        .map(CapabilityBadgeMapper.normalize)
        .where((e) => e.isNotEmpty)
        .toList();

    // 顶栏折叠区间（与飞牛同口径）：滚动到 infoStart 收起处标题淡入。
    final collapseRange =
        (layout.infoStart - media.padding.top - kToolbarHeight).clamp(
          1.0,
          layout.infoStart,
        );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              _buildHeroSliver(
                height: layout.infoStart,
                title: title,
                subtitle: episodeHeroSubtitle,
                titleFontSize: isEpisode ? 28 : null,
                bottomInset: isEpisode ? 20 : 36,
                titleChild: isEpisode ? null : logoChild,
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: colors.backgroundBase,
                  padding: const EdgeInsets.fromLTRB(
                    DetailTokens.screenHorizontalPadding,
                    8,
                    DetailTokens.screenHorizontalPadding,
                    10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DetailMetaLines(
                        metaLineA: metaLineA,
                        metaLineB: metaLineB,
                      ),
                      if (showSelectorRow) ...[
                        const SizedBox(height: 8),
                        DetailSelectorRow(
                          subtitleLabel: _neutralSubtitleLabel(),
                          audioLabel: _neutralAudioLabel(),
                          capabilityLabels: capabilityLabels,
                          showSubtitleArrow: subtitleTracks.isNotEmpty,
                          showAudioArrow: audioTracks.length > 1,
                          subtitleExpanded: _neutralSubtitleSelectorExpanded,
                          audioExpanded: _neutralAudioSelectorExpanded,
                          onSubtitleTap: subtitleTracks.isNotEmpty
                              ? () => _showNeutralSubtitleSheet()
                              : null,
                          onAudioTap: audioTracks.length > 1
                              ? () => _showNeutralAudioSheet()
                              : null,
                        ),
                      ],
                      const SizedBox(height: 16),
                      // 与飞牛同一动作条组件:续看进度条 + 主播放键 + 收藏/下载/已看。收藏/已看走
                      // 中立后端接口（按能力开关启用，不支持的后端置灰 null）；下载暂无公共后端
                      // 实现,统一提示不可用。
                      PlayActionBar(
                        progress: PlayDetailFormatters.progress(
                          effectiveDuration,
                          resumeTs,
                        ),
                        remainText: PlayDetailFormatters.remainText(
                          effectiveDuration,
                          resumeTs,
                          AppLocalizations.of(context),
                        ),
                        showProgress: showResumeProgress,
                        primaryText: resolvedPlayText,
                        primaryEnabled: true,
                        liked: _liked,
                        watched: _watched,
                        downloaded: false,
                        onPrimaryTap: _startNeutralPlayback,
                        onLikeTap: capabilities.supportsFavorite
                            ? _toggleFavorite
                            : null,
                        onWatchedTap: capabilities.supportsWatched
                            ? _toggleWatched
                            : null,
                        onDownloadTap: _neutralDownloadUnavailable,
                      ),
                      if (showVersionSelector)
                        DetailResolutionSection(
                          options: versionLabels,
                          selected: versionSelectedKey,
                          onSelected: _selectNeutralVersion,
                        ),
                    ],
                  ),
                ),
              ),
              if (detail.overview.trim().isNotEmpty)
                _buildDescriptionSliver(
                  colors: colors,
                  text: detail.overview.trim(),
                  overlayTitle: title,
                  bottomPadding: media.padding.bottom + 18,
                ),
              if (creditItems.isNotEmpty)
                _buildCreditsSliver(
                  colors: colors,
                  items: creditItems,
                  onTap: _openCreditPerson,
                ),
              // 文件信息：复用飞牛同款 FileInfoSection（独立区块，与飞牛顺序一致排在视频信息前）。
              // Emby 路径无 /vol 概念 → 隐藏路径切换按钮。
              if (_neutralFileInfo != null)
                SliverToBoxAdapter(
                  child: _sectionReveal(
                    child: Container(
                      color: colors.backgroundBase,
                      padding: const EdgeInsets.fromLTRB(
                        DetailTokens.screenHorizontalPadding,
                        8,
                        DetailTokens.screenHorizontalPadding,
                        20,
                      ),
                      child: FileInfoSection(
                        file: _neutralFileInfo,
                        showPathToggle: false,
                        title: AppLocalizations.of(context).detailFileInfoTitle,
                        locationLabel: AppLocalizations.of(
                          context,
                        ).detailFileLocation,
                        sizeLabel: AppLocalizations.of(context).detailFileSize,
                        createdAtLabel: AppLocalizations.of(
                          context,
                        ).detailFileCreatedAt,
                        addedAtLabel: AppLocalizations.of(
                          context,
                        ).detailFileAddedAt,
                      ),
                    ),
                  ),
                ),
              if (_sourceInfo != null && _sourceInfo!.isNotEmpty)
                SliverToBoxAdapter(
                  child: _sectionReveal(
                    child: Container(
                      color: colors.backgroundBase,
                      padding: const EdgeInsets.fromLTRB(
                        DetailTokens.screenHorizontalPadding,
                        8,
                        DetailTokens.screenHorizontalPadding,
                        20,
                      ),
                      // 与飞牛同一「视频信息」组件（紧凑三行 + 查看全部）；「查看全部」展开
                      // 逐流字段明细（复用飞牛同款 MediaDetailOverlayPage）。
                      child: VideoInfoSection(
                        lines: VideoInfoLines.fromSource(
                          _localizeNeutralSourceInfo(
                            _sourceInfo!,
                            AppLocalizations.of(context),
                          ),
                        ),
                        onViewAll: () => _showNeutralSourceInfoSheet(),
                      ),
                    ),
                  ),
                ),
              // 链接放最后(与飞牛顺序一致:文件信息 → 视频信息 → 链接)。
              if (_imdbId.trim().isNotEmpty || _trimId.trim().isNotEmpty)
                _buildLinkSliver(colors: colors),
            ],
          ),
          // 悬浮顶栏（与飞牛同口径）：返回 + 折叠标题。Emby 详情暂不挂「更多」动作面板
          // （动态主题 / 分享等飞牛专属），故 showMore: false。
          ValueListenableBuilder<double>(
            valueListenable: _scrollOffsetNotifier,
            builder: (context, offset, _) {
              final collapseT = (offset / collapseRange).clamp(0.0, 1.0);
              final centerTitleOpacity = ((collapseT - 0.84) / 0.12).clamp(
                0.0,
                1.0,
              );
              return DetailFloatingTopBar(
                onBack: () =>
                    unawaited(EmbeddedDetailLauncher.closeHostOrPop(context)),
                onMore: () {},
                title: title,
                titleOpacity: centerTitleOpacity,
                showBack: true,
                showMore: false,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 演职员 sliver(飞牛 + Emby 共享):复刻飞牛树(`_sectionReveal` 入场 + `Container` 内边距 +
  /// `CreditsSection`)。可见性 / 非空门控由调用方负责;头像鉴权随条目的
  /// [CreditPersonItem.images] 走(飞牛 NAS header / Emby api_key 直链),`onTap` 由调用方传入。
  /// `colors` 必须由调用方传 builder 作用域的 `context.appColors`
  /// (`DynamicPageThemeScope` 会改写子树主题,不可在此重取)。
  Widget _buildCreditsSliver({
    required AppThemeColors colors,
    required List<CreditPersonItem> items,
    ValueChanged<CreditPersonItem>? onTap,
  }) {
    return SliverToBoxAdapter(
      child: _sectionReveal(
        child: Container(
          color: colors.backgroundBase,
          padding: const EdgeInsets.fromLTRB(
            DetailTokens.screenHorizontalPadding,
            8,
            DetailTokens.screenHorizontalPadding,
            20,
          ),
          child: CreditsSection(
            title: AppLocalizations.of(context).detailCastCrewTitle,
            items: items,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  /// 描述 sliver(飞牛 + Emby 共享):复刻飞牛树(`_descriptionPopController` 的 `AnimatedBuilder`
  /// 入场 + `Container` 内边距 + `DetailDescriptionSection`)。`text` 由调用方传(飞牛传未 trim 的
  /// `detail.overview`,Emby 传已 trim 文案)并同时用于「展开全文」浮层内容;非空门控由调用方负责
  /// (飞牛无门控、恒显)。`overlayTitle` 是浮层标题(飞牛 `detailTitle` / Emby `title`)。`colors`
  /// 必须由调用方传 builder 作用域值(`DynamicPageThemeScope` 改写子树主题,不可在此重取)。
  Widget _buildDescriptionSliver({
    required AppThemeColors colors,
    required String text,
    required String overlayTitle,
    required double bottomPadding,
  }) {
    return SliverToBoxAdapter(
      child: AnimatedBuilder(
        animation: _descriptionPopController,
        builder: (context, child) {
          return Opacity(
            opacity: _descriptionVisible ? _descriptionOpacity.value : 0,
            child: Transform.translate(
              offset: Offset(
                0,
                _descriptionVisible ? _descriptionTranslateY.value : 10,
              ),
              child: Transform.scale(
                scale: _descriptionVisible ? _descriptionScale.value : 0.97,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
        child: Container(
          color: colors.backgroundBase,
          padding: EdgeInsets.fromLTRB(
            DetailTokens.screenHorizontalPadding,
            4,
            DetailTokens.screenHorizontalPadding,
            bottomPadding,
          ),
          child: DetailDescriptionSection(
            text: text,
            onMoreTap: () {
              LongTextOverlayPage.show(
                context,
                title: overlayTitle,
                sectionTitle: AppLocalizations.of(context).detailOverviewTitle,
                content: text,
              );
            },
          ),
        ),
      ),
    );
  }

  /// Hero sliver(飞牛 + Emby 共享):复刻飞牛树(`FadeTransition(_headerTitleOpacity)` 入场 +
  /// `DetailHeroOverlay`,`useSoftGradient: true` 恒定)。各参数由调用方传(飞牛剧集态有
  /// `titleFontSize`/较小 `bottomInset`/副标题,Emby 传裸标题 + logo)。Emby 顺带获得标题淡入
  /// (`_headerFadeController` 在中立加载路径已 `forward`)。
  Widget _buildHeroSliver({
    required double height,
    required String title,
    required String subtitle,
    double? titleFontSize,
    required double bottomInset,
    Widget? titleChild,
  }) {
    return SliverToBoxAdapter(
      child: FadeTransition(
        opacity: _headerTitleOpacity,
        child: DetailHeroOverlay(
          height: height,
          title: title,
          subtitle: subtitle,
          titleFontSize: titleFontSize,
          bottomInset: bottomInset,
          useSoftGradient: true,
          titleChild: titleChild,
        ),
      ),
    );
  }

  /// 外部链接 sliver(飞牛 + Emby 共享):复刻飞牛树(`_sectionReveal` + `Container` + `LinkSection`)。
  /// 读 `_imdbId`/`_trimId`(两后端都在 `_load` 设好)与 `_openImdb`/`_openTmdb`;非空门控由调用方负责。
  /// `colors` 由调用方传 builder 作用域值(`DynamicPageThemeScope` 改写子树主题,不可在此重取)。
  Widget _buildLinkSliver({required AppThemeColors colors}) {
    return SliverToBoxAdapter(
      child: _sectionReveal(
        child: Container(
          color: colors.backgroundBase,
          padding: const EdgeInsets.fromLTRB(
            DetailTokens.screenHorizontalPadding,
            8,
            DetailTokens.screenHorizontalPadding,
            24,
          ),
          child: LinkSection(
            imdbId: _imdbId,
            tmdbId: _trimId,
            onImdbTap: _openImdb,
            onTmdbTap: _openTmdb,
          ),
        ),
      ),
    );
  }

  String _paneEpisodeThemeBackdropFallback() {
    final initial = widget.initialItemDetail;
    if (initial == null) {
      return '';
    }
    final rawItem = initial['item'];
    final item = rawItem is Map<String, dynamic> ? rawItem : initial;
    return (item['backdrops'] ?? item['backdrop'] ?? '').toString().trim();
  }

  String _dynamicThemePathForPlayItem(PlayItem item) {
    final type = item.type.trim().toLowerCase();
    if (_isPane && type == 'episode') {
      if (item.backdrops.isNotEmpty) return item.backdrops;
      final fallbackBackdrop = _paneEpisodeThemeBackdropFallback();
      if (fallbackBackdrop.isNotEmpty) return fallbackBackdrop;
      if (item.stillPath.isNotEmpty) return item.stillPath;
      return item.posters;
    }
    return _heroPathForPlayItem(item);
  }

  String _episodeHeroSubtitle(PlayItem item) {
    final itemType = item.type.trim().toLowerCase();
    if (itemType != 'episode') return '';

    final parts = <String>[];
    final tvTitle = item.tvTitle.trim();
    if (tvTitle.isNotEmpty) {
      parts.add(tvTitle);
    }

    if (item.seasonNumber == 0) {
      parts.add(AppLocalizations.of(context).detailSeasonSpecial);
    } else if (item.seasonNumber > 0) {
      parts.add(
        AppLocalizations.of(context).detailSeasonNumber(item.seasonNumber),
      );
    } else if (item.parentTitle.trim().isNotEmpty) {
      parts.add(item.parentTitle.trim());
    }

    if (item.episodeNumber > 0) {
      parts.add(
        AppLocalizations.of(context).detailEpisodeNumber(item.episodeNumber),
      );
    }

    return parts.join(' · ');
  }

  /// 中立(Emby)剧集 hero 副标题（剧名 · 季 · 集），与飞牛 [_episodeHeroSubtitle] 同口径。
  /// 非剧集返回空 → hero 不显示副标题。
  String _neutralEpisodeHeroSubtitle(MediaDetail detail) {
    if (detail.type.trim().toLowerCase() != 'episode') return '';

    final parts = <String>[];
    final series = detail.parentTitle.trim();
    if (series.isNotEmpty) parts.add(series);

    if (detail.seasonNumber == 0) {
      parts.add(AppLocalizations.of(context).detailSeasonSpecial);
    } else if (detail.seasonNumber > 0) {
      parts.add(
        AppLocalizations.of(context).detailSeasonNumber(detail.seasonNumber),
      );
    }

    if (detail.episodeNumber > 0) {
      parts.add(
        AppLocalizations.of(context).detailEpisodeNumber(detail.episodeNumber),
      );
    }

    return parts.join(' · ');
  }

  String _suggestedThemeNameBase(PlayItem item, String detailTitle) {
    final itemType = item.type.trim().toLowerCase();
    if (itemType == 'episode') {
      final seriesTitle = item.tvTitle.trim().isNotEmpty
          ? item.tvTitle.trim()
          : (item.parentTitle.trim().isNotEmpty
                ? item.parentTitle.trim()
                : detailTitle);
      return buildThemeSaveNameBase(
        l10n: AppLocalizations.of(context),
        title: detailTitle,
        seriesTitle: seriesTitle,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        isEpisode: true,
      );
    }
    return buildThemeSaveNameBase(
      l10n: AppLocalizations.of(context),
      title: detailTitle,
    );
  }

  Future<void> _load() async {
    _entryActionTimer?.cancel();
    _deferredSectionTimer?.cancel();
    _headerFadeController.reset();
    _actionsPopController.reset();
    _descriptionPopController.reset();
    _downloadedRecordSignatureForCurrentItem = null;
    _localDownloadedFileInfoSnapshot = null;
    _localDownloadedFileInfoRequestId++;
    setState(() {
      _loading = true;
      _error = null;
      _descriptionVisible = false;
      _creditsVisible = false;
      _fileInfoVisible = false;
      _videoInfoVisible = false;
      _linkVisible = false;
      _deferredSectionLoadStarted = false;
      _heroAsyncSectionsResolved = false;
      _personCredits = const [];
      _streamOptions = const [];
      _streamTrackData = null;
      _selectedStreamIndex = null;
      _selectedSubtitleGuid = null;
      _selectedAudioGuid = null;
      _subtitleSelectorExpanded = false;
      _audioSelectorExpanded = false;
      _genresMapZhCn = const <int, String>{};
      _locateMapZhCn = const <String, String>{};
      _authorizedDirs = const <AuthorizedDirEntry>[];
      _sourceInfo = null;
      _neutralVersions = const <MediaSourceVersion>[];
      _neutralSelectedVersionIndex = 0;
      _neutralSelectedAudioId = null;
      _neutralSelectedSubtitleId = null;
      _neutralAudioSelectorExpanded = false;
      _neutralSubtitleSelectorExpanded = false;
    });

    // 分屏详情等副引擎冷启动时,后端会话可能尚未从磁盘就绪 → MediaBackendProvider 会暂时
    // 默认回飞牛,导致 Emby 条目误用飞牛查询(noData)。读后端前先等会话就绪。
    final session = context.read<BackendSessionProvider>();
    try {
      await session.ensureReady();
    } on BackendSessionUnavailableException catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          error,
          action: 'play detail',
          fallbackKind: AppExceptionKind.transient,
          stackTrace: stackTrace,
        );
        _loading = false;
      });
      return;
    }
    if (!mounted) return;

    // 非飞牛后端(如 Emby):只读中立 MediaDetail 渲染展示半身,不加载飞牛播放数据。
    // 数据/导航层按 backend 能力分支,UI 渲染不写 if(isEmby)。
    final backend = context.read<MediaBackendProvider>().backend;
    if (backend.capabilities.kind != MediaBackendKind.feiniu) {
      _neutralDisplayOnly = true;
      try {
        final detail = await backend.getItemDetail(_currentItemGuid);
        // 版本 + 文件/视频信息 best-effort:失败不阻断详情展示。
        var versions = const <MediaSourceVersion>[];
        try {
          versions = await backend.getItemSourceVersions(_currentItemGuid);
        } catch (error, stackTrace) {
          await logSwallowedError(
            action: 'load neutral source versions',
            id: _currentItemGuid,
            error: error,
            stackTrace: stackTrace,
            source: 'play_detail_page',
            details: 'backend=${backend.capabilities.kind.name}',
          );
          versions = const <MediaSourceVersion>[];
        }
        if (!mounted) return;
        // 地区本地化在此渲染层做（mapper 无 l10n）：英文国名 / ISO code → 中文，未知原样。
        final l10n = AppLocalizations.of(context);
        final localizedVersions = _localizeNeutralSourceVersions(
          versions,
          l10n,
        );
        final selectedVersion = localizedVersions.isNotEmpty
            ? localizedVersions.first
            : null;
        final localizedDetail = detail.copyWith(
          regionLabels: RegionNameLocalizer.localizeAll(
            l10n,
            detail.regionLabels,
          ),
        );
        // 骨架→正文整树替换等转场结束再应用，避免落在 380ms 转场窗口内
        // （对齐 tv_detail 中立分支的既有闸门模式）。
        await RouteTransitionGate.of(context);
        if (!mounted) return;
        setState(() {
          _detail = localizedDetail;
          _neutralVersions = localizedVersions;
          _neutralSelectedVersionIndex = 0;
          // 音轨/字幕初始化为选中版本的默认轨(无默认则首条音轨 / 字幕关闭)。
          _neutralSelectedAudioId = _defaultAudioIdFor(selectedVersion);
          _neutralSelectedSubtitleId = selectedVersion?.defaultSubtitleId ?? '';
          _sourceInfo = selectedVersion?.info;
          _data = null;
          _liked = detail.favorite;
          _watched = detail.watched;
          _imdbId = detail.externalIds.imdbId;
          _trimId = detail.externalIds.tmdbId;
          _descriptionVisible = true;
          _creditsVisible = true;
          _loading = false;
        });
        _handleDownloadTasksChanged();
        _headerFadeController.forward(from: 0);
        _actionsPopController.forward(from: 0);
        _descriptionPopController.forward(from: 0);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = AppException.from(
            e,
            action: 'play detail',
            fallbackKind: AppExceptionKind.transient,
          );
          _loading = false;
        });
      }
      return;
    }
    _neutralDisplayOnly = false;

    try {
      final api = FeiniuApi(context.read<NasProvider>());
      // Phase 1: load only base play info for immediate first paint.
      final info = await _loadPlayInfo(api, _currentItemGuid);
      if (!mounted) return;
      _currentItemGuid = info.item.guid.trim().isNotEmpty
          ? info.item.guid.trim()
          : _currentItemGuid;

      // Phase 2 与下载画质预取先行发起，让网络请求与转场动画并行；
      // 它们应用结果时各自过闸（_loadPhase2 内已有 RouteTransitionGate）。
      unawaited(_loadPhase2(api: api, info: info));

      // Pre-fetch download qualities so the download sheet opens instantly.
      unawaited(
        _prefetchDownloadQualities(
          gateway: FeiniuDetailDataGateway.forApi(api),
          itemGuid: _currentItemGuid,
          playItem: info.item,
        ),
      );

      // 骨架→正文的整树替换 + 入场动画等转场结束再做，避免与 380ms
      // enter 动画同窗叠加（对齐 Phase-2 与 tv_detail 的既有闸门模式）。
      await RouteTransitionGate.of(context);
      if (!mounted) return;
      setState(() {
        _data = info;
        _liked = info.item.isFavorite == 1;
        _watched = info.item.isWatched == 1;
        _imdbId = _extractInitialImdbId();
        _trimId = _extractInitialTrimId();
        _rebuildDetail();
        _loading = false;
      });
      _handleDownloadTasksChanged();
      _startEntryAnimations();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'play detail',
          fallbackKind: AppExceptionKind.transient,
        );
        _loading = false;
      });
    }
  }

  String _extractInitialImdbId() {
    final initial = widget.initialItemDetail;
    if (initial == null) return '';
    return PlayDetailDataLoader.extractImdbId(initial);
  }

  String _extractInitialTrimId() {
    final initial = widget.initialItemDetail;
    if (initial == null) return '';
    return PlayDetailDataLoader.extractTrimId(initial);
  }

  /// 用页面当前已加载的数据在进程内构造公共详情展示快照 [_detail]，零额外网络。
  ///
  /// 渐进加载下随各阶段数据到达调用：首屏拿到 [_data] 后即可建（此时题材/地区字典与
  /// 演职员可能尚空 → 题材名回退原 id、演职员为空），Phase 2 字典就绪、deferred 演职员
  /// 就绪后重建即补齐。复用 [mapFeiniuItemDetail]（纯函数），不触网、不改播放路径。
  void _rebuildDetail() {
    final info = _data;
    if (info == null) {
      _detail = null;
      return;
    }
    _detail = mapFeiniuItemDetail(
      info,
      genresMap: _genresMapZhCn,
      regionNames: _locateMapZhCn,
      credits: _personCredits,
      imdbId: _imdbId,
    );
  }

  void _startEntryAnimations() {
    if (_playerRouteActive) return;
    _headerFadeController.forward(from: 0);
    _actionsPopController.forward(from: 0);
    _entryActionTimer?.cancel();
    _deferredSectionTimer?.cancel();
    _deferredSectionTimer = Timer(_deferredSectionStartDelay, () {
      if (!mounted || _playerRouteActive) return;
      setState(() => _descriptionVisible = true);
      _descriptionPopController.forward(from: 0);
      unawaited(_loadDeferredSections());
    });
  }

  Future<void> _loadPhase2({
    required FeiniuApi api,
    required PlayInfoData info,
  }) async {
    if (!mounted || _playerRouteActive) return;
    try {
      final genresMapFuture = api
          .getTagGenresMap(lan: 'zh-CN')
          .catchError((_) => const <int, String>{});
      final locateMapFuture = api
          .getTagIso3166Map(lan: 'zh-CN')
          .catchError((_) => const <String, String>{});
      final languageMapFuture = api
          .getTagIso6392Map(lan: 'zh-CN')
          .catchError((_) => const <String, String>{});
      final trackData = await _loadStreamTrackData(api, _currentItemGuid);
      if (!mounted || _playerRouteActive) return;
      final streams = trackData.options;
      final initialIndex = streams.indexWhere(
        (e) => e.mediaGuid == info.mediaGuid,
      );
      final selectedIndex = initialIndex >= 0 ? initialIndex : null;
      final selectedMediaGuid =
          (selectedIndex != null &&
              selectedIndex >= 0 &&
              selectedIndex < streams.length)
          ? streams[selectedIndex].mediaGuid
          : '';
      final subtitleTracks = trackData.subtitlesForMedia(selectedMediaGuid);
      final audioTracks = trackData.audiosForMedia(selectedMediaGuid);
      final genresMap = await genresMapFuture;
      final locateMap = await locateMapFuture;
      final languageMap = await languageMapFuture;
      if (!mounted || _playerRouteActive) return;
      MediaLanguageMapper.mergeLanguageMap(languageMap);
      // 轨道/地区数据就绪后等转场结束再应用，避免转场窗口内的整树重建。
      await RouteTransitionGate.of(context);
      if (!mounted || _playerRouteActive) return;
      setState(() {
        _streamTrackData = trackData;
        _streamOptions = streams;
        _selectedStreamIndex = selectedIndex;
        _selectedSubtitleGuid = PlayDetailTrackSelector.pickInitialSubtitleGuid(
          preferred: info.subtitleGuid,
          tracks: subtitleTracks,
        );
        _selectedAudioGuid = PlayDetailTrackSelector.pickInitialAudioGuid(
          preferred: info.audioGuid,
          tracks: audioTracks,
        );
        _genresMapZhCn = genresMap;
        _locateMapZhCn = locateMap;
        _rebuildDetail();
      });
      // 轨道数据就绪后加载手动导入的本地字幕（面板合并展示）。
      unawaited(_refreshManualSubtitleEntries());
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'load play detail locale maps',
          source: 'play_detail_page',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      // Keep base UI alive even if track request fails.
    } finally {
      if (mounted && !_playerRouteActive && !_heroAsyncSectionsResolved) {
        setState(() => _heroAsyncSectionsResolved = true);
      }
    }
  }

  Future<void> _loadDeferredSections() async {
    if (_deferredSectionLoadStarted || !mounted || _playerRouteActive) return;
    _deferredSectionLoadStarted = true;
    final api = FeiniuApi(context.read<NasProvider>());

    try {
      final people = await _loadPersonCredits(api, _currentItemGuid)
          .then<List<PersonCredit>>((v) => v)
          .catchError((Object error, StackTrace stackTrace) {
            unawaited(
              logSwallowedError(
                action: 'load play detail credits',
                id: _currentItemGuid,
                error: error,
                stackTrace: stackTrace,
                source: 'play_detail_page',
              ),
            );
            return const <PersonCredit>[];
          });
      if (!mounted) return;
      if (_playerRouteActive) {
        _deferredSectionLoadStarted = false;
        return;
      }
      setState(() {
        _personCredits = people;
        _creditsVisible = people.isNotEmpty;
        _rebuildDetail();
      });
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'apply play detail credits',
        id: _currentItemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'play_detail_page',
      );
    }

    await Future<void>.delayed(_deferredSectionStepDelay);
    if (!mounted) return;
    if (_playerRouteActive) {
      _deferredSectionLoadStarted = false;
      return;
    }
    setState(() {
      _fileInfoVisible = true;
      _videoInfoVisible = true;
    });

    try {
      final dirs = await api
          .getAppAuthorizedDirs()
          .then<List<AuthorizedDirEntry>>((value) => value)
          .catchError((Object error, StackTrace stackTrace) {
            unawaited(
              logSwallowedError(
                action: 'load app authorized directories',
                id: _currentItemGuid,
                error: error,
                stackTrace: stackTrace,
                source: 'play_detail_page',
              ),
            );
            return const <AuthorizedDirEntry>[];
          });
      if (!mounted) return;
      if (_playerRouteActive) {
        _deferredSectionLoadStarted = false;
        return;
      }
      setState(() => _authorizedDirs = dirs);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'apply play detail authorized directories',
        id: _currentItemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'play_detail_page',
      );
    }

    await Future<void>.delayed(_deferredSectionStepDelay);
    if (!mounted) return;
    if (_playerRouteActive) {
      _deferredSectionLoadStarted = false;
      return;
    }
    try {
      final initialDetail = widget.initialItemDetail;
      var imdbId = initialDetail == null
          ? ''
          : PlayDetailDataLoader.extractImdbId(initialDetail);
      var trimId = initialDetail == null
          ? ''
          : PlayDetailDataLoader.extractTrimId(initialDetail);
      if (trimId.isEmpty) {
        trimId = _data?.item.trimId.trim() ?? '';
      }
      if (imdbId.isEmpty && trimId.isEmpty) {
        final detail = await _loadItemDetail(api, _currentItemGuid);
        if (!mounted) return;
        if (_playerRouteActive) {
          _deferredSectionLoadStarted = false;
          return;
        }
        imdbId = PlayDetailDataLoader.extractImdbId(detail);
        trimId = PlayDetailDataLoader.extractTrimId(detail);
      }
      if (!mounted) return;
      if (_playerRouteActive) {
        _deferredSectionLoadStarted = false;
        return;
      }
      setState(() {
        _imdbId = imdbId;
        _trimId = trimId;
        _linkVisible = _imdbId.trim().isNotEmpty || _trimId.trim().isNotEmpty;
      });
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load play detail external links',
        id: _currentItemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'play_detail_page',
      );
    }
  }

  Future<PlayInfoData> _loadPlayInfo(FeiniuApi api, String itemGuid) {
    if (!_useRuntimeCache) {
      return api.getPlayInfo(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<PlayInfoData>(
      bucket: 'play_info',
      key: itemGuid,
      loader: () => api.getPlayInfo(itemGuid),
    );
  }

  Future<StreamTrackData> _loadStreamTrackData(FeiniuApi api, String itemGuid) {
    if (!_useRuntimeCache) {
      return api.getStreamTrackData(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<StreamTrackData>(
      bucket: 'stream_track',
      key: itemGuid,
      loader: () => api.getStreamTrackData(itemGuid),
    );
  }

  Future<List<PersonCredit>> _loadPersonCredits(
    FeiniuApi api,
    String itemGuid,
  ) {
    if (!_useRuntimeCache) {
      return api.getPersonList(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<List<PersonCredit>>(
      bucket: 'person_list',
      key: itemGuid,
      loader: () => api.getPersonList(itemGuid),
    );
  }

  Future<Map<String, dynamic>> _loadItemDetail(FeiniuApi api, String itemGuid) {
    if (!_useRuntimeCache) {
      return api.getItemDetail(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<Map<String, dynamic>>(
      bucket: 'item_detail',
      key: itemGuid,
      loader: () => api.getItemDetail(itemGuid),
    );
  }

  StreamListOption? _currentStreamOption() {
    return PlayDetailTrackSelector.currentStreamOption(
      options: _streamOptions,
      selectedIndex: _selectedStreamIndex,
    );
  }

  List<SubtitleTrackOption> _currentSubtitleTracks() {
    final backendTracks = PlayDetailTrackSelector.subtitleTracksForCurrentMedia(
      options: _streamOptions,
      selectedIndex: _selectedStreamIndex,
      trackData: _streamTrackData,
    );
    // 合并当前媒体的手动导入本地字幕轨（SAF 添加，持久化）。
    final mediaGuid = _currentStreamOption()?.mediaGuid ?? '';
    final manualTracks = manualSubtitleTracksForMedia(
      mediaGuid,
      _manualSubtitleEntries,
    );
    return PlayDetailTrackSelector.mergeSubtitleTracks(
      primaryTracks: backendTracks,
      extraTracks: manualTracks,
    );
  }

  List<AudioTrackOption> _currentAudioTracks() {
    return PlayDetailTrackSelector.audioTracksForCurrentMedia(
      options: _streamOptions,
      selectedIndex: _selectedStreamIndex,
      trackData: _streamTrackData,
    );
  }

  String _currentAudioTypeForBadges() {
    return PlayDetailTrackSelector.currentAudioTypeForBadges(
      selectedAudioGuid: _selectedAudioGuid,
      audioTracks: _currentAudioTracks(),
      selectedOption: _currentStreamOption(),
    );
  }

  /// 重新加载当前媒体的手动导入本地字幕元数据（store 变更 / 原生壳导入通知 / 回前台时刷新）。
  Future<void> _refreshManualSubtitleEntries() async {
    final itemGuid = _currentItemGuid;
    final mediaGuid = _currentStreamOption()?.mediaGuid ?? '';
    // 按 itemGuid 优先匹配（mediaGuid 经画质归一化可能不一致），回退 mediaGuid。
    const store = ManualSubtitleStore();
    final entries = await store.loadForItem(itemGuid, mediaGuid: mediaGuid);
    final persistedSelection = await store.selectedGuidForItem(
      itemGuid,
      mediaGuid: mediaGuid,
    );
    if (!mounted ||
        itemGuid != _currentItemGuid ||
        mediaGuid != (_currentStreamOption()?.mediaGuid ?? '')) {
      return;
    }
    var nextSelectedSubtitleGuid = _selectedSubtitleGuid;
    if (persistedSelection != null &&
        entries.any((entry) => entry.guid == persistedSelection)) {
      nextSelectedSubtitleGuid = persistedSelection;
    } else if (isManualSubtitleGuid(nextSelectedSubtitleGuid ?? '') &&
        !entries.any((entry) => entry.guid == nextSelectedSubtitleGuid)) {
      nextSelectedSubtitleGuid = null;
    }
    final entriesChanged =
        _manualSubtitleEntries.length != entries.length ||
        !_sameManualSubtitleEntries(_manualSubtitleEntries, entries);
    final selectionChanged = nextSelectedSubtitleGuid != _selectedSubtitleGuid;
    if (entriesChanged || selectionChanged) {
      setState(() {
        _manualSubtitleEntries = entries;
        _selectedSubtitleGuid = nextSelectedSubtitleGuid;
      });
    } else {
      _manualSubtitleEntries = entries;
    }
  }

  static bool _sameManualSubtitleEntries(
    List<ManualSubtitleEntry> a,
    List<ManualSubtitleEntry> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].guid != b[i].guid ||
          a[i].path != b[i].path ||
          a[i].fileName != b[i].fileName ||
          a[i].format != b[i].format) {
        return false;
      }
    }
    return true;
  }

  void _syncTrackSelectionForCurrentMedia() {
    final synced = PlayDetailTrackSelector.syncTrackSelectionForCurrentMedia(
      currentSubtitleGuid: _selectedSubtitleGuid,
      currentAudioGuid: _selectedAudioGuid,
      subtitleTracks: _currentSubtitleTracks(),
      audioTracks: _currentAudioTracks(),
    );
    _selectedSubtitleGuid = synced.subtitleGuid;
    _selectedAudioGuid = synced.audioGuid;
  }

  Future<void> _showSubtitleSheet(BuildContext sheetContext) async {
    // 打开前刷新本地字幕元数据，确保原生壳刚导入的字幕立即出现在面板。
    await _refreshManualSubtitleEntries();
    if (!mounted || !sheetContext.mounted) return;
    final tracks = _currentSubtitleTracks();
    if (tracks.isEmpty) return;
    if (mounted) {
      setState(() => _subtitleSelectorExpanded = true);
    }
    final result = await PlayDetailSheetController.showSubtitleSheet(
      sheetContext,
      subtitleTracks: tracks,
      selectedSubtitleGuid: _selectedSubtitleGuid,
    );
    if (mounted) {
      setState(() => _subtitleSelectorExpanded = false);
    }
    if (!mounted || result == null) return;
    // 删除标记：删除本地字幕（prefs 元数据 + 私有目录文件），随后重开面板。
    final deleteGuid = PlayDetailSheetController.subtitleDeleteGuidOf(result);
    if (deleteGuid != null && deleteGuid.isNotEmpty) {
      await _deleteManualSubtitle(deleteGuid);
      await _refreshManualSubtitleEntries();
      if (mounted) {
        await _showSubtitleSheet(context);
      }
      return;
    }
    await const ManualSubtitleStore().setSelectedGuid(
      itemGuid: _currentItemGuid,
      mediaGuid: _currentStreamOption()?.mediaGuid ?? '',
      guid: isManualSubtitleGuid(result) ? result : null,
    );
    if (!mounted) return;
    setState(() {
      _selectedSubtitleGuid = result;
    });
  }

  /// 删除一条手动导入的本地字幕：先删私有目录文件，再删 prefs 元数据。
  Future<void> _deleteManualSubtitle(String guid) async {
    final deleted = await const ManualSubtitleStore().deleteByGuid(guid);
    if (deleted && mounted && _selectedSubtitleGuid == guid) {
      setState(() => _selectedSubtitleGuid = null);
    }
  }

  Future<void> _showAudioSheet(BuildContext sheetContext) async {
    final tracks = _currentAudioTracks();
    if (tracks.length <= 1) return;
    if (mounted) {
      setState(() => _audioSelectorExpanded = true);
    }
    final result = await PlayDetailSheetController.showAudioSheet(
      sheetContext,
      audioTracks: tracks,
      selectedAudioGuid: _selectedAudioGuid,
    );
    if (mounted) {
      setState(() => _audioSelectorExpanded = false);
    }
    if (!mounted || result == null) return;
    setState(() {
      _selectedAudioGuid = result;
    });
  }

  Future<void> _showMediaInfoDetail(BuildContext sheetContext) async {
    await PlayDetailSheetController.showMediaInfoDetail(
      sheetContext,
      streamOptions: _streamOptions,
      streamTrackData: _streamTrackData,
      selectedStreamIndex: _selectedStreamIndex,
      onVariantChanged: (index) {
        if (!mounted || index == _selectedStreamIndex) return;
        setState(() {
          _selectedStreamIndex = index;
          _syncTrackSelectionForCurrentMedia();
        });
      },
    );
  }

  Future<void> _openPlayer() async {
    final actionKey = 'play_detail_player:${_currentItemGuid.trim()}';
    if (_playerRouteActive || AsyncActionGuard.isRunning(actionKey)) {
      _showTopTip(
        AppLocalizations.of(context).detailPreparingPlayback,
        context.appColors.warning,
      );
      return;
    }
    final l10n = AppLocalizations.of(context);

    await AsyncActionGuard.run<void>(
      actionKey,
      settleDuration: const Duration(milliseconds: 500),
      action: () async {
        final data = _data;
        if (data == null) return;

        final localRecord = _downloadedRecordForCurrentItem();
        if (localRecord != null) {
          await _openLocalPlayer(localRecord);
          return;
        }

        final provider = context.read<NasProvider>();
        final api = FeiniuApi(provider);
        final selectedOption = _currentStreamOption();
        final mediaGuid = selectedOption?.mediaGuid ?? data.mediaGuid;
        if (mediaGuid.trim().isEmpty) {
          _showTopTip(
            AppLocalizations.of(
              context,
            ).detailPlaybackError('missing media guid'),
            context.appColors.danger,
          );
          return;
        }

        final streamUrl = api.getStreamUrl(mediaGuid);
        if (streamUrl.trim().isEmpty) {
          _showTopTip(
            AppLocalizations.of(
              context,
            ).detailPlaybackError('missing stream url'),
            context.appColors.danger,
          );
          return;
        }

        late final PlaybackStreamData playbackStream;
        try {
          playbackStream = await api.getPlaybackStream(mediaGuid);
        } catch (error) {
          if (!mounted) return;
          _showTopTip(
            AppLocalizations.of(context).detailPlaybackError('$error'),
            context.appColors.danger,
          );
          return;
        }

        final effectiveDuration =
            (selectedOption != null && selectedOption.duration > 0)
            ? selectedOption.duration
            : data.item.duration;
        final sourceTs = data.ts > 0 ? data.ts : data.item.watchedTs;
        final playbackCompleted =
            effectiveDuration > 0 &&
            ((effectiveDuration - sourceTs) <= 0 ||
                _watched ||
                data.item.isWatched == 1);
        final resume = await PlaybackResumePositionResolver.resolve(
          videoIds: <String>[data.item.guid, _currentItemGuid],
          durationSeconds: effectiveDuration,
          networkPositionSeconds: sourceTs,
          networkPositionAvailable: true,
          networkCompleted: playbackCompleted,
        );
        final effectiveTs = resume.position.inSeconds;
        final item = data.item;
        final title = formatPlayerTitleFromPlayItem(
          item,
          fallbackTitle: item.displayTitle,
          l10n: l10n,
        );

        final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
          selectedAudioGuid: _selectedAudioGuid?.trim().isNotEmpty == true
              ? _selectedAudioGuid
              : data.audioGuid,
          audioTracks: playbackStream.audioStreams,
        );
        final playerSubtitleTracks =
            PlayDetailTrackSelector.mergeSubtitleTracks(
              primaryTracks: playbackStream.subtitleStreams,
              extraTracks: _currentSubtitleTracks(),
            );
        final selectedSubtitle =
            PlayDetailTrackSelector.selectedOrFirstSubtitle(
              selectedSubtitleGuid:
                  _selectedSubtitleGuid?.trim().isNotEmpty == true
                  ? _selectedSubtitleGuid
                  : data.subtitleGuid,
              subtitleTracks: playerSubtitleTracks,
            );
        final playbackVideoGuid =
            playbackStream.videoStream?.guid.trim().isNotEmpty == true
            ? playbackStream.videoStream!.guid.trim()
            : data.videoGuid.trim();
        final playbackResolution =
            playbackStream.videoStream?.resolutionType.trim().isNotEmpty == true
            ? playbackStream.videoStream!.resolutionType.trim()
            : selectedOption?.resolutionType ?? '';
        final playbackBitrate = playbackStream.videoStream?.bps ?? 0;
        final preferExternalSubtitle =
            selectedSubtitle != null &&
            (selectedSubtitle.isExternal == 1 ||
                selectedSubtitle.extraFile == 1 ||
                selectedSubtitle.guid.startsWith('local:'));
        final embeddedSubtitleTrackIndex =
            selectedSubtitle == null || preferExternalSubtitle
            ? null
            : (() {
                final embeddedTracks = playerSubtitleTracks
                    .where((track) {
                      if (track.guid.trim().isEmpty) return false;
                      if (track.guid.startsWith('local:')) return false;
                      return track.isExternal != 1 && track.extraFile != 1;
                    })
                    .toList(growable: false);
                final ordinal = embeddedTracks.indexWhere(
                  (track) => track.guid == selectedSubtitle.guid,
                );
                if (ordinal < 0) return null;
                return ordinal + 1;
              })();
        final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
          playbackStream.qualities,
          _streamTrackData,
        );
        final selectedQuality = PlayerSourceController.preferredInitialQuality(
          mergedQualities,
        );
        final initialPlaybackVideoGuid =
            selectedQuality?.videoGuid.trim().isNotEmpty == true
            ? selectedQuality!.videoGuid.trim()
            : playbackVideoGuid;
        final initialPlaybackResolution =
            selectedQuality?.isDirectLink == true &&
                selectedQuality!.resolution.trim().isNotEmpty
            ? selectedQuality.resolution.trim()
            : playbackResolution;
        final initialPlaybackBitrate = selectedQuality?.isDirectLink == true
            ? selectedQuality!.bitrate
            : playbackBitrate;
        final initialPlayback = await const PlayerSourceController()
            .buildInitialPlaybackResult(
              api: api,
              directUrl: streamUrl,
              mediaGuid: mediaGuid,
              videoGuid: initialPlaybackVideoGuid,
              playbackStream: playbackStream,
              quality: selectedQuality,
              selectedAudio: selectedAudio,
              selectedSubtitle: selectedSubtitle,
              startPosition: Duration(seconds: effectiveTs),
            );
        final playableSource = initialPlayback.playableSource;
        final resolvedStartPosition =
            !playableSource.reliableSeek && effectiveTs > 0
            ? Duration.zero
            : resume.position;

        final source = MpvMediaSource(
          loadNonce: createMpvLoadNonce(),
          itemGuid: _currentItemGuid,
          seriesGuid: widget.seriesGuid.trim().isNotEmpty
              ? widget.seriesGuid.trim()
              : data.grandGuid.trim(),
          seasonGuid: data.parentGuid.trim().isNotEmpty
              ? data.parentGuid.trim()
              : (widget.initialItemDetail?['parent_guid'] ?? '')
                    .toString()
                    .trim(),
          posterPath: resolvePlayerArtworkPathForPlayItem(item),
          mediaGuid: initialPlayback.mediaGuid,
          mediaType: item.type,
          ancestorName: item.ancestorName,
          videoGuid: initialPlayback.videoGuid,
          directLinkQualityIndex: selectedQuality?.isDirectLink == true
              ? selectedQuality!.directLinkQualityIndex
              : null,
          videoWidth: playbackStream.videoStream?.width ?? 0,
          videoHeight: playbackStream.videoStream?.height ?? 0,
          proxySessionId: playableSource.proxySessionId,
          playLink: initialPlayback.playLink,
          serverSessionHlsTimeSeconds:
              initialPlayback.serverSessionHlsTimeSeconds,
          url: playableSource.url,
          headers: playableSource.headers,
          title: title,
          seriesTitle: item.tvTitle.trim().isNotEmpty
              ? item.tvTitle.trim()
              : title,
          seasonNumber: item.seasonNumber,
          tmdbId: item.trimId,
          episodeNumber: item.episodeNumber,
          startPosition: resolvedStartPosition,
          audioTrackIndex: selectedAudio?.index,
          subtitleTrackIndex: embeddedSubtitleTrackIndex,
          audioTrackGuid: selectedAudio?.guid ?? data.audioGuid,
          subtitleTrackGuid: selectedSubtitle?.guid ?? data.subtitleGuid,
          resolution: initialPlaybackResolution,
          bitrate: initialPlaybackBitrate,
          durationSeconds: effectiveDuration,
          videoCodecName: playbackStream.videoStream?.codecName ?? '',
          videoProfile: playbackStream.videoStream?.profile ?? '',
          colorSpace: playbackStream.videoStream?.colorSpace ?? '',
          colorTransfer: playbackStream.videoStream?.colorTransfer ?? '',
          colorPrimaries: playbackStream.videoStream?.colorPrimaries ?? '',
          bitDepth: playbackStream.videoStream?.bitDepth ?? 0,
          preferExternalSubtitle: preferExternalSubtitle,
          forceNativeProxy: playableSource.forceNativeProxy,
          reliableSeek: playableSource.reliableSeek,
          seekProbeSummary: playableSource.seekProbeSummary,
          playbackMode: initialPlayback.playbackMode,
          playbackSpeed: 1.0,
          audioTracks: playbackStream.audioStreams,
          subtitleTracks: playerSubtitleTracks,
          qualities: mergedQualities,
        );

        await _launchPlayer(source: source);
      },
    );
  }

  Future<void> _openLocalPlayer(DownloadTaskRecord record) async {
    final data = _data;
    if (data == null) return;
    if (record.filePath.trim().isEmpty) {
      _showTopTip(
        AppLocalizations.of(context).detailLocalVideoInvalid,
        context.appColors.warning,
      );
      return;
    }
    final l10n = AppLocalizations.of(context);

    final selectedOption = _currentStreamOption();
    final effectiveDuration =
        (selectedOption != null && selectedOption.duration > 0)
        ? selectedOption.duration
        : data.item.duration;
    final sourceTs = data.ts > 0 ? data.ts : data.item.watchedTs;
    final playbackCompleted =
        effectiveDuration > 0 &&
        ((effectiveDuration - sourceTs) <= 0 ||
            _watched ||
            data.item.isWatched == 1);
    final resume = await PlaybackResumePositionResolver.resolve(
      videoIds: <String>[data.item.guid, _currentItemGuid, record.itemGuid],
      durationSeconds: effectiveDuration,
      networkPositionSeconds: sourceTs,
      networkPositionAvailable: true,
      networkCompleted: playbackCompleted,
    );
    final startPosition = resume.position;
    final item = data.item;
    final title = formatPlayerTitleFromPlayItem(
      item,
      fallbackTitle: item.displayTitle,
      l10n: l10n,
    );
    final localVideo =
        _streamTrackData?.videoForMedia(record.mediaGuid) ??
        _streamTrackData?.videoForMedia(selectedOption?.mediaGuid ?? '') ??
        _streamTrackData?.videoForMedia(data.mediaGuid);
    final resolvedMediaGuid = record.mediaGuid.trim().isEmpty
        ? data.mediaGuid
        : record.mediaGuid;
    final localAudioTracks = _currentAudioTracks().isNotEmpty
        ? _currentAudioTracks()
        : record.audioTracks;
    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: _selectedAudioGuid?.trim().isNotEmpty == true
          ? _selectedAudioGuid
          : data.audioGuid,
      audioTracks: localAudioTracks,
    );
    final localSubtitleTracks = _currentSubtitleTracks().isNotEmpty
        ? _currentSubtitleTracks()
        : record.subtitleTracks;
    final selectedSubtitle = PlayDetailTrackSelector.selectedOrFirstSubtitle(
      selectedSubtitleGuid: _selectedSubtitleGuid?.trim().isNotEmpty == true
          ? _selectedSubtitleGuid
          : data.subtitleGuid,
      subtitleTracks: localSubtitleTracks,
    );
    final embeddedSubtitleTrackIndex =
        PlayDetailTrackSelector.embeddedSubtitleTrackIndex(
          selectedSubtitle: selectedSubtitle,
          subtitleTracks: localSubtitleTracks,
        );
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      const <PlaybackQualityOption>[],
      _streamTrackData,
    );
    final localSubtitleBundle = await discoverLocalSubtitleBundleAsync(
      mediaGuid: resolvedMediaGuid,
      videoFilePath: record.filePath,
    );
    // 合并当前媒体的持久化手动导入本地字幕（SAF 添加），使本地文件播放也能 sub-add。
    final manualEntries = await const ManualSubtitleStore().loadForMedia(
      resolvedMediaGuid,
    );
    final manualTracks = manualSubtitleTracksForMedia(
      resolvedMediaGuid,
      manualEntries,
    );
    final manualBundle = LocalSubtitleBundle(
      tracks: manualTracks,
      fileByGuid: <String, String>{
        for (final entry in manualEntries) entry.guid: entry.path,
      },
      preferredGuid: manualTracks.isEmpty ? null : manualTracks.first.guid,
    );
    final mergedLocalSubtitleBundle = LocalSubtitleBundle.merge(
      localSubtitleBundle,
      manualBundle,
    );
    final source = MpvMediaSource.localFile(
      filePath: record.filePath,
      itemGuid: _currentItemGuid,
      seriesGuid: widget.seriesGuid.trim().isNotEmpty
          ? widget.seriesGuid.trim()
          : data.grandGuid.trim(),
      seasonGuid: data.parentGuid.trim().isNotEmpty
          ? data.parentGuid.trim()
          : (widget.initialItemDetail?['parent_guid'] ?? '').toString().trim(),
      posterPath: resolvePlayerArtworkPathForPlayItem(item),
      mediaGuid: resolvedMediaGuid,
      mediaType: item.type,
      ancestorName: item.ancestorName,
      videoGuid: localVideo?.guid.trim().isNotEmpty == true
          ? localVideo!.guid.trim()
          : data.videoGuid,
      title: title,
      seriesTitle: item.tvTitle.trim().isNotEmpty ? item.tvTitle.trim() : title,
      seasonNumber: item.seasonNumber,
      tmdbId: item.trimId,
      episodeNumber: item.episodeNumber,
      startPosition: startPosition,
      audioTrackGuid: selectedAudio?.guid ?? data.audioGuid,
      subtitleTrackIndex: embeddedSubtitleTrackIndex,
      subtitleTrackGuid: _selectedSubtitleGuid?.trim().isNotEmpty == true
          ? _selectedSubtitleGuid
          : data.subtitleGuid,
      localSubtitleBundle: mergedLocalSubtitleBundle,
      resolution: record.resolution,
      bitrate: 0,
      durationSeconds: effectiveDuration,
      videoWidth: localVideo?.width ?? 0,
      videoHeight: localVideo?.height ?? 0,
      videoCodecName: localVideo?.codecName ?? '',
      videoProfile: localVideo?.profile ?? '',
      colorSpace: localVideo?.colorSpace ?? '',
      colorTransfer: localVideo?.colorTransfer ?? '',
      colorPrimaries: localVideo?.colorPrimaries ?? '',
      bitDepth: localVideo?.bitDepth ?? 0,
      audioTracks: localAudioTracks,
      subtitleTracks: localSubtitleTracks,
      qualities: mergedQualities,
      playbackSpeed: 1.0,
    );

    await _launchPlayer(source: source);
  }

  Future<void> _launchPlayer({required MpvMediaSource source}) async {
    final actionKey = <String>[
      'play_detail_launch',
      source.itemGuid.trim(),
      source.mediaGuid.trim(),
      source.videoGuid.trim(),
      source.url.trim(),
    ].where((value) => value.isNotEmpty).join(':');
    if (_playerRouteActive || AsyncActionGuard.isRunning(actionKey)) {
      _showTopTip(
        AppLocalizations.of(context).detailPreparingPlayback,
        context.appColors.warning,
      );
      return;
    }

    await AsyncActionGuard.run<void>(
      actionKey,
      settleDuration: const Duration(milliseconds: 500),
      action: () async {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        // 灰度：原生渲染器开启时走纯原生播放壳（无 Hybrid Composition，弹幕丝滑）。
        // 直接 launch + return，不触碰 _playerRouteActive/try-finally 状态机。
        final danmakuSettings = await const DanmakuSettingsStore().load();
        if (NativePlayerBridge.preferNativePlayerShell) {
          if (!mounted) return;
          // 反向通道：电影/单视频用 ItemPlaybackLauncher 重解析画质 + 续播回写（无选集）。
          // 本地外部视频无 NAS 上下文，resolver 自然返回 null/进度回写跳过，降级不影响播放。
          final nas = context.read<NasProvider>();
          final backend = context.read<MediaBackendProvider>().backend;
          // Bug fix(继续观看无选集 + 无弹幕)：episode 类型加载整季集列表供原生壳
          // 选集对话框使用；同时改为 launch + 手动弹幕预取（原 launch 不预取弹幕）。
          List<Map<String, dynamic>> episodes = const [];
          final seasonGuid = source.seasonGuid.trim();
          if (source.mediaType.toLowerCase() == 'episode' &&
              seasonGuid.isNotEmpty) {
            try {
              episodes = await const ItemPlaybackLauncher().loadSeasonEpisodes(
                nas,
                seasonGuid,
              );
            } catch (error, stackTrace) {
              await logSwallowedError(
                action: 'prefetch native season episodes',
                id: seasonGuid,
                error: error,
                stackTrace: stackTrace,
                source: 'play_detail_page',
              );
            }
          }
          // 弹幕预取(danmakuSettings 已在外层加载)。
          String? danmakuFile;
          if (danmakuSettings.enabled) {
            danmakuFile = await NativeDanmakuPrefetch.resolveToFile(
              seriesTitle: source.seriesTitle,
              itemTitle: source.title,
              seasonNumber: source.seasonNumber,
              episodeNumber: source.episodeNumber,
              tmdbId: source.tmdbId,
              settings: danmakuSettings,
              itemGuid: source.itemGuid,
              mediaGuid: source.mediaGuid,
              seasonGuid: source.seasonGuid,
            );
          }
          // Bug 1 fix(选集消失)：捕获 episodes 进闭包，切集时回传给 resolver 合并进
          // loadArgs["episodes"]，保证每次换源后原生壳选集数据不丢。
          final capturedEpisodes = episodes;
          // 经统一 binder 按后端接线（本路径为飞牛电影/单视频，backend 即飞牛）。切集回传
          // 捕获的整季 episodes 合并进 loadArgs，保证换源后原生壳选集数据不丢。
          NativePlaybackReentry.bind(
            backend: backend,
            nas: nas,
            l10n: l10n,
            fallbackEpisodes: () => capturedEpisodes,
            onLocalSubtitleImported: (_) => _refreshManualSubtitleEntries(),
            onLocalSubtitleRemoved: (_) => _refreshManualSubtitleEntries(),
            onResolvePlayback:
                (
                  itemGuid, {
                  qualityIndex,
                  qualityMediaGuid,
                  startPositionMs,
                  subtitleGuid,
                  audioGuid,
                  // 单条目 launcher 本期不接序号/画质继承；声明以匹配桥接器函数类型。
                  audioTrackIndex,
                  subtitleTrackIndex,
                  preferredQualityResolution,
                }) {
                  // 记录原生壳当前(切集后)条目,回前台据此把详情跟到最后播放的那一集。
                  if (itemGuid.trim().isNotEmpty) {
                    _lastNativePlayedItemGuid = itemGuid.trim();
                  }
                  return const ItemPlaybackLauncher().resolveForNative(
                    nas,
                    itemGuid: itemGuid,
                    qualityIndex: qualityIndex,
                    qualityMediaGuid: qualityMediaGuid,
                    startPositionMs: startPositionMs,
                    subtitleGuid: subtitleGuid,
                    audioGuid: audioGuid,
                    episodes: capturedEpisodes.isEmpty
                        ? null
                        : capturedEpisodes,
                    l10n: AppLocalizations.of(context),
                  );
                },
          );
          // 标记已启动原生壳 + 初始播放条目;回前台时一次性刷新进度/跟到新集(性能门控)。
          _nativePlayerLaunched = true;
          _lastNativePlayedItemGuid = source.itemGuid.trim();
          if (await const NativePlaybackHost().launch(
            source: source,
            danmakuFilePath: danmakuFile,
            episodes: episodes.isEmpty ? null : episodes,
            nas: nas,
          )) {
            return;
          }
        }
        if (!mounted) return;
        _nativePlayerLaunched = false;
        _showTopTip(l10n.detailPlayInfoFailed, context.appColors.danger);
      },
    );
  }

  Future<void> _refreshAfterItemStateChange() async {
    final api = FeiniuApi(context.read<NasProvider>());
    final currentMediaGuid = _currentStreamOption()?.mediaGuid ?? '';
    final refreshed =
        await PlayDetailDataLoader(
          FeiniuDetailDataGateway.forApi(api),
        ).refreshAfterItemStateChange(
          itemGuid: _currentItemGuid,
          currentMediaGuid: currentMediaGuid,
          currentSubtitleGuid: _selectedSubtitleGuid,
          currentAudioGuid: _selectedAudioGuid,
        );

    _applyRefreshedDetailData(refreshed);
  }

  void _applyRefreshedDetailData(
    PlayDetailRefreshData refreshed, {
    int? currentTsSeconds,
  }) {
    if (!mounted) return;
    setState(() {
      _currentItemGuid = refreshed.info.item.guid.trim().isNotEmpty
          ? refreshed.info.item.guid.trim()
          : _currentItemGuid;
      _data = currentTsSeconds == null
          ? refreshed.info
          : refreshed.info.copyWith(ts: currentTsSeconds);
      _streamTrackData = refreshed.streamTrackData;
      _streamOptions = refreshed.streamOptions;
      _selectedStreamIndex = refreshed.selectedStreamIndex;
      _selectedSubtitleGuid = refreshed.selectedSubtitleGuid;
      _selectedAudioGuid = refreshed.selectedAudioGuid;
      _heroAsyncSectionsResolved = true;
      _liked = refreshed.info.item.isFavorite == 1;
      _watched = refreshed.info.item.isWatched == 1;
      _imdbId = refreshed.imdbId;
      _trimId = refreshed.trimId;
      _rebuildDetail();
    });
    _restoreContentVisibilityAfterPlayerExit();
  }

  void _restoreContentVisibilityAfterPlayerExit() {
    if (!mounted) return;
    if (!_descriptionVisible) {
      setState(() => _descriptionVisible = true);
    }
    if (_descriptionPopController.status != AnimationStatus.forward &&
        _descriptionPopController.value < 1.0) {
      _descriptionPopController.forward();
    }
  }

  Future<void> _openImdb() async {
    final result = await ImdbLauncher.openExternal(_imdbId);
    if (!mounted) return;
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          AppLocalizations.of(context).detailImdbEmpty,
          context.appColors.warning,
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          AppLocalizations.of(context).detailImdbOpenFailed,
          context.appColors.danger,
        );
    }
  }

  Future<void> _openTmdb() async {
    final result = await ImdbLauncher.openTmdbExternal(_trimId);
    if (!mounted) return;
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          AppLocalizations.of(context).detailTmdbEmpty,
          context.appColors.warning,
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          AppLocalizations.of(context).detailTmdbOpenFailed,
          context.appColors.danger,
        );
    }
  }

  void _openCreditPerson(CreditPersonItem person) {
    final guid = person.personGuid.trim();
    if (guid.isEmpty) return;
    AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.person(
        personGuid: guid,
        initialName: person.name,
        initialLocaleMap: _localeMap,
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
  }

  void _showTopTip(String message, Color color) {
    if (!mounted) return;
    _topTip.show(context, message: message, color: color);
  }

  Future<void> _toggleFavorite() async {
    final now = DateTime.now();
    if (_favoriteUpdating ||
        now.difference(_lastFavoriteTapAt) < _favoriteTapCooldown) {
      _showTopTip(
        AppLocalizations.of(context).commonClickTooFastRetryLater,
        context.appColors.warning,
      );
      return;
    }
    _lastFavoriteTapAt = now;
    _favoriteUpdating = true;
    final target = !_liked;
    final l10n = AppLocalizations.of(context);
    try {
      // 统一走中立后端接口:飞牛→FeiniuApi.setFavorite、Emby→FavoriteItems 端点，文案同口径。
      final backend = context.read<MediaBackendProvider>().backend;
      final state = await backend.setItemFavorite(
        _currentItemGuid,
        favorite: target,
      );
      if (!mounted) return;
      setState(() => _liked = state);
      _showTopTip(
        state ? l10n.actionFavoriteAdded : l10n.actionFavoriteRemoved,
        state ? context.appColors.success : context.appColors.textMuted,
      );
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'toggle favorite',
          source: 'play_detail_page',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.transient,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      _showTopTip(
        _liked
            ? AppLocalizations.of(context).detailUnfavoriteFailed
            : AppLocalizations.of(context).detailFavoriteFailed,
        context.appColors.danger,
      );
    } finally {
      _favoriteUpdating = false;
    }
  }

  Future<void> _toggleWatched() async {
    final now = DateTime.now();
    if (_watchedUpdating ||
        now.difference(_lastWatchedTapAt) < _watchedTapCooldown) {
      _showTopTip(
        AppLocalizations.of(context).commonClickTooFastRetryLater,
        context.appColors.warning,
      );
      return;
    }
    _lastWatchedTapAt = now;
    _watchedUpdating = true;
    final target = !_watched;
    final l10n = AppLocalizations.of(context);
    try {
      // 统一走中立后端接口:飞牛→FeiniuApi.setWatched、Emby→PlayedItems 端点，文案同口径。
      final backend = context.read<MediaBackendProvider>().backend;
      final state = await backend.setItemWatched(
        _currentItemGuid,
        watched: target,
      );
      if (!mounted) return;
      setState(() => _watched = state);
      _showTopTip(
        state ? l10n.actionMarkedAsWatched : l10n.actionMarkedAsUnwatched,
        state ? context.appColors.success : context.appColors.textMuted,
      );
      // 飞牛已看切换需回灌 PlayInfo（更新跨 UI 的已看/进度态）；中立后端无此数据通道,跳过。
      if (backend.capabilities.kind == MediaBackendKind.feiniu) {
        await _refreshAfterItemStateChange();
      }
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'toggle watched',
          source: 'play_detail_page',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.transient,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      if (!mounted) return;
      _showTopTip(
        _watched
            ? AppLocalizations.of(context).detailMarkUnwatchedFailed
            : AppLocalizations.of(context).detailMarkWatchedFailed,
        context.appColors.danger,
      );
    } finally {
      _watchedUpdating = false;
    }
  }

  /// 中立态下载占位:当前公共后端（Emby）未接下载队列,统一提示「不可用」（l10n）。
  void _neutralDownloadUnavailable() {
    _showTopTip(
      AppLocalizations.of(context).detailDownloadUnavailable,
      context.appColors.textMuted,
    );
  }

  /// 中立(Emby)「视频信息 → 查看全部」:底部弹窗展开完整文件信息 + 逐流明细
  /// 中立(Emby)文件信息 → 飞牛 [StreamFileInfo]（喂复用的 `FileInfoSection`）。Emby 仅有
  /// `DateCreated`（→ 添加时间），无单独「创建时间」故留空（显示 `-`）。无路径且无大小时返回
  /// null → 区块隐藏。
  StreamFileInfo? get _neutralFileInfo {
    final info = _sourceInfo;
    if (info == null || (info.path.isEmpty && info.sizeBytes <= 0)) return null;
    final added = DateTime.tryParse(info.addedDate);
    return StreamFileInfo(
      mediaGuid: '',
      path: info.path,
      fileName: '',
      size: info.sizeBytes,
      fileBirthTime: 0,
      createTime: added?.millisecondsSinceEpoch ?? 0,
      updateTime: 0,
    );
  }

  /// 「查看全部」：复用飞牛同款 [MediaDetailOverlayPage]（逐字段明细 + 多版本切换），
  /// 数据经 [MediaDetailVariant.fromSource] 由中立 [MediaSourceInfo] 适配；版本切换回写
  /// [_selectNeutralVersion]（与主页版本选择器联动）。无多源时退化为单版本。
  Future<void> _showNeutralSourceInfoSheet() async {
    final versions = _neutralVersions;
    final variants = <MediaDetailVariant>[];
    if (versions.isNotEmpty) {
      for (var i = 0; i < versions.length; i++) {
        final version = versions[i];
        if (!version.info.isNotEmpty) continue;
        variants.add(
          MediaDetailVariant.fromSource(
            key: version.id.isNotEmpty ? version.id : 'source-$i',
            title: version.label,
            info: version.info,
          ),
        );
      }
    } else if (_sourceInfo != null && _sourceInfo!.isNotEmpty) {
      variants.add(
        MediaDetailVariant.fromSource(
          key: 'source-0',
          title: AppLocalizations.of(context).detailVideoInfoTitle,
          info: _sourceInfo!,
        ),
      );
    }
    if (variants.isEmpty) return;
    final initial = (variants.length == versions.length)
        ? _neutralSelectedVersionIndex.clamp(0, variants.length - 1)
        : 0;
    await MediaDetailOverlayPage.show(
      context,
      variants: variants,
      initialIndex: initial,
      onVariantChanged: (index) {
        if (variants.length == versions.length) _selectNeutralVersion(index);
      },
    );
  }

  Future<void> _prefetchDownloadQualities({
    required FeiniuDetailDataGateway gateway,
    required String itemGuid,
    required PlayItem playItem,
  }) async {
    // Pre-fetch item detail so the download sheet opens instantly.
    await PlayDetailDownloadSheetController.prefetchItemDetail(
      gateway,
      itemGuid,
    );
    // Pre-fetch quality options for likely play-item guids.
    final candidates = <String>{
      itemGuid.trim(),
      playItem.guid.trim(),
    }.where((v) => v.isNotEmpty).toSet();
    for (final guid in candidates) {
      unawaited(
        PlayDetailDownloadSheetController.prefetchQualities(gateway, guid),
      );
    }
  }

  void _handleDownloadTap() {
    final item = _data?.item;
    final itemGuid = _currentItemGuid.trim();
    if (item == null || itemGuid.isEmpty) {
      _showTopTip(
        AppLocalizations.of(context).detailDownloadUnavailable,
        context.appColors.warning,
      );
      return;
    }
    final subtitleTracks = _currentSubtitleTracks();
    final selectedOption = _currentStreamOption();
    final selectedSubtitle = PlayDetailTrackSelector.selectedOrFirstSubtitle(
      selectedSubtitleGuid: _selectedSubtitleGuid?.trim().isNotEmpty == true
          ? _selectedSubtitleGuid
          : _data?.subtitleGuid,
      subtitleTracks: subtitleTracks,
    );
    unawaited(
      _downloadSheetController.show(
        context,
        gateway: FeiniuDetailDataGateway.forNas(context.read<NasProvider>()),
        itemGuid: itemGuid,
        item: item,
        selectedSubtitleTrack: selectedSubtitle,
        parentGuid:
            (widget.initialItemDetail?['parent_guid'] ?? '')
                .toString()
                .trim()
                .isNotEmpty
            ? (widget.initialItemDetail?['parent_guid'] ?? '').toString().trim()
            : (_data?.parentGuid.trim() ?? ''),
        previewUrls: ApiUrlHelper.imageCandidates(
          context.read<NasProvider>().baseUrl,
          _heroPathForPlayItem(item),
          width: 720,
        ),
        localeMap: _localeMap,
        itemDetail: PlayDetailDownloadSheetController.cachedItemDetail(
          itemGuid,
        ),
        playItemGuid: selectedOption?.mediaGuid,
        selectedMediaGuid: selectedOption?.mediaGuid ?? '',
        selectedResolution: selectedOption?.resolutionType ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (
      dynamicThemeEnabled: dynamicThemeEnabled,
      dynamicThemeIntensity: dynamicThemeIntensity,
    ) = context
        .select<
          AppThemeProvider,
          ({
            bool dynamicThemeEnabled,
            AppDynamicThemeIntensity dynamicThemeIntensity,
          })
        >(
          (themeProvider) => (
            dynamicThemeEnabled: themeProvider.dynamicThemeEnabled,
            dynamicThemeIntensity: themeProvider.dynamicThemeIntensity,
          ),
        );
    final nasProvider = context.read<NasProvider>();
    final inPlayerPaneHost = PlayerPaneHostScope.maybeOf(context) != null;
    // 中立态 hero/取色就绪条件看 _detail（_data 恒 null）；飞牛态仍看 _data。
    final deferHeroArtwork = _neutralDisplayOnly
        ? (_loading || _detail == null)
        : (_loading || _data == null);
    final deferAuxiliaryArtwork = _neutralDisplayOnly
        ? (_loading || _detail == null)
        : (_loading || !_heroAsyncSectionsResolved);
    var dynamicThemeKey = _currentItemGuid.trim().isNotEmpty
        ? _currentItemGuid
        : widget.itemGuid;
    // 取色图源同样经 resolver 统一解析(与背景 hero 同一入口);此处只取首候选喂调色板。
    final dynamicThemeResolver = DetailArtworkResolver(
      baseUrl: _neutralDisplayOnly ? '' : nasProvider.baseUrl,
      token: _neutralDisplayOnly ? '' : nasProvider.token,
      accessCode: _neutralDisplayOnly ? '' : nasProvider.accessCode,
    );
    var dynamicThemeImages = MediaImageRequest.empty;
    if (_neutralDisplayOnly && _detail != null) {
      // Emby 等中立后端:取色图用 _detail 的完整直链(自带 api_key),背景图优先、退海报。
      final neutral = _detail!;
      dynamicThemeImages = dynamicThemeResolver.resolveRefs(<MediaImageRef>[
        neutral.backdropImage,
        neutral.primaryImage,
      ]);
    } else if (_data != null) {
      final item = _data!.item;
      dynamicThemeImages = dynamicThemeResolver.resolvePath(
        _dynamicThemePathForPlayItem(item),
        width: 360,
      );
    } else if (widget.initialItemDetail != null) {
      final initialRawItem = widget.initialItemDetail!['item'];
      final initialItemMap = initialRawItem is Map<String, dynamic>
          ? initialRawItem
          : widget.initialItemDetail!;
      final initialItem = PlayItem.fromJson(initialItemMap);
      dynamicThemeImages = dynamicThemeResolver.resolvePath(
        _dynamicThemePathForPlayItem(initialItem),
        width: 360,
      );
    }
    final dynamicThemeImageUrl = dynamicThemeImages.urls.isNotEmpty
        ? dynamicThemeImages.urls.first
        : '';
    final allowRuntimeThemeSync = dynamicThemeIntensity
        .allowsGlobalRuntimeThemeSync(
          inPlayerPaneHost: inPlayerPaneHost,
          isPane: _isPane,
        );
    final dynamicThemeScopeEnabled = dynamicThemeEnabled;
    final syncGlobalTheme = dynamicThemeScopeEnabled && allowRuntimeThemeSync;
    final detailItemType = (_data?.item.type ?? '').trim().toLowerCase();
    assert(() {
      debugPrint(
        '[THEME][PLAY_DETAIL] page=$dynamicThemeKey type=$detailItemType enabled=$dynamicThemeScopeEnabled syncGlobal=$syncGlobalTheme live=${!deferHeroArtwork && dynamicThemeImageUrl.isNotEmpty} hasImage=${dynamicThemeImageUrl.isNotEmpty}',
      );
      return true;
    }());
    return DynamicPageThemeScope(
      pageKey: dynamicThemeKey,
      imageUrl: dynamicThemeImageUrl,
      imageHeaders: dynamicThemeImages.headers,
      enabled: dynamicThemeScopeEnabled,
      allowLiveResolve: !deferHeroArtwork && dynamicThemeImageUrl.isNotEmpty,
      syncGlobalTheme: syncGlobalTheme,
      deferLocalThemeApplyUntilGlobalSync: _isPane && allowRuntimeThemeSync,
      intensity: dynamicThemeIntensity,
      builder: (context, ambientTint) {
        final colors = context.appColors;
        // Persistent background layer — lives OUTSIDE the loading↔ready
        // crossFade so the backdrop image is never rebuilt/reloaded (and never
        // double-fades) when _loading flips. It reads the live scroll offset so
        // parallax still works once the ready content scrolls.
        final persistentProvider = context.read<NasProvider>();
        final persistentMedia = MediaQuery.of(context);
        final persistentBackdropWidth =
            (_isPane
                    ? persistentMedia.size.width *
                          persistentMedia.devicePixelRatio *
                          1.2
                    : 1200.0)
                .clamp(720.0, 1200.0)
                .round();
        // 图源经 DetailArtworkResolver 统一解析:Emby 的 _detail 引用是完整 api_key 直链
        // (直接用),飞牛的 _persistentHeroPath 是相对路径(走 imageCandidates + NAS token)。
        // 两分支同一入口,输出与旧内联逻辑逐字节等价。
        final persistentResolver = DetailArtworkResolver(
          baseUrl: _neutralDisplayOnly ? '' : persistentProvider.baseUrl,
          token: _neutralDisplayOnly ? '' : persistentProvider.token,
          accessCode: _neutralDisplayOnly ? '' : persistentProvider.accessCode,
        );
        final persistentHeroPath = _neutralDisplayOnly
            ? ''
            : _persistentHeroPath();
        final persistentHeroImages = _neutralDisplayOnly
            ? persistentResolver.resolveRefs(<MediaImageRef>[
                if (_detail != null) _detail!.backdropImage,
                if (_detail != null) _detail!.primaryImage,
              ])
            : (persistentHeroPath.isEmpty
                  ? MediaImageRequest.empty
                  : persistentResolver.resolvePath(
                      persistentHeroPath,
                      width: persistentBackdropWidth,
                    ));
        final persistentPosterHeight = _backdropHeroHeight(
          persistentMedia.size,
        );
        final persistentImageAlignment = _backdropImageAlignment(
          persistentMedia.size,
        );
        final persistentImageScale = _backdropImageScale(persistentMedia.size);
        final persistentBackground = ValueListenableBuilder<double>(
          valueListenable: _scrollOffsetNotifier,
          builder: (context, offset, _) {
            return ImmersiveDetailBackground(
              images: persistentHeroImages,
              // 低清铺底已全链路停用（实机决策 2026-07-26）：360 小图放大到大半屏
              // 高糊感明显，慢网下"糊图期"数秒，比纯色等待更差；Emby 侧拿海报垫
              // backdrop 更是两张图跳变。hero 就绪前保持主题底色，一次淡入到位。
              // 组件的垫底/就绪卸载机制保留，将来有"同图小宽度"引用可直接启用。
              scrollOffset: offset,
              posterHeight: persistentPosterHeight,
              imageScale: persistentImageScale,
              imageFit: BoxFit.cover,
              imageAlignment: persistentImageAlignment,
              parallaxFactor: 1.0,
              overlayOpacity: 0.62,
              ambientTintOverride: ambientTint,
            );
          },
        );
        late final Widget pageBody;
        if (_loading) {
          final initial = widget.initialItemDetail;
          if (initial == null) {
            pageBody = DetailLoadingSkeleton(presentation: widget.presentation);
          } else {
            final provider = context.read<NasProvider>();
            final artworkResolver = DetailArtworkResolver(
              baseUrl: _neutralDisplayOnly ? '' : provider.baseUrl,
              token: _neutralDisplayOnly ? '' : provider.token,
              accessCode: _neutralDisplayOnly ? '' : provider.accessCode,
            );
            final media = MediaQuery.of(context);
            final logoRequestWidth =
                (_isPane ? media.size.width * media.devicePixelRatio : 1200.0)
                    .clamp(480.0, 1200.0)
                    .round();
            final rawItem = initial['item'];
            final item = rawItem is Map<String, dynamic> ? rawItem : initial;
            final initialItemType = (item['type'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final fallbackTitle = formatPlayerTitle(
              seriesTitle: (item['tv_title'] ?? '').toString().trim().isNotEmpty
                  ? (item['tv_title'] ?? '').toString()
                  : (item['display_title'] ?? item['title'] ?? '').toString(),
              episodeTitle: (item['title'] ?? '').toString(),
              seasonNumber: _asInt(item['season_number']),
              episodeNumber: _asInt(item['episode_number']),
              fallbackTitle: (item['display_title'] ?? item['title'] ?? '')
                  .toString(),
              l10n: AppLocalizations.of(context),
            );
            final initialEpisodeTitle = (item['title'] ?? '').toString().trim();
            final initialDisplayTitle =
                (item['display_title'] ?? item['title'] ?? '')
                    .toString()
                    .trim();
            final title =
                initialItemType == 'episode' && initialEpisodeTitle.isNotEmpty
                ? initialEpisodeTitle
                : (initialDisplayTitle.isNotEmpty
                      ? initialDisplayTitle
                      : fallbackTitle);
            final logoImages = deferAuxiliaryArtwork
                ? MediaImageRequest.empty
                : artworkResolver.resolvePath(
                    (item['logos'] ?? '').toString(),
                    width: logoRequestWidth,
                  );
            final episodeHeroSubtitle =
                ((item['type'] ?? '').toString().trim().toLowerCase() ==
                    'episode')
                ? [
                    if ((item['tv_title'] ?? '').toString().trim().isNotEmpty)
                      (item['tv_title'] ?? '').toString().trim(),
                    if (_asInt(item['season_number']) == 0)
                      AppLocalizations.of(context).detailSeasonSpecial
                    else if (_asInt(item['season_number']) > 0)
                      AppLocalizations.of(
                        context,
                      ).detailSeasonNumber(_asInt(item['season_number'])),
                    if (_asInt(item['episode_number']) > 0)
                      AppLocalizations.of(
                        context,
                      ).detailEpisodeNumber(_asInt(item['episode_number'])),
                  ].join(' · ')
                : '';
            final initialHeroTitleChild = initialItemType != 'episode'
                ? (deferAuxiliaryArtwork
                      ? const SizedBox.shrink()
                      : (logoImages.isNotEmpty
                            ? DetailHeroLogoTitle(
                                images: logoImages,
                                fallbackTitle: title,
                                maxHeight: 112,
                                maxWidth:
                                    media.size.width -
                                    (DetailTokens.screenHorizontalPadding * 2),
                                fallbackFontSize: 28,
                              )
                            : null))
                : null;
            final posterHeight = _backdropHeroHeight(media.size);
            final layout = DetailLayoutSolver.solve(
              screenSize: media.size,
              safePadding: media.padding,
              posterHeight: posterHeight,
            );
            pageBody = Scaffold(
              backgroundColor: Colors.transparent,
              body: CustomScrollView(
                physics: const NeverScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: DetailHeroOverlay(
                      height: layout.infoStart,
                      title: title,
                      subtitle: episodeHeroSubtitle,
                      titleFontSize: initialItemType == 'episode' ? 28 : null,
                      bottomInset: initialItemType == 'episode' ? 20 : 36,
                      useSoftGradient: true,
                      titleChild: initialHeroTitleChild,
                    ),
                  ),
                ],
              ),
            );
          }
        } else if (_neutralDisplayOnly && _detail != null && _error == null) {
          // 中立后端(Emby)展示体:复用本页 hero/meta/描述/演职员组件,从 _detail 渲染。
          pageBody = _buildNeutralBody(colors);
        } else if (_error != null || _data == null) {
          pageBody = Scaffold(
            backgroundColor: colors.backgroundBase,
            appBar: _isPane
                ? null
                : AppBar(backgroundColor: colors.backgroundBase),
            body: AppErrorState(
              error: _error!,
              localeMap: _localeMap,
              onRetry: _load,
            ),
          );
        } else {
          final provider = context.read<NasProvider>();
          // logo / 海报 / 演职员头像图源经同一 resolver 解析(飞牛相对路径 → imageCandidates +
          // NAS token,Emby 直链直接用)。为 S2-6 统一两分支铺路;飞牛输出逐字节等价。
          final artworkResolver = DetailArtworkResolver(
            baseUrl: provider.baseUrl,
            token: provider.token,
            accessCode: provider.accessCode,
          );
          final data = _data!;
          final item = data.item;
          // 展示快照（Phase 5 详情页迁移）：与 _data 同 setState 构造，_data 非空即非空。
          // 本期仅迁可证逐字段等价的展示项；题材行/演职员/角标/播放态仍读旧源（各有等价坑或属播放半）。
          final detail = _detail!;
          final media = MediaQuery.of(context);
          final screenSize = media.size;
          final logoRequestWidth =
              (_isPane ? screenSize.width * media.devicePixelRatio : 1200.0)
                  .clamp(480.0, 1200.0)
                  .round();

          final posterHeight = _backdropHeroHeight(screenSize);
          final layout = DetailLayoutSolver.solve(
            screenSize: screenSize,
            safePadding: media.padding,
            posterHeight: posterHeight,
          );

          final collapseRange =
              (layout.infoStart - media.padding.top - kToolbarHeight).clamp(
                1.0,
                layout.infoStart,
              );

          final selectedOption =
              (_selectedStreamIndex != null &&
                  _selectedStreamIndex! >= 0 &&
                  _selectedStreamIndex! < _streamOptions.length)
              ? _streamOptions[_selectedStreamIndex!]
              : null;

          final effectiveDuration =
              (selectedOption != null && selectedOption.duration > 0)
              ? selectedOption.duration
              : item.duration;
          final sourceTs = data.ts > 0 ? data.ts : item.watchedTs;
          final effectiveTs = sourceTs.clamp(0, effectiveDuration);
          final remainSeconds = (effectiveDuration - effectiveTs).clamp(
            0,
            effectiveDuration,
          );
          final playbackCompleted =
              effectiveDuration > 0 &&
              (remainSeconds <= 0 || _watched || item.isWatched == 1);
          final showProgress = effectiveTs > 0 && remainSeconds > 0;

          final resolvedPlayText = playbackCompleted
              ? AppLocalizations.of(context).playerReplayAction
              : effectiveTs > 0
              ? AppLocalizations.of(context).detailContinuePlay
              : AppLocalizations.of(context).detailPlay;
          final metaLineA = PlayDetailFormatters.metaLineA(
            item,
            genreMap: _genresMapZhCn,
            locateMap: _locateMapZhCn,
          );
          final metaLineB = [
            PlayDetailFormatters.formatDuration(
              effectiveDuration,
              AppLocalizations.of(context),
            ),
            item.ancestorName,
          ].where((e) => e.isNotEmpty).join(' / ');

          final resolutionOptions = _streamOptions
              .map((e) => e.label)
              .where((e) => e.trim().isNotEmpty)
              .toList();
          final showResolutionSelector = resolutionOptions.length > 1;

          final itemType = item.type.trim().toLowerCase();
          // 复刻 PlayItem.displayTitle 语义（tvTitle 非空优先，否则 title），逐字段等价：
          // detail.title==item.title、detail.secondaryTitle==item.tvTitle。不走 MediaDetail.
          // displayTitle 以避免其「皆空回退 'Unknown'」与旧 ''（空串）的差异。
          final detailTitle =
              (itemType == 'episode' && detail.title.trim().isNotEmpty)
              ? detail.title.trim()
              : (detail.secondaryTitle.trim().isNotEmpty
                    ? detail.secondaryTitle.trim()
                    : detail.title);
          final heroInfoBlockReservedHeight = _heroInfoBlockReservedHeight(
            screenSize,
            canPlay: item.canPlay == 1,
          );
          final reserveHeroInfoBlockHeight =
              _isPane || !_heroAsyncSectionsResolved;
          final logoImages = deferAuxiliaryArtwork
              ? MediaImageRequest.empty
              : artworkResolver.resolveRef(
                  detail.logoImage,
                  width: logoRequestWidth,
                );
          final heroTitleChild = itemType != 'episode'
              ? (deferAuxiliaryArtwork
                    ? const SizedBox.shrink()
                    : (logoImages.isNotEmpty
                          ? DetailHeroLogoTitle(
                              images: logoImages,
                              fallbackTitle: detailTitle,
                              maxHeight: 112,
                              maxWidth:
                                  screenSize.width -
                                  (DetailTokens.screenHorizontalPadding * 2),
                            )
                          : null))
              : null;
          final episodeHeroSubtitle = _episodeHeroSubtitle(item);

          String? selectedKey;
          if (_selectedStreamIndex != null &&
              _selectedStreamIndex! >= 0 &&
              _selectedStreamIndex! < resolutionOptions.length) {
            selectedKey =
                '${_selectedStreamIndex!}:${resolutionOptions[_selectedStreamIndex!]}';
          }

          final capabilityLabels = () {
            if (selectedOption != null) {
              return <String>[
                    selectedOption.resolutionType,
                    selectedOption.colorRangeType,
                    _currentAudioTypeForBadges(),
                  ]
                  .map(CapabilityBadgeMapper.normalize)
                  .where((e) => e.isNotEmpty)
                  .toList();
            }
            return <String>[
                  ...item.resolutions,
                  ...item.colorRanges,
                  ...item.audioTypes,
                ]
                .map(CapabilityBadgeMapper.normalize)
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();
          }();
          final subtitleTracks = _currentSubtitleTracks();
          final audioTracks = _currentAudioTracks();
          final showSubtitleArrow = subtitleTracks.isNotEmpty;
          final showAudioArrow = audioTracks.length > 1;
          final subtitleLabel =
              PlayDetailTrackSelector.subtitleLabelForCurrentMedia(
                selectedSubtitleGuid: _selectedSubtitleGuid,
                subtitleTracks: subtitleTracks,
                l10n: AppLocalizations.of(context),
              );
          final audioLabel = PlayDetailTrackSelector.audioLabelForCurrentMedia(
            selectedAudioGuid: _selectedAudioGuid,
            audioTracks: audioTracks,
            selectedOption: selectedOption,
            l10n: AppLocalizations.of(context),
          );

          final currentMediaGuid = _currentStreamOption()?.mediaGuid ?? '';
          final localDownloadedFile = _localDownloadedFileInfoSnapshot;
          final currentFile =
              localDownloadedFile ??
              ((currentMediaGuid.isNotEmpty)
                  ? _streamTrackData?.fileForMedia(currentMediaGuid)
                  : null);
          final currentVideo = (currentMediaGuid.isNotEmpty)
              ? _streamTrackData?.videoForMedia(currentMediaGuid)
              : null;
          final currentAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
            selectedAudioGuid: _selectedAudioGuid,
            audioTracks: audioTracks,
          );
          final currentSubtitle =
              PlayDetailTrackSelector.selectedOrFirstSubtitle(
                selectedSubtitleGuid: _selectedSubtitleGuid,
                subtitleTracks: subtitleTracks,
              );
          // 演职员读公共详情快照 detail.people；显示文案经 CreditPersonPresenter 复刻飞牛
          // displayName/displaySubTitle 语义（显示逻辑留 UI 层、不进中立模型）。
          // detail.people 与 _personCredits 同源（_rebuildDetail 用 credits: _personCredits）。
          // 头像不走 deferAuxiliaryArtwork 门控:演职员区块本身已被 _loadDeferredSections
          // 延迟到列表就绪后才显示(_creditsVisible && creditItems.isNotEmpty),此时一定要真
          // 头像。若再用 _heroAsyncSectionsResolved 二次门控,Phase 2 慢于演职员列表时会先渲染
          // 占位图标、待 Phase 2 完成整页重建再整批换真照片 → 肉眼可见的「跳闪」。与 Emby 路径对齐。
          final creditItems = detail.people
              .map(
                (e) => CreditPersonItem(
                  personGuid: e.id,
                  name: CreditPersonPresenter.displayName(
                    e,
                    AppLocalizations.of(context),
                  ),
                  subtitle: CreditPersonPresenter.displaySubTitle(
                    e,
                    AppLocalizations.of(context),
                  ),
                  images: artworkResolver.resolveRef(e.avatar, width: 180),
                ),
              )
              .toList();

          pageBody = Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    _buildHeroSliver(
                      height: layout.infoStart,
                      title: detailTitle,
                      subtitle: episodeHeroSubtitle,
                      titleFontSize: itemType == 'episode' ? 28 : null,
                      bottomInset: itemType == 'episode' ? 20 : 36,
                      titleChild: heroTitleChild,
                    ),
                    SliverToBoxAdapter(
                      child: Container(
                        color: colors.backgroundBase,
                        padding: const EdgeInsets.fromLTRB(
                          DetailTokens.screenHorizontalPadding,
                          8,
                          DetailTokens.screenHorizontalPadding,
                          10,
                        ),
                        child: AnimatedSize(
                          duration: _asyncContentFadeDuration,
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: reserveHeroInfoBlockHeight
                                  ? heroInfoBlockReservedHeight
                                  : 0.0,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FadeTransition(
                                  opacity: _headerMetaOpacity,
                                  child: _asyncFadeSwitcher(
                                    DetailMetaLines(
                                      metaLineA: metaLineA,
                                      metaLineB: metaLineB,
                                    ),
                                    switchKey: 'meta:$metaLineA|$metaLineB',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FadeTransition(
                                  opacity: _headerSelectorOpacity,
                                  child: _asyncFadeSwitcher(
                                    DetailSelectorRow(
                                      subtitleLabel: subtitleLabel,
                                      audioLabel: audioLabel,
                                      capabilityLabels: capabilityLabels,
                                      showSubtitleArrow: showSubtitleArrow,
                                      showAudioArrow: showAudioArrow,
                                      subtitleExpanded:
                                          _subtitleSelectorExpanded,
                                      audioExpanded: _audioSelectorExpanded,
                                      onSubtitleTap: showSubtitleArrow
                                          ? () => _showSubtitleSheet(context)
                                          : null,
                                      onAudioTap: showAudioArrow
                                          ? () => _showAudioSheet(context)
                                          : null,
                                    ),
                                    switchKey:
                                        'selector:$subtitleLabel|$audioLabel|${capabilityLabels.join(",")}',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                AnimatedBuilder(
                                  animation: _actionsPopController,
                                  builder: (context, child) {
                                    return Opacity(
                                      opacity: _actionsOpacity.value,
                                      child: Transform.translate(
                                        offset: Offset(
                                          0,
                                          _actionsTranslateY.value,
                                        ),
                                        child: Transform.scale(
                                          scale: _actionsScale.value,
                                          alignment: Alignment.topCenter,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                                  child: AnimatedBuilder(
                                    animation: _downloadTaskService,
                                    builder: (context, _) {
                                      final downloaded =
                                          _downloadedRecordForCurrentItem() !=
                                          null;
                                      return PlayActionBar(
                                        progress: PlayDetailFormatters.progress(
                                          effectiveDuration,
                                          effectiveTs,
                                        ),
                                        remainText:
                                            PlayDetailFormatters.remainText(
                                              effectiveDuration,
                                              effectiveTs,
                                              AppLocalizations.of(context),
                                            ),
                                        showProgress: showProgress,
                                        primaryText: resolvedPlayText,
                                        primaryEnabled: item.canPlay == 1,
                                        liked: _liked,
                                        watched: _watched,
                                        downloaded: downloaded,
                                        onPrimaryTap: _openPlayer,
                                        onLikeTap: _toggleFavorite,
                                        onDownloadTap: _handleDownloadTap,
                                        onWatchedTap: _toggleWatched,
                                      );
                                    },
                                  ),
                                ),
                                AnimatedBuilder(
                                  animation: _actionsPopController,
                                  builder: (context, child) {
                                    return Opacity(
                                      opacity: showResolutionSelector
                                          ? _resolutionOpacity.value
                                          : 1.0,
                                      child: Transform.translate(
                                        offset: Offset(
                                          0,
                                          showResolutionSelector
                                              ? _resolutionTranslateY.value
                                              : 0,
                                        ),
                                        child: Transform.scale(
                                          scale: showResolutionSelector
                                              ? _resolutionScale.value
                                              : 1.0,
                                          alignment: Alignment.topCenter,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                                  child: _asyncFadeSwitcher(
                                    showResolutionSelector
                                        ? DetailResolutionSection(
                                            options: resolutionOptions,
                                            selected: selectedKey,
                                            onSelected: (index) {
                                              setState(() {
                                                _selectedStreamIndex = index;
                                                _syncTrackSelectionForCurrentMedia();
                                              });
                                            },
                                          )
                                        : const SizedBox.shrink(),
                                    // 仅在「选项集合 / 是否显示」变化时淡入淡出；
                                    // 切换选中项不应触发整条 chip 的交叉淡变（会"闪"），
                                    // 故 switchKey 不含 selectedKey——选中态在原子树内就地更新。
                                    switchKey:
                                        'resolution:${showResolutionSelector ? resolutionOptions.join(",") : "empty"}',
                                  ),
                                ),
                                if (item.playError.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    AppLocalizations.of(
                                      context,
                                    ).detailPlaybackError(item.playError),
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    _buildDescriptionSliver(
                      colors: colors,
                      text: detail.overview,
                      overlayTitle: detailTitle,
                      bottomPadding: media.padding.bottom + 18,
                    ),
                    if (_creditsVisible && creditItems.isNotEmpty)
                      _buildCreditsSliver(
                        colors: colors,
                        items: creditItems,
                        onTap: _openCreditPerson,
                      ),
                    if (_fileInfoVisible)
                      SliverToBoxAdapter(
                        child: _sectionReveal(
                          child: Container(
                            color: colors.backgroundBase,
                            padding: const EdgeInsets.fromLTRB(
                              DetailTokens.screenHorizontalPadding,
                              8,
                              DetailTokens.screenHorizontalPadding,
                              20,
                            ),
                            child: FileInfoSection(
                              file: currentFile,
                              authorizedDirs: _authorizedDirs,
                              title: AppLocalizations.of(
                                context,
                              ).detailFileInfoTitle,
                              locationLabel: AppLocalizations.of(
                                context,
                              ).detailFileLocation,
                              sizeLabel: AppLocalizations.of(
                                context,
                              ).detailFileSize,
                              createdAtLabel: AppLocalizations.of(
                                context,
                              ).detailFileCreatedAt,
                              addedAtLabel: AppLocalizations.of(
                                context,
                              ).detailFileAddedAt,
                              toggleToFriendlyLabel: AppLocalizations.of(
                                context,
                              ).detailFileConvert,
                              toggleToRawLabel: '/vol',
                            ),
                          ),
                        ),
                      ),
                    if (_videoInfoVisible)
                      SliverToBoxAdapter(
                        child: _sectionReveal(
                          child: Container(
                            color: colors.backgroundBase,
                            padding: const EdgeInsets.fromLTRB(
                              DetailTokens.screenHorizontalPadding,
                              8,
                              DetailTokens.screenHorizontalPadding,
                              20,
                            ),
                            child: VideoInfoSection(
                              lines: feiniuVideoInfoLines(
                                currentVideo,
                                currentAudio,
                                currentSubtitle,
                              ),
                              onViewAll: () => _showMediaInfoDetail(context),
                            ),
                          ),
                        ),
                      ),
                    if (_linkVisible &&
                        (_imdbId.trim().isNotEmpty ||
                            _trimId.trim().isNotEmpty))
                      _buildLinkSliver(colors: colors),
                  ],
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _scrollOffsetNotifier,
                  builder: (context, offset, _) {
                    final collapseT = (offset / collapseRange).clamp(0.0, 1.0);
                    final centerTitleOpacity = ((collapseT - 0.84) / 0.12)
                        .clamp(0.0, 1.0);
                    return DetailFloatingTopBar(
                      onBack: () => unawaited(
                        EmbeddedDetailLauncher.closeHostOrPop(context),
                      ),
                      onMore: () => unawaited(
                        showDetailMoreActionsSheet(
                          context,
                          pageKey: dynamicThemeKey,
                          pageTitle: detailTitle,
                          suggestedThemeName: context
                              .read<AppThemeProvider>()
                              .nextSavedThemeNameFromBase(
                                _suggestedThemeNameBase(item, detailTitle),
                              ),
                          clearRuntimeBroadcastToMain: !inPlayerPaneHost,
                        ),
                      ),
                      title: detailTitle,
                      titleOpacity: centerTitleOpacity,
                      showBack: true,
                    );
                  },
                ),
              ],
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            // Persistent backdrop: stays mounted across loading→ready so it
            // never reloads or double-fades. Only the foreground content
            // crossfades on top of it.
            RepaintBoundary(child: persistentBackground),
            AppTransitions.crossFadeSwitch(
              switchKey: 'detail-${_loading ? 'loading' : 'ready'}',
              duration: AppTransitions.switchDuration,
              child: pageBody,
            ),
          ],
        );
      },
    );
  }
}
