library mpv_player_page;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../danmaku/api/dandanplay_api.dart';
import '../danmaku/api/dandanplay_config.dart';
import '../danmaku/api/dandanplay_resolver.dart';
import '../danmaku/controller/danmaku_controller.dart';
import '../danmaku/models/dandanplay_episode_search_item.dart';
import '../danmaku/models/danmaku_import_result.dart';
import '../danmaku/models/danmaku_saved_source.dart';
import '../danmaku/parser/danmaku_import_parser.dart';
import '../danmaku/models/danmaku_settings.dart';
import '../danmaku/render/danmaku_overlay.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../controllers/play_detail_data_loader.dart';
import '../models/media_library_item.dart';
import '../models/play_info.dart';
import '../models/playback_stream.dart';
import '../models/remote_subtitle.dart';
import '../models/stream_track_data.dart';
import '../providers/nas_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/app_log_service.dart';
import '../services/player_host_bridge.dart';
import '../services/player_system_session_bridge.dart';
import '../theme/app_theme.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/media_language_mapper.dart';
import '../utils/media_locale_store.dart';
import '../utils/player_title_formatter.dart';
import '../utils/play_detail_track_selector.dart';
import '../utils/app_top_tip.dart';
import '../ui/bookmark_note_dialog.dart';
import '../ui/bookmark_note_preview.dart';
import '../ui/mpv_audio_eq_advanced_panel.dart';
import '../widgets/common/local_file_browser_sheet.dart';
import 'stores/bookmark_store.dart';
import 'controllers/episode_picker_presenter.dart';
import 'panels/episode_picker_sheet.dart';
import 'stores/mpv_settings_store.dart';
import 'controllers/mpv_player_controller.dart';
import 'controllers/player_runtime_controller.dart';
import 'controllers/player_session_controller.dart';
import 'stores/screenshot_settings_store.dart';
import 'services/mpv_proxy_server.dart';
import 'services/player_runtime_preferences_store.dart';
import 'services/player_subtitle_service.dart';
import 'widgets/mpv_player_widgets.dart';
import 'controllers/player_completion_controller.dart';
import 'widgets/player_controls_chrome.dart';
import 'controllers/player_gesture_controller.dart';
import 'widgets/player_gesture_overlay.dart';
import 'widgets/player_nested_sheet.dart';
import 'widgets/player_option_sheet.dart';
import 'widgets/player_overlay_sections.dart';
import 'controllers/player_settings_controller.dart';
import 'controllers/player_overlay_state.dart';
import 'controllers/player_source_controller.dart';
import 'controllers/player_subtitle_controller.dart';
import 'controllers/player_ui_controller.dart';
import 'widgets/player_system_controls.dart';

part 'page_parts/core/mpv_player_episode_mixin.dart';
part 'page_parts/view/mpv_player_options_mixin.dart';
part 'page_parts/core/mpv_player_playback_feedback_mixin.dart';
part 'page_parts/danmaku/mpv_player_danmaku_mixin.dart';
part 'page_parts/danmaku/mpv_player_danmaku_settings_mixin.dart';
part 'page_parts/danmaku/mpv_player_danmaku_sources_mixin.dart';
part 'page_parts/danmaku/mpv_player_danmaku_pages_mixin.dart';
part 'page_parts/danmaku/mpv_player_danmaku_widgets.dart';
part 'page_parts/core/mpv_player_runtime_mixin.dart';
part 'page_parts/settings/mpv_player_settings_drawer_mixin.dart';
part 'page_parts/settings/mpv_player_settings_intro_outro_mixin.dart';
part 'page_parts/settings/mpv_player_settings_video_info_mixin.dart';
part 'page_parts/settings/mpv_player_settings_mpv_mixin.dart';
part 'page_parts/settings/mpv_player_settings_widgets.dart';
part 'page_parts/settings/mpv_player_audio_drawer_mixin.dart';
part 'page_parts/settings/mpv_player_subtitle_drawer_mixin.dart';
part 'page_parts/settings/mpv_player_video_adjust_mixin.dart';
part 'page_parts/core/mpv_player_source_mixin.dart';
part 'page_parts/core/mpv_player_ab_loop_mixin.dart';
part 'page_parts/core/mpv_player_bookmark_mixin.dart';
part 'page_parts/core/mpv_player_system_session_mixin.dart';
part 'page_parts/view/mpv_player_view_mixin.dart';

const AppThemeColors _playerFixedThemeColors = AppThemeColors(
  backgroundBase: Colors.black,
  backgroundElevated: Color(0xFF050505),
  surface: Color(0xFF0B0B0B),
  surfaceSubtle: Color(0xFF111111),
  surfaceStrong: Color(0xFF171717),
  navBarBackground: Colors.black,
  borderSubtle: Color(0x1AFFFFFF),
  borderStrong: Color(0x33506076),
  accent: Color(0xFF3A82F7),
  accentSoft: Color(0x243A82F7),
  accentStrong: Color(0xFF63A0FF),
  selection: Color(0xFF3A82F7),
  selectionSoft: Color(0x243A82F7),
  selectionStrong: Color(0xFF63A0FF),
  link: Color(0xFF63A0FF),
  chipBackground: Color(0xFF141414),
  chipBorder: Color(0x33506076),
  chipText: Color(0xFFE0E6EE),
  textPrimary: Colors.white,
  textSecondary: Color(0xFFC4D0DE),
  textMuted: Color(0xFF8EA2BA),
  success: Color(0xFF19A35B),
  warning: Color(0xFFB8860B),
  danger: Color(0xFFD64545),
  overlayScrim: Color(0xCC000000),
);

