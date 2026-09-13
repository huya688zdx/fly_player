import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../media_backend/detail/media_season_summary.dart';
import '../../media_backend/media_image_request.dart';
import '../../danmaku/models/danmaku_comment.dart';
import '../../danmaku/models/danmaku_settings.dart';
import '../../danmaku/settings/danmaku_settings_store.dart';
import '../../media_backend/playback/media_session_reload.dart';
import '../../playback/bookmarks/bookmark_store.dart';
import '../../playback/playback_source.dart';
import '../../playback/weak_network_quality_recommender.dart';
import '../../playback/settings/mpv_settings_store.dart';
import '../../services/native_danmaku_prefetch.dart';
import '../../services/fly_data/fly_oped.dart';
import '../../services/fly_data/fly_playback_service_client.dart';
import '../../widgets/fly_assistant_panel.dart';
import '../../services/fly_data/fly_nas_danmaku_cache.dart';
import '../../services/fly_data/fly_data_service.dart';
import '../../services/play_stats/play_stats_database.dart';
import '../../services/play_stats/play_stats_service.dart';
import 'desktop_danmaku_overlay.dart';
import 'desktop_mpv_runtime.dart';
import 'desktop_playback_chapters.dart';
import 'desktop_playback_reporter.dart';
import 'desktop_playback_session.dart';
import 'desktop_system_media_controls.dart';
import 'desktop_weak_network_monitor.dart';
import 'desktop_player_controls.dart';
import 'desktop_player_dialogs.dart';
import '../desktop_floating_panel.dart';
import 'desktop_player_hover_overlays.dart';
import 'desktop_player_panels.dart';

const Duration _controlsHideDelay = Duration(milliseconds: 2800);
const Duration _controlsAnimationDuration = Duration(milliseconds: 220);

typedef DesktopResolvedEpisode = ({
  MpvMediaSource source,
  String? danmakuFilePath,
  List<Map<String, dynamic>> episodes,
});

/// 片头片尾跳过提示种类。
enum _SkipPromptKind { intro, outro }

/// Windows 桌面正式播放页。
///
/// 桌面媒体播放页：播放状态由 media_kit 持有，页面只负责桌面控制层和面板。
class DesktopPlaybackScreen extends StatefulWidget {
  const DesktopPlaybackScreen({
    super.key,
    required this.source,
    required this.session,
    this.episodes,
    this.resolveEpisode,
    this.loadSeasons,
    this.loadSeasonEpisodes,
    this.reloadSource,
    this.danmakuFilePath,
    this.onRecordProgress,
    this.resolveSubtitleFile,
    this.releaseServerSession,
    this.resolveSegmentedSubtitle,
    this.refreshDirectLink,
    this.resolveArtwork,
  });

  final MpvMediaSource source;
  final DesktopPlaybackSession session;
  final List<Map<String, dynamic>>? episodes;
  final Future<List<MediaSeasonSummary>> Function()? loadSeasons;
  final Future<List<Map<String, dynamic>>> Function(String)? loadSeasonEpisodes;
  final Future<DesktopResolvedEpisode?> Function(Map<String, dynamic> episode)?
  resolveEpisode;
  final Future<MpvMediaSource?> Function(
    MpvMediaSource current,
    MediaSessionReloadIntent intent,
  )?
  reloadSource;
  final String? danmakuFilePath;
  final Future<void> Function(Map<String, dynamic>)? onRecordProgress;
  final Future<String?> Function(String guid, {String? format})?
  resolveSubtitleFile;
  final Future<void> Function(String playLink)? releaseServerSession;
  final Future<String?> Function(MpvMediaSource source, Duration position)?
  resolveSegmentedSubtitle;
  final Future<MpvMediaSource> Function(MpvMediaSource source)?
  refreshDirectLink;
  final MediaImageRequest Function(String path)? resolveArtwork;

  @override
  State<DesktopPlaybackScreen> createState() => _DesktopPlaybackScreenState();
}

