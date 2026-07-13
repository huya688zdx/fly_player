library mpv_player_page;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../danmaku/api/dandanplay_api.dart';
import '../danmaku/api/dandanplay_config.dart';
import '../danmaku/api/dandanplay_resolver.dart';
import '../danmaku/controller/danmaku_controller.dart';
import '../danmaku/models/dandanplay_episode_search_item.dart';
import '../danmaku/models/danmaku_comment.dart';
import '../danmaku/models/danmaku_import_result.dart';
import '../danmaku/models/danmaku_saved_source.dart';
import '../danmaku/parser/danmaku_import_parser.dart';
import '../danmaku/models/danmaku_settings.dart';
import '../danmaku/render/danmaku_overlay.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../controllers/play_detail_data_loader.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/download_task_record.dart';
import '../models/media_library_item.dart';
import '../models/play_info.dart';
import '../models/playback_stream.dart';
import '../models/remote_subtitle.dart';
import '../models/stream_track_data.dart';
import '../models/tv_episode_browser_models.dart';
import '../models/tv_episode_picker_mode.dart';
import '../providers/nas_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/app_log_service.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/parallel_window_settings_bridge.dart';
import '../services/player_host_bridge.dart';
import '../services/storage_access_service.dart';
import '../services/storage_management_service.dart';
import '../services/player_system_session_bridge.dart';
import '../services/play_stats/play_stats.dart';
import '../theme/app_theme.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/back_dismiss_manager.dart';
import '../utils/media_language_mapper.dart';
import '../utils/nas_image_headers.dart';
import '../utils/player_title_formatter.dart';
import '../utils/playback_resume_position_resolver.dart';
import '../utils/play_detail_track_selector.dart';
import '../utils/app_top_tip.dart';
import '../utils/action_rate_limiter.dart';
import 'mpv_settings_l10n.dart';
import '../ui/app_sheet_transitions.dart';
import '../ui/bookmark_note_dialog.dart';
import '../ui/bookmark_note_preview.dart';
import '../ui/mpv_audio_eq_advanced_panel.dart';
import '../widgets/common/named_preset_save_dialog.dart';
import '../widgets/common/local_file_browser_sheet.dart';
import 'stores/bookmark_store.dart';
import 'controllers/episode_picker_presenter.dart';
import 'panels/episode_picker_sheet.dart';
import 'stores/mpv_settings_store.dart';
import 'controllers/mpv_player_controller.dart';
import '../playback/playback_source.dart';
import 'controllers/player_runtime_controller.dart';
import 'models/player_runtime_preferences.dart';
import 'controllers/player_session_controller.dart';
import 'controllers/play_stats_session_controller.dart';
import 'controllers/local_runtime_track_controller.dart';
import 'controllers/weak_network_quality_recommender.dart';
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
import 'widgets/player_speed_dial_overlay.dart';
import 'controllers/player_settings_controller.dart';
import 'controllers/player_overlay_state.dart';
import 'controllers/player_source_controller.dart';
import 'controllers/player_subtitle_controller.dart';
import 'controllers/player_ui_controller.dart';
import 'widgets/player_listen_video_presentation.dart';
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
  final PlayInfoData? initialPlayInfo;
  final PlayStartSource startSource;
  final bool parallelLayoutToggleEnabled;
  final String parallelLayoutMode;
  final ValueChanged<String>? onParallelLayoutModeChanged;
  final bool interceptSystemBack;
  final bool pictureInPictureActive;
  final ValueChanged<Future<bool> Function()?>? onBackActionHandlerChanged;
  final Future<void> Function(PlayDetailPlayerReturnData result)?
  onCloseRequested;
  final BackDismissManager? backDismissManager;

  const MpvPlayerPage({
    super.key,
    required this.title,
    required this.source,
    this.initialPlayInfo,
    this.startSource = PlayStartSource.manual,
    this.parallelLayoutToggleEnabled = false,
    this.parallelLayoutMode = 'fullscreen',
    this.onParallelLayoutModeChanged,
    this.interceptSystemBack = true,
    this.pictureInPictureActive = false,
    this.onBackActionHandlerChanged,
    this.onCloseRequested,
    this.backDismissManager,
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
  static const String _backDismissUiLockId = 'player_ui_lock';
  static const String _backDismissSpeedDialId = 'player_speed_dial';
  static const String _backDismissRouteOverlayId = 'player_route_overlay';
  static const String _backDismissChapterSkipId = 'player_chapter_skip';
  static const String _backDismissAutoPlayPromptId = 'player_auto_play_prompt';
  static const String _backDismissPlaybackCompletedId =
      'player_playback_completed';
  static const String _backDismissResumePromptId = 'player_resume_prompt';
  static const String _autoPlayPrefKey = 'player_auto_play_enabled';
  static const String _nextEpisodePreloadPrefKey =
      'player_next_episode_preload_enabled';
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
  static const Duration _episodePickerPrefetchDelay = Duration(
    milliseconds: 1800,
  );
  static const Duration _videoLoadingPlaybackProgressTolerance = Duration(
    milliseconds: 750,
  );
  static const Duration _autoPlayPromptMinimumProgress = Duration(seconds: 5);
  static const String _introOutroEnabledPrefKey = 'player_intro_outro_enabled';
  static const String _introOutroSourceModePrefKey =
      'player_intro_outro_source_mode';
  static const String _introOutroChapterModePrefKey =
      'player_intro_outro_chapter_mode';
  static const String _introOutroIntroMaxPrefKey =
      'player_intro_outro_intro_max_seconds';
  static const String _introOutroOutroMaxPrefKey =
      'player_intro_outro_outro_max_seconds';
  static const String _subtitleDelayPrefKey = 'player_subtitle_delay_seconds';
  static const String _subtitlePositionFactorPrefKey =
      'player_subtitle_position_factor';
  static const String _subtitleScaleFactorPrefKey =
      'player_subtitle_scale_factor';
  static const String _subtitleAdjustmentRecordsPrefKey =
      'player_subtitle_adjustment_records';
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
  static const String _introOutroSourceModeOff = 'off';
  static const String _introOutroSourceModeOfficial = 'official';
  static const String _introOutroSourceModeChapter = 'chapter';
  static const String _chapterSkipModeAuto = 'auto';
  static const String _chapterSkipModeManual = 'manual';
  static const Duration _systemPlaybackSessionPositionThreshold = Duration(
    seconds: 3,
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
  final PlayerGestureTapCoordinator _gestureTapCoordinator =
      PlayerGestureTapCoordinator();
  final PlayerCompletionController _completionController =
      PlayerCompletionController();
  final PlayerRuntimeController _runtimeController = PlayerRuntimeController();
  final LocalRuntimeTrackController _localRuntimeTrackController =
      const LocalRuntimeTrackController();
  final MpvSettingsStore _mpvSettingsStore = const MpvSettingsStore();
  final PlayerSessionController _sessionController = PlayerSessionController();
  final PlayStatsSessionController _playStatsSessionController =
      PlayStatsService.instance.sessionController;
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
  List<SavedMpvPreset> _savedMpvPicturePresets = const <SavedMpvPreset>[];
  List<SavedMpvPreset> _savedMpvAudioPresets = const <SavedMpvPreset>[];
  final PlayerRuntimePreferencesStore _runtimePreferencesStore =
      const PlayerRuntimePreferencesStore(
        autoPlayPrefKey: _autoPlayPrefKey,
        nextEpisodePreloadPrefKey: _nextEpisodePreloadPrefKey,
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
        subtitleDelayPrefKey: _subtitleDelayPrefKey,
        subtitlePositionFactorPrefKey: _subtitlePositionFactorPrefKey,
        subtitleScaleFactorPrefKey: _subtitleScaleFactorPrefKey,
        subtitleAdjustmentRecordsPrefKey: _subtitleAdjustmentRecordsPrefKey,
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
        defaultSubtitleDelaySeconds: 0,
        defaultSubtitlePositionFactor:
            PlayerSettingsController.defaultSubtitlePositionFactor,
        defaultSubtitleScaleFactor:
            (1.0 - _subtitleScaleMin) / (_subtitleScaleMax - _subtitleScaleMin),
        subtitleDelayMinSeconds: -10,
        subtitleDelayMaxSeconds: 10,
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
  final ActionRateLimiter _danmakuSearchRateLimiter = ActionRateLimiter(
    cooldown: const Duration(seconds: 8),
  );
  final Map<String, Timer> _proxyReleaseTimers = <String, Timer>{};
  final Set<String> _dismissedChapterSkipKeys = <String>{};
  final Set<String> _completedChapterSkipKeys = <String>{};

  Timer? _recordTimer;
  Timer? _controlsTimer;
  Timer? _playerSystemStatusTimer;
  Timer? _statusMessageTimer;
  Timer? _subtitleSwitchOverlayTimer;
  Timer? _deferredSubtitleSelectionTimer;
  Timer? _videoLoadingOverlayTimer;
  Timer? _performanceOverlayTimer;
  Timer? _chapterRetryTimer;
  Timer? _centerPopupTimer;
  Timer? _initialSourceLoadTimer;
  int? _lastAppliedEffectiveSubtitlePosition;
  double? _lastAppliedSubtitleDelaySeconds;
  double? _lastAppliedSubtitleScale;
  NasProvider? _nasProvider;
  bool _abLoopSeekPending = false;
  bool _resumeAfterLifecyclePause = false;
  bool _episodeListLoading = false;
  bool _exitInProgress = false;
  bool _exitPlaybackRecordQueued = false;
  bool _danmakuSearchLoading = false;
  bool _playbackSettingsDrawerVisible = false;
  bool _audioDrawerVisible = false;
  bool _subtitleDrawerVisible = false;
  bool _episodeSheetVisible = false;
  bool _speedDialVisible = false;
  bool _playerUiLocked = false;
  String _playerSystemTimeLabel = '';
  String _playerSystemNetworkType = 'unknown';
  int? _playerSystemBatteryLevel;
  bool _playerSystemCharging = false;
  bool _initialPlayerPreferencesLoaded = false;
  bool _initialDanmakuPreferencesLoaded = false;
  bool _platformViewAttached = false;
  bool _initialSourceLoadStarted = false;
  bool _initialFrameReady = false;
  bool _runtimeTrackSnapshotInFlight = false;
  bool _runtimeTrackSnapshotLoaded = false;
  bool _serverManagedPlayLinkCheckInFlight = false;
  bool _serverSessionRecoveryInFlight = false;
  bool _cacheDownloadAvailable = false;
  bool _cacheDownloadCheckInFlight = false;
  bool _cacheDownloadImportInFlight = false;
  bool _cacheCompletionTipShown = false;
  bool _cacheDownloadConsumedForSource = false;
  bool _pictureInPictureSupported = false;
  bool _parallelWindowSupported = false;
  bool _parallelWindowEnabled = false;
  bool _audioDrawerSyncInFlight = false;
  int _cacheDownloadCheckToken = 0;
  int _loadNonceSeed = 0;
  int _runtimeTrackSnapshotLoadNonce = 0;
  _ChapterSkipSegment? _inferredIntroSkip;
  _ChapterSkipSegment? _inferredOutroSkip;
  Duration? _abLoopStart;
  Duration? _abLoopEnd;
  String? _activeDanmakuSourceKey;
  String? _lockedPlatformViewBackend;
  int _danmakuContextToken = 0;
  String _lastNativeDanmakuCommentsSignature = '';
  String _lastNativeDanmakuSettingsSignature = '';
  String _lastDanmakuOcclusionConfigSignature = '';
  Timer? _nativeDanmakuSyncTimer;
  Timer? _episodePickerPrefetchTimer;
  bool _nativeDanmakuSyncInFlight = false;
  bool _nativeDanmakuSyncDirty = false;
  int _systemPlaybackSessionWarmupUntilMs = 0;
  int _lastSystemPlaybackSessionRequestMs = 0;
  String _lastSystemPlaybackSessionRequestKey = '';
  int _runtimeTrackAutoRefreshReadyAtMs = 0;
  int _runtimeTrackAutoRefreshLoadNonce = 0;
  int _externalSubtitleAutoApplyReadyAtMs = 0;
  int _externalSubtitleAutoApplyLoadNonce = 0;
  int _lastRuntimeTrackRefreshRequestMs = 0;
  String _lastRuntimeTrackRefreshRequestKey = '';
  bool _episodePickerPrefetchInFlight = false;
  int _episodePickerPrefetchGeneration = 0;
  int? _danmakuImportingEpisodeId;
  String? _danmakuImportingLocalPath;
  String? _danmakuDeletingLocalPath;
  String _danmakuSearchPreparedContextKey = '';
  String _danmakuSearchLastCompletedContextKey = '';
  String _currentPosterPath = '';
  String _chapterMediaGuid = '';
  String _runtimeTrackSnapshotStatus = '';
  PlayDetailRefreshData? _prefetchedReturnDetailData;
  String _prefetchedReturnDetailItemGuid = '';
  String _prefetchedReturnDetailMediaGuid = '';
  String? _prefetchedReturnDetailAudioGuid;
  String? _prefetchedReturnDetailSubtitleGuid;
  int _returnDetailPrefetchGeneration = 0;
  _PreparedEpisodeSwitchResult? _prefetchedNextEpisodeSwitchResult;
  bool _nextEpisodePreloadInFlight = false;
  int _nextEpisodePreloadGeneration = 0;
  List<MediaLibraryItem>? _episodeSeasonItems;
  final Map<String, List<MediaLibraryItem>> _episodeItemsBySeasonGuid =
      <String, List<MediaLibraryItem>>{};
  final Map<String, Future<List<MediaLibraryItem>>>
  _episodeItemsInflightBySeason = <String, Future<List<MediaLibraryItem>>>{};
  final ValueNotifier<MpvPerformanceOverlayStats>
  _performanceOverlayStatsNotifier = ValueNotifier<MpvPerformanceOverlayStats>(
    MpvPerformanceOverlayStats.empty,
  );
  final ValueNotifier<Offset> _performanceOverlayOffsetNotifier =
      ValueNotifier<Offset>(const Offset(12, 56));

  // Merged listenables cached as late final so each AnimatedBuilder subtree
  // subscribes once instead of rebuilding the merge on every parent build.
  late final Listenable _danmakuLayerListenable = Listenable.merge(<Listenable>[
    _controller.value,
    _controller.danmakuOcclusionState,
    _gestureController.speedBoostListenable,
    AppSheetTransitions.activeSheetCount,
  ]);
  late final Listenable _gestureCaptureLayerListenable = Listenable.merge(
    <Listenable>[_gestureController.seekListenable, _overlayState],
  );
  late final Listenable _controlsChromeLayerListenable = Listenable.merge(
    <Listenable>[_gestureController.seekListenable, _overlayState],
  );
  late final Listenable _bottomChromeListenable = Listenable.merge(<Listenable>[
    _gestureController.seekListenable,
    _overlayState,
  ]);
  late final Listenable _performanceOverlayListenable = Listenable.merge(
    <Listenable>[
      _performanceOverlayStatsNotifier,
      _performanceOverlayOffsetNotifier,
    ],
  );
  List<MediaLibraryItem> _episodeItems = const <MediaLibraryItem>[];
  TvEpisodePickerMode _episodePickerMode = TvEpisodePickerMode.list;
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
  PlayerNestedSheetController<void>? _activeAudioDrawerController;
  PlayerNestedSheetController<void>? _activeSubtitleDrawerController;
  PlayerNestedSheetController<void>? _activePlaybackSettingsDrawerController;
  bool _autoPlayPromptRequestInFlight = false;
  Map<String, Object?>? _lastSystemPlaybackSessionPayload;
  SystemUiMode? _lastAppliedSystemUiMode;
  bool? _lastAppliedPlayerImmersiveMode;
  PlayInfoData? _playStatsCurrentInfo;
  String _playStatsCurrentVideoId = '';
  DateTime? _lastServerManagedPlayLinkCheckAt;
  DateTime? _lastServerSessionRecoveryAt;

  bool get _gestureSeekActive => _gestureController.gestureSeekActive;
  bool get _speedBoostActive => _gestureController.speedBoostActive;
  bool get _playbackCompleted => _completionController.playbackCompleted;
  bool get _completionActionInFlight =>
      _completionController.completionActionInFlight;
  bool get _controlsVisible => _overlayState.controlsVisible;
  bool get _controlsAnimatingOut => _overlayState.controlsAnimatingOut;
  bool get _uiTransientOverlayVisible =>
      _playbackSettingsDrawerVisible ||
      _audioDrawerVisible ||
      _subtitleDrawerVisible ||
      _episodeSheetVisible ||
      _speedDialVisible;
  PlayerAdjustmentOverlayData? get _gestureOverlayData =>
      _gestureController.gestureOverlayData;
  Map<String, String> get _subtitleFileByGuid =>
      _subtitleController.subtitleFileByGuid;
  Map<String, Future<String?>> get _subtitleFileRequestByGuid =>
      _subtitleController.subtitleFileRequestByGuid;
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
  String get _subtitleSearchLanguage =>
      _subtitleController.subtitleSearchLanguage;
  String? get _subtitleSearchLoadingLanguage =>
      _subtitleController.subtitleSearchLoadingLanguage;
  String? get _subtitleDownloadTrimId =>
      _subtitleController.subtitleDownloadTrimId;
  List<RemoteSubtitleSearchItem> get _subtitleSearchResults =>
      _subtitleController.subtitleSearchResults;
  bool get _autoPlayEnabled => _settingsController.autoPlayEnabled;
  set _autoPlayEnabled(bool value) =>
      _settingsController.autoPlayEnabled = value;
  bool get _nextEpisodePreloadEnabled =>
      _settingsController.nextEpisodePreloadEnabled;
  set _nextEpisodePreloadEnabled(bool value) =>
      _settingsController.nextEpisodePreloadEnabled = value;
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
  String get _currentSeriesGuid => _sessionController.currentSeriesGuid;
  set _currentSeriesGuid(String value) =>
      _sessionController.currentSeriesGuid = value;
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
  String? get _activeCacheResourceKey =>
      _sessionController.activeCacheResourceKey;
  set _activeCacheResourceKey(String? value) =>
      _sessionController.activeCacheResourceKey = value;
  String? get _currentPlayLink => _sessionController.currentPlayLink;
  set _currentPlayLink(String? value) =>
      _sessionController.currentPlayLink = value;
  int get _currentServerSessionHlsTimeSeconds =>
      _sessionController.currentServerSessionHlsTimeSeconds;
  set _currentServerSessionHlsTimeSeconds(int value) =>
      _sessionController.currentServerSessionHlsTimeSeconds = value;
  String get _currentUrl => _sessionController.currentUrl;
  set _currentUrl(String value) => _sessionController.currentUrl = value;
  bool get _externalLocalSource => widget.source.externalLocalSource;
  bool get _danmakuAutoSearchAllowed => widget.source.danmakuAutoSearchAllowed;
  bool get _currentSourceIsDownloadedFile {
    if (_externalLocalSource) return true;
    final normalizedUrl = _currentUrl.trim().toLowerCase();
    if (normalizedUrl.startsWith('file:') ||
        normalizedUrl.startsWith('content:')) {
      return true;
    }
    if (normalizedUrl.isNotEmpty) return false;
    return widget.source.isDownloadedFile;
  }

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
  bool get _listenVideoModeEnabled => _sessionController.listenVideoModeEnabled;
  set _listenVideoModeEnabled(bool value) =>
      _sessionController.listenVideoModeEnabled = value;
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
    if (_externalLocalSource) return false;
    if (_currentSeasonGuid.trim().isNotEmpty) return true;
    if (_currentEpisodeNumber > 0) return true;
    if (widget.source.seasonGuid.trim().isNotEmpty) return true;
    if (widget.source.episodeNumber > 0) return true;
    return false;
  }

  bool get _showCloudDriveUiEntry {
    if (_externalLocalSource) return false;
    if (_playbackMode.isDirectLink) return true;
    return _qualities.any((quality) => quality.isDirectLink);
  }

  Future<bool> _hostBackActionHandler() async {
    await _handleBackAction();
    return true;
  }

  @override
  void initState() {
    super.initState();
    unawaited(PlayStatsService.instance.database.open());
    _registerBackDismissHandlers(widget.backDismissManager);
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      PlayerSystemSessionBridge.registerCommandHandler(
        this,
        _handleSystemPlaybackMethodCall,
      ),
    );
    _hydrateFromSource(widget.source);
    unawaited(_gestureController.primeSystemSnapshot());
    _playerSystemTimeLabel = _formatPlayerSystemClock(DateTime.now());
    _startPlayerSystemStatusTicker();
    unawaited(_loadInitialPlayerPreferences());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updatePlayerState(() => _initialFrameReady = true);
      _tryStartInitialSourceLoad();
      unawaited(_loadDanmakuPreferences());
    });
    widget.onBackActionHandlerChanged?.call(_hostBackActionHandler);
    _danmakuController.addListener(_handleDanmakuControllerChanged);
    _controller.danmakuOcclusionState.addListener(
      _handleDanmakuOcclusionStateChanged,
    );
    _controller.value.addListener(_handlePlayerValueChanged);
    _completionController.addListener(_handleOverlayControllersChanged);
    _recordTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_submitPlaybackRecordAndFlushStats()),
    );
    _scheduleControlsAutoHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncParallelLayoutOrientationLock());
      unawaited(
        _applySystemUiForOrientation(_isLandscapeViewport(), force: true),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nasProvider ??= context.read<NasProvider>();
    if (!_externalLocalSource &&
        !_introOutroConfigLoaded &&
        _currentItemGuid.trim().isNotEmpty) {
      _introOutroConfigLoaded = true;
      unawaited(_loadIntroOutroConfigForItem(_currentItemGuid));
    }
  }

  @override
  void didUpdateWidget(covariant MpvPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onBackActionHandlerChanged !=
        widget.onBackActionHandlerChanged) {
      oldWidget.onBackActionHandlerChanged?.call(null);
      widget.onBackActionHandlerChanged?.call(_hostBackActionHandler);
    }
    if (oldWidget.backDismissManager != widget.backDismissManager) {
      _unregisterBackDismissHandlers(oldWidget.backDismissManager);
      _registerBackDismissHandlers(widget.backDismissManager);
    }
    final layoutModeChanged =
        oldWidget.parallelLayoutMode != widget.parallelLayoutMode;
    final sourceChanged =
        oldWidget.source.loadNonce != widget.source.loadNonce ||
        oldWidget.source.url != widget.source.url ||
        oldWidget.source.itemGuid != widget.source.itemGuid ||
        oldWidget.source.mediaGuid != widget.source.mediaGuid ||
        oldWidget.source.videoGuid != widget.source.videoGuid ||
        oldWidget.source.externalLocalSource !=
            widget.source.externalLocalSource ||
        oldWidget.source.danmakuAutoSearchAllowed !=
            widget.source.danmakuAutoSearchAllowed ||
        oldWidget.source.audioTrackGuid != widget.source.audioTrackGuid ||
        oldWidget.source.subtitleTrackGuid != widget.source.subtitleTrackGuid ||
        oldWidget.source.audioTrackIndex != widget.source.audioTrackIndex ||
        oldWidget.source.subtitleTrackIndex !=
            widget.source.subtitleTrackIndex ||
        oldWidget.source.preferExternalSubtitle !=
            widget.source.preferExternalSubtitle ||
        oldWidget.source.startPosition != widget.source.startPosition;
    if (layoutModeChanged) {
      unawaited(_syncParallelLayoutOrientationLock());
      unawaited(
        _applySystemUiForOrientation(_isLandscapeViewport(), force: true),
      );
    }
    if (oldWidget.pictureInPictureActive != widget.pictureInPictureActive) {
      unawaited(_syncDanmakuDynamicOcclusionConfig());
      if (widget.pictureInPictureActive) {
        unawaited(_handlePictureInPictureActivated());
      } else {
        _scheduleControlsAutoHide();
      }
    }
    if (sourceChanged) {
      if (!_initialSourceLoadStarted) {
        _initialSourceLoadTimer?.cancel();
        _initialSourceLoadTimer = null;
        _hydrateFromSource(widget.source);
        _tryStartInitialSourceLoad();
      } else {
        unawaited(_replacePlayerSource(widget.source));
      }
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final isLandscape = _isLandscapeViewport();
    if (widget.parallelLayoutMode == 'split') {
      unawaited(() async {
        final systemMultiWindowActive =
            await PlayerHostBridge.isSystemMultiWindowActive();
        if (!mounted) return;
        if (systemMultiWindowActive) {
          widget.onParallelLayoutModeChanged?.call('fullscreen');
          return;
        }
        if (!_isLandscapeViewport()) {
          await _setPlayerOrientationMode('landscape');
        }
      }());
    }
    unawaited(_applySystemUiForOrientation(isLandscape, force: true));
    if (_uiController.orientationChangeInProgress) {
      _completeOrientationTransitionAfterMetrics();
      return;
    }
    unawaited(_controller.refreshState());
  }

  @override
  void dispose() {
    _invalidateNextEpisodePreload();
    _invalidateEpisodePickerSeasonCache(clearCurrentItems: true);
    widget.onBackActionHandlerChanged?.call(null);
    _unregisterBackDismissHandlers(widget.backDismissManager);
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    _controlsTimer?.cancel();
    _playerSystemStatusTimer?.cancel();
    _statusMessageTimer?.cancel();
    _subtitleSwitchOverlayTimer?.cancel();
    _deferredSubtitleSelectionTimer?.cancel();
    _videoLoadingOverlayTimer?.cancel();
    _performanceOverlayTimer?.cancel();
    _chapterRetryTimer?.cancel();
    _centerPopupTimer?.cancel();
    _initialSourceLoadTimer?.cancel();
    _nativeDanmakuSyncTimer?.cancel();
    _danmakuController.removeListener(_handleDanmakuControllerChanged);
    _controller.danmakuOcclusionState.removeListener(
      _handleDanmakuOcclusionStateChanged,
    );
    _controller.value.removeListener(_handlePlayerValueChanged);
    _completionController.removeListener(_handleOverlayControllersChanged);
    _gestureTapCoordinator.dispose();
    if (_playStatsCurrentVideoId.isNotEmpty) {
      _playStatsCurrentVideoId = '';
      unawaited(_playStatsSessionController.finishPlayback(reason: 'dispose'));
    }
    unawaited(_stopSystemPlaybackSession());
    unawaited(PlayerSystemSessionBridge.unregisterCommandHandler(this));
    unawaited(_flushPlaybackRecordOnExit());
    final tempRoot = Directory.systemTemp.path.replaceAll('\\', '/');
    for (final path in _subtitleFileByGuid.values.toSet()) {
      final normalizedPath = path.replaceAll('\\', '/');
      if (!normalizedPath.startsWith(tempRoot)) continue;
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
    unawaited(_setPlayerImmersiveMode(false));
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
        unawaited(_refreshPlayerSystemStatus());
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

  void _registerBackDismissHandlers(BackDismissManager? manager) {
    if (manager == null) return;
    manager.register(
      id: _backDismissUiLockId,
      priority: 130,
      handler: _dismissUiLockIfNeeded,
    );
    manager.register(
      id: _backDismissSpeedDialId,
      priority: 100,
      handler: _dismissSpeedDialOverlayIfNeeded,
    );
    manager.register(
      id: _backDismissChapterSkipId,
      priority: 90,
      handler: _dismissChapterSkipPromptIfNeeded,
    );
    manager.register(
      id: _backDismissAutoPlayPromptId,
      priority: 80,
      handler: _dismissAutoPlayPromptIfNeeded,
    );
    manager.register(
      id: _backDismissPlaybackCompletedId,
      priority: 70,
      handler: _dismissPlaybackCompletedOverlayIfNeeded,
    );
    manager.register(
      id: _backDismissResumePromptId,
      priority: 60,
      handler: _dismissResumePromptIfNeeded,
    );
    manager.register(
      id: _backDismissRouteOverlayId,
      priority: 10,
      handler: _dismissOverlayRouteIfNeeded,
    );
  }

  void _unregisterBackDismissHandlers(BackDismissManager? manager) {
    if (manager == null) return;
    manager.unregister(_backDismissUiLockId);
    manager.unregister(_backDismissSpeedDialId);
    manager.unregister(_backDismissChapterSkipId);
    manager.unregister(_backDismissAutoPlayPromptId);
    manager.unregister(_backDismissPlaybackCompletedId);
    manager.unregister(_backDismissResumePromptId);
    manager.unregister(_backDismissRouteOverlayId);
  }

  Future<bool> _dismissSpeedDialOverlayIfNeeded() async {
    if (!_speedDialVisible) return false;
    _hideSpeedDialOverlay();
    return true;
  }

  Future<bool> _dismissUiLockIfNeeded() async {
    if (!_playerUiLocked) return false;
    await _unlockPlayerUi();
    return true;
  }

  Future<bool> _dismissChapterSkipPromptIfNeeded() async {
    if (_uiController.activeChapterSkipPrompt == null) return false;
    _dismissCurrentChapterSkipPrompt();
    return true;
  }

  Future<bool> _dismissAutoPlayPromptIfNeeded() async {
    if (!_completionController.autoPlayPromptVisible) return false;
    _cancelAutoPlayPrompt();
    return true;
  }

  Future<bool> _dismissPlaybackCompletedOverlayIfNeeded() async {
    if (!_playbackCompleted) return false;
    _clearPlaybackCompletionState();
    _overlayState.showControls();
    _overlayState.cancelAutoHide();
    return true;
  }

  Future<bool> _dismissResumePromptIfNeeded() async {
    if (!_overlayState.resumePromptVisible) return false;
    _setResumePromptVisibility(false);
    _scheduleControlsAutoHide();
    return true;
  }

  Future<bool> _dismissOverlayRouteIfNeeded() async {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true) return false;
    return Navigator.of(context).maybePop();
  }

  Future<bool> _dismissActiveTransientUi() async {
    final manager = widget.backDismissManager;
    if (manager != null) {
      return manager.dismissActive();
    }
    if (await _dismissSpeedDialOverlayIfNeeded()) return true;
    if (await _dismissChapterSkipPromptIfNeeded()) return true;
    if (await _dismissAutoPlayPromptIfNeeded()) return true;
    if (await _dismissPlaybackCompletedOverlayIfNeeded()) return true;
    if (await _dismissResumePromptIfNeeded()) return true;
    return _dismissOverlayRouteIfNeeded();
  }

  Future<void> _handleBackAction() async {
    if (await _dismissUiLockIfNeeded()) {
      return;
    }
    if (await _dismissActiveTransientUi()) {
      return;
    }
    await _closePlayer();
  }

  void _updatePlayerState(VoidCallback update) {
    if (!mounted) return;
    if (_uiTransientOverlayVisible) {
      update();
    } else {
      setState(update);
    }
    _syncVideoLoadingOverlayVisibility();
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