class MpvPlayerPage extends StatefulWidget {
  final String title;
  final MpvMediaSource source;
  final bool parallelLayoutToggleEnabled;
  final String parallelLayoutMode;
  final ValueChanged<String>? onParallelLayoutModeChanged;
  final bool interceptSystemBack;
  final Future<void> Function(PlayDetailPlayerReturnData result)?
  onCloseRequested;

  const MpvPlayerPage({
    super.key,
    required this.title,
    required this.source,
    this.parallelLayoutToggleEnabled = false,
    this.parallelLayoutMode = 'fullscreen',
    this.onParallelLayoutModeChanged,
    this.interceptSystemBack = true,
    this.onCloseRequested,
  });

  @override
  State<MpvPlayerPage> createState() => _MpvPlayerPageState();
}

Future<String> _writeSubtitleTextToTempFile({
  required String path,
  required String text,
}) {
  return Isolate.run(() async {
    final file = File(path);
    await file.writeAsString(text, flush: true);
    return file.path;
  });
}

Future<String> _writeSubtitleBytesToTempFile({
  required String path,
  required Uint8List bytes,
}) {
  return Isolate.run(() async {
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  });
}

class _MpvPlayerPageState extends State<MpvPlayerPage>
    with WidgetsBindingObserver {
  static const String _autoPlayPrefKey = 'player_auto_play_enabled';
  static const String _autoRotatePrefKey = 'player_auto_rotate_enabled';
  static const String _extremePlaybackPrefKey =
      'player_extreme_playback_enabled';
  static const String _decoderModePrefKey = 'player_decoder_mode';
  static const String _displayAspectRatioPrefKey =
      'player_display_aspect_ratio';
  static const String _performanceOverlayPrefKey =
      'player_performance_overlay_enabled';
  static const String _fpsOverlayPrefKey = 'player_fps_overlay_enabled';
  static const String _performanceOverlayOffsetXPrefKey =
      'player_performance_overlay_offset_x';
  static const String _performanceOverlayOffsetYPrefKey =
      'player_performance_overlay_offset_y';
  static const Duration _videoLoadingPlaybackStartTolerance = Duration(
    milliseconds: 450,
  );
  static const String _introOutroEnabledPrefKey = 'player_intro_outro_enabled';
  static const String _introOutroSourceModePrefKey =
      'player_intro_outro_source_mode';
  static const String _introOutroChapterModePrefKey =
      'player_intro_outro_chapter_mode';
  static const String _introOutroIntroMaxPrefKey =
      'player_intro_outro_intro_max_seconds';
  static const String _introOutroOutroMaxPrefKey =
      'player_intro_outro_outro_max_seconds';
  static const String _mpvSettingPrefPrefix = 'player_mpv_setting_';
  static const String _decoderModeHardware = 'hardware';
  static const String _decoderModeSoftware = 'software';
  static const String _displayAspectRatioFit = 'fit';
  static const String _displayAspectRatioFill = 'fill';
  static const String _displayAspectRatio4x3 = '4:3';
  static const String _displayAspectRatio16x9 = '16:9';
  static const String _displayAspectRatio21x9 = '21:9';
  static const String _autoFilterFallbackStatusText =
      'Auto performance fallback: filters disabled';
  static const String _introOutroModeAuto = 'auto';
  static const String _introOutroModeChapter = 'chapter';
  static const String _introOutroModeManual = 'manual';
  static const String _introOutroSourceModeOff = 'off';
  static const String _introOutroSourceModeOfficial = 'official';
  static const String _introOutroSourceModeChapter = 'chapter';
  static const String _chapterSkipModeAuto = 'auto';
  static const String _chapterSkipModeManual = 'manual';
  static const Duration _systemPlaybackSessionPositionThreshold = Duration(
    seconds: 1,
  );
  static const String _mpvSettingDeband = 'deband';
  static const String _mpvSettingSharpen = 'sharpen';
  static const String _mpvSettingDenoise = 'denoise';
  static const String _mpvSettingDeinterlace = 'deinterlace';
  static const String _mpvSettingScaleProfile = 'scale_profile';
  static const String _mpvSettingHdrMode = 'hdr_mode';
  static const String _mpvSettingFrameInterpolation = 'frame_interpolation';
  static const String _mpvSettingVideoSync = 'video_sync';
  static const String _mpvSettingCacheProfile = 'cache_profile';
  static const String _mpvSettingCacheSizeMb = 'cache_size_mb';
  static const String _mpvSettingVolumeGain = 'volume_gain';
  static const String _mpvSettingAudioHighFidelity = 'audio_high_fidelity';
  static const String _mpvSettingDynamicRange = 'dynamic_range';
  static const String _mpvSettingAudioEq = 'audio_eq';
  static const String _mpvSettingAudioLimiter = 'audio_limiter';
  static const String _mpvSettingAudioBassBoost = 'audio_bass_boost';
  static const String _mpvSettingAudioVoiceEnhance = 'audio_voice_enhance';
  static const String _mpvSettingAudioEqBand60 = 'audio_eq_band_60';
  static const String _mpvSettingAudioEqBand170 = 'audio_eq_band_170';
  static const String _mpvSettingAudioEqBand310 = 'audio_eq_band_310';
  static const String _mpvSettingAudioEqBand1000 = 'audio_eq_band_1000';
  static const String _mpvSettingAudioEqBand6000 = 'audio_eq_band_6000';
  static const String _mpvSettingChannelMix = 'channel_mix';
  static const String _mpvSettingCompatibility = 'compatibility_profile';
  static const String _videoAdjustBrightness = 'brightness';
  static const String _videoAdjustContrast = 'contrast';
  static const String _videoAdjustSaturation = 'saturation';
  static const String _videoAdjustGamma = 'gamma';
  static const String _videoAdjustHue = 'hue';
  static const Map<String, String> _defaultMpvSettings = <String, String>{
    _mpvSettingDeband: 'off',
    _mpvSettingSharpen: 'off',
    _mpvSettingDenoise: 'off',
    _mpvSettingDeinterlace: 'auto',
    _mpvSettingScaleProfile: 'balanced',
    _mpvSettingHdrMode: 'auto',
    _mpvSettingFrameInterpolation: 'off',
    _mpvSettingVideoSync: 'auto',
    _mpvSettingCacheProfile: 'default',
    _mpvSettingCacheSizeMb: 'auto',
    _mpvSettingVolumeGain: '100',
    _mpvSettingAudioHighFidelity: 'off',
    _mpvSettingDynamicRange: 'off',
    _mpvSettingAudioEq: 'off',
    _mpvSettingAudioLimiter: 'off',
    _mpvSettingAudioBassBoost: 'off',
    _mpvSettingAudioVoiceEnhance: 'off',
    _mpvSettingAudioEqBand60: '0',
    _mpvSettingAudioEqBand170: '0',
    _mpvSettingAudioEqBand310: '0',
    _mpvSettingAudioEqBand1000: '0',
    _mpvSettingAudioEqBand6000: '0',
    _mpvSettingChannelMix: 'auto',
    _mpvSettingCompatibility: 'default',
  };
  static const Map<String, double> _defaultVideoAdjustments = <String, double>{
    _videoAdjustBrightness: 0,
    _videoAdjustContrast: 0,
    _videoAdjustSaturation: 0,
    _videoAdjustGamma: 0,
    _videoAdjustHue: 0,
  };
  static const int _introOutroReminderLeadSeconds = 5;
  static const MethodChannel _systemChannel = MethodChannel(
    'fly_player/system',
  );

  final MpvPlayerController _controller = MpvPlayerController();
  final PlayerOverlayStateController _overlayState =
      PlayerOverlayStateController();
  final PlayerGestureController _gestureController = PlayerGestureController(
    systemController: const PlayerSystemController(),
  );
  final PlayerCompletionController _completionController =
      PlayerCompletionController();
  final PlayerRuntimeController _runtimeController = PlayerRuntimeController();
  final PlayerSessionController _sessionController = PlayerSessionController();
  final PlayerUiController _uiController = PlayerUiController();
  final PlayerSourceController _sourceController =
      const PlayerSourceController();
  final PlayerSettingsController _settingsController =
      PlayerSettingsController(
          defaultMpvSettings: _defaultMpvSettings,
          defaultVideoAdjustments: _defaultVideoAdjustments,
        )
        ..decoderMode = _decoderModeHardware
        ..displayAspectRatioMode = _displayAspectRatioFit
        ..introOutroSourceMode = _introOutroSourceModeOff
        ..chapterSkipMode = _chapterSkipModeAuto
        ..introOutroMode = _introOutroModeAuto
        ..subtitleScaleFactor =
            (1.0 - _subtitleScaleMin) / (_subtitleScaleMax - _subtitleScaleMin);
  final PlayerSubtitleController _subtitleController =
      PlayerSubtitleController();
  final PlayerRuntimePreferencesStore _runtimePreferencesStore =
      const PlayerRuntimePreferencesStore(
        autoPlayPrefKey: _autoPlayPrefKey,
        autoRotatePrefKey: _autoRotatePrefKey,
        extremePlaybackPrefKey: _extremePlaybackPrefKey,
        performanceOverlayPrefKey: _performanceOverlayPrefKey,
        fpsOverlayPrefKey: _fpsOverlayPrefKey,
        performanceOverlayOffsetXPrefKey: _performanceOverlayOffsetXPrefKey,
        performanceOverlayOffsetYPrefKey: _performanceOverlayOffsetYPrefKey,
        decoderModePrefKey: _decoderModePrefKey,
        displayAspectRatioPrefKey: _displayAspectRatioPrefKey,
        introOutroEnabledPrefKey: _introOutroEnabledPrefKey,
        introOutroSourceModePrefKey: _introOutroSourceModePrefKey,
        introOutroChapterModePrefKey: _introOutroChapterModePrefKey,
        introOutroIntroMaxPrefKey: _introOutroIntroMaxPrefKey,
        introOutroOutroMaxPrefKey: _introOutroOutroMaxPrefKey,
        mpvSettingPrefPrefix: _mpvSettingPrefPrefix,
        decoderModeHardware: _decoderModeHardware,
        decoderModeSoftware: _decoderModeSoftware,
        displayAspectRatioFit: _displayAspectRatioFit,
        supportedDisplayAspectRatioModes: <String>{
          _displayAspectRatioFit,
          _displayAspectRatioFill,
          _displayAspectRatio4x3,
          _displayAspectRatio16x9,
          _displayAspectRatio21x9,
        },
        introOutroSourceModeOff: _introOutroSourceModeOff,
        supportedIntroOutroSourceModes: <String>{
          _introOutroSourceModeOff,
          _introOutroSourceModeOfficial,
          _introOutroSourceModeChapter,
        },
        chapterSkipModeAuto: _chapterSkipModeAuto,
        supportedChapterSkipModes: <String>{
          _chapterSkipModeAuto,
          _chapterSkipModeManual,
        },
        defaultMpvSettings: _defaultMpvSettings,
        defaultPerformanceOverlayOffset: Offset(12, 56),
        introDurationMinSeconds: 60,
        introDurationMaxSeconds: 240,
        outroDurationMinSeconds: 60,
        outroDurationMaxSeconds: 240,
      );
  final PlayerSubtitleService _subtitleService = const PlayerSubtitleService();
  final DanmakuController _danmakuController = DanmakuController(
    const DanmakuSettingsStore(),
  );
  final DanmakuSavedSourceStore _danmakuSavedSourceStore =
      const DanmakuSavedSourceStore();
  final AppTopTip _topTip = AppTopTip();
  final TextEditingController _danmakuSearchController =
      TextEditingController();
  final Map<String, Timer> _proxyReleaseTimers = <String, Timer>{};
  final Set<String> _dismissedChapterSkipKeys = <String>{};
  final Set<String> _completedChapterSkipKeys = <String>{};

  Timer? _recordTimer;
  Timer? _controlsTimer;
  Timer? _statusMessageTimer;
  Timer? _subtitleSwitchOverlayTimer;
  Timer? _deferredSubtitleSelectionTimer;
  Timer? _videoLoadingOverlayTimer;
  Timer? _performanceOverlayTimer;
  Timer? _chapterRetryTimer;
  Timer? _centerPopupTimer;
  NasProvider? _nasProvider;
  bool _abLoopSeekPending = false;
  bool _resumeAfterLifecyclePause = false;
  bool _episodeListLoading = false;
  bool _exitInProgress = false;
  bool _exitPlaybackRecordQueued = false;
  bool _danmakuSearchLoading = false;
  bool _playbackSettingsDrawerVisible = false;
  int _loadNonceSeed = 0;
  _ChapterSkipSegment? _inferredIntroSkip;
  _ChapterSkipSegment? _inferredOutroSkip;
  Duration? _abLoopStart;
  Duration? _abLoopEnd;
  String? _activeDanmakuSourceKey;
  int? _danmakuImportingEpisodeId;
  String? _danmakuImportingLocalPath;
  String? _danmakuDeletingLocalPath;
  String _currentPosterPath = '';
  String _chapterMediaGuid = '';
  PlayDetailRefreshData? _prefetchedReturnDetailData;
  String _prefetchedReturnDetailItemGuid = '';
  String _prefetchedReturnDetailMediaGuid = '';
  String? _prefetchedReturnDetailAudioGuid;
  String? _prefetchedReturnDetailSubtitleGuid;
  int _returnDetailPrefetchGeneration = 0;
  final ValueNotifier<MpvPerformanceOverlayStats>
  _performanceOverlayStatsNotifier = ValueNotifier<MpvPerformanceOverlayStats>(
    MpvPerformanceOverlayStats.empty,
  );
  final ValueNotifier<Offset> _performanceOverlayOffsetNotifier =
      ValueNotifier<Offset>(const Offset(12, 56));
  List<MediaLibraryItem> _episodeItems = const <MediaLibraryItem>[];
  List<MpvChapterItem> _chapters = const <MpvChapterItem>[];
  List<DanDanPlayEpisodeSearchItem> _danmakuSearchResults =
      const <DanDanPlayEpisodeSearchItem>[];
  List<DanmakuSavedSource> _savedLocalDanmakuSources =
      const <DanmakuSavedSource>[];
  final BookmarkStore _bookmarkStore = const BookmarkStore();
  List<PlayerBookmarkEntry> _bookmarksForCurrentMedia =
      const <PlayerBookmarkEntry>[];
  bool _captureFrameInFlight = false;
  bool _systemPlaybackSessionStarted = false;
  Map<String, Object?>? _lastSystemPlaybackSessionPayload;
  SystemUiMode? _lastAppliedSystemUiMode;

  bool get _gestureSeekActive => _gestureController.gestureSeekActive;
  bool get _speedBoostActive => _gestureController.speedBoostActive;
  bool get _playbackCompleted => _completionController.playbackCompleted;
  bool get _completionActionInFlight =>
      _completionController.completionActionInFlight;
  bool get _controlsVisible => _overlayState.controlsVisible;
  bool get _controlsAnimatingOut => _overlayState.controlsAnimatingOut;
  PlayerAdjustmentOverlayData? get _gestureOverlayData =>
      _gestureController.gestureOverlayData;
  Map<String, String> get _subtitleFileByGuid =>
      _subtitleController.subtitleFileByGuid;
  Set<String> get _serverFallbackSubtitleGuids =>
      _subtitleController.serverFallbackSubtitleGuids;
  Set<String> get _subtitleFailureNoticeShownGuids =>
      _subtitleController.subtitleFailureNoticeShownGuids;
  bool get _subtitleLoading => _subtitleController.subtitleLoading;
  set _subtitleLoading(bool value) =>
      _subtitleController.subtitleLoading = value;
  bool get _subtitleSelectionRefreshInFlight =>
      _subtitleController.subtitleSelectionRefreshInFlight;
  set _subtitleSelectionRefreshInFlight(bool value) =>
      _subtitleController.subtitleSelectionRefreshInFlight = value;
  DateTime? get _subtitleStatusTipSuppressedUntil =>
      _subtitleController.subtitleStatusTipSuppressedUntil;
  set _subtitleStatusTipSuppressedUntil(DateTime? value) =>
      _subtitleController.subtitleStatusTipSuppressedUntil = value;
  bool get _subtitleExplicitlyDisabled =>
      _subtitleController.subtitleExplicitlyDisabled;
  set _subtitleExplicitlyDisabled(bool value) =>
      _subtitleController.subtitleExplicitlyDisabled = value;
  bool get _pendingSubtitleSelectionRefresh =>
      _subtitleController.pendingSubtitleSelectionRefresh;
  set _pendingSubtitleSelectionRefresh(bool value) =>
      _subtitleController.pendingSubtitleSelectionRefresh = value;
  String? get _pendingExternalSubtitlePath =>
      _subtitleController.pendingExternalSubtitlePath;
  set _pendingExternalSubtitlePath(String? value) =>
      _subtitleController.pendingExternalSubtitlePath = value;
  String? get _subtitleDeletingGuid => _subtitleController.subtitleDeletingGuid;
  set _subtitleDeletingGuid(String? value) =>
      _subtitleController.subtitleDeletingGuid = value;
  String get _subtitleSearchLanguage =>
      _subtitleController.subtitleSearchLanguage;
  set _subtitleSearchLanguage(String value) =>
      _subtitleController.subtitleSearchLanguage = value;
  String? get _subtitleSearchLoadingLanguage =>
      _subtitleController.subtitleSearchLoadingLanguage;
  set _subtitleSearchLoadingLanguage(String? value) =>
      _subtitleController.subtitleSearchLoadingLanguage = value;
  String? get _subtitleDownloadTrimId =>
      _subtitleController.subtitleDownloadTrimId;
  set _subtitleDownloadTrimId(String? value) =>
      _subtitleController.subtitleDownloadTrimId = value;
  List<RemoteSubtitleSearchItem> get _subtitleSearchResults =>
      _subtitleController.subtitleSearchResults;
  set _subtitleSearchResults(List<RemoteSubtitleSearchItem> value) =>
      _subtitleController.subtitleSearchResults = value;
  bool get _autoPlayEnabled => _settingsController.autoPlayEnabled;
  set _autoPlayEnabled(bool value) =>
      _settingsController.autoPlayEnabled = value;
  bool get _autoRotateEnabled => _settingsController.autoRotateEnabled;
  set _autoRotateEnabled(bool value) =>
      _settingsController.autoRotateEnabled = value;
  bool get _extremePlaybackEnabled =>
      _settingsController.extremePlaybackEnabled;
  set _extremePlaybackEnabled(bool value) =>
      _settingsController.extremePlaybackEnabled = value;
  bool get _performanceOverlayEnabled =>
      _settingsController.performanceOverlayEnabled;
  set _performanceOverlayEnabled(bool value) =>
      _settingsController.performanceOverlayEnabled = value;
  bool get _fpsOverlayEnabled => _settingsController.fpsOverlayEnabled;
  set _fpsOverlayEnabled(bool value) =>
      _settingsController.fpsOverlayEnabled = value;
  bool get _introOutroEnabled => _settingsController.introOutroEnabled;
  set _introOutroEnabled(bool value) =>
      _settingsController.introOutroEnabled = value;
  bool get _introOutroConfigLoaded =>
      _settingsController.introOutroConfigLoaded;
  set _introOutroConfigLoaded(bool value) =>
      _settingsController.introOutroConfigLoaded = value;
  bool get _introOutroSkipInFlight =>
      _settingsController.introOutroSkipInFlight;
  set _introOutroSkipInFlight(bool value) =>
      _settingsController.introOutroSkipInFlight = value;
  bool get _pendingReloadAutoplayRefresh =>
      _settingsController.pendingReloadAutoplayRefresh;
  set _pendingReloadAutoplayRefresh(bool value) =>
      _settingsController.pendingReloadAutoplayRefresh = value;
  bool get _watchedMarkedForCurrentItem =>
      _settingsController.watchedMarkedForCurrentItem;
  set _watchedMarkedForCurrentItem(bool value) =>
      _settingsController.watchedMarkedForCurrentItem = value;
  int get _skipPromptCountdownSeconds =>
      _settingsController.skipPromptCountdownSeconds;
  set _skipPromptCountdownSeconds(int value) =>
      _settingsController.skipPromptCountdownSeconds = value;
  int? get _introChapterIndex => _settingsController.introChapterIndex;
  set _introChapterIndex(int? value) =>
      _settingsController.introChapterIndex = value;
  int? get _outroChapterIndex => _settingsController.outroChapterIndex;
  set _outroChapterIndex(int? value) =>
      _settingsController.outroChapterIndex = value;
  int get _officialIntroDurationSeconds =>
      _settingsController.officialIntroDurationSeconds;
  set _officialIntroDurationSeconds(int value) =>
      _settingsController.officialIntroDurationSeconds = value;
  int get _officialOutroDurationSeconds =>
      _settingsController.officialOutroDurationSeconds;
  set _officialOutroDurationSeconds(int value) =>
      _settingsController.officialOutroDurationSeconds = value;
  int get _introDurationSeconds => _settingsController.introDurationSeconds;
  set _introDurationSeconds(int value) =>
      _settingsController.introDurationSeconds = value;
  int get _outroDurationSeconds => _settingsController.outroDurationSeconds;
  set _outroDurationSeconds(int value) =>
      _settingsController.outroDurationSeconds = value;
  String get _decoderMode => _settingsController.decoderMode;
  set _decoderMode(String value) => _settingsController.decoderMode = value;
  String get _displayAspectRatioMode =>
      _settingsController.displayAspectRatioMode;
  set _displayAspectRatioMode(String value) =>
      _settingsController.displayAspectRatioMode = value;
  String get _introOutroSourceMode => _settingsController.introOutroSourceMode;
  set _introOutroSourceMode(String value) =>
      _settingsController.introOutroSourceMode = value;
  String get _chapterSkipMode => _settingsController.chapterSkipMode;
  set _chapterSkipMode(String value) =>
      _settingsController.chapterSkipMode = value;
  String get _introOutroMode => _settingsController.introOutroMode;
  set _introOutroMode(String value) =>
      _settingsController.introOutroMode = value;
  Map<String, String> get _mpvSettings => _settingsController.mpvSettings;
  set _mpvSettings(Map<String, String> value) =>
      _settingsController.mpvSettings = value;
  Map<String, double> get _videoAdjustments =>
      _settingsController.videoAdjustments;
  set _videoAdjustments(Map<String, double> value) =>
      _settingsController.videoAdjustments = value;
  String get _introOutroConfigGuid => _settingsController.introOutroConfigGuid;
  set _introOutroConfigGuid(String value) =>
      _settingsController.introOutroConfigGuid = value;
  double get _audioDelaySeconds => _settingsController.audioDelaySeconds;
  set _audioDelaySeconds(double value) =>
      _settingsController.audioDelaySeconds = value;
  double get _subtitleDelaySeconds => _settingsController.subtitleDelaySeconds;
  set _subtitleDelaySeconds(double value) =>
      _settingsController.subtitleDelaySeconds = value;
  double get _subtitlePositionFactor =>
      _settingsController.subtitlePositionFactor;
  set _subtitlePositionFactor(double value) =>
      _settingsController.subtitlePositionFactor = value;
  double get _subtitleScaleFactor => _settingsController.subtitleScaleFactor;
  set _subtitleScaleFactor(double value) =>
      _settingsController.subtitleScaleFactor = value;
  PlayerPlaybackMode get _playbackMode => _sessionController.playbackMode;
  set _playbackMode(PlayerPlaybackMode value) =>
      _sessionController.playbackMode = value;
  String get _currentItemGuid => _sessionController.currentItemGuid;
  set _currentItemGuid(String value) =>
      _sessionController.currentItemGuid = value;
  String get _currentMediaType => _sessionController.currentMediaType;
  set _currentMediaType(String value) =>
      _sessionController.currentMediaType = value;
  String get _currentAncestorName => _sessionController.currentAncestorName;
  set _currentAncestorName(String value) =>
      _sessionController.currentAncestorName = value;
  String get _currentTitle => _sessionController.currentTitle;
  set _currentTitle(String value) => _sessionController.currentTitle = value;
  String get _currentSeriesTitle => _sessionController.currentSeriesTitle;
  set _currentSeriesTitle(String value) =>
      _sessionController.currentSeriesTitle = value;
  String get _currentSeasonGuid => _sessionController.currentSeasonGuid;
  set _currentSeasonGuid(String value) =>
      _sessionController.currentSeasonGuid = value;
  int get _currentSeasonNumber => _sessionController.currentSeasonNumber;
  set _currentSeasonNumber(int value) =>
      _sessionController.currentSeasonNumber = value;
  int get _currentEpisodeNumber => _sessionController.currentEpisodeNumber;
  set _currentEpisodeNumber(int value) =>
      _sessionController.currentEpisodeNumber = value;
  String get _currentTmdbId => _sessionController.currentTmdbId;
  set _currentTmdbId(String value) => _sessionController.currentTmdbId = value;
  String get _currentMediaGuid => _sessionController.currentMediaGuid;
  set _currentMediaGuid(String value) =>
      _sessionController.currentMediaGuid = value;
  String get _subtitleSourceMediaGuid =>
      _sessionController.subtitleSourceMediaGuid;
  set _subtitleSourceMediaGuid(String value) =>
      _sessionController.subtitleSourceMediaGuid = value;
  String get _currentVideoGuid => _sessionController.currentVideoGuid;
  set _currentVideoGuid(String value) =>
      _sessionController.currentVideoGuid = value;
  int? get _currentDirectLinkQualityIndex =>
      _sessionController.currentDirectLinkQualityIndex;
  set _currentDirectLinkQualityIndex(int? value) =>
      _sessionController.currentDirectLinkQualityIndex = value;
  int get _currentVideoWidth => _sessionController.currentVideoWidth;
  set _currentVideoWidth(int value) =>
      _sessionController.currentVideoWidth = value;
  int get _currentVideoHeight => _sessionController.currentVideoHeight;
  set _currentVideoHeight(int value) =>
      _sessionController.currentVideoHeight = value;
  String get _currentVideoCodecName => _sessionController.currentVideoCodecName;
  set _currentVideoCodecName(String value) =>
      _sessionController.currentVideoCodecName = value;
  String get _currentVideoProfile => _sessionController.currentVideoProfile;
  set _currentVideoProfile(String value) =>
      _sessionController.currentVideoProfile = value;
  String get _currentColorSpace => _sessionController.currentColorSpace;
  set _currentColorSpace(String value) =>
      _sessionController.currentColorSpace = value;
  String get _currentColorTransfer => _sessionController.currentColorTransfer;
  set _currentColorTransfer(String value) =>
      _sessionController.currentColorTransfer = value;
  String get _currentColorPrimaries => _sessionController.currentColorPrimaries;
  set _currentColorPrimaries(String value) =>
      _sessionController.currentColorPrimaries = value;
  int get _currentBitDepth => _sessionController.currentBitDepth;
  set _currentBitDepth(int value) => _sessionController.currentBitDepth = value;
  String? get _activeProxySessionId => _sessionController.activeProxySessionId;
  set _activeProxySessionId(String? value) =>
      _sessionController.activeProxySessionId = value;
  String? get _activeSubtitleProxySessionId =>
      _sessionController.activeSubtitleProxySessionId;
  set _activeSubtitleProxySessionId(String? value) =>
      _sessionController.activeSubtitleProxySessionId = value;
  String? get _currentPlayLink => _sessionController.currentPlayLink;
  set _currentPlayLink(String? value) =>
      _sessionController.currentPlayLink = value;
  String get _currentUrl => _sessionController.currentUrl;
  set _currentUrl(String value) => _sessionController.currentUrl = value;
  Map<String, String> get _currentHeaders => _sessionController.currentHeaders;
  set _currentHeaders(Map<String, String> value) =>
      _sessionController.currentHeaders = value;
  bool get _currentReliableSeek => _sessionController.currentReliableSeek;
  set _currentReliableSeek(bool value) =>
      _sessionController.currentReliableSeek = value;
  String? get _currentSeekProbeSummary =>
      _sessionController.currentSeekProbeSummary;
  set _currentSeekProbeSummary(String? value) =>
      _sessionController.currentSeekProbeSummary = value;
  String? get _currentAudioGuid => _sessionController.currentAudioGuid;
  set _currentAudioGuid(String? value) =>
      _sessionController.currentAudioGuid = value;
  String? get _currentSubtitleGuid => _sessionController.currentSubtitleGuid;
  set _currentSubtitleGuid(String? value) =>
      _sessionController.currentSubtitleGuid = value;
  String get _currentResolution => _sessionController.currentResolution;
  set _currentResolution(String value) =>
      _sessionController.currentResolution = value;
  int get _currentBitrate => _sessionController.currentBitrate;
  set _currentBitrate(int value) => _sessionController.currentBitrate = value;
  int get _durationSeconds => _sessionController.durationSeconds;
  set _durationSeconds(int value) => _sessionController.durationSeconds = value;
  double get _playbackSpeed => _sessionController.playbackSpeed;
  set _playbackSpeed(double value) => _sessionController.playbackSpeed = value;
  Duration get _resumeStartPosition => _sessionController.resumeStartPosition;
  set _resumeStartPosition(Duration value) =>
      _sessionController.resumeStartPosition = value;
  List<AudioTrackOption> get _audioTracks => _sessionController.audioTracks;
  set _audioTracks(List<AudioTrackOption> value) =>
      _sessionController.audioTracks = value;
  List<SubtitleTrackOption> get _subtitleTracks =>
      _sessionController.subtitleTracks;
  set _subtitleTracks(List<SubtitleTrackOption> value) =>
      _sessionController.subtitleTracks = value;
  List<PlaybackQualityOption> get _qualities => _sessionController.qualities;
  set _qualities(List<PlaybackQualityOption> value) =>
      _sessionController.qualities = value;
  bool get _supportsIntroOutroUi {
    if (_currentSeasonGuid.trim().isNotEmpty) return true;
    if (_currentEpisodeNumber > 0) return true;
    if (widget.source.seasonGuid.trim().isNotEmpty) return true;
    if (widget.source.episodeNumber > 0) return true;
    return false;
  }

  bool get _showCloudDriveUiEntry {
    if (_playbackMode.isDirectLink) return true;
    return _qualities.any((quality) => quality.isDirectLink);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      PlayerSystemSessionBridge.registerCommandHandler(
        this,
        _handleSystemPlaybackMethodCall,
      ),
    );
    _hydrateFromSource(widget.source);
    unawaited(_gestureController.primeSystemSnapshot());
    unawaited(_loadInitialPlayerPreferences());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadDanmakuPreferences());
    });
    _controller.value.addListener(_handlePlayerValueChanged);
    _recordTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_submitPlaybackRecord()),
    );
    _scheduleControlsAutoHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncParallelLayoutOrientationLock());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nasProvider ??= context.read<NasProvider>();
    if (!_introOutroConfigLoaded && _currentItemGuid.trim().isNotEmpty) {
      _introOutroConfigLoaded = true;
      unawaited(_loadIntroOutroConfigForItem(_currentItemGuid));
    }
  }

  @override
  void didUpdateWidget(covariant MpvPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final layoutModeChanged =
        oldWidget.parallelLayoutMode != widget.parallelLayoutMode;
    final sourceChanged =
        oldWidget.source.loadNonce != widget.source.loadNonce ||
        oldWidget.source.url != widget.source.url ||
        oldWidget.source.itemGuid != widget.source.itemGuid ||
        oldWidget.source.mediaGuid != widget.source.mediaGuid ||
        oldWidget.source.videoGuid != widget.source.videoGuid ||
        oldWidget.source.startPosition != widget.source.startPosition;
    if (layoutModeChanged) {
      unawaited(_syncParallelLayoutOrientationLock());
      unawaited(
        _applySystemUiForOrientation(
          _isLandscapeViewport(),
          controlsVisible: _controlsVisible,
        ),
      );
    }
    if (sourceChanged) {
      _replacePlayerSource(widget.source);
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final isLandscape = _isLandscapeViewport();
    if (widget.parallelLayoutMode == 'split' && !isLandscape) {
      unawaited(_setPlayerOrientationMode('landscape'));
    }
    unawaited(_applySystemUiForOrientation(isLandscape));
    if (_uiController.orientationChangeInProgress) {
      _completeOrientationTransitionAfterMetrics();
      return;
    }
    unawaited(_controller.refreshState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    _controlsTimer?.cancel();
    _statusMessageTimer?.cancel();
    _subtitleSwitchOverlayTimer?.cancel();
    _deferredSubtitleSelectionTimer?.cancel();
    _videoLoadingOverlayTimer?.cancel();
    _performanceOverlayTimer?.cancel();
    _chapterRetryTimer?.cancel();
    _centerPopupTimer?.cancel();
    _controller.value.removeListener(_handlePlayerValueChanged);
    unawaited(_stopSystemPlaybackSession());
    unawaited(PlayerSystemSessionBridge.unregisterCommandHandler(this));
    unawaited(_flushPlaybackRecordOnExit());
    for (final path in _subtitleFileByGuid.values.toSet()) {
      unawaited(_deleteTempFile(path));
    }
    final proxySessionId = _activeProxySessionId;
    if (proxySessionId != null && proxySessionId.isNotEmpty) {
      MpvProxyServer.instance.unregister(proxySessionId);
    }
    final subtitleProxySessionId = _activeSubtitleProxySessionId;
    if (subtitleProxySessionId != null && subtitleProxySessionId.isNotEmpty) {
      MpvProxyServer.instance.unregister(subtitleProxySessionId);
    }
    unawaited(_setPlayerOrientationMode('system'));
    unawaited(_setSystemUiModeIfNeeded(SystemUiMode.edgeToEdge, force: true));
    _completionController.dispose();
    _gestureController.dispose();
    _danmakuController.dispose();
    _danmakuSearchController.dispose();
    _topTip.dispose();
    _overlayState.dispose();
    _performanceOverlayStatsNotifier.dispose();
    _performanceOverlayOffsetNotifier.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (_uiController.orientationChangeInProgress) {
      if (state == AppLifecycleState.resumed) {
        unawaited(_controller.refreshState());
      }
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.refreshState());
        if (_resumeAfterLifecyclePause) {
          _resumeAfterLifecyclePause = false;
          unawaited(_controller.play());
        }
      case AppLifecycleState.inactive:
        // Do not pause on transient system overlays (e.g. status bar pull-down).
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_shouldKeepPlaybackAliveInBackground()) {
          _resumeAfterLifecyclePause = false;
          unawaited(_startOrUpdateSystemPlaybackSession(force: true));
          return;
        }
        final playing = !_controller.value.value.paused;
        _resumeAfterLifecyclePause = playing;
        if (playing) {
          unawaited(_controller.pause());
        }
      case AppLifecycleState.detached:
        _resumeAfterLifecyclePause = false;
    }
  }

  bool _shouldKeepPlaybackAliveInBackground() {
    if (!Platform.isAndroid) {
      return false;
    }
    return _systemPlaybackSessionStarted && !_exitInProgress;
  }

  Future<void> _syncParallelLayoutOrientationLock() async {
    if (!Platform.isAndroid) return;
    await _setPlayerOrientationMode(
      widget.parallelLayoutMode == 'split' ? 'landscape' : 'system',
    );
  }

  void _completeOrientationTransitionAfterMetrics() {
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      unawaited(_controller.refreshState());
      _showControls();
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        setState(_uiController.finishOrientationChange);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerTheme = AppThemeBuilder.buildFromColors(
      _playerFixedThemeColors,
      baseTheme: Theme.of(context),
    );
    return Theme(
      data: playerTheme,
      child: Builder(
        builder: (playerContext) {
          if (!Platform.isAndroid) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.title)),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'The libmpv integration in this project is currently implemented for Android only.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          return _buildAndroidPlayerScaffold(playerContext);
        },
      ),
    );
  }
}