class _DesktopPlaybackScreenState extends State<DesktopPlaybackScreen>
    with WindowListener {
  late List<Map<String, dynamic>> _episodes = widget.episodes ?? const [];
  bool get _canBrowseEpisodes =>
      _episodes.isNotEmpty || widget.loadSeasons != null;
  static const String _autoPlayPrefKey = 'player_auto_play_enabled';
  static const String _nextEpisodePreloadPrefKey =
      'player_next_episode_preload_enabled';
  static const String _aspectRatioPrefKey = 'player_display_aspect_ratio';
  static const String _decoderModePrefKey = 'player_decoder_mode';
  static const String _introOutroEnabledPrefKey = 'player_intro_outro_enabled';
  static const String _introMaxMinutesPrefKey = 'player_intro_outro_intro_min';
  static const String _outroMaxMinutesPrefKey = 'player_intro_outro_outro_min';
  static const String _fixedDurationSkipPrefKey =
      'player_intro_outro_fixed_duration_enabled';
  static const String _subDelayPrefKey = 'player_subtitle_delay_seconds';
  static const String _subPosPrefKey = 'player_subtitle_position';
  static const String _subScalePrefKey = 'player_subtitle_scale';

  late final Player _player;
  late final VideoController _videoController;
  DesktopSystemMediaControls? _systemMediaControls;
  late final DesktopWeakNetworkMonitor _weakNetwork;
  late MpvMediaSource _source;
  late final StreamSubscription<String> _errorSubscription;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<double> _volumeSubscription;
  late final StreamSubscription<bool> _bufferingSubscription;
  late final StreamSubscription<bool> _completedSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;

  Timer? _controlsHideTimer;
  Timer? _hoverOpenTimer;
  Timer? _hoverCloseTimer;
  Timer? _hoverClearTimer;
  Timer? _resumePromptTimer;
  Timer? _autoNextTimer;
  Timer? _toastTimer;
  Timer? _progressTimer;
  Timer? _directLinkTimer;
  bool _directLinkRefreshPending = false;
  DateTime? _lastDirectLinkRefreshAttempt;
  int _sourceChangeGeneration = 0;
  final _flyClient = FlyPlaybackServiceClient.instance;
  String _flyContextId = '', _flyScopeEpoch = '';
  FlyOpedSet? _flyOped;
  FlyOpedAction? _flyAction;
  FlyOpedPlaybackPolicy _flySkipPolicy = FlyOpedPlaybackPolicy();
  Timer? _flyActionTimeout;
  Timer? _flyObservationTimer;
  bool _flySeekCommandAccepted = false;
  bool _flySamplePending = false;
  bool _flyAuthorizing = false;
  bool _flyEdTailProtected = false;
  int _preloadGeneration = 0;
  String _preloadingItemGuid = '';
  bool _subtitleWindowPending = false;
  SubtitleTrack? _menuSubtitleTrack;
  int _subtitleWindowSecond = -100;
  late final DesktopPlaybackReporter _reporter;
  bool _reportReady = false;
  String? _errorMessage;
  String? _toastMessage;
  bool _isLoading = true;
  String? _qualitySwitchingMessage;
  bool _isBuffering = false;
  bool _pausedByUser = false;
  // 控制条可见性、播放状态与悬停弹层都用 ValueNotifier 驱动：
  // media_kit 全屏是独立路由上的另一个 Video，宿主 setState 刷不到它。
  final ValueNotifier<bool> _controlsVisibleNotifier = ValueNotifier<bool>(
    true,
  );
  final ValueNotifier<bool> _playingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<PlayerHoverOverlaySnapshot> _hoverOverlayNotifier =
      ValueNotifier<PlayerHoverOverlaySnapshot>(
        const PlayerHoverOverlaySnapshot(),
      );
  bool get _controlsVisible => _controlsVisibleNotifier.value;
  set _controlsVisible(bool value) => _controlsVisibleNotifier.value = value;
  bool get _isPlaying => _playingNotifier.value;
  set _isPlaying(bool value) => _playingNotifier.value = value;
  bool get _hoverOverlayVisible => _hoverOverlayNotifier.value.visible;
  PlayerHoverOverlayKind? get _hoverOverlayKind =>
      _hoverOverlayNotifier.value.kind;
  bool _takingScreenshot = false;
  Duration? _abLoopStart;
  Duration? _abLoopEnd;
  bool _updatingAbLoop = false;
  bool _showResumePrompt = false;
  bool _playbackCompleted = false;
  bool _isLocked = false;
  Duration? _lastLockedEscapeTime;
  bool _autoNextSuppressed = false;
  int _autoNextSeconds = 0;
  bool _autoPlayEnabled = true;
  bool _nextEpisodePreloadEnabled = false;
  double _volume = 100;
  double _lastAudibleVolume = 100;
  double _playbackRate = 1;
  BoxFit _fit = BoxFit.contain;
  String _aspectRatioMode = 'fit';
  String _decoderMode = 'hardware';
  DanmakuSettings _danmakuSettings = DanmakuSettings.defaults;
  List<DanmakuComment> _danmakuComments = const <DanmakuComment>[];
  String _danmakuSourceLabel = '';
  bool _danmakuLoading = false;
  int _danmakuLoadGeneration = 0;
  FlyNasDanmakuStatus _nasDanmakuStatus = FlyNasDanmakuStatus.notRequested;
  int _danmakuSeekRevision = 0;
  Map<String, String> _mpvSettings = Map<String, String>.from(
    MpvSettingsCatalog.defaults,
  );
  Map<String, double> _videoAdjustments = Map<String, double>.from(
    MpvSettingsCatalog.videoAdjustmentDefaults,
  );
  late final DesktopPlaybackChapters _chapterLoader;
  List<DesktopPlayerChapter> get _chapters => _chapterLoader.value;
  bool _introOutroEnabled = true;
  int _introMaxMinutes = 2;
  int _outroMaxMinutes = 2;
  bool _fixedDurationSkipEnabled = false;
  // 片头片尾跳过提示：ValueNotifier 驱动，全屏路由下也能即时显隐。
  final ValueNotifier<_SkipPromptKind?> _skipPromptKindNotifier =
      ValueNotifier<_SkipPromptKind?>(null);
  bool _introSkipDismissed = false;
  bool _outroSkipDismissed = false;
  // 字幕样式：默认值对齐安卓 NativeSubtitleStyleSettings（延迟 0 / 位置 92 / 缩放 1.0）。
  double _subtitleDelaySeconds = 0;
  int _subtitlePosition = 92;
  double _subtitleScale = 1;
  double _audioDelaySeconds = 0;
  final BookmarkStore _bookmarkStore = const BookmarkStore();
  final DanmakuSettingsStore _danmakuSettingsStore =
      const DanmakuSettingsStore();
  final MpvSettingsStore _mpvSettingsStore = const MpvSettingsStore();
  List<PlayerBookmarkEntry> _bookmarks = const <PlayerBookmarkEntry>[];
  DesktopResolvedEpisode? _preloadedNextSource;
  String _preloadedNextItemGuid = '';

  final ValueNotifier<int> _viewRevision = ValueNotifier<int>(0);

  void _updateView(VoidCallback update) {
    if (!mounted) return;
    setState(update);
    _weakNetwork.updatePlayback(
      loading: _isLoading,
      paused: _pausedByUser,
      buffering: _isBuffering,
      completed: _playbackCompleted || _errorMessage != null,
    );
    // media_kit 的全屏控制层属于另一条路由，宿主页 setState 不会重建它。
    _viewRevision.value++;
    _syncSystemMediaControls();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _source = widget.source;
    _reporter = DesktopPlaybackReporter(
      reportProgress: widget.onRecordProgress,
      releaseServerSession: widget.releaseServerSession,
    );
    // 本地统计需要连续采样；服务端每 15 秒回写不足以计算实际观看时长。
    _localStatsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _recordLocalStats(),
    );
    _pausedByUser = _source.startPaused;
    MediaKit.ensureInitialized();
    _player = widget.session.player;
    _videoController = widget.session.videoController;
    _weakNetwork = DesktopWeakNetworkMonitor(
      readProperty: (name) async {
        final platform = _player.platform;
        return platform is NativePlayer ? platform.getProperty(name) : '0';
      },
    )..setSource(_source);
    widget.session.releaseSource = _reporter.release;
    _chapterLoader = DesktopPlaybackChapters(() async {
      final platform = _player.platform;
      return platform is NativePlayer
          ? platform.getProperty('chapter-list')
          : '[]';
    })..addListener(_onChaptersChanged);
    _playbackRate = _validPlaybackRate(_source.playbackSpeed);
    _volume = _player.state.volume;
    if (_volume > 0) _lastAudibleVolume = _volume;
    if (Platform.isWindows) {
      _systemMediaControls = DesktopSystemMediaControls(
        onPlaying: _setSystemPlaying,
        onSeek: (position) async {
          if (mounted && !_isLoading) await _seekTo(position);
        },
      );
      _updateSystemMediaMetadata();
    }

    _errorSubscription = _player.stream.error.listen(_onPlayerError);
    _playingSubscription = _player.stream.playing.listen(_onPlayingChanged);
    _volumeSubscription = _player.stream.volume.listen(_onVolumeChanged);
    _bufferingSubscription = _player.stream.buffering.listen(
      _onBufferingChanged,
    );
    _completedSubscription = _player.stream.completed.listen(
      _onCompletedChanged,
    );
    _positionSubscription = _player.stream.position.listen(_onPositionChanged);
    _durationSubscription = _player.stream.duration.listen(_onDurationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadDesktopPreferences();
      if (!mounted) return;
      await _loadBookmarks();
      if (!mounted) return;
      if (widget.session.ready) {
        await widget.session.paused;
        if (!mounted) return;
        _playbackRate = _player.state.rate;
        _reportReady = true;
        _pausedByUser = false;
        _onDurationChanged(_player.state.duration);
        await _applyDesktopMpvProperties();
        if (!mounted) return;
        await _player.play();
        if (!mounted) return;
        _reporter.onLaunch(_source);
        _finishLoading();
        _scheduleProgressReport();
        unawaited(_loadDanmakuForSource(widget.session.danmakuFilePath));
        debugPrint('[桌面播放] 已复用暂停会话，无需重新打开媒体');
      } else {
        await _openSource();
      }
    });
  }

  @override
  void dispose() {
    _finishFlyAction('cancelled');
    unawaited(_systemMediaControls?.dispose());
    windowManager.removeListener(this);
    if (_isLocked) unawaited(windowManager.setPreventClose(false));
    _weakNetwork.dispose();
    final session = widget.session;
    final retain =
        session.ready &&
        _errorMessage == null &&
        !_playbackCompleted &&
        !_isLoading;
    if (retain) {
      session.paused = _player.pause();
      _pausedByUser = true;
      debugPrint('[桌面播放] 已暂停并保留最近会话');
    }
    session.source = _source;
    session.active = false;
    _recordLocalStats();
    _localStatsTimer?.cancel();
    unawaited(_reporter.dispose());
    _reportProgress();
    _sourceChangeGeneration++;
    _clearPreloadedNext();
    _progressTimer?.cancel();
    _directLinkTimer?.cancel();
    _controlsHideTimer?.cancel();
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _hoverClearTimer?.cancel();
    _resumePromptTimer?.cancel();
    _autoNextTimer?.cancel();
    _toastTimer?.cancel();
    unawaited(_errorSubscription.cancel());
    unawaited(_playingSubscription.cancel());
    unawaited(_volumeSubscription.cancel());
    unawaited(_bufferingSubscription.cancel());
    unawaited(_completedSubscription.cancel());
    unawaited(_durationSubscription.cancel());
    unawaited(_positionSubscription.cancel());
    _chapterLoader.dispose();
    _skipPromptKindNotifier.dispose();
    if (!retain) unawaited(session.dispose());
    _controlsVisibleNotifier.dispose();
    _playingNotifier.dispose();
    _hoverOverlayNotifier.dispose();
    _viewRevision.dispose();
    super.dispose();
  }

  Future<void> _loadDesktopPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final danmakuSettings = await _danmakuSettingsStore.load();
    final mpvBundle = await _mpvSettingsStore.loadBundle();
    final aspect = prefs.getString(_aspectRatioPrefKey) ?? 'fit';
    final normalizedAspect =
        const <String>{'fit', 'fill', '4:3', '16:9', '21:9'}.contains(aspect)
        ? aspect
        : 'fit';
    final decoder = prefs.getString(_decoderModePrefKey);
    if (!mounted) return;
    _updateView(() {
      _autoPlayEnabled = prefs.getBool(_autoPlayPrefKey) ?? true;
      _nextEpisodePreloadEnabled =
          prefs.getBool(_nextEpisodePreloadPrefKey) ?? false;
      _aspectRatioMode = normalizedAspect;
      _fit = normalizedAspect == 'fill' ? BoxFit.cover : BoxFit.contain;
      _decoderMode = decoder == 'software' ? 'software' : 'hardware';
      _danmakuSettings = danmakuSettings;
      _mpvSettings = mpvBundle.settings;
      _videoAdjustments = mpvBundle.videoAdjustments;
      _introOutroEnabled = prefs.getBool(_introOutroEnabledPrefKey) ?? true;
      _introMaxMinutes = prefs.getInt(_introMaxMinutesPrefKey) ?? 2;
      _outroMaxMinutes = prefs.getInt(_outroMaxMinutesPrefKey) ?? 2;
      _fixedDurationSkipEnabled =
          prefs.getBool(_fixedDurationSkipPrefKey) ?? false;
      _subtitleDelaySeconds = prefs.getDouble(_subDelayPrefKey) ?? 0;
      _subtitlePosition = prefs.getInt(_subPosPrefKey) ?? 92;
      _subtitleScale = prefs.getDouble(_subScalePrefKey) ?? 1;
    });
  }

  Future<void> _loadBookmarks() async {
    final source = _source;
    final bookmarks = await _bookmarkStore.loadForMedia(
      itemGuid: _source.itemGuid,
      mediaGuid: _source.mediaGuid,
    );
    if (mounted && identical(source, _source)) {
      _updateView(() => _bookmarks = bookmarks);
    }
  }

  Future<void> _applyDesktopMpvProperties() async {
    await _setMpvProperty(
      'hwdec',
      _decoderMode == 'software' ? 'no' : 'auto-safe',
    );
    await _applyDesktopCacheProperties();
    await _setMpvProperty(
      'video-aspect-override',
      const <String>{'4:3', '16:9', '21:9'}.contains(_aspectRatioMode)
          ? _aspectRatioMode
          : 'no',
    );
    for (final entry in _videoAdjustments.entries) {
      await _setMpvProperty(entry.key, entry.value.toStringAsFixed(0));
    }
    await _applyDesktopVideoEnhancement();
    await _applyDesktopAudioProperties();
    await _applySubtitleStyle();
    await _setMpvProperty('audio-delay', _audioDelaySeconds.toStringAsFixed(1));
  }

  /// 字幕样式 → mpv 属性（sub-delay / sub-pos / sub-scale），改动即时生效。
  Future<void> _applySubtitleStyle() async {
    await _setMpvProperty(
      'sub-delay',
      _subtitleDelaySeconds.toStringAsFixed(1),
    );
    await _setMpvProperty('sub-pos', '$_subtitlePosition');
    await _setMpvProperty('sub-scale', _subtitleScale.toStringAsFixed(2));
  }

  Future<void> _setSubtitleStyleSettings({
    required double delaySeconds,
    required int position,
    required double scale,
  }) async {
    if (mounted) {
      _updateView(() {
        _subtitleDelaySeconds = delaySeconds.clamp(-10.0, 10.0);
        _subtitlePosition = position.clamp(0, 100);
        _subtitleScale = scale.clamp(0.5, 2.5);
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subDelayPrefKey, _subtitleDelaySeconds);
    await prefs.setInt(_subPosPrefKey, _subtitlePosition);
    await prefs.setDouble(_subScalePrefKey, _subtitleScale);
    await _applySubtitleStyle();
  }

  /// 外挂字幕导入（对齐安卓「+添加」）：sub-add 本地文件并立即选用。
  Future<void> _importLocalSubtitle() async {
    final generation = _sourceChangeGeneration;
    _dismissHoverOverlay();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>[
        'srt',
        'ass',
        'ssa',
        'sub',
        'vtt',
        'sup',
        'lrc',
        'sami',
        'smi',
      ],
    );
    final path = result?.files.single.path;
    if (!_isCurrentSourceChange(generation) || path == null || path.isEmpty) {
      return;
    }
    final previousSource = _source;
    final source = previousSource.copyWith(
      clearSubtitleTrackGuid: true,
      clearSubtitleTrackIndex: true,
    );
    // 先让进行中的服务端分段字幕请求失效，再安装用户选择的外挂。
    _source = source;
    try {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(path, title: 'external', language: 'auto'),
      );
      if (!_isCurrentSourceChange(generation) || !identical(source, _source)) {
        return;
      }
      _updateView(() {});
      _reportProgress();
      _showPlayerMessage('已导入本地字幕');
    } catch (_) {
      if (_isCurrentSourceChange(generation) && identical(source, _source)) {
        _source = previousSource;
        _showGenericError(_l10n.desktopPlaybackErrorTrackSwitchFailed);
      }
    }
  }

  bool get _isRemoteHttpSource =>
      _source.url.startsWith('http://') || _source.url.startsWith('https://');

  /// 缓存策略 → mpv 属性：映射语义对齐安卓 MpvAdvancedSettingsController.applyCacheProfile
  /// （default 档在远端 HTTP 上按码率/分辨率自适应，用户显式设置的缓存大小优先）。
  Future<void> _applyDesktopCacheProperties() async {
    var profile = _mpvSettings[MpvSettingsCatalog.cacheProfileKey] ?? 'default';
    if (profile == 'default' && _isRemoteHttpSource) {
      final ultraHd = _source.videoWidth >= 3800 || _source.videoHeight >= 2100;
      profile = ultraHd || _source.bitrate >= 8000000 ? 'network' : 'stable';
    }
    final cacheEnabled = _isRemoteHttpSource && profile != 'low_latency';
    final maxBytesMb = switch (profile) {
      'stable' => 128,
      'network' => 256,
      'low_latency' => 32,
      _ => 64,
    };
    final readahead = switch (profile) {
      'stable' => 20.0,
      'network' => 30.0,
      'low_latency' => 5.0,
      _ => 10.0,
    };
    final configuredMb = int.tryParse(
      _mpvSettings[MpvSettingsCatalog.cacheSizeMbKey] ?? '',
    );
    final effectiveMb = configuredMb != null && configuredMb > 0
        ? configuredMb
        : maxBytesMb;
    await _setMpvProperty('cache', cacheEnabled ? 'yes' : 'no');
    // 磁盘包缓存会让字节上限只约束元数据，无法约束临时文件大小。
    await _setMpvProperty('cache-on-disk', 'no');
    await _setMpvProperty('cache-secs', '$readahead');
    await _setMpvProperty('demuxer-max-bytes', '${effectiveMb * 1024 * 1024}');
    await _setMpvProperty('demuxer-max-back-bytes', '${32 * 1024 * 1024}');
    await _setMpvProperty('demuxer-readahead-secs', '$readahead');
  }

  /// 画质增强键 → mpv 属性：映射语义对齐安卓 MpvAdvancedSettingsController
  /// （deband/vf 滤镜/反交错/缩放配置/补帧/视频同步/色调映射）。
  Future<void> _applyDesktopVideoEnhancement() async {
    final settings = _mpvSettings;
    final deband = settings[MpvSettingsCatalog.debandKey] ?? 'off';
    await _setMpvProperty('deband', deband == 'off' ? 'no' : 'yes');
    if (deband != 'off') {
      await _setMpvProperty('deband-iterations', switch (deband) {
        'low' => '1',
        'high' => '4',
        _ => '3',
      });
    }
    final filters = <String>[];
    switch (settings[MpvSettingsCatalog.sharpenKey] ?? 'off') {
      case 'low':
        filters.add('lavfi=[unsharp=3:3:0.35:3:3:0.0]');
      case 'medium':
        filters.add('lavfi=[unsharp=5:5:0.45:5:5:0.0]');
      case 'high':
        filters.add('lavfi=[unsharp=7:7:0.55:7:7:0.0]');
    }
    switch (settings[MpvSettingsCatalog.denoiseKey] ?? 'off') {
      case 'low':
        filters.add('lavfi=[hqdn3d=1.5:1.5:6:6]');
      case 'medium':
        filters.add('lavfi=[hqdn3d=3:2:9:7]');
    }
    await _setMpvProperty('vf', filters.join(','));
    await _setMpvProperty(
      'deinterlace',
      switch (settings[MpvSettingsCatalog.deinterlaceKey]) {
        'force' => 'yes',
        _ => 'no',
      },
    );
    final scale = switch (settings[MpvSettingsCatalog.scaleProfileKey] ??
        'balanced') {
      'fast' => ('bilinear', 'bilinear', 'bilinear'),
      'quality' => ('ewa_lanczossharp', 'spline64', 'mitchell'),
      _ => ('spline36', 'spline36', 'mitchell'),
    };
    await _setMpvProperty('scale', scale.$1);
    await _setMpvProperty('cscale', scale.$2);
    await _setMpvProperty('dscale', scale.$3);
    // 补帧 auto：安卓的自动判定只对本地低码率内容启用，桌面片源均为远端 HTTP，恒为关闭。
    final interpolation =
        settings[MpvSettingsCatalog.frameInterpolationKey] == 'on';
    await _setMpvProperty('interpolation', interpolation ? 'yes' : 'no');
    await _setMpvProperty('tscale', interpolation ? 'oversample' : 'mitchell');
    await _setMpvProperty(
      'video-sync',
      switch (settings[MpvSettingsCatalog.videoSyncKey] ?? 'auto') {
        'audio' => 'audio',
        'smooth' => 'display-tempo',
        _ => 'display-resample',
      },
    );
    await _setMpvProperty(
      'tone-mapping',
      switch (settings[MpvSettingsCatalog.toneMappingKey] ?? 'auto') {
        'auto' || 'bt2390' => 'bt.2390',
        final other => other,
      },
    );
  }

  Future<void> _applyDesktopAudioProperties({bool resetVolume = false}) async {
    final passthrough = DesktopMpvRuntime.passthroughCodecs(_mpvSettings);
    await _setMpvProperty('audio-spdif', passthrough);
    await _setMpvProperty(
      'audio-channels',
      passthrough.isNotEmpty
          ? 'auto'
          : DesktopMpvRuntime.audioChannels(_mpvSettings),
    );
    final volumeMax = passthrough.isNotEmpty
        ? 100
        : DesktopMpvRuntime.volumeMax(_mpvSettings);
    await _setMpvProperty('volume-max', '$volumeMax');
    await _setMpvProperty('af', DesktopMpvRuntime.audioFilters(_mpvSettings));
    if (resetVolume) {
      await _setMpvProperty('volume', '$volumeMax');
    }
  }

  Future<void> _setMpvProperty(String name, String value) async {
    if (!mounted) return;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(name, value);
    }
  }

  Future<bool> _loadDanmakuForSource(
    String? preferredPath, {
    String sourceLabel = '',
    bool enableOnSuccess = false,
  }) async {
    final generation = ++_danmakuLoadGeneration;
    final source = _source;
    widget.session.danmakuFilePath = preferredPath;
    if (mounted) {
      _updateView(() {
        _danmakuLoading = true;
        _danmakuComments = const <DanmakuComment>[];
        _danmakuSourceLabel = '';
        _nasDanmakuStatus = FlyDataService.instance.session == null
            ? FlyNasDanmakuStatus.notSignedIn
            : source.statsScope.isEmpty
            ? FlyNasDanmakuStatus.notBound
            : FlyNasDanmakuStatus.notRequested;
      });
    }
    try {
      var path = preferredPath?.trim() ?? '';
      if (path.isEmpty) {
        path =
            await NativeDanmakuPrefetch.resolveToFile(
              statsScope: source.statsScope,
              isCurrent: () =>
                  mounted &&
                  generation == _danmakuLoadGeneration &&
                  identical(source, _source),
              seriesTitle: source.seriesTitle,
              itemTitle: source.title,
              seasonNumber: source.seasonNumber,
              episodeNumber: source.episodeNumber,
              tmdbId: source.tmdbId,
              settings: _danmakuSettings,
              itemGuid: source.itemGuid,
              mediaGuid: source.mediaGuid,
              seasonGuid: source.seasonGuid,
              nasCache: FlyNasDanmakuCache(
                onStatus: (status) {
                  if (mounted &&
                      generation == _danmakuLoadGeneration &&
                      identical(source, _source)) {
                    _updateView(() => _nasDanmakuStatus = status);
                  }
                },
              ),
            ) ??
            '';
      }
      if (path.isEmpty) return false;
      final payload = await DesktopDanmakuPayload.load(path);
      if (!mounted || generation != _danmakuLoadGeneration) return false;
      widget.session.danmakuFilePath = path;
      _updateView(() {
        _danmakuComments = payload.comments;
        _danmakuSourceLabel = sourceLabel.trim().isNotEmpty
            ? sourceLabel.trim()
            : payload.sourceLabel;
      });
      if (enableOnSuccess && payload.comments.isNotEmpty) {
        await _updateDanmakuSettings(_danmakuSettings.copyWith(enabled: true));
      }
      return payload.comments.isNotEmpty;
    } catch (_) {
      if (!mounted || generation != _danmakuLoadGeneration) return false;
      _updateView(() {
        _danmakuComments = const <DanmakuComment>[];
        _danmakuSourceLabel = '';
      });
      return false;
    } finally {
      if (mounted && generation == _danmakuLoadGeneration) {
        _updateView(() => _danmakuLoading = false);
      }
    }
  }

  /// User initiated fetch gets its own bounded budget and leaves the current
  /// comments in place until a verified replacement is completely available.
  Future<FlyNasDanmakuStatus> _reloadNasDanmaku() async {
    final generation = ++_danmakuLoadGeneration;
    final source = _source;
    bool current() =>
        mounted &&
        generation == _danmakuLoadGeneration &&
        identical(source, _source);
    var status = FlyNasDanmakuStatus.failed;
    _updateView(() => _danmakuLoading = true);
    try {
      final result =
          await FlyNasDanmakuCache(
            budget: const Duration(seconds: 12),
            onStatus: (value) => status = value,
          ).resolve(
            statsScope: source.statsScope,
            itemGuid: source.itemGuid,
            mediaGuid: source.mediaGuid,
            isCurrent: current,
          );
      if (!current() || result == null) return status;
      final path = await NativeDanmakuPrefetch.writeNasPayloadToFile(
        result: result,
        settings: _danmakuSettings.copyWith(enabled: true),
        isCurrent: current,
      );
      if (!current() || path == null || !result.isCurrent()) {
        status = FlyNasDanmakuStatus.failed;
        return status;
      }
      widget.session.danmakuFilePath = path;
      _updateView(() {
        _danmakuComments = result.comments;
        _danmakuSourceLabel = result.sourceLabel;
      });
      await _updateDanmakuSettings(_danmakuSettings.copyWith(enabled: true));
      return status = FlyNasDanmakuStatus.ready;
    } catch (_) {
      return status = FlyNasDanmakuStatus.failed;
    } finally {
      if (current()) {
        _updateView(() {
          _danmakuLoading = false;
          _nasDanmakuStatus = status;
        });
      }
    }
  }

  String get _nasScopeLabel {
    final stats = PlayStatsService.instance;
    final reference =
        (stats.database as SqflitePlayStatsDatabase).bindingReference;
    final binding = _source.statsScope == stats.currentScope
        ? switch (reference['backend_kind']) {
            'feiniu' => '飞牛影视',
            'emby' => 'Emby',
            _ => '未选择飞翔媒体绑定',
          }
        : '播放连接已改变';
    return '$binding · ${_source.title}';
  }

  Future<void> _updateDanmakuSettings(DanmakuSettings settings) async {
    if (!mounted) return;
    _updateView(() => _danmakuSettings = settings);
    await _danmakuSettingsStore.save(settings);
    if (settings.enabled && _danmakuComments.isEmpty && !_danmakuLoading) {
      unawaited(_loadDanmakuForSource(null));
    }
  }

  Future<bool> _importDanmakuFile() async {
    final generation = _sourceChangeGeneration;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入弹幕文件',
      type: FileType.custom,
      allowedExtensions: const <String>['xml', 'json'],
      lockParentWindow: true,
    );
    final path = result?.files.single.path?.trim() ?? '';
    if (!_isCurrentSourceChange(generation) || path.isEmpty) return false;
    final imported = await NativeDanmakuPrefetch.importLocalFileToFile(
      path,
      itemGuid: _source.itemGuid,
      mediaGuid: _source.mediaGuid,
      seasonGuid: _source.seasonGuid,
      seasonNumber: _source.seasonNumber,
      episodeNumber: _source.episodeNumber,
      seriesTitle: _source.seriesTitle,
      itemTitle: _source.title,
      mediaType: _source.mediaType,
    );
    if (!_isCurrentSourceChange(generation)) return false;
    final payloadPath = imported?['danmakuFile']?.toString().trim() ?? '';
    if (payloadPath.isEmpty) {
      _showPlayerMessage('弹幕文件无法识别');
      return false;
    }
    final loaded = await _loadDanmakuForSource(
      payloadPath,
      sourceLabel: result?.files.single.name ?? '',
      enableOnSuccess: true,
    );
    if (loaded) {
      _showPlayerMessage('已导入 ${_danmakuComments.length} 条弹幕');
    }
    return loaded;
  }

  Future<List<Map<String, dynamic>>> _loadSavedDanmakuSources() {
    return NativeDanmakuPrefetch.listSavedSources(
      itemGuid: _source.itemGuid,
      mediaGuid: _source.mediaGuid,
      seasonGuid: _source.seasonGuid,
      seasonNumber: _source.seasonNumber,
      episodeNumber: _source.episodeNumber,
      seriesTitle: _source.seriesTitle,
    );
  }

  Future<List<Map<String, dynamic>>> _searchDanmakuSources(String keyword) {
    return NativeDanmakuPrefetch.searchCandidates(
      keyword: keyword,
      currentEpisodeNumber: _source.episodeNumber,
      seasonNumber: _source.seasonNumber,
    );
  }

  Future<bool> _selectSavedDanmakuSource(Map<String, dynamic> source) async {
    final generation = _sourceChangeGeneration;
    final sourceKey = '${source['sourceKey'] ?? ''}'.trim();
    final result = await NativeDanmakuPrefetch.loadSavedSourceToFile(
      sourceKey: sourceKey,
      itemGuid: _source.itemGuid,
      mediaGuid: _source.mediaGuid,
      seasonGuid: _source.seasonGuid,
      seasonNumber: _source.seasonNumber,
      episodeNumber: _source.episodeNumber,
      seriesTitle: _source.seriesTitle,
    );
    if (!_isCurrentSourceChange(generation)) return false;
    final path = result?['danmakuFile']?.toString().trim() ?? '';
    if (path.isEmpty) {
      _showPlayerMessage('弹幕源加载失败');
      return false;
    }
    final label = '${source['label'] ?? sourceKey}'.trim();
    final loaded = await _loadDanmakuForSource(
      path,
      sourceLabel: label,
      enableOnSuccess: true,
    );
    if (loaded) _showPlayerMessage('已切换弹幕源');
    return loaded;
  }

  Future<bool> _selectDanmakuSearchResult(
    Map<String, dynamic> candidate,
  ) async {
    final generation = _sourceChangeGeneration;
    final episodeId = (candidate['episodeId'] as num?)?.toInt() ?? 0;
    if (episodeId <= 0) return false;
    final result = await NativeDanmakuPrefetch.importEpisodeToFile(
      episodeId: episodeId,
      animeTitle: '${candidate['animeTitle'] ?? ''}',
      episodeTitle: '${candidate['episodeTitle'] ?? ''}',
      episodeNumber: (candidate['episodeNumber'] as num?)?.toInt() ?? 0,
      itemGuid: _source.itemGuid,
      mediaGuid: _source.mediaGuid,
      seasonGuid: _source.seasonGuid,
      seasonNumber: _source.seasonNumber,
      currentEpisodeNumber: _source.episodeNumber,
      seriesTitle: _source.seriesTitle,
      mediaItemTitle: _source.title,
    );
    if (!_isCurrentSourceChange(generation)) return false;
    final path = result?['danmakuFile']?.toString().trim() ?? '';
    if (path.isEmpty) {
      _showPlayerMessage('在线弹幕加载失败');
      return false;
    }
    final episodeTitle = '${candidate['episodeTitle'] ?? ''}'.trim();
    final animeTitle = '${candidate['animeTitle'] ?? ''}'.trim();
    final loaded = await _loadDanmakuForSource(
      path,
      sourceLabel: episodeTitle.isNotEmpty ? episodeTitle : animeTitle,
      enableOnSuccess: true,
    );
    if (loaded) _showPlayerMessage('已加载在线弹幕');
    return loaded;
  }

  Future<void> _deleteSavedDanmakuSource(Map<String, dynamic> source) async {
    final sourceKey = '${source['sourceKey'] ?? ''}'.trim();
    final removed = await NativeDanmakuPrefetch.removeSavedSource(
      sourceKey: sourceKey,
      itemGuid: _source.itemGuid,
      mediaGuid: _source.mediaGuid,
      seasonGuid: _source.seasonGuid,
      seasonNumber: _source.seasonNumber,
      episodeNumber: _source.episodeNumber,
      seriesTitle: _source.seriesTitle,
    );
    if (removed) _showPlayerMessage('已删除弹幕源');
  }

  void _toggleDanmaku() {
    unawaited(
      _updateDanmakuSettings(
        _danmakuSettings.copyWith(enabled: !_danmakuSettings.enabled),
      ),
    );
  }

  Future<void> _setVideoAdjustment(String key, double value) async {
    if (!MpvSettingsCatalog.isVideoAdjustmentKey(key)) return;
    final next = Map<String, double>.from(_videoAdjustments)..[key] = value;
    final normalized = MpvSettingsCatalog.normalizeVideoAdjustments(next);
    if (mounted) _updateView(() => _videoAdjustments = normalized);
    await _mpvSettingsStore.saveVideoAdjustments(normalized);
    await _setMpvProperty(key, (normalized[key] ?? 0).toStringAsFixed(0));
  }

  /// 播放设置面板的高级键统一入口：落盘 + 按键所属分组即时下发对应 mpv 属性。
  Future<void> _setMpvAdvancedSetting(String key, String value) async {
    final next = await _mpvSettingsStore.savePatch(<String, String>{
      key: value,
    });
    if (mounted) _updateView(() => _mpvSettings = next);
    await _applyMpvAdvancedProperty(key);
  }

  Future<void> _applyMpvAdvancedProperty(String key) async {
    if (MpvSettingsCatalog.audioPresetKeys.contains(key) ||
        MpvSettingsCatalog.audioEqBands.any((band) => band.key == key)) {
      await _applyDesktopAudioProperties(resetVolume: true);
      return;
    }
    switch (key) {
      case MpvSettingsCatalog.cacheProfileKey:
      case MpvSettingsCatalog.cacheSizeMbKey:
        await _applyDesktopCacheProperties();
      case MpvSettingsCatalog.debandKey:
      case MpvSettingsCatalog.sharpenKey:
      case MpvSettingsCatalog.denoiseKey:
      case MpvSettingsCatalog.deinterlaceKey:
      case MpvSettingsCatalog.scaleProfileKey:
      case MpvSettingsCatalog.frameInterpolationKey:
      case MpvSettingsCatalog.videoSyncKey:
      case MpvSettingsCatalog.toneMappingKey:
        await _applyDesktopVideoEnhancement();
    }
  }

  Future<List<SavedMpvPreset>> _loadSavedPresets(SavedMpvPresetKind kind) =>
      _mpvSettingsStore.loadSavedPresets(kind);

  Future<void> _applySavedMpvPreset(SavedMpvPreset preset) async {
    final bundle = await _mpvSettingsStore.applySavedPreset(
      preset,
      currentSettings: _mpvSettings,
      currentVideoAdjustments: _videoAdjustments,
    );
    if (!mounted) return;
    _updateView(() {
      _mpvSettings = bundle.settings;
      _videoAdjustments = bundle.videoAdjustments;
    });
    for (final entry in _videoAdjustments.entries) {
      await _setMpvProperty(entry.key, entry.value.toStringAsFixed(0));
    }
    await _applyDesktopVideoEnhancement();
    await _applyDesktopCacheProperties();
    await _applyDesktopAudioProperties(resetVolume: true);
  }

  Future<void> _setAudioDelay(double value) async {
    final normalized = value.clamp(-10.0, 10.0).toDouble();
    if (mounted) _updateView(() => _audioDelaySeconds = normalized);
    await _setMpvProperty('audio-delay', normalized.toStringAsFixed(1));
  }

  void _onDurationChanged(Duration duration) {
    _chapterLoader.load(duration);
    _syncSystemMediaControls();
  }

  void _onChaptersChanged() {
    if (!mounted) return;
    _updateView(() {});
    _skipPromptKindNotifier.value = _computeSkipPromptKind(
      _player.state.position,
    );
  }

  get _skipBounds => desktopPlaybackSkipBounds(
    _chapters,
    _player.state.duration,
    chapterEnabled: _introOutroEnabled,
    fixedDurationEnabled: _fixedDurationSkipEnabled,
    introMinutes: _introMaxMinutes,
    outroMinutes: _outroMaxMinutes,
  );

  /// 仅在已启用的章节或固定时长范围内提示跳过。
  void _onPositionChanged(Duration position) {
    _observeFlyOped(position);
    _syncSystemMediaControls();
    _weakNetwork.onPosition(position);
    unawaited(_refreshSegmentedSubtitle(position));
    if (!_isLoading && _errorMessage == null) {
      final remaining = _player.state.duration - position;
      final nearEnd =
          position > Duration.zero &&
          remaining > Duration.zero &&
          remaining <= const Duration(seconds: 5);
      if (nearEnd) {
        _startAutoNextCountdown();
      } else if (!_player.state.completed &&
          remaining > const Duration(seconds: 5)) {
        _cancelAutoNext(suppress: false);
        if (_playbackCompleted) {
          _updateView(() => _playbackCompleted = false);
        }
      }
    }
    final kind = _computeSkipPromptKind(position);
    if (kind == _skipPromptKindNotifier.value) return;
    _skipPromptKindNotifier.value = kind;
  }

  _SkipPromptKind? _computeSkipPromptKind(Duration position) {
    if ((!_introOutroEnabled && !_fixedDurationSkipEnabled) ||
        _playbackCompleted ||
        _isLoading ||
        _abLoopStart != null) {
      return null;
    }
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return null;
    final published = _currentFlyOped;
    if (published != null) {
      final segment = published.at(position.inMilliseconds, enabled: _introOutroEnabled);
      if (segment == null || _flyAction != null) return null;
      if (segment.kind == 'op' && !_introSkipDismissed) return _SkipPromptKind.intro;
      if (segment.kind == 'ed' && !_outroSkipDismissed) return _SkipPromptKind.outro;
      return null;
    }
    final bounds = _skipBounds;
    final introStart = bounds.introStart;
    final introEnd = bounds.introEnd;
    final outroStart = bounds.outroStart;
    if (!_introSkipDismissed &&
        introStart != null &&
        introEnd != null &&
        position >= const Duration(seconds: 2) &&
        position >= introStart &&
        position < introEnd) {
      return _SkipPromptKind.intro;
    }
    if (!_outroSkipDismissed && outroStart != null && position >= outroStart) {
      return _SkipPromptKind.outro;
    }
    return null;
  }

  void _dismissSkipPrompt() {
    final kind = _skipPromptKindNotifier.value;
    if (kind == _SkipPromptKind.intro) _introSkipDismissed = true;
    if (kind == _SkipPromptKind.outro) _outroSkipDismissed = true;
    _skipPromptKindNotifier.value = null;
  }

  Future<void> _skipIntroOrOutro() async {
    final kind = _skipPromptKindNotifier.value;
    if (kind == null) return;
    final published = _currentFlyOped;
    if (published != null) {
      final segment = published.at(_player.state.position.inMilliseconds);
      if (segment != null) await _skipPublished(published, segment);
      return;
    }
    _dismissSkipPrompt();
    if (kind == _SkipPromptKind.intro) {
      final target = _skipBounds.introEnd;
      if (target != null) await _seekTo(target);
      return;
    }
    final next = _nextEpisode;
    if (next != null) {
      await _showNextEpisode();
    } else {
      await _seekTo(_player.state.duration);
    }
  }

  Future<void> _setIntroOutroSettings({
    required bool enabled,
    required int introMaxMinutes,
    required int outroMaxMinutes,
    required bool fixedDurationEnabled,
  }) async {
    if (mounted) {
      _updateView(() {
        _introOutroEnabled = enabled;
        _introMaxMinutes = introMaxMinutes.clamp(1, 4);
        _outroMaxMinutes = outroMaxMinutes.clamp(1, 4);
        _fixedDurationSkipEnabled = fixedDurationEnabled;
        _skipPromptKindNotifier.value = _computeSkipPromptKind(
          _player.state.position,
        );
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introOutroEnabledPrefKey, enabled);
    await prefs.setInt(_introMaxMinutesPrefKey, _introMaxMinutes);
    await prefs.setInt(_outroMaxMinutesPrefKey, _outroMaxMinutes);
    await prefs.setBool(_fixedDurationSkipPrefKey, fixedDurationEnabled);
  }

  Future<void> _selectChapter(Duration position) async {
    _dismissHoverOverlay();
    await _seekTo(position);
  }

  bool _isCurrentSourceChange(int generation) =>
      mounted && generation == _sourceChangeGeneration;

  /// 所有打开入口共用暂停加载、恢复属性和播放的顺序。
  /// 每个异步边界检查请求身份，旧请求不能继续操作新媒体。
  Future<bool> _installSource(
    MpvMediaSource source,
    int generation, {
    required bool play,
    Duration? startPosition,
    bool preserveTracks = false,
  }) async {
    if (!_isCurrentSourceChange(generation)) return false;
    _recordLocalStats();
    _reportProgress();
    _reportReady = false;
    final previousSource = _source;
    final previousTracks = _player.state.track;
    _source = source;
    _resetFlyOped();
    _updateSystemMediaMetadata();
    _weakNetwork.setSource(source);
    _pausedByUser = !play;
    widget.session.ready = false;
    _subtitleWindowSecond = -100;
    try {
      // 每次打开媒体都清除旧循环，避免换集后沿用上一集的时间点。
      await _setMpvProperty('ab-loop-b', 'no');
      if (!_isCurrentSourceChange(generation)) return false;
      await _setMpvProperty('ab-loop-a', 'no');
      if (!_isCurrentSourceChange(generation)) return false;
      _updateView(() {
        _abLoopStart = null;
        _abLoopEnd = null;
      });
      await _applyDesktopMpvProperties();
      if (!_isCurrentSourceChange(generation)) return false;
      _chapterLoader.reset();
      await _player.open(
        DesktopMpvRuntime.mediaFor(source, startPosition: startPosition),
        play: false,
      );
      if (!_isCurrentSourceChange(generation)) return false;
      await _applyDesktopMpvProperties();
      if (!_isCurrentSourceChange(generation)) return false;
      if (preserveTracks) {
        await _player.setAudioTrack(previousTracks.audio);
        if (!_isCurrentSourceChange(generation)) return false;
        await _player.setSubtitleTrack(previousTracks.subtitle);
      } else {
        await _applyPreferredSubtitle(source);
      }
      if (!_isCurrentSourceChange(generation)) return false;
      await _player.setRate(_playbackRate);
      if (!_isCurrentSourceChange(generation)) return false;
      if (play) await _player.play();
      if (!_isCurrentSourceChange(generation)) return false;
      _reportReady = true;
      widget.session.ready = true;
      return true;
    } finally {
      _releaseSource(previousSource, replacement: _source);
    }
  }

  Future<void> _openSource() async {
    if (!mounted) return;
    final generation = ++_sourceChangeGeneration;
    _lastDirectLinkRefreshAttempt = null;
    _resetPlaybackOverlays();
    _pausedByUser = _source.startPaused;
    if (_source.url.trim().isEmpty) {
      _showGenericError(_l10n.desktopPlaybackErrorSourceUnavailable);
      _finishLoading();
      return;
    }

    try {
      final source = await _freshDirectLinkSource(_source);
      if (!_isCurrentSourceChange(generation)) {
        _releaseSource(source, replacement: _source);
        return;
      }
      if (!await _installSource(
        source,
        generation,
        play: !source.startPaused,
      )) {
        return;
      }
      _reporter.onLaunch(source);
      _showResumeFromPrompt(source.startPosition);
      unawaited(_loadDanmakuForSource(widget.danmakuFilePath));
      unawaited(_preloadNextEpisodeIfEnabled());
    } catch (_) {
      if (_isCurrentSourceChange(generation)) {
        _showGenericError(_l10n.desktopPlaybackErrorStartFailed);
      }
    } finally {
      if (_isCurrentSourceChange(generation)) {
        _finishLoading();
        _scheduleProgressReport();
      }
    }
  }

  Future<void> _openEpisode(Map<String, dynamic> episode) async {
    final resolver = widget.resolveEpisode;
    if (!mounted || resolver == null) return;
    final generation = ++_sourceChangeGeneration;
    _lastDirectLinkRefreshAttempt = null;
    final episodeGuid = '${episode['itemGuid'] ?? episode['guid'] ?? ''}'
        .trim();
    final cached =
        episodeGuid.isNotEmpty && episodeGuid == _preloadedNextItemGuid
        ? _preloadedNextSource
        : null;
    _clearPreloadedNext(replacement: cached?.source);
    _resetPlaybackOverlays();
    _wakeControls(scheduleHide: false);
    _updateView(() {
      _isLoading = true;
      _errorMessage = null;
    });
    DesktopResolvedEpisode? resolved;
    var adopted = false;
    try {
      resolved = cached ?? await resolver(episode);
      if (!_isCurrentSourceChange(generation)) return;
      if (resolved == null || resolved.source.url.trim().isEmpty) {
        _showGenericError(_l10n.desktopPlaybackErrorEpisodeResolveFailed);
        return;
      }
      final source = await _freshDirectLinkSource(resolved.source);
      _releaseSource(resolved.source, replacement: source);
      resolved = (
        source: source,
        danmakuFilePath: resolved.danmakuFilePath,
        episodes: resolved.episodes,
      );
      if (!_isCurrentSourceChange(generation)) return;
      _playbackRate = _validPlaybackRate(source.playbackSpeed);
      adopted = true;
      if (!await _installSource(
        source,
        generation,
        play: !source.startPaused,
      )) {
        return;
      }
      _showResumeFromPrompt(source.startPosition);
      _updateView(() => _episodes = resolved!.episodes);
      unawaited(_loadDanmakuForSource(resolved.danmakuFilePath));
      await _loadBookmarks();
      if (!_isCurrentSourceChange(generation)) return;
      unawaited(_preloadNextEpisodeIfEnabled());
    } catch (_) {
      if (_isCurrentSourceChange(generation)) {
        _showGenericError(_l10n.desktopPlaybackErrorEpisodeSwitchFailed);
      }
    } finally {
      if (resolved != null && !adopted) {
        _releaseSource(resolved.source, replacement: _source);
      }
      if (_isCurrentSourceChange(generation)) {
        _finishLoading();
        _scheduleProgressReport();
      }
    }
  }

  Future<void> _reloadPlaybackSource({
    String? audioTrackId,
    String? subtitleTrackId,
    bool subtitleDisabled = false,
    int? qualityIndex,
  }) async {
    final resolver = widget.reloadSource;
    if (!mounted || resolver == null) return;
    final generation = ++_sourceChangeGeneration;
    _lastDirectLinkRefreshAttempt = null;
    final wasPlaying = _isPlaying || (_isBuffering && !_pausedByUser);
    final quality = qualityIndex == null
        ? null
        : DesktopMpvRuntime.qualityMenu(_source).customGroups.values
              .expand((group) => group)
              .where((choice) => choice.sourceIndex == qualityIndex)
              .firstOrNull;
    _wakeControls(scheduleHide: false);
    _updateView(() {
      _isLoading = true;
      _qualitySwitchingMessage = quality == null
          ? null
          : _l10n.playerQualitySwitching(
              quality.isOriginal
                  ? '${quality.displayTier} ${_l10n.playerQualityOriginal}'
                  : quality.displayTier,
              quality.quality.bitrate > 0
                  ? '（${DesktopMpvRuntime.qualityBitrateLabel(quality.quality.bitrate)}）'
                  : '',
            );
      _errorMessage = null;
    });
    MpvMediaSource? resolved;
    var adopted = false;
    try {
      resolved = await resolver(
        _source,
        MediaSessionReloadIntent(
          audioTrackId: audioTrackId,
          subtitleTrackId: subtitleTrackId,
          subtitleDisabled: subtitleDisabled,
          qualityIndex: qualityIndex,
          startPosition: _player.state.position,
        ),
      );
      if (!_isCurrentSourceChange(generation)) return;
      if (resolved == null || resolved.url.trim().isEmpty) {
        _showGenericError(
          qualityIndex == null
              ? _l10n.desktopPlaybackErrorTrackSwitchFailed
              : _l10n.nativePlayerSwitchQualityUnavailable,
        );
        return;
      }
      adopted = true;
      await _installSource(resolved, generation, play: wasPlaying);
    } catch (_) {
      if (_isCurrentSourceChange(generation)) {
        _showGenericError(
          qualityIndex == null
              ? _l10n.desktopPlaybackErrorTrackSwitchFailed
              : _l10n.nativePlayerSwitchQualityUnavailable,
        );
      }
    } finally {
      if (resolved != null && !adopted) {
        _releaseSource(resolved, replacement: _source);
      }
      if (_isCurrentSourceChange(generation)) {
        _finishLoading();
        _scheduleProgressReport();
      }
    }
  }

  void _releaseSource(MpvMediaSource source, {MpvMediaSource? replacement}) =>
      _reporter.release(source, replacement: replacement);

  void _scheduleProgressReport() {
    _progressTimer?.cancel();
    _directLinkTimer?.cancel();
    if (mounted &&
        _reportReady &&
        _isPlaying &&
        _source.playbackMode.isDirectLink &&
        widget.refreshDirectLink != null) {
      unawaited(_refreshDirectLinkIfNeeded());
      _directLinkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(_refreshDirectLinkIfNeeded());
      });
    }
    if (!mounted ||
        !_reportReady ||
        !_isPlaying ||
        widget.onRecordProgress == null) {
      return;
    }
    _progressTimer = Timer(const Duration(seconds: 1), () {
      _reportProgress();
      _progressTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_isPlaying && !_isBuffering) _reportProgress();
      });
    });
  }

  /// 预加载下一集可能早于真正起播；到播放时按墙钟重新检查有效期。
  Future<MpvMediaSource> _freshDirectLinkSource(MpvMediaSource source) async {
    final refresh = widget.refreshDirectLink;
    if (refresh == null ||
        !DesktopMpvRuntime.directLinkNeedsRefresh(source, DateTime.now())) {
      return source;
    }
    return refresh(source);
  }

  Future<void> _refreshDirectLinkIfNeeded({bool beforePlay = false}) async {
    final refresh = widget.refreshDirectLink;
    final now = DateTime.now();
    if (!mounted ||
        !_reportReady ||
        (!_isPlaying && !beforePlay) ||
        _isLoading ||
        _directLinkRefreshPending ||
        refresh == null ||
        !DesktopMpvRuntime.directLinkNeedsRefresh(_source, now) ||
        (_lastDirectLinkRefreshAttempt != null &&
            now.difference(_lastDirectLinkRefreshAttempt!) <
                const Duration(seconds: 30))) {
      return;
    }
    _directLinkRefreshPending = true;
    _lastDirectLinkRefreshAttempt = now;
    final previousSource = _source;
    final generation = _sourceChangeGeneration;
    bool isCurrent() =>
        mounted &&
        generation == _sourceChangeGeneration &&
        _source.loadNonce == previousSource.loadNonce;
    var reopening = false;
    try {
      final refreshed = await refresh(previousSource);
      if (!isCurrent() || _isLoading || _source.url != previousSource.url) {
        return;
      }
      final changed =
          refreshed.url != _source.url ||
          !mapEquals(refreshed.headers, _source.headers);
      _source = _source.copyWith(
        url: refreshed.url,
        headers: refreshed.headers,
        qualities: refreshed.qualities,
      );
      if (!changed) return;
      // 网络请求完成后才取当前位置，不能回到请求开始时的旧进度。
      final position = _player.state.position;
      final wasPlaying = _player.state.playing;
      final audio = _player.state.track.audio;
      final subtitle = _player.state.track.subtitle;
      _reportProgress();
      _reportReady = false;
      reopening = true;
      _updateView(() {
        _isLoading = true;
        _errorMessage = null;
      });
      await _player.open(
        DesktopMpvRuntime.mediaFor(_source, startPosition: position),
        play: false,
      );
      if (!isCurrent()) return;
      await _applyDesktopMpvProperties();
      if (!isCurrent()) return;
      await _player.setAudioTrack(audio);
      if (!isCurrent()) return;
      await _player.setSubtitleTrack(subtitle);
      if (!isCurrent()) return;
      await _player.setRate(_playbackRate);
      if (!isCurrent()) return;
      if (wasPlaying) await _player.play();
      if (isCurrent()) _reportReady = true;
    } catch (_) {
      // 续签失败保留当前播放，下个周期再试；不把临时网络错误升级为播放失败。
      debugPrint('[desktop-playback] 直链续期失败');
      if (reopening && isCurrent()) {
        _reportReady = true;
        _showGenericError(_l10n.desktopPlaybackErrorStartFailed);
      }
    } finally {
      _directLinkRefreshPending = false;
      if (reopening && isCurrent()) {
        _finishLoading();
        _scheduleProgressReport();
      }
    }
  }

  Timer? _localStatsTimer;

  void _recordLocalStats() {
    if (!_reportReady || _isLoading || _errorMessage != null) return;
    _reporter.recordLocal(
      _source,
      position: _player.state.position,
      duration: _player.state.duration,
      paused: _pausedByUser || !_player.state.playing || _isBuffering,
    );
  }

  void _reportProgress() {
    if (!_reportReady || _errorMessage != null) return;
    _reporter.recordServer(
      _source,
      position: _player.state.position,
      duration: _player.state.duration,
      paused: _pausedByUser || !_player.state.playing,
      completed: _player.state.completed,
    );
  }

  double _validPlaybackRate(double value) {
    return value.isFinite && value > 0 ? value : 1;
  }

  Future<void> _refreshSegmentedSubtitle(Duration position) async {
    final resolve = widget.resolveSegmentedSubtitle;
    if (resolve == null ||
        _isLoading ||
        _subtitleWindowPending ||
        (position.inSeconds - _subtitleWindowSecond).abs() < 3) {
      return;
    }
    final source = _source;
    _subtitleWindowPending = true;
    _subtitleWindowSecond = position.inSeconds;
    try {
      final path = await resolve(source, position);
      if (!mounted ||
          !identical(source, _source) ||
          path == null ||
          (_player.state.position - position).abs() >
              const Duration(seconds: 12)) {
        return;
      }
      await _player.setSubtitleTrack(SubtitleTrack.uri(_subtitleUri(path)));
    } finally {
      _subtitleWindowPending = false;
    }
  }

  Future<void> _applyPreferredSubtitle(MpvMediaSource source) async {
    final generation = _sourceChangeGeneration;
    final selectedGuid = source.subtitleTrackGuid?.trim() ?? '';
    if (selectedGuid.isEmpty) return;
    var path = source.localSubtitleFiles[selectedGuid]?.trim() ?? '';
    String? title;
    String? language;
    for (final track in source.subtitleTracks) {
      if (track.guid != selectedGuid) continue;
      title = track.title.trim().isEmpty ? null : track.title.trim();
      language = track.language.trim().isEmpty ? null : track.language.trim();
      if (path.isEmpty && (track.isExternal == 1 || track.extraFile == 1)) {
        try {
          final request = widget.resolveSubtitleFile?.call(
            selectedGuid,
            format: track.format,
          );
          path = request == null
              ? ''
              : (await (source.isDownloadedFile
                        ? request.timeout(const Duration(seconds: 2))
                        : request) ??
                    '');
        } catch (_) {
          // 本地视频可以没有外挂字幕，不能因 NAS 不可达而起播失败。
          if (!source.isDownloadedFile) rethrow;
        }
      }
      break;
    }
    if (!_isCurrentSourceChange(generation) ||
        !identical(source, _source) ||
        path.isEmpty) {
      return;
    }
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(_subtitleUri(path), title: title, language: language),
    );
  }

  String _subtitleUri(String path) {
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.hasScheme) return path;
    return Uri.file(path, windows: true).toString();
  }

  void _finishLoading() {
    if (_flyContextId.isEmpty) _resetFlyOped();
    if (mounted) {
      _updateView(() {
        _isLoading = false;
        _qualitySwitchingMessage = null;
      });
    }
  }

  void _showGenericError(String message) {
    if (mounted) _updateView(() => _errorMessage = message);
  }

  void _onPlayerError(String error) {
    final diagnostic = error.replaceAll(RegExp(r'https?://\S+'), '<media-url>');
    debugPrint(
      '[desktop-playback] media_kit error '
      '(pausedByUser=$_pausedByUser, loading=$_isLoading): $diagnostic',
    );
    if (!mounted || _pausedByUser || _isLoading) return;
    _showGenericError(_l10n.desktopPlaybackErrorGeneric);
  }

  void _onPlayingChanged(bool playing) {
    if (!mounted) return;
    if (!playing) _reportProgress();
    _updateView(() {
      _isPlaying = playing;
      if (playing) _pausedByUser = false;
      if (!playing) _controlsVisible = true;
    });
    if (playing) {
      _scheduleControlsHide();
      _scheduleProgressReport();
    } else {
      _progressTimer?.cancel();
      _directLinkTimer?.cancel();
      _controlsHideTimer?.cancel();
    }
  }

  void _onVolumeChanged(double volume) {
    if (!mounted) return;
    _updateView(() {
      _volume = volume.clamp(0.0, 100.0).toDouble();
      if (_volume > 0) _lastAudibleVolume = _volume;
    });
  }

  void _onBufferingChanged(bool buffering) {
    if (!mounted || _isBuffering == buffering) return;
    _updateView(() => _isBuffering = buffering);
  }

  void _onCompletedChanged(bool completed) {
    if (!mounted || !completed || _playbackCompleted || _isLoading) return;
    _reportProgress();
    _progressTimer?.cancel();
    _directLinkTimer?.cancel();
    _controlsHideTimer?.cancel();
    _resumePromptTimer?.cancel();
    _startAutoNextCountdown();
    _updateView(() {
      _playbackCompleted = _autoNextSeconds == 0;
      _controlsVisible = false;
      _showResumePrompt = false;
    });
  }

  void _resetPlaybackOverlays() {
    _danmakuLoadGeneration++;
    _resumePromptTimer?.cancel();
    _autoNextTimer?.cancel();
    _toastTimer?.cancel();
    _introSkipDismissed = false;
    _outroSkipDismissed = false;
    _skipPromptKindNotifier.value = null;
    if (!mounted) return;
    _updateView(() {
      _playbackCompleted = false;
      _qualitySwitchingMessage = null;
      _autoNextSeconds = 0;
      _autoNextSuppressed = false;
      _showResumePrompt = false;
      _danmakuComments = const [];
      _danmakuSourceLabel = '';
      _danmakuLoading = false;
      _toastMessage = null;
    });
  }

  void _showResumeFromPrompt(Duration position) {
    if (!mounted || position < const Duration(seconds: 10)) return;
    _resumePromptTimer?.cancel();
    _updateView(() => _showResumePrompt = true);
    _resumePromptTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) _updateView(() => _showResumePrompt = false);
    });
  }

  void _dismissResumePrompt() {
    _resumePromptTimer?.cancel();
    if (mounted) _updateView(() => _showResumePrompt = false);
  }

  Future<void> _restartFromBeginning() async {
    _dismissResumePrompt();
    await _seekTo(Duration.zero);
    if (!_isPlaying) {
      _pausedByUser = false;
      await _player.play();
    }
  }

  void _startAutoNextCountdown() {
    if (!flyOpedAllowsAutoNext(protectedEdTail: _flyEdTailProtected,
          playbackEnded: _player.state.completed, pausedByUser: _pausedByUser) ||
        _autoNextSeconds > 0 ||
        _autoNextSuppressed ||
        !_autoPlayEnabled ||
        _nextEpisode == null ||
        widget.resolveEpisode == null ||
        _abLoopStart != null) {
      return;
    }
    _updateView(() => _autoNextSeconds = 5);
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoNextSeconds <= 1) {
        timer.cancel();
        _updateView(() => _autoNextSeconds = 0);
        unawaited(_showNextEpisode());
        return;
      }
      _updateView(() => _autoNextSeconds -= 1);
    });
  }

  void _cancelAutoNext({bool suppress = true}) {
    _autoNextTimer?.cancel();
    if (suppress) _autoNextSuppressed = true;
    if (mounted && _autoNextSeconds > 0) {
      _updateView(() {
        _autoNextSeconds = 0;
        _playbackCompleted = _player.state.completed;
      });
    }
  }

  Future<void> _replayCompleted() async {
    _autoNextTimer?.cancel();
    _updateView(() {
      _playbackCompleted = false;
      _autoNextSeconds = 0;
      _autoNextSuppressed = false;
      _controlsVisible = true;
    });
    await _seekTo(Duration.zero);
    _pausedByUser = false;
    await _player.play();
  }

  void _wakeControls({bool scheduleHide = true}) {
    if (_hoverOverlayKind != null) scheduleHide = false;
    if (!_controlsVisible && mounted) {
      _updateView(() => _controlsVisible = true);
    }
    _controlsHideTimer?.cancel();
    if (scheduleHide && _isPlaying) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(_controlsHideDelay, () {
      if (mounted && _isPlaying) {
        _updateView(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    _wakeControls();
    if (!_isPlaying) await _refreshDirectLinkIfNeeded(beforePlay: true);
    if (!mounted || _isLoading) return;
    _pausedByUser = _isPlaying;
    await _player.playOrPause();
  }

  void _updateSystemMediaMetadata() {
    unawaited(
      _systemMediaControls?.setMetadata(
        title: _source.title.trim().isEmpty
            ? _source.seriesTitle
            : _source.title,
        subtitle: _subtitle,
      ),
    );
  }

  void _syncSystemMediaControls() {
    if (!mounted) return;
    unawaited(
      _systemMediaControls?.update(
        status: _errorMessage != null
            ? 'closed'
            : _isLoading
            ? 'changing'
            : _player.state.completed
            ? 'stopped'
            : _player.state.playing
            ? 'playing'
            : 'paused',
        position: _player.state.position,
        duration: _player.state.duration,
        rate: _playbackRate,
      ),
    );
  }

  Future<void> _setSystemPlaying(bool playing) async {
    if (!mounted || _isLoading || _errorMessage != null) return;
    if (playing == _player.state.playing && !_player.state.completed) return;
    _wakeControls();
    if (playing && _player.state.completed) {
      await _replayCompleted();
    } else if (playing) {
      await _refreshDirectLinkIfNeeded(beforePlay: true);
      if (!mounted || _isLoading) return;
      _pausedByUser = false;
      await _player.play();
    } else {
      _pausedByUser = true;
      await _player.pause();
    }
  }

  Future<void> _seekRelative(Duration offset) async {
    _wakeControls();
    var target = _player.state.position.inMicroseconds + offset.inMicroseconds;
    if (target < 0) target = 0;
    final duration = _player.state.duration.inMicroseconds;
    if (duration > 0 && target > duration) target = duration;
    await _seekTo(Duration(microseconds: target));
  }

  Future<void> _seekTo(Duration position, {bool publishedAction = false}) {
    if (!publishedAction) {
      _flySkipPolicy.userSeek();
      _finishFlyAction('cancelled');
      if (_currentFlyOped != null) {
        _introSkipDismissed = false;
        _outroSkipDismissed = false;
      }
    }
    _weakNetwork.markSeek();
    _danmakuSeekRevision++;
    _viewRevision.value++;
    return _player.seek(position < Duration.zero ? Duration.zero : position);
  }

  FlyOpedSet? get _currentFlyOped {
    if (!_source.supportsVerifiedFileOped || _flyScopeEpoch != _flyClient.epoch ||
        _flyClient.sourceRef(statsScope: _source.statsScope, itemGuid: _source.itemGuid, mediaGuid: _source.mediaGuid) == null) {
      return null;
    }
    return _flyOped;
  }

  void _resetFlyOped() {
    _finishFlyAction('cancelled');
    _flyEdTailProtected = false;
    _flyOped = null;
    _flyAuthorizing = false;
    _flySkipPolicy = FlyOpedPlaybackPolicy();
    _flyContextId = 'desktop-${_source.loadNonce}-${FlyPlaybackServiceClient.newId()}';
    _flyScopeEpoch = _flyClient.epoch;
    unawaited(_resolveFlyOped());
  }

  Future<void> _resolveFlyOped() async {
    final contextId = _flyContextId, source = _source;
    if (!source.supportsVerifiedFileOped) return;
    final generation = _danmakuSeekRevision, sourceGeneration = _sourceChangeGeneration;
    final result = await _flyClient.resolve(statsScope: source.statsScope, itemGuid: source.itemGuid,
      mediaGuid: source.mediaGuid, contextId: contextId, generation: generation);
    if (!mounted || contextId != _flyContextId || sourceGeneration != _sourceChangeGeneration ||
        generation != _danmakuSeekRevision || !identical(source, _source) || _flyScopeEpoch != _flyClient.epoch) {
      return;
    }
    _flyOped = result;
    _skipPromptKindNotifier.value = _computeSkipPromptKind(_player.state.position);
  }

  Future<void> _skipPublished(FlyOpedSet set, FlyOpedSegment segment, {bool automatic = false}) async {
    if (!_introOutroEnabled || _flyAction != null || _flyAuthorizing || !identical(set, _currentFlyOped) || !segment.contains(_player.state.position.inMilliseconds)) return;
    final generation = _danmakuSeekRevision, contextId = _flyContextId, source = _source;
    _flyAuthorizing = true;
    final authorized = await _flyClient.resolve(statsScope: source.statsScope, itemGuid: source.itemGuid,
      mediaGuid: source.mediaGuid, contextId: contextId, generation: generation);
    if (!mounted || contextId != _flyContextId) return;
    _flyAuthorizing = false;
    if (generation != _danmakuSeekRevision || !identical(source, _source) || !identical(set, _currentFlyOped)) return;
    if (authorized == null || !set.samePublication(authorized)) {
      _flyOped = null;
      _skipPromptKindNotifier.value = null;
      _showPlayerMessage('该跳过区间已失效或暂不可用，请重新加载节目资料。');
      return;
    }
    if (!_introOutroEnabled || (automatic && !_flyAutomaticAllowed) || !segment.contains(_player.state.position.inMilliseconds)) return;
    final action = FlyOpedAction(set: set, segment: segment, generation: _danmakuSeekRevision,
      positionMs: _player.state.position.inMilliseconds, actionId: FlyPlaybackServiceClient.newId());
    if (segment.kind == 'ed') {
      _flyEdTailProtected = true;
      _cancelAutoNext(suppress: false);
    }
    _flyAction = action;
    _flySeekCommandAccepted = false;
    unawaited(_flyClient.record(action.event('intent'), statsScope: _source.statsScope));
    _dismissSkipPrompt();
    _flyActionTimeout = Timer(const Duration(seconds: 12), () => _finishFlyAction('failed'));
    try {
      final command = _seekTo(Duration(milliseconds: segment.endMs), publishedAction: true);
      action.expectedGeneration = _danmakuSeekRevision;
      await command;
      if (identical(action, _flyAction)) {
        _flySeekCommandAccepted = true;
        // Paused playback may emit its sole position event before command ack.
        // Read actual engine properties now and retry only while this action lives.
        _sampleFlyOpedAction();
        _flyObservationTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _sampleFlyOpedAction());
      }
    } catch (_) { if (identical(action, _flyAction)) _finishFlyAction('failed'); }
  }

  void _observeFlyOped(Duration position) {
    final set = _currentFlyOped;
    if (set == null) { _finishFlyAction('cancelled'); return; }
    _sampleFlyOpedAction();
    if (_flyAutomaticAllowed && _flyAction == null) {
      final auto = _flySkipPolicy.observe(set, position.inMilliseconds);
      if (auto != null) unawaited(_skipPublished(set, auto, automatic: true));
    }
  }

  bool get _flyAutomaticAllowed => !_isLoading && !_isBuffering && _isPlaying &&
      !_player.state.completed && _introOutroEnabled && _abLoopStart == null;

  void _sampleFlyOpedAction() {
    final set = _currentFlyOped;
    if (set == null) { _finishFlyAction('cancelled'); return; }
    final action = _flyAction;
    if (action != null && !_flySamplePending && _flySeekCommandAccepted) {
      _flySamplePending = true;
      final epoch = _danmakuSeekRevision;
      final platform = _player.platform;
      // Confirm actual mpv seeking=false and a fresh matching position. A
      // completed command Future alone is never a settled observation.
      Future<void> observe() async {
        if (platform is! NativePlayer) return;
        final seeking = await platform.getProperty('seeking');
        final seconds = double.tryParse(await platform.getProperty('time-pos'));
        if (!mounted || epoch != _danmakuSeekRevision || !identical(action, _flyAction) || !identical(set, _currentFlyOped) || seconds == null || !seconds.isFinite) return;
        final phase = action.sample(positionMs: (seconds * 1000).round(),
          engineAccepted: seeking == 'no' || seeking == 'false', generation: epoch);
        if (phase != null) _finishFlyAction(phase, alreadyFinished: true);
      }
      unawaited(observe().timeout(const Duration(seconds: 1)).catchError((Object _) {}).whenComplete(() => _flySamplePending = false));
    }
  }

  void _finishFlyAction(String phase, {bool alreadyFinished = false}) {
    final action = _flyAction;
    if (action == null) return;
    final terminal = alreadyFinished ? phase : action.finish(phase);
    _flyAction = null;
    _flyActionTimeout?.cancel();
    _flyActionTimeout = null;
    _flyObservationTimer?.cancel();
    _flyObservationTimer = null;
    if (terminal != null) unawaited(_flyClient.record(action.event(terminal), statsScope: _source.statsScope));
  }

  Future<void> _setVolume(double value) async {
    _wakeControls();
    final next = value.clamp(0.0, 100.0).toDouble();
    _updateView(() {
      _volume = next;
      if (next > 0) _lastAudibleVolume = next;
    });
    await _player.setVolume(next);
  }

  Future<void> _toggleMute() async {
    await _setVolume(_volume > 0 ? 0 : _lastAudibleVolume);
  }

  Future<void> _setPlaybackRate(double value) async {
    _wakeControls();
    _updateView(() => _playbackRate = value);
    await _player.setRate(value);
  }

  Future<void> _captureScreenshot() async {
    if (_takingScreenshot || _isLoading) return;
    _wakeControls(scheduleHide: false);
    _takingScreenshot = true;
    try {
      final bytes = await _player.screenshot(
        format: 'image/png',
        includeLibassSubtitles: true,
      );
      if (bytes == null || bytes.isEmpty) {
        _showPlayerMessage(_l10n.playerScreenshotUnavailable);
        return;
      }
      final now = DateTime.now();
      final timestamp = <int>[
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      ].map((value) => value.toString().padLeft(2, '0')).join();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: _l10n.desktopPlaybackScreenshotDialogTitle,
        fileName: 'FlyPlayer_$timestamp.png',
        type: FileType.custom,
        allowedExtensions: const <String>['png'],
        bytes: bytes,
        lockParentWindow: true,
      );
      if (path != null && mounted) {
        _showPlayerMessage(_l10n.playerScreenshotSaved);
      }
    } catch (_) {
      _showPlayerMessage(_l10n.playerScreenshotSaveFailed);
    } finally {
      _takingScreenshot = false;
    }
  }

  void _showPlayerMessage(String message) {
    if (!mounted) return;
    _toastTimer?.cancel();
    _updateView(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _updateView(() => _toastMessage = null);
    });
  }

  Future<void> _toggleAbRepeat() async {
    if (_updatingAbLoop || _isLoading) return;
    if (_player.state.duration <= Duration.zero) {
      _showPlayerMessage(_l10n.playerAbLoopUnavailable);
      return;
    }
    _wakeControls();
    final generation = _sourceChangeGeneration;
    final position = _player.state.position;
    final start = _abLoopStart;
    _updatingAbLoop = true;
    try {
      if (_abLoopEnd != null) {
        // B 点关闭即可停止循环，A 点在下一次设置或打开媒体时覆盖。
        await _setMpvProperty('ab-loop-b', 'no');
        if (!_isCurrentSourceChange(generation)) return;
        _updateView(() {
          _abLoopStart = null;
          _abLoopEnd = null;
        });
        _showPlayerMessage(_l10n.playerAbLoopCleared);
      } else if (start == null) {
        await _setMpvProperty(
          'ab-loop-a',
          (position.inMilliseconds / 1000).toStringAsFixed(3),
        );
        if (!_isCurrentSourceChange(generation)) return;
        _updateView(() => _abLoopStart = position);
        _skipPromptKindNotifier.value = null;
        _showPlayerMessage(
          _l10n.playerAbLoopPointSet(_formatDuration(position)),
        );
      } else if (position <= start) {
        _showPlayerMessage(_l10n.nativePlayerAbEndMustAfterStart);
      } else {
        await _setMpvProperty(
          'ab-loop-b',
          (position.inMilliseconds / 1000).toStringAsFixed(3),
        );
        if (!_isCurrentSourceChange(generation)) return;
        _updateView(() => _abLoopEnd = position);
        _showPlayerMessage(
          _l10n.playerAbLoopSet(
            _formatDuration(start),
            _formatDuration(position),
          ),
        );
      }
    } catch (_) {
      if (_isCurrentSourceChange(generation)) {
        _showPlayerMessage(_l10n.playerAbLoopUnavailable);
      }
    } finally {
      _updatingAbLoop = false;
    }
  }

  void _cycleFit() {
    _wakeControls();
    unawaited(_setAspectRatioMode(_aspectRatioMode == 'fit' ? 'fill' : 'fit'));
  }

  Future<void> _setAutoPlayEnabled(bool value) async {
    if (!value) _cancelAutoNext(suppress: false);
    if (mounted) {
      _updateView(() {
        _autoPlayEnabled = value;
        if (!value) {
          _nextEpisodePreloadEnabled = false;
          _clearPreloadedNext();
        }
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPlayPrefKey, value);
  }

  Future<void> _setNextEpisodePreloadEnabled(bool value) async {
    if (!_autoPlayEnabled && value) return;
    if (mounted) _updateView(() => _nextEpisodePreloadEnabled = value);
    if (!value) {
      _clearPreloadedNext();
    } else {
      unawaited(_preloadNextEpisodeIfEnabled());
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nextEpisodePreloadPrefKey, value);
  }

  Future<void> _setAspectRatioMode(String value) async {
    final normalized =
        const <String>{'fit', 'fill', '4:3', '16:9', '21:9'}.contains(value)
        ? value
        : 'fit';
    if (mounted) {
      _updateView(() {
        _aspectRatioMode = normalized;
        _fit = normalized == 'fill' ? BoxFit.cover : BoxFit.contain;
      });
    }
    await _setMpvProperty(
      'video-aspect-override',
      const <String>{'4:3', '16:9', '21:9'}.contains(normalized)
          ? normalized
          : 'no',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aspectRatioPrefKey, normalized);
  }

  Future<void> _setDecoderMode(String value) async {
    final normalized = value == 'software' ? 'software' : 'hardware';
    if (_decoderMode == normalized) return;
    if (mounted) _updateView(() => _decoderMode = normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_decoderModePrefKey, normalized);
    await _setMpvProperty(
      'hwdec',
      normalized == 'software' ? 'no' : 'auto-safe',
    );
    await _reopenCurrentMedia();
  }

  Future<void> _reopenCurrentMedia() async {
    if (!mounted || _source.url.trim().isEmpty || _isLoading) return;
    final generation = ++_sourceChangeGeneration;
    final position = _player.state.position;
    final wasPlaying = _isPlaying;
    _wakeControls(scheduleHide: false);
    _updateView(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _installSource(
        _source,
        generation,
        play: wasPlaying,
        startPosition: position,
        preserveTracks: true,
      );
    } catch (_) {
      if (_isCurrentSourceChange(generation)) {
        _showGenericError(_l10n.desktopPlaybackErrorStartFailed);
      }
    } finally {
      if (_isCurrentSourceChange(generation)) {
        _finishLoading();
        _scheduleProgressReport();
      }
    }
  }

  Future<List<PlayerBookmarkEntry>> _addBookmark() async {
    final position = _player.state.position;
    if (position <= Duration.zero) return _bookmarks;
    final duration = _player.state.duration;
    final entry = await _bookmarkStore.add(
      itemGuid: _source.itemGuid,
      mediaGuid: _source.mediaGuid,
      mediaType: _source.mediaType,
      ancestorName: _source.ancestorName,
      title: _source.title,
      seriesTitle: _source.seriesTitle,
      seasonNumber: _source.seasonNumber,
      episodeNumber: _source.episodeNumber,
      position: position,
      durationSeconds: duration.inSeconds > 0
          ? duration.inSeconds
          : _source.durationSeconds,
    );
    await _loadBookmarks();
    _showPlayerMessage(
      _l10n.playerBookmarkAdded(_formatDuration(entry.position)),
    );
    return _bookmarks;
  }

  Future<List<PlayerBookmarkEntry>> _deleteBookmark(
    PlayerBookmarkEntry entry,
  ) async {
    await _bookmarkStore.remove(entry.id);
    await _loadBookmarks();
    _showPlayerMessage(_l10n.playerBookmarkDeleted);
    return _bookmarks;
  }

  Future<void> _selectBookmark(PlayerBookmarkEntry entry) async {
    await _seekTo(entry.position);
    _showPlayerMessage(
      _l10n.playerBookmarkJumped(_formatDuration(entry.position)),
    );
  }

  Future<void> _showTracks({required bool audio, Rect? anchor}) async {
    _wakeControls(scheduleHide: false);
    if (!audio) await _refreshMenuSubtitleTrack();
    if (!mounted) return;
    final usesServerReload =
        _source.serverPlaybackManaged && widget.reloadSource != null;
    if (usesServerReload) {
      final options = <DesktopPlayerPanelOption>[
        if (audio)
          for (final track in _source.audioTracks)
            DesktopPlayerPanelOption(
              value: track.guid,
              title: _sourceTrackTitle(
                track.displayLabel,
                track.detailLabel,
                track.index,
              ),
              subtitle: track.detailLabel,
              selected: track.guid == _source.audioTrackGuid,
            )
        else
          for (final track in _source.subtitleTracks)
            DesktopPlayerPanelOption(
              value: track.guid,
              title: _sourceTrackTitle(
                track.displayLabel,
                track.detailLabel,
                track.index,
              ),
              subtitle: track.detailLabel,
              selected: track.guid == _source.subtitleTrackGuid,
            ),
      ];
      if (!mounted) return;
      if (anchor != null) {
        await _showCompactOptions(
          anchor: anchor,
          title: audio
              ? _l10n.nativePlayerAudioTrackPickerTitle
              : _l10n.nativePlayerSubtitleTrackPickerTitle,
          options: options,
          onSelected: (option) {
            final id = option.value.toString();
            unawaited(
              audio
                  ? _reloadPlaybackSource(audioTrackId: id)
                  : _reloadPlaybackSource(subtitleTrackId: id),
            );
          },
          onOff: audio
              ? null
              : () => unawaited(_reloadPlaybackSource(subtitleDisabled: true)),
        );
        return;
      }
      await _showSidePanel(
        (context) => DesktopTrackPanel(
          title: audio
              ? _l10n.nativePlayerAudioTrackPickerTitle
              : _l10n.nativePlayerSubtitleTrackPickerTitle,
          emptyLabel: audio
              ? _l10n.desktopPlaybackNoAudioTracks
              : _l10n.desktopPlaybackNoSubtitleTracks,
          offLabel: _l10n.nativePlayerTrackOff,
          options: options,
          onOff: audio
              ? null
              : () {
                  Navigator.of(context).pop();
                  unawaited(_reloadPlaybackSource(subtitleDisabled: true));
                },
          onSelected: (option) {
            Navigator.of(context).pop();
            final id = option.value.toString();
            unawaited(
              audio
                  ? _reloadPlaybackSource(audioTrackId: id)
                  : _reloadPlaybackSource(subtitleTrackId: id),
            );
          },
        ),
      );
      return;
    }

    final audioTracks = DesktopMpvRuntime.selectableAudioTracks(
      _player.state.tracks.audio,
    );
    final selectedAudioTrack = DesktopMpvRuntime.selectedAudioTrack(
      audioTracks,
      _player.state.track.audio,
    );
    final subtitleTracks = DesktopMpvRuntime.selectableSubtitleTracks(
      _player.state.tracks.subtitle,
    );
    final selectedSubtitleTrack = DesktopMpvRuntime.selectedSubtitleTrack(
      subtitleTracks,
      _menuSubtitleTrack ?? _player.state.track.subtitle,
    );
    final options = <DesktopPlayerPanelOption>[
      if (audio)
        for (var index = 0; index < audioTracks.length; index++)
          DesktopPlayerPanelOption(
            value: audioTracks[index],
            title: _mediaKitAudioTrackTitle(audioTracks[index], index),
            selected: audioTracks[index] == selectedAudioTrack,
          )
      else
        for (var index = 0; index < subtitleTracks.length; index++)
          DesktopPlayerPanelOption(
            value: subtitleTracks[index],
            title: _mediaKitSubtitleTrackTitle(subtitleTracks[index], index),
            selected: subtitleTracks[index] == selectedSubtitleTrack,
          ),
      if (!audio) ..._localSubtitleOptions(),
    ];
    if (!mounted) return;
    if (anchor != null) {
      await _showCompactOptions(
        anchor: anchor,
        title: audio
            ? _l10n.nativePlayerAudioTrackPickerTitle
            : _l10n.nativePlayerSubtitleTrackPickerTitle,
        options: options,
        onSelected: (option) async {
          try {
            final track = option.value;
            if (audio) {
              await _selectLocalAudioTrack(track as AudioTrack);
            } else {
              await _player.setSubtitleTrack(track as SubtitleTrack);
            }
          } catch (_) {
            _showGenericError(_l10n.desktopPlaybackErrorTrackSwitchFailed);
          }
        },
        onOff: audio
            ? null
            : () async => _player.setSubtitleTrack(SubtitleTrack.no()),
      );
      return;
    }
    await _showSidePanel(
      (context) => DesktopTrackPanel(
        title: audio
            ? _l10n.nativePlayerAudioTrackPickerTitle
            : _l10n.nativePlayerSubtitleTrackPickerTitle,
        emptyLabel: audio
            ? _l10n.desktopPlaybackNoAudioTracks
            : _l10n.desktopPlaybackNoSubtitleTracks,
        offLabel: _l10n.nativePlayerTrackOff,
        options: options,
        onOff: audio
            ? null
            : () async {
                await _player.setSubtitleTrack(SubtitleTrack.no());
                if (context.mounted) Navigator.of(context).pop();
              },
        onSelected: (option) async {
          try {
            final track = option.value;
            if (audio) {
              await _selectLocalAudioTrack(track as AudioTrack);
            } else {
              await _player.setSubtitleTrack(track as SubtitleTrack);
            }
          } catch (_) {
            _showGenericError(_l10n.desktopPlaybackErrorTrackSwitchFailed);
          }
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  void _openHoverOverlay(
    PlayerHoverOverlayKind kind,
    Rect anchor, {
    bool immediate = false,
  }) {
    _hoverCloseTimer?.cancel();
    _hoverClearTimer?.cancel();
    _hoverOpenTimer?.cancel();
    final delay = immediate || _hoverOverlayKind != null
        ? Duration.zero
        : const Duration(milliseconds: 80);
    _hoverOpenTimer = Timer(delay, () {
      if (!mounted) return;
      _wakeControls(scheduleHide: false);
      _hoverOverlayNotifier.value = PlayerHoverOverlaySnapshot(
        kind: kind,
        visible: true,
        anchor: anchor,
      );
      if (kind == PlayerHoverOverlayKind.subtitle) {
        unawaited(_refreshMenuSubtitleTrack(_hoverOverlayNotifier.value));
      }
    });
  }

  Future<void> _refreshMenuSubtitleTrack([
    PlayerHoverOverlaySnapshot? snapshot,
  ]) async {
    _menuSubtitleTrack = null;
    final platform = _player.platform;
    if (_source.serverPlaybackManaged || platform is! NativePlayer) return;
    final generation = _sourceChangeGeneration;
    try {
      // 外挂字幕的应用状态保存 URI，内核轨道列表使用数字 ID；以实际 sid 为准。
      final id = (await platform.getProperty('sid')).trim();
      if (!_isCurrentSourceChange(generation) ||
          (snapshot != null &&
              !identical(snapshot, _hoverOverlayNotifier.value))) {
        return;
      }
      if (id.isNotEmpty) _menuSubtitleTrack = SubtitleTrack(id, null, null);
      if (snapshot != null) {
        _hoverOverlayNotifier.value = snapshot.copyWith();
      }
    } catch (_) {
      // 内核尚未就绪时沿用 media_kit 已知的选轨状态。
    }
  }

  void _scheduleHoverOverlayClose() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = Timer(const Duration(milliseconds: 210), () {
      if (!mounted || _hoverOverlayKind == null) return;
      _hoverOverlayNotifier.value = _hoverOverlayNotifier.value.copyWith(
        visible: false,
      );
      _hoverClearTimer?.cancel();
      _hoverClearTimer = Timer(const Duration(milliseconds: 190), () {
        if (!mounted || _hoverOverlayVisible) return;
        _hoverOverlayNotifier.value = const PlayerHoverOverlaySnapshot();
        _wakeControls();
      });
    });
  }

  void _keepHoverOverlayOpen() {
    _hoverCloseTimer?.cancel();
    _hoverClearTimer?.cancel();
    final value = _hoverOverlayNotifier.value;
    if (mounted && value.kind != null && !value.visible) {
      _hoverOverlayNotifier.value = value.copyWith(visible: true);
    }
    _wakeControls(scheduleHide: false);
  }

  void _dismissHoverOverlay() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _hoverClearTimer?.cancel();
    final closingKind = _hoverOverlayKind;
    if (!mounted || closingKind == null) return;
    _hoverOverlayNotifier.value = _hoverOverlayNotifier.value.copyWith(
      visible: false,
    );
    _hoverClearTimer = Timer(const Duration(milliseconds: 190), () {
      if (!mounted ||
          _hoverOverlayVisible ||
          _hoverOverlayKind != closingKind) {
        return;
      }
      _hoverOverlayNotifier.value = const PlayerHoverOverlaySnapshot();
      _wakeControls();
    });
  }

  /// 音轨弹层「调节」等入口：不另开弹窗，把当前悬停弹层原位放大成设置卡。
  void _expandHoverOverlayToSettings(DesktopPlaybackSettingsPage initialPage) {
    _hoverCloseTimer?.cancel();
    _hoverClearTimer?.cancel();
    _hoverOpenTimer?.cancel();
    final current = _hoverOverlayNotifier.value;
    _hoverOverlayNotifier.value = PlayerHoverOverlaySnapshot(
      kind: PlayerHoverOverlayKind.settings,
      visible: true,
      anchor: current.anchor,
      initialPage: initialPage,
    );
    _wakeControls(scheduleHide: false);
  }

  List<DesktopPlayerPanelOption> _hoverTrackOptions(bool audio) {
    if (_source.serverPlaybackManaged && widget.reloadSource != null) {
      return <DesktopPlayerPanelOption>[
        if (audio)
          for (final track in _source.audioTracks)
            DesktopPlayerPanelOption(
              value: track.guid,
              title: _sourceTrackTitle(
                track.displayLabel,
                track.detailLabel,
                track.index,
              ),
              subtitle: track.detailLabel,
              selected: track.guid == _source.audioTrackGuid,
            )
        else
          for (final track in _source.subtitleTracks)
            DesktopPlayerPanelOption(
              value: track.guid,
              title: _sourceTrackTitle(
                track.displayLabel,
                track.detailLabel,
                track.index,
              ),
              subtitle: track.detailLabel,
              selected: track.guid == _source.subtitleTrackGuid,
            ),
      ];
    }
    if (audio) {
      final tracks = DesktopMpvRuntime.selectableAudioTracks(
        _player.state.tracks.audio,
      );
      final selectedTrack = DesktopMpvRuntime.selectedAudioTrack(
        tracks,
        _player.state.track.audio,
      );
      return <DesktopPlayerPanelOption>[
        for (var index = 0; index < tracks.length; index++)
          DesktopPlayerPanelOption(
            value: tracks[index],
            title: _mediaKitAudioTrackTitle(tracks[index], index),
            selected: tracks[index] == selectedTrack,
          ),
      ];
    }
    final tracks = DesktopMpvRuntime.selectableSubtitleTracks(
      _player.state.tracks.subtitle,
    );
    final selectedTrack = DesktopMpvRuntime.selectedSubtitleTrack(
      tracks,
      _menuSubtitleTrack ?? _player.state.track.subtitle,
    );
    return <DesktopPlayerPanelOption>[
      for (var index = 0; index < tracks.length; index++)
        DesktopPlayerPanelOption(
          value: tracks[index],
          title: _mediaKitSubtitleTrackTitle(tracks[index], index),
          selected: tracks[index] == selectedTrack,
        ),
      ..._localSubtitleOptions(),
    ];
  }

  Future<void> _selectHoverTrack(
    bool audio,
    DesktopPlayerPanelOption option,
  ) async {
    _dismissHoverOverlay();
    if (_source.serverPlaybackManaged && widget.reloadSource != null) {
      final id = option.value.toString();
      await (audio
          ? _reloadPlaybackSource(audioTrackId: id)
          : _reloadPlaybackSource(subtitleTrackId: id));
      return;
    }
    try {
      if (audio) {
        await _selectLocalAudioTrack(option.value as AudioTrack);
      } else {
        await _player.setSubtitleTrack(option.value as SubtitleTrack);
      }
    } catch (_) {
      _showGenericError(_l10n.desktopPlaybackErrorTrackSwitchFailed);
    }
  }

  Future<void> _selectLocalAudioTrack(AudioTrack track) async {
    final source = _source;
    await _player.setAudioTrack(track);
    int? streamIndex;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        streamIndex = int.tryParse(
          await platform.getProperty('current-tracks/audio/ff-index'),
        );
      } catch (_) {
        // 切轨已经成功；无法识别原文件索引时不再上报旧 GUID。
      }
    }
    if (!mounted ||
        _isLoading ||
        source.loadNonce != _source.loadNonce ||
        source.url != _source.url) {
      return;
    }
    _updateView(() {
      _source = DesktopMpvRuntime.sourceWithAudioStream(_source, streamIndex);
    });
    _reportProgress();
  }

  Future<void> _disableHoverSubtitle() async {
    _dismissHoverOverlay();
    if (_source.serverPlaybackManaged && widget.reloadSource != null) {
      await _reloadPlaybackSource(subtitleDisabled: true);
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  Widget _buildHoverOverlayLayer() {
    return PlayerHoverOverlayLayer(
      snapshot: _hoverOverlayNotifier,
      contentBuilder: _buildHoverOverlayContent,
      onPanelEnter: _keepHoverOverlayOpen,
      onPanelExit: _scheduleHoverOverlayClose,
    );
  }

  PlayerHoverOverlayContent? _buildHoverOverlayContent(
    PlayerHoverOverlayKind kind,
    Size size,
    PlayerHoverOverlaySnapshot snapshot,
  ) {
    late final Widget content;
    late final double width;

    switch (kind) {
      case PlayerHoverOverlayKind.speed:
        width = 164;
        content = DesktopHoverOptionsPanel(
          title: _l10n.playerDiagnosticsSpeed,
          options: <DesktopPlayerPanelOption>[
            for (final rate in const <double>[0.5, 0.75, 1, 1.25, 1.5, 2])
              DesktopPlayerPanelOption(
                value: rate,
                title: '${_formatPlaybackRate(rate)}x',
                selected: (_playbackRate - rate).abs() < 0.001,
              ),
          ],
          emptyLabel: '',
          onSelected: (option) {
            _dismissHoverOverlay();
            unawaited(_setPlaybackRate(option.value as double));
          },
        );
        break;
      case PlayerHoverOverlayKind.quality:
        width = 420;
        content = DesktopHoverQualityPanel(
          source: _source,
          onSelected: (index) {
            _dismissHoverOverlay();
            unawaited(_reloadPlaybackSource(qualityIndex: index));
          },
        );
        break;
      case PlayerHoverOverlayKind.subtitle:
        width = 254;
        content = DesktopHoverOptionsPanel(
          title: _l10n.nativePlayerSubtitleTrackPickerTitle,
          options: _hoverTrackOptions(false),
          emptyLabel: _l10n.desktopPlaybackNoSubtitleTracks,
          offLabel: _l10n.nativePlayerTrackOff,
          offSelected: _source.serverPlaybackManaged
              ? (_source.subtitleTrackGuid?.isEmpty ?? true)
              : (_menuSubtitleTrack ?? _player.state.track.subtitle).id == 'no',
          actions: <DesktopPanelHeaderAction>[
            DesktopPanelHeaderAction(
              label: '样式',
              onTap: () => _expandHoverOverlayToSettings(
                DesktopPlaybackSettingsPage.subtitleStyle,
              ),
            ),
            DesktopPanelHeaderAction(
              label: '导入',
              onTap: () => unawaited(_importLocalSubtitle()),
            ),
          ],
          onOff: () => unawaited(_disableHoverSubtitle()),
          onSelected: (option) => unawaited(_selectHoverTrack(false, option)),
        );
        break;
      case PlayerHoverOverlayKind.audio:
        width = 254;
        content = DesktopHoverOptionsPanel(
          title: _l10n.nativePlayerAudioTrackPickerTitle,
          options: _hoverTrackOptions(true),
          emptyLabel: _l10n.desktopPlaybackNoAudioTracks,
          actions: <DesktopPanelHeaderAction>[
            DesktopPanelHeaderAction(
              label: '调节',
              onTap: () => _expandHoverOverlayToSettings(
                DesktopPlaybackSettingsPage.audioAdjust,
              ),
            ),
          ],
          onSelected: (option) => unawaited(_selectHoverTrack(true, option)),
        );
        break;
      case PlayerHoverOverlayKind.episodes:
        width = (size.width * 0.30).clamp(360.0, 430.0).toDouble();
        content = DesktopEpisodePanel(
          title: _source.seriesTitle.trim().isNotEmpty
              ? '${_source.seriesTitle.trim()} · ${_l10n.playerEpisodeAction}'
              : _l10n.nativePlayerEpisodePickerTitle,
          emptyLabel: _l10n.desktopPlaybackEpisodesEmpty,
          episodes: _episodes,
          currentItemGuid: _source.itemGuid,
          currentSeasonGuid: _source.seasonGuid,
          loadSeasons: widget.loadSeasons,
          loadSeasonEpisodes: widget.loadSeasonEpisodes,
          seriesTitle: _subtitle,
          onSelected: widget.resolveEpisode == null
              ? null
              : (episode) {
                  _dismissHoverOverlay();
                  unawaited(_openEpisode(episode));
                },
        );
        break;
      case PlayerHoverOverlayKind.previousEpisode:
      case PlayerHoverOverlayKind.nextEpisode:
        width = 224;
        final isNext = kind == PlayerHoverOverlayKind.nextEpisode;
        final episode = isNext ? _nextEpisode : _previousEpisode;
        // 悬停入口与按钮同源：无上一集/下一集（首集/末集）时不该走到这里，兜底空内容。
        if (episode == null) {
          content = const SizedBox.shrink();
        } else {
          content = _hoverEpisodePreviewCard(
            episode,
            label: isNext
                ? _l10n.nativePlayerText0062
                : _l10n.desktopPlaybackPrevEpisodeLabel,
          );
        }
        break;
      case PlayerHoverOverlayKind.settings:
        width = (size.width * 0.42).clamp(420.0, 560.0).toDouble();
        content = DesktopPlaybackSettingsPanel(
          key: ValueKey<DesktopPlaybackSettingsPage?>(snapshot.initialPage),
          initialPage: snapshot.initialPage ?? DesktopPlaybackSettingsPage.main,
          source: _source,
          position: _player.state.position,
          duration: _player.state.duration,
          autoPlayEnabled: _autoPlayEnabled,
          nextEpisodePreloadEnabled: _nextEpisodePreloadEnabled,
          aspectRatioMode: _aspectRatioMode,
          decoderMode: _decoderMode,
          mpvSettings: _mpvSettings,
          videoAdjustments: _videoAdjustments,
          audioDelaySeconds: _audioDelaySeconds,
          bookmarks: _bookmarks,
          danmakuEnabled: _danmakuSettings.enabled,
          danmakuSourceLabel: _danmakuSourceLabel,
          danmakuCommentCount: _danmakuComments.length,
          onAutoPlayChanged: _setAutoPlayEnabled,
          onNextEpisodePreloadChanged: _setNextEpisodePreloadEnabled,
          onAspectRatioChanged: _setAspectRatioMode,
          onDecoderChanged: _setDecoderMode,
          onMpvAdvancedChanged: _setMpvAdvancedSetting,
          onVideoAdjustmentChanged: _setVideoAdjustment,
          onAudioDelayChanged: _setAudioDelay,
          onLoadSavedPresets: _loadSavedPresets,
          onApplySavedPreset: _applySavedMpvPreset,
          chapters: _chapters,
          introOutroEnabled: _introOutroEnabled,
          introMaxMinutes: _introMaxMinutes,
          outroMaxMinutes: _outroMaxMinutes,
          fixedDurationSkipEnabled: _fixedDurationSkipEnabled,
          hasNextEpisode: _nextEpisode != null,
          subtitleDelaySeconds: _subtitleDelaySeconds,
          subtitlePosition: _subtitlePosition,
          subtitleScale: _subtitleScale,
          onIntroOutroChanged: _setIntroOutroSettings,
          onSubtitleStyleChanged: _setSubtitleStyleSettings,
          onSelectChapter: _selectChapter,
          onAddBookmark: _addBookmark,
          onDeleteBookmark: _deleteBookmark,
          onSelectBookmark: (entry) async {
            _dismissHoverOverlay();
            await _selectBookmark(entry);
          },
          danmakuSettingsPageBuilder: _buildDanmakuSettingsPage,
          danmakuSourcesPageBuilder: _buildDanmakuSourcesPage,
        );
        break;
    }
    return PlayerHoverOverlayContent(child: content, width: width);
  }

  String _formatPlaybackRate(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  String _sourceTrackTitle(String display, String detail, int index) {
    final normalizedDisplay = display.trim();
    if (normalizedDisplay.isNotEmpty) return normalizedDisplay;
    final normalizedDetail = detail.trim();
    if (normalizedDetail.isNotEmpty) return normalizedDetail;
    return '${_l10n.nativePlayerTrackGeneric} ${index + 1}';
  }

  String _mediaKitAudioTrackTitle(AudioTrack track, int index) {
    return DesktopMpvRuntime.audioTrackTitle(
      track,
      '${_l10n.nativePlayerTrackGeneric} ${index + 1}',
    );
  }

  String _mediaKitSubtitleTrackTitle(SubtitleTrack track, int index) {
    return DesktopMpvRuntime.subtitleTrackTitle(
      track,
      '${_l10n.nativePlayerTrackGeneric} ${index + 1}',
    );
  }

  Future<void> _showCompactOptions({
    required Rect anchor,
    required String title,
    required List<DesktopPlayerPanelOption> options,
    required FutureOr<void> Function(DesktopPlayerPanelOption option)
    onSelected,
    FutureOr<void> Function()? onOff,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final items = <PopupMenuEntry<void>>[
      PopupMenuItem<void>(
        enabled: false,
        height: 28,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ),
      if (onOff != null)
        _compactOptionItem(
          label: _l10n.nativePlayerTrackOff,
          selected: false,
          onTap: onOff,
        ),
      if (onOff != null)
        const PopupMenuDivider(height: 8, indent: 8, endIndent: 8),
      if (options.isEmpty)
        const PopupMenuItem<void>(
          enabled: false,
          height: 38,
          child: Text(
            '暂无可用选项',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        )
      else
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          height: (options.length * 40.0).clamp(40.0, 280.0),
          child: SizedBox(
            width: 218,
            height: (options.length * 40.0).clamp(40.0, 280.0),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: const Color(0x38FFFFFF),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(Future<void>.sync(() => onSelected(option)));
                  },
                  child: SizedBox(
                    height: 38,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            option.selected
                                ? Icons.check_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 15,
                            color: option.selected
                                ? const Color(0xFF9CC4FF)
                                : Colors.white24,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              option.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: option.selected
                                    ? const Color(0xFFB8D3FF)
                                    : Colors.white.withValues(alpha: 0.88),
                                fontSize: 12.5,
                                fontWeight: option.selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    ];
    await showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
      color: const Color(0x990B111C),
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.all(6),
      elevation: 18,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: Color(0x24FFFFFF)),
      ),
      items: items,
    );
  }

  PopupMenuItem<void> _compactOptionItem({
    required String label,
    required bool selected,
    required FutureOr<void> Function() onTap,
  }) => PopupMenuItem<void>(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      hoverColor: const Color(0x38FFFFFF),
      onTap: () {
        Navigator.of(context).pop();
        unawaited(Future<void>.sync(onTap));
      },
      child: Row(
        children: <Widget>[
          const Icon(Icons.block_rounded, size: 15, color: Colors.white54),
          const SizedBox(width: 9),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ],
      ),
    ),
  );

  List<DesktopPlayerPanelOption> _localSubtitleOptions() {
    final currentId = (_menuSubtitleTrack ?? _player.state.track.subtitle).id;
    final existingIds = _player.state.tracks.subtitle
        .map((track) => track.id)
        .toSet();
    final options = <DesktopPlayerPanelOption>[];
    for (final entry in _source.localSubtitleFiles.entries) {
      final path = entry.value.trim();
      if (path.isEmpty) continue;
      final uri = _subtitleUri(path);
      if (existingIds.contains(uri)) continue;
      String title = '';
      String language = '';
      for (final track in _source.subtitleTracks) {
        if (track.guid != entry.key) continue;
        title = track.title.trim();
        language = track.displayLabel.trim();
        break;
      }
      final subtitle = SubtitleTrack.uri(
        uri,
        title: title.isEmpty ? null : title,
        language: language.isEmpty ? null : language,
      );
      options.add(
        DesktopPlayerPanelOption(
          value: subtitle,
          title: DesktopMpvRuntime.subtitleTrackTitle(
            subtitle,
            _l10n.nativePlayerTrackGeneric,
          ),
          subtitle: language,
          selected: currentId == uri,
        ),
      );
    }
    return options;
  }

  Future<void> _showQualities({Rect? anchor}) async {
    _wakeControls(scheduleHide: false);
    if (_source.qualities.isEmpty || widget.reloadSource == null || !mounted) {
      return;
    }
    final menu = DesktopMpvRuntime.qualityMenu(_source);
    final options = <DesktopPlayerPanelOption>[
      for (final choice in menu.mainChoices)
        DesktopPlayerPanelOption(
          value: choice.sourceIndex,
          title: choice.isOriginal
              ? _l10n.playerQualityOriginal
              : choice.displayTier,
          subtitle: DesktopMpvRuntime.qualityBitrateLabel(
            choice.quality.bitrate,
          ),
          selected: DesktopMpvRuntime.isCurrentQuality(_source, choice),
        ),
    ];
    if (anchor != null) {
      await _showCompactOptions(
        anchor: anchor,
        title: _l10n.nativePlayerQualityPickerTitle,
        options: options,
        onSelected: (option) =>
            unawaited(_reloadPlaybackSource(qualityIndex: option.value as int)),
      );
      return;
    }
    await _showSidePanel(
      (context) => DesktopTrackPanel(
        title: _l10n.nativePlayerQualityPickerTitle,
        emptyLabel: _l10n.nativePlayerNoQuality,
        offLabel: _l10n.nativePlayerTrackOff,
        options: options,
        onSelected: (option) {
          Navigator.of(context).pop();
          unawaited(_reloadPlaybackSource(qualityIndex: option.value as int));
        },
      ),
    );
  }

  Future<void> _showEpisodes() async {
    _wakeControls(scheduleHide: false);
    final episodes = _episodes;
    if (!mounted) return;
    await showPlayerOverlayPanel(
      context,
      style: PlayerOverlayPanelStyle.floatCard,
      barrierLabel: _l10n.commonClose,
      builder: (context) => DesktopEpisodePanel(
        title: _source.seriesTitle.trim().isNotEmpty
            ? '${_source.seriesTitle.trim()} · ${_l10n.playerEpisodeAction}'
            : _l10n.nativePlayerEpisodePickerTitle,
        emptyLabel: _l10n.desktopPlaybackEpisodesEmpty,
        episodes: episodes,
        currentItemGuid: _source.itemGuid,
        currentSeasonGuid: _source.seasonGuid,
        loadSeasons: widget.loadSeasons,
        loadSeasonEpisodes: widget.loadSeasonEpisodes,
        seriesTitle: _subtitle,
        onSelected: widget.resolveEpisode == null
            ? null
            : (episode) {
                Navigator.of(context).pop();
                unawaited(_openEpisode(episode));
              },
      ),
    );
  }

  Map<String, dynamic>? get _nextEpisode {
    final episodes = _episodes;
    if (episodes.isEmpty) return null;
    final currentGuid = _source.itemGuid.trim();
    var index = episodes.indexWhere(
      (episode) =>
          '${episode['itemGuid'] ?? episode['guid'] ?? ''}'.trim() ==
          currentGuid,
    );
    if (index < 0 && _source.episodeNumber > 0) {
      index = episodes.indexWhere(
        (episode) =>
            (int.tryParse('${episode['episodeNumber'] ?? ''}') ?? -1) ==
            _source.episodeNumber,
      );
    }
    if (index < 0 || index + 1 >= episodes.length) return null;
    return episodes[index + 1];
  }

  /// 上/下一集悬停预览卡。
  Widget _hoverEpisodePreviewCard(
    Map<String, dynamic> episode, {
    required String label,
  }) {
    return DesktopHoverEpisodePreviewPanel(
      label: label,
      title: _episodePreviewTitle(episode),
      posterPath: '${episode['poster'] ?? episode['posterPath'] ?? ''}'.trim(),
      headers:
          (episode['imageHeaders'] as Map?)?.map(
            (key, value) => MapEntry('$key', '$value'),
          ) ??
          const <String, String>{},
    );
  }

  /// 预览卡标题：与选集面板卡片同构（「第N集 · 标题」，缺号时只显示标题）。
  String _episodePreviewTitle(Map<String, dynamic> episode) {
    final shortLabel = '${episode['shortLabel'] ?? ''}'.trim();
    final number = '${episode['episodeNumber'] ?? ''}'.trim();
    final numberLabel = shortLabel.isNotEmpty ? shortLabel : number;
    final rawTitle = '${episode['title'] ?? ''}'.trim();
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (numberLabel.isNotEmpty ? '第$numberLabel集' : '');
    if (title.isEmpty) return '—';
    return numberLabel.isNotEmpty ? '第$numberLabel集 · $title' : title;
  }

  /// 上一集（与 [_nextEpisode] 同一定位规则，向前找一集）。
  Map<String, dynamic>? get _previousEpisode {
    final episodes = _episodes;
    if (episodes.isEmpty) return null;
    final currentGuid = _source.itemGuid.trim();
    var index = episodes.indexWhere(
      (episode) =>
          '${episode['itemGuid'] ?? episode['guid'] ?? ''}'.trim() ==
          currentGuid,
    );
    if (index < 0 && _source.episodeNumber > 0) {
      index = episodes.indexWhere(
        (episode) =>
            (int.tryParse('${episode['episodeNumber'] ?? ''}') ?? -1) ==
            _source.episodeNumber,
      );
    }
    if (index <= 0) return null;
    return episodes[index - 1];
  }

  void _clearPreloadedNext({MpvMediaSource? replacement}) {
    _preloadGeneration++;
    _preloadingItemGuid = '';
    final preloaded = _preloadedNextSource;
    _preloadedNextSource = null;
    _preloadedNextItemGuid = '';
    if (preloaded != null) {
      _releaseSource(preloaded.source, replacement: replacement ?? _source);
    }
  }

  Future<void> _preloadNextEpisodeIfEnabled() async {
    final resolver = widget.resolveEpisode;
    final episode = _nextEpisode;
    if (!mounted ||
        !_autoPlayEnabled ||
        !_nextEpisodePreloadEnabled ||
        resolver == null ||
        episode == null) {
      return;
    }
    final itemGuid = '${episode['itemGuid'] ?? episode['guid'] ?? ''}'.trim();
    if (itemGuid.isEmpty ||
        itemGuid == _preloadingItemGuid ||
        (itemGuid == _preloadedNextItemGuid && _preloadedNextSource != null)) {
      return;
    }
    _clearPreloadedNext();
    final generation = _preloadGeneration;
    final currentItemGuid = _source.itemGuid;
    _preloadingItemGuid = itemGuid;
    try {
      final resolved = await resolver(episode);
      if (resolved == null) return;
      if (!mounted ||
          generation != _preloadGeneration ||
          currentItemGuid != _source.itemGuid ||
          !_nextEpisodePreloadEnabled ||
          resolved.source.url.trim().isEmpty) {
        _releaseSource(resolved.source, replacement: _source);
        return;
      }
      _preloadedNextItemGuid = itemGuid;
      _preloadedNextSource = resolved;
    } catch (_) {
      // 预加载只是加速；失败后真正切集仍可重新解析。
      debugPrint('[desktop-playback] 下一集预加载失败');
    } finally {
      if (generation == _preloadGeneration) _preloadingItemGuid = '';
    }
  }

  Future<void> _showNextEpisode() async {
    final episode = _nextEpisode;
    if (episode == null) return;
    await _openEpisode(episode);
  }

  Future<void> _showPreviousEpisode() async {
    final episode = _previousEpisode;
    if (episode == null) return;
    await _openEpisode(episode);
  }

  Widget _buildDanmakuSettingsPage(VoidCallback _) =>
      DesktopDanmakuSettingsPanel(
        settings: _danmakuSettings,
        onChanged: _updateDanmakuSettings,
        embedded: true,
      );

  Widget _buildDanmakuSourcesPage(VoidCallback onApplied) =>
      DesktopDanmakuSourcePanel(
        key: ValueKey(
          'nas:${_source.statsScope}:${_source.itemGuid}:${_source.mediaGuid}',
        ),
        currentSourceLabel: _danmakuSourceLabel,
        commentCount: _danmakuComments.length,
        loading: _danmakuLoading,
        initialKeyword: _source.seriesTitle.trim().isNotEmpty
            ? _source.seriesTitle
            : _source.title,
        currentTmdbId: _source.tmdbId,
        nasScopeLabel: _nasScopeLabel,
        nasStatus: _nasDanmakuStatus,
        onReloadNas: _reloadNasDanmaku,
        onLoadSavedSources: _loadSavedDanmakuSources,
        onSearch: _searchDanmakuSources,
        onSelectSavedSource: _selectSavedDanmakuSource,
        onSelectSearchResult: _selectDanmakuSearchResult,
        onDeleteSavedSource: _deleteSavedDanmakuSource,
        onImportFile: _importDanmakuFile,
        embedded: true,
        onApplied: onApplied,
      );

  Future<void> _showPlaybackSettingsPanel({
    DesktopPlaybackSettingsPage initialPage = DesktopPlaybackSettingsPage.main,
  }) async {
    _wakeControls(scheduleHide: false);
    if (!mounted) return;
    // 设置是独立弹窗：居中悬浮、不依附窗口边缘，关闭后焦点回到播放层。
    await showPlayerOverlayPanel(
      context,
      style: PlayerOverlayPanelStyle.centeredDialog,
      barrierLabel: _l10n.commonClose,
      closeTooltip: _l10n.commonClose,
      builder: (context) => ValueListenableBuilder<int>(
        valueListenable: _viewRevision,
        builder: (context, _, __) => DesktopPlaybackSettingsPanel(
          reserveCloseButtonSpace: true,
          source: _source,
          position: _player.state.position,
          duration: _player.state.duration,
          autoPlayEnabled: _autoPlayEnabled,
          nextEpisodePreloadEnabled: _nextEpisodePreloadEnabled,
          aspectRatioMode: _aspectRatioMode,
          decoderMode: _decoderMode,
          mpvSettings: _mpvSettings,
          videoAdjustments: _videoAdjustments,
          audioDelaySeconds: _audioDelaySeconds,
          bookmarks: _bookmarks,
          danmakuEnabled: _danmakuSettings.enabled,
          danmakuSourceLabel: _danmakuSourceLabel,
          danmakuCommentCount: _danmakuComments.length,
          initialPage: initialPage,
          onAutoPlayChanged: _setAutoPlayEnabled,
          onNextEpisodePreloadChanged: _setNextEpisodePreloadEnabled,
          onAspectRatioChanged: _setAspectRatioMode,
          onDecoderChanged: _setDecoderMode,
          onMpvAdvancedChanged: _setMpvAdvancedSetting,
          onVideoAdjustmentChanged: _setVideoAdjustment,
          onAudioDelayChanged: _setAudioDelay,
          onLoadSavedPresets: _loadSavedPresets,
          onApplySavedPreset: _applySavedMpvPreset,
          chapters: _chapters,
          introOutroEnabled: _introOutroEnabled,
          introMaxMinutes: _introMaxMinutes,
          outroMaxMinutes: _outroMaxMinutes,
          fixedDurationSkipEnabled: _fixedDurationSkipEnabled,
          hasNextEpisode: _nextEpisode != null,
          subtitleDelaySeconds: _subtitleDelaySeconds,
          subtitlePosition: _subtitlePosition,
          subtitleScale: _subtitleScale,
          onIntroOutroChanged: _setIntroOutroSettings,
          onSubtitleStyleChanged: _setSubtitleStyleSettings,
          onSelectChapter: _selectChapter,
          onAddBookmark: _addBookmark,
          onDeleteBookmark: _deleteBookmark,
          onSelectBookmark: (entry) async {
            Navigator.of(context).pop();
            await _selectBookmark(entry);
          },
          danmakuSettingsPageBuilder: _buildDanmakuSettingsPage,
          danmakuSourcesPageBuilder: _buildDanmakuSourcesPage,
        ),
      ),
    );
  }

  Future<void> _showSidePanel(WidgetBuilder builder) {
    return showPlayerOverlayPanel(
      context,
      style: PlayerOverlayPanelStyle.sideDrawer,
      barrierLabel: _l10n.commonClose,
      closeTooltip: _l10n.commonClose,
      builder: builder,
    );
  }

  Future<void> _showContextMenu(Offset position, VideoState videoState) async {
    _wakeControls(scheduleHide: false);
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final localPosition = overlay.globalToLocal(position);
    final contextAnchor = position & Size.zero;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: const Color(0x990D1624),
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.all(6),
      elevation: 18,
      constraints: const BoxConstraints(minWidth: 186, maxWidth: 230),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: Color(0x24FFFFFF)),
      ),
      items: <PopupMenuEntry<String>>[
        if (_flyClient.sourceRef(statsScope: _source.statsScope, itemGuid: _source.itemGuid, mediaGuid: _source.mediaGuid) != null)
          _contextMenuItem('assistant', Icons.auto_awesome_outlined, '资料助手 · 当前节目'),
        _contextMenuItem(
          'toggle',
          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          _isPlaying
              ? _l10n.desktopPlaybackPauseTooltip
              : _l10n.desktopPlaybackPlayTooltip,
        ),
        const PopupMenuDivider(height: 8, indent: 8, endIndent: 8),
        if (_source.qualities.isNotEmpty && widget.reloadSource != null)
          _contextMenuItem(
            'quality',
            Icons.hd_rounded,
            _l10n.nativePlayerQualityPickerTitle,
          ),
        _contextMenuItem(
          'audio',
          Icons.audiotrack_rounded,
          _l10n.nativePlayerAudioTrackPickerTitle,
        ),
        _contextMenuItem(
          'subtitle',
          Icons.subtitles_rounded,
          _l10n.nativePlayerSubtitleTrackPickerTitle,
        ),
        if (_canBrowseEpisodes)
          _contextMenuItem(
            'episodes',
            Icons.video_library_rounded,
            _l10n.nativePlayerEpisodePickerTitle,
          ),
        const PopupMenuDivider(height: 8, indent: 8, endIndent: 8),
        _contextMenuItem(
          'mute',
          _volume > 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          _volume > 0
              ? _l10n.desktopPlaybackMuteTooltip
              : _l10n.desktopPlaybackRestoreVolumeTooltip,
        ),
        _contextMenuItem(
          'screenshot',
          Icons.photo_camera_outlined,
          _l10n.desktopPlaybackScreenshotAction,
        ),
        _contextMenuItem(
          'fit',
          Icons.fit_screen_outlined,
          _l10n.desktopPlaybackFitTooltip(_fitLabel),
        ),
        _contextMenuItem(
          'fullscreen',
          videoState.isFullscreen()
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          videoState.isFullscreen()
              ? _l10n.desktopPlaybackExitFullscreenTooltip
              : _l10n.desktopPlaybackFullscreenTooltip,
        ),
        _contextMenuItem('exit', Icons.close_rounded, _l10n.playerBackAction),
      ],
    );
    if (!mounted) return;
    switch (selected) {
      case 'assistant':
        final source = _flyClient.sourceRef(statsScope: _source.statsScope, itemGuid: _source.itemGuid, mediaGuid: _source.mediaGuid);
        if (source != null) await showFlyAssistant(context, source: source);
      case 'toggle':
        await _togglePlayback();
      case 'quality':
        await _showQualities(anchor: contextAnchor);
      case 'audio':
        await _showTracks(audio: true, anchor: contextAnchor);
      case 'subtitle':
        await _showTracks(audio: false, anchor: contextAnchor);
      case 'episodes':
        await _showEpisodes();
      case 'mute':
        await _toggleMute();
      case 'screenshot':
        await _captureScreenshot();
      case 'fit':
        _cycleFit();
      case 'fullscreen':
        await videoState.toggleFullscreen();
      case 'exit':
        await _leavePlayer(videoState);
    }
  }

  PopupMenuItem<String> _contextMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: Colors.white60),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _leavePlayer(VideoState videoState) async {
    _wakeControls();
    if (_hoverOverlayKind != null) {
      _dismissHoverOverlay();
      return;
    }
    if (_isLocked) {
      _showLockedHint();
      return;
    }
    if (videoState.isFullscreen()) {
      await videoState.exitFullscreen();
      return;
    }
    if (mounted) await Navigator.of(context).maybePop();
  }

  void _toggleLock() {
    _lastLockedEscapeTime = null;
    _dismissHoverOverlay();
    _updateView(() => _isLocked = !_isLocked);
    unawaited(windowManager.setPreventClose(_isLocked));
    _wakeControls();
    _showPlayerMessage(
      _isLocked ? _l10n.nativePlayerText0009 : _l10n.nativePlayerText0010,
    );
  }

  void _showLockedHint() {
    _wakeControls();
    _showPlayerMessage('${_l10n.nativePlayerLockedUnlockHint} · Esc × 2');
  }

  @override
  void onWindowClose() {
    if (_isLocked) _showLockedHint();
  }

  KeyEventResult _handleKeyEvent(VideoState videoState, KeyEvent event) {
    final isInitialPress = event is KeyDownEvent;
    final isRepeatablePress = isInitialPress || event is KeyRepeatEvent;
    if (!isRepeatablePress) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (_isLocked) {
      if (isInitialPress) {
        if (key == LogicalKeyboardKey.escape) {
          final previous = _lastLockedEscapeTime;
          _lastLockedEscapeTime = event.timeStamp;
          if (previous != null &&
              event.timeStamp - previous <= const Duration(seconds: 2)) {
            _toggleLock();
          } else {
            _wakeControls();
            _showPlayerMessage('再按一次 Esc 解锁');
          }
        } else {
          _lastLockedEscapeTime = null;
          _showLockedHint();
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space && isInitialPress) {
      unawaited(_togglePlayback());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS &&
        isInitialPress &&
        HardwareKeyboard.instance.isControlPressed) {
      unawaited(_captureScreenshot());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK && isInitialPress) {
      unawaited(_togglePlayback());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekRelative(const Duration(seconds: -10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ) {
      unawaited(_seekRelative(const Duration(seconds: -10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekRelative(const Duration(seconds: 10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL) {
      unawaited(_seekRelative(const Duration(seconds: 10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      unawaited(_setVolume(_volume + 5));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      unawaited(_setVolume(_volume - 5));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && isInitialPress) {
      unawaited(_leavePlayer(videoState));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM && isInitialPress) {
      unawaited(_toggleMute());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN &&
        isInitialPress &&
        _nextEpisode != null) {
      _wakeControls();
      unawaited(_showNextEpisode());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP &&
        isInitialPress &&
        _previousEpisode != null) {
      _wakeControls();
      unawaited(_showPreviousEpisode());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF && isInitialPress) {
      _wakeControls();
      unawaited(videoState.toggleFullscreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && isInitialPress) {
      _wakeControls();
      unawaited(videoState.toggleFullscreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home && isInitialPress) {
      unawaited(_seekTo(Duration.zero));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end && isInitialPress) {
      unawaited(_seekTo(_player.state.duration));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ColoredBox(
        color: Colors.black,
        child: Video(
          controller: _videoController,
          fit: _fit,
          // Windows 全屏与窗口外壳共用入口，避免两套原生窗口样式互相覆盖。
          onEnterFullscreen: Platform.isWindows
              ? () => windowManager.setFullScreen(true)
              : defaultEnterNativeFullscreen,
          onExitFullscreen: Platform.isWindows
              ? () => windowManager.setFullScreen(false)
              : defaultExitNativeFullscreen,
          // 使用自建控制层，明确关闭 media_kit 的默认 controls。
          controls: _buildVideoControls,
        ),
      ),
    );
  }

  Widget _buildVideoControls(VideoState videoState) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _controlsVisibleNotifier,
        _playingNotifier,
        _viewRevision,
      ]),
      builder: (context, _) => PopScope(
        canPop: !_isLocked,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isLocked) _showLockedHint();
        },
        child: _DesktopPlaybackKeyboardFocus(
          onKeyEvent: (event) => _handleKeyEvent(videoState, event),
          child: MouseRegion(
            opaque: true,
            cursor: _controlsVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            onEnter: (_) =>
                _wakeControls(scheduleHide: _hoverOverlayKind == null),
            onHover: (_) =>
                _wakeControls(scheduleHide: _hoverOverlayKind == null),
            child: Listener(
              onPointerSignal: (event) {
                if (_isLocked) return;
                if (event is! PointerScrollEvent) return;
                if (_hoverOverlayKind != null) return;
                final delta = event.scrollDelta.dy < 0 ? 5.0 : -5.0;
                unawaited(_setVolume(_volume + delta));
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_isLocked) {
                    _wakeControls();
                    return;
                  }
                  if (_hoverOverlayKind != null) {
                    _dismissHoverOverlay();
                    return;
                  }
                  unawaited(_togglePlayback());
                },
                onSecondaryTapUp: (details) {
                  if (_isLocked) {
                    _showLockedHint();
                    return;
                  }
                  if (_hoverOverlayKind != null) {
                    _dismissHoverOverlay();
                    return;
                  }
                  unawaited(
                    _showContextMenu(details.globalPosition, videoState),
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // 双击只由视频背景接收，避免抢走进度条的连续点击。
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: () {
                          if (_isLocked) {
                            _wakeControls();
                            return;
                          }
                          if (_hoverOverlayKind != null) return;
                          _wakeControls();
                          unawaited(videoState.toggleFullscreen());
                        },
                      ),
                    ),
                    ListenableBuilder(
                      listenable: _weakNetwork,
                      builder: (context, _) => _buildStatusLayer(),
                    ),
                    if (_danmakuSettings.enabled && _danmakuComments.isNotEmpty)
                      Positioned.fill(
                        child: DesktopDanmakuOverlay(
                          player: _player,
                          comments: _danmakuComments,
                          settings: _danmakuSettings,
                          fit: _fit,
                          seekRevision: _danmakuSeekRevision,
                        ),
                      ),
                    IgnorePointer(
                      ignoring: !_controlsVisible || _isLocked,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible && !_isLocked ? 1 : 0,
                        duration: _controlsAnimationDuration,
                        curve: Curves.easeOutCubic,
                        child: ValueListenableBuilder<PlayerHoverOverlaySnapshot>(
                          valueListenable: _hoverOverlayNotifier,
                          builder: (context, hover, _) => DesktopPlayerControls(
                            activeMenu: hover.visible ? hover.kind?.name : null,
                            player: _player,
                            showBuffer: !Uri.parse(
                              _source.url,
                            ).isScheme('file'),
                            chapters: _chapters,
                            seekThumbnails: _source.seekThumbnails,
                            seekThumbnailBifUrl: _source.seekThumbnailBifUrl,
                            thumbnailHeaders: _source.headers,
                            videoState: videoState,
                            title: _source.title,
                            resolution: _resolutionLabel,
                            playing: _isPlaying,
                            loading: _isLoading || _isBuffering,
                            volume: _volume,
                            rate: _playbackRate,
                            nowPlayingLabel: _l10n.nativeNotificationNowPlaying,
                            playTooltip: _l10n.desktopPlaybackPlayTooltip,
                            pauseTooltip: _l10n.desktopPlaybackPauseTooltip,
                            muteTooltip: _volume > 0
                                ? _l10n.desktopPlaybackMuteTooltip
                                : _l10n.desktopPlaybackRestoreVolumeTooltip,
                            speedTooltip: _l10n.playerDiagnosticsSpeed,
                            fullscreenTooltip: videoState.isFullscreen()
                                ? _l10n.desktopPlaybackExitFullscreenTooltip
                                : _l10n.desktopPlaybackFullscreenTooltip,
                            settingsTooltip: _l10n.desktopPlaybackMoreOptions,
                            prevTooltip:
                                _l10n.desktopPlaybackPrevEpisodeTooltip,
                            bookmarkTooltip: _l10n.playerBookmarkAddCurrent,
                            episodeLabel: _l10n.playerEpisodeAction,
                            subtitleLabel:
                                _player.state.track.subtitle.id == 'no'
                                ? _l10n.playerSubtitleOffAction
                                : _l10n.playerSubtitleAction,
                            audioTooltip: _l10n.playerAudioTrackAction,
                            screenshotLabel:
                                _l10n.desktopPlaybackScreenshotAction,
                            danmakuEnabled: _danmakuSettings.enabled,
                            danmakuLabel: _danmakuSettings.enabled
                                ? '弹幕设置 · 已开启'
                                : '弹幕设置 · 已关闭',
                            onBack: () => unawaited(_leavePlayer(videoState)),
                            onToggle: () => unawaited(_togglePlayback()),
                            onSeek: _seekTo,
                            onVolume: (value) => unawaited(_setVolume(value)),
                            onMute: () => unawaited(_toggleMute()),
                            onRate: (value) =>
                                unawaited(_setPlaybackRate(value)),
                            onScreenshot: () => unawaited(_captureScreenshot()),
                            abRepeatLabel: _abLoopEnd != null
                                ? 'A-B'
                                : _abLoopStart != null
                                ? 'A'
                                : 'AB',
                            abRepeatTooltip: _abLoopEnd != null
                                ? '关闭 A-B 循环'
                                : _abLoopStart != null
                                ? '设置 B 点'
                                : '设置 A 点',
                            onAbRepeat: () => unawaited(_toggleAbRepeat()),
                            onToggleDanmaku: _toggleDanmaku,
                            onSettings: () =>
                                unawaited(_showPlaybackSettingsPanel()),
                            onSettingsAt: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.settings,
                              anchor,
                              immediate: true,
                            ),
                            onNext: _nextEpisode == null
                                ? null
                                : () => unawaited(_showNextEpisode()),
                            onHoverNext: _nextEpisode == null
                                ? null
                                : (anchor) => _openHoverOverlay(
                                    PlayerHoverOverlayKind.nextEpisode,
                                    anchor,
                                  ),
                            onPrevious: _previousEpisode == null
                                ? null
                                : () => unawaited(_showPreviousEpisode()),
                            onHoverPrevious: _previousEpisode == null
                                ? null
                                : (anchor) => _openHoverOverlay(
                                    PlayerHoverOverlayKind.previousEpisode,
                                    anchor,
                                  ),
                            onEpisodes: _canBrowseEpisodes
                                ? () => unawaited(_showEpisodes())
                                : null,
                            onEpisodesAt: _canBrowseEpisodes
                                ? (anchor) => _openHoverOverlay(
                                    PlayerHoverOverlayKind.episodes,
                                    anchor,
                                    immediate: true,
                                  )
                                : null,
                            onAudio: () => unawaited(_showTracks(audio: true)),
                            onSubtitle: () =>
                                unawaited(_showTracks(audio: false)),
                            onAudioAt: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.audio,
                              anchor,
                              immediate: true,
                            ),
                            onSubtitleAt: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.subtitle,
                              anchor,
                              immediate: true,
                            ),
                            onQuality:
                                _source.qualities.isEmpty ||
                                    widget.reloadSource == null
                                ? null
                                : () => unawaited(_showQualities()),
                            onQualityAt: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.quality,
                              anchor,
                              immediate: true,
                            ),
                            onSpeedAt: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.speed,
                              anchor,
                              immediate: true,
                            ),
                            onHoverSpeed: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.speed,
                              anchor,
                            ),
                            onHoverEpisodes: _canBrowseEpisodes
                                ? (anchor) => _openHoverOverlay(
                                    PlayerHoverOverlayKind.episodes,
                                    anchor,
                                  )
                                : null,
                            onHoverQuality:
                                _source.qualities.isEmpty ||
                                    widget.reloadSource == null
                                ? null
                                : (anchor) => _openHoverOverlay(
                                    PlayerHoverOverlayKind.quality,
                                    anchor,
                                  ),
                            onHoverSubtitle: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.subtitle,
                              anchor,
                            ),
                            onHoverAudio: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.audio,
                              anchor,
                            ),
                            onHoverSettings: (anchor) => _openHoverOverlay(
                              PlayerHoverOverlayKind.settings,
                              anchor,
                            ),
                            onHoverExit: _scheduleHoverOverlayClose,
                            onAddBookmark: () => unawaited(_addBookmark()),
                          ),
                        ),
                      ),
                    ),
                    _buildHoverOverlayLayer(),
                    if (!_isLocked) ...[
                      _buildResumePromptLayer(),
                      _buildWeakNetworkPromptLayer(),
                      if (_autoNextSeconds == 0) _buildSkipPromptLayer(),
                    ],
                    if (_autoNextSeconds > 0) _buildAutoNextPromptLayer(),
                    if (_playbackCompleted)
                      _buildPlaybackCompletedLayer(videoState),
                    _buildLockLayer(),
                    _buildToastLayer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockLayer() {
    return ValueListenableBuilder<PlayerHoverOverlaySnapshot>(
      valueListenable: _hoverOverlayNotifier,
      builder: (context, overlay, _) {
        // 浮层淡出期间也让出位置，避免锁图标压住面板内容。
        if (overlay.kind != null) return const SizedBox.shrink();
        return Positioned(
          top: 0,
          bottom: 0,
          right: 24,
          child: Center(
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: _controlsAnimationDuration,
                child: IconButton(
                  tooltip: _isLocked ? '解锁（连按两次 Esc）' : '返回锁',
                  onPressed: _toggleLock,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(44, 44),
                    foregroundColor: Colors.white,
                    backgroundColor: _isLocked
                        ? Colors.black38
                        : Colors.transparent,
                  ),
                  icon: Icon(
                    _isLocked ? Icons.lock_outline : Icons.lock_open_rounded,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAutoNextPromptLayer() {
    return Positioned(
      right: 24,
      bottom: 110,
      child: DesktopPanelGestureShield(
        child: DesktopFloatingPanel(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _l10n.playerAutoPlayNextPrompt(_autoNextSeconds),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => _cancelAutoNext(),
                  child: Text(_l10n.nativePlayerText0059),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _weakNetworkDetails {
    final speed = formatWeakNetworkSpeedLabel(_weakNetwork.bytesPerSecond);
    final wait = _weakNetwork.estimatedResumeWait;
    if (wait == null) {
      return _l10n.nativePlayerCurrentSpeed.replaceAll(r'%1$s', speed);
    }
    return _l10n.nativePlayerCurrentSpeedResume
        .replaceAll(r'%1$s', speed)
        .replaceAll(
          r'%2$d',
          ((wait.inMilliseconds + 999) ~/ 1000).clamp(1, 9999).toString(),
        );
  }

  Future<void> _switchWeakNetworkQuality() async {
    final choice = _weakNetwork.recommendation;
    if (choice == null || widget.reloadSource == null || _isLoading) return;
    _weakNetwork.dismiss();
    _showPlayerMessage(_l10n.playerWeakNetworkSwitching(choice.displayTier));
    await _reloadPlaybackSource(qualityIndex: choice.sourceIndex);
  }

  Widget _buildWeakNetworkPromptLayer() => ListenableBuilder(
    listenable: _weakNetwork,
    builder: (context, _) {
      final choice = _weakNetwork.recommendation;
      final colors = context.appColors;
      if (choice == null || widget.reloadSource == null) {
        return const SizedBox.shrink();
      }
      return Positioned(
        left: 24,
        bottom: 186,
        width: (MediaQuery.sizeOf(context).width - 48).clamp(0, 440).toDouble(),
        child: DesktopFloatingPanel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _l10n.playerWeakNetworkSuggestionTitle(choice.displayTier),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _weakNetworkDetails,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _weakNetwork.dismiss,
                      child: Text(_l10n.nativePlayerText0061),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_switchWeakNetworkQuality()),
                      child: Text(_l10n.nativePlayerText0060),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _buildResumePromptLayer() {
    return Positioned(
      left: 24,
      bottom: 132,
      child: IgnorePointer(
        ignoring: !_showResumePrompt,
        child: AnimatedSlide(
          offset: _showResumePrompt ? Offset.zero : const Offset(0, 0.18),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _showResumePrompt ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: DesktopFloatingPanel(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.history_rounded,
                        color: Color(0xFF9CC4FF),
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          _l10n.playerResumePrompt(
                            _formatDuration(_source.startPosition),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => unawaited(_restartFromBeginning()),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF9CC4FF),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          minimumSize: const Size(0, 30),
                        ),
                        child: Text(
                          _l10n.playerRestartFromBeginning,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _l10n.commonClose,
                        onPressed: _dismissResumePrompt,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white54,
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 片头片尾跳过提示卡：右下角，样式对齐续播提示；ValueNotifier 驱动全屏可用。
  Widget _buildSkipPromptLayer() {
    return Positioned(
      right: 24,
      bottom: 110,
      child: IgnorePointer(
        ignoring: false,
        child: ValueListenableBuilder<_SkipPromptKind?>(
          valueListenable: _skipPromptKindNotifier,
          builder: (context, kind, _) {
            final hasNext =
                kind == _SkipPromptKind.outro && _nextEpisode != null;
            final bounds = _skipBounds;
            final fromChapter = kind == _SkipPromptKind.intro
                ? bounds.introFromChapter
                : bounds.outroFromChapter;
            final basis = _currentFlyOped != null ? '飞翔已核验' : fromChapter ? '章节识别' : '固定时长';
            final message = kind == _SkipPromptKind.intro
                ? '片头 · $basis'
                : kind == null
                ? null
                : '片尾 · $basis';
            return IgnorePointer(
              ignoring: kind == null,
              child: AnimatedSlide(
                offset: kind == null ? const Offset(0, 0.18) : Offset.zero,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: kind == null ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: DesktopFloatingPanel(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.skip_next_rounded,
                            color: Color(0xFF9CC4FF),
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Text(
                            message ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 10),
                          TextButton(
                            onPressed: () => unawaited(_skipIntroOrOutro()),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF9CC4FF),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              minimumSize: const Size(0, 30),
                            ),
                            child: Text(
                              _currentFlyOped?.at(_player.state.position.inMilliseconds) != null
                                  ? '跳到 ${_formatDuration(Duration(milliseconds: _currentFlyOped!.at(_player.state.position.inMilliseconds)!.endMs))}'
                                  : kind == _SkipPromptKind.intro
                                  ? '跳到 ${_formatDuration(bounds.introEnd ?? Duration.zero)}'
                                  : hasNext
                                  ? '播放下一集'
                                  : '跳到视频结束',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildToastLayer() {
    final message = _toastMessage;
    return Positioned(
      top: 82,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: AnimatedSlide(
          offset: message == null ? const Offset(0, -0.18) : Offset.zero,
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: message == null ? 0 : 1,
            duration: const Duration(milliseconds: 160),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: DesktopFloatingPanel(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Text(
                      message ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackCompletedLayer(VideoState videoState) {
    final episode = _episodes
        .where(
          (episode) =>
              '${episode['itemGuid'] ?? episode['guid'] ?? ''}' ==
              _source.itemGuid,
        )
        .firstOrNull;
    final episodePoster =
        '${episode?['poster'] ?? episode?['posterPath'] ?? ''}'.trim();
    final poster = episodePoster.isEmpty ? _source.posterPath : episodePoster;
    final localPoster =
        poster.startsWith('file:') ||
        RegExp(r'^[a-zA-Z]:[\\/]|^\\\\').hasMatch(poster);
    final artwork = localPoster ? null : widget.resolveArtwork?.call(poster);
    return Positioned.fill(
      // 空白处不触发底层的播放、暂停或双击全屏。
      child: DesktopPanelGestureShield(
        child: Material(
          color: const Color(0xCC000000),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 232,
                        height: 132,
                        child: DesktopEpisodePoster(
                          artwork?.urls.firstOrNull ?? poster,
                          true,
                          headers: artwork?.headers ?? const {},
                          current: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _source.title.trim().isNotEmpty
                          ? _source.title
                          : _source.seriesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => unawaited(_replayCompleted()),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6EA8FF),
                            foregroundColor: const Color(0xFF0B1119),
                          ),
                          child: Text(_l10n.nativePlayerText0063),
                        ),
                        if (_autoPlayEnabled && _nextEpisode != null)
                          OutlinedButton(
                            onPressed: () => unawaited(_showNextEpisode()),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              _l10n.nativeNotificationActionNextEpisode,
                            ),
                          ),
                        OutlinedButton(
                          onPressed: () => unawaited(_leavePlayer(videoState)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_l10n.playerBackAction),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusLayer() {
    if (_errorMessage == null && (_isLoading || _isBuffering)) {
      return Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: (MediaQuery.sizeOf(context).width - 48)
                .clamp(0, 520)
                .toDouble(),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xC9141C28),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFF9CC4FF),
                ),
              ),
              const SizedBox(width: 11),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLoading
                          ? (_qualitySwitchingMessage ??
                                _l10n.playerLoadingOpeningSource)
                          : _l10n.playerLoadingBuffering,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_weakNetwork.remote) ...[
                      const SizedBox(height: 4),
                      Text(
                        _weakNetworkDetails,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_errorMessage == null) return const SizedBox.shrink();

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xE60D1624),
          border: Border.all(color: const Color(0x66D64545)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x99000000), blurRadius: 30),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFFF8A92),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => unawaited(_retryCurrentSource()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_l10n.commonRetry),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6EA8FF),
                  foregroundColor: const Color(0xFF0B1119),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retryCurrentSource() async {
    if (!mounted) return;
    _updateView(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _openSource();
  }

  String _formatDuration(Duration value) {
    final safe = value < Duration.zero ? Duration.zero : value;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String get _fitLabel => switch (_aspectRatioMode) {
    'fill' => _l10n.playerAspectFill,
    '4:3' || '16:9' || '21:9' => _aspectRatioMode,
    _ => _l10n.playerAspectFit,
  };

  String get _subtitle {
    final parts = <String>[];
    if (_source.seriesTitle.trim().isNotEmpty) {
      parts.add(_source.seriesTitle.trim());
    }
    if (_source.seasonNumber > 0 || _source.episodeNumber > 0) {
      final season = _source.seasonNumber > 0
          ? 'S${_source.seasonNumber.toString().padLeft(2, '0')}'
          : '';
      final episode = _source.episodeNumber > 0
          ? 'E${_source.episodeNumber.toString().padLeft(2, '0')}'
          : '';
      parts.add('$season$episode');
    }
    return parts.join(' · ');
  }

  String get _resolutionLabel {
    return DesktopMpvRuntime.currentQualityLabel(
      _source,
      _l10n.playerQualityOriginal,
    );
  }
}

class _DesktopPlaybackKeyboardFocus extends StatefulWidget {
  const _DesktopPlaybackKeyboardFocus({
    required this.onKeyEvent,
    required this.child,
  });

  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final Widget child;

  @override
  State<_DesktopPlaybackKeyboardFocus> createState() =>
      _DesktopPlaybackKeyboardFocusState();
}

class _DesktopPlaybackKeyboardFocusState
    extends State<_DesktopPlaybackKeyboardFocus> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'desktop-playback-controls');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      descendantsAreFocusable: false,
      onKeyEvent: (_, event) => widget.onKeyEvent(event),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _focusNode.requestFocus(),
        child: widget.child,
      ),
    );
  }
}
