import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/feiniu_api.dart';
import '../controllers/play_detail_data_loader.dart';
import '../models/media_library_item.dart';
import '../models/play_info.dart';
import '../models/playback_stream.dart';
import '../models/remote_subtitle.dart';
import '../models/stream_track_data.dart';
import '../providers/nas_provider.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/media_language_mapper.dart';
import '../utils/media_locale_store.dart';
import '../utils/play_detail_track_selector.dart';
import 'episode_picker_presenter.dart';
import 'episode_picker_sheet.dart';
import 'mpv_player_controller.dart';
import 'mpv_proxy_server.dart';
import 'mpv_player_widgets.dart';
import 'player_backdrop_image.dart';
import 'player_completion_controller.dart';
import 'player_gesture_controller.dart';
import 'player_gesture_overlay.dart';
import 'player_nested_sheet.dart';
import 'player_option_sheet.dart';
import 'player_overlay_sections.dart';
import 'player_overlay_state.dart';
import 'player_source_controller.dart';
import 'player_system_controls.dart';

part 'mpv_player_episode_mixin.dart';
part 'mpv_player_options_mixin.dart';
part 'mpv_player_playback_feedback_mixin.dart';
part 'mpv_player_runtime_mixin.dart';
part 'mpv_player_settings_drawer_mixin.dart';
part 'mpv_player_settings_widgets.dart';
part 'mpv_player_subtitle_drawer_mixin.dart';
part 'mpv_player_source_mixin.dart';
part 'mpv_player_view_mixin.dart';

class MpvPlayerPage extends StatefulWidget {
  final String title;
  final MpvMediaSource source;

  const MpvPlayerPage({super.key, required this.title, required this.source});

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
  static const String _decoderModePrefKey = 'player_decoder_mode';
  static const String _displayAspectRatioPrefKey =
      'player_display_aspect_ratio';
  static const String _introOutroEnabledPrefKey = 'player_intro_outro_enabled';
  static const String _introOutroSourceModePrefKey =
      'player_intro_outro_source_mode';
  static const String _introOutroChapterModePrefKey =
      'player_intro_outro_chapter_mode';
  static const String _introOutroIntroMaxPrefKey =
      'player_intro_outro_intro_max_seconds';
  static const String _introOutroOutroMaxPrefKey =
      'player_intro_outro_outro_max_seconds';
  static const String _decoderModeHardware = 'hardware';
  static const String _decoderModeSoftware = 'software';
  static const String _displayAspectRatioFit = 'fit';
  static const String _displayAspectRatioFill = 'fill';
  static const String _displayAspectRatio4x3 = '4:3';
  static const String _displayAspectRatio16x9 = '16:9';
  static const String _displayAspectRatio21x9 = '21:9';
  static const String _introOutroModeAuto = 'auto';
  static const String _introOutroModeChapter = 'chapter';
  static const String _introOutroModeManual = 'manual';
  static const String _introOutroSourceModeOff = 'off';
  static const String _introOutroSourceModeOfficial = 'official';
  static const String _introOutroSourceModeChapter = 'chapter';
  static const String _chapterSkipModeAuto = 'auto';
  static const String _chapterSkipModeManual = 'manual';
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
  final PlayerSourceController _sourceController =
      const PlayerSourceController();
  final Map<String, String> _subtitleFileByGuid = <String, String>{};
  final Set<String> _serverFallbackSubtitleGuids = <String>{};
  final Set<String> _subtitleFailureNoticeShownGuids = <String>{};
  final Map<String, Timer> _proxyReleaseTimers = <String, Timer>{};
  final Set<String> _dismissedChapterSkipKeys = <String>{};
  final Set<String> _completedChapterSkipKeys = <String>{};

  Timer? _recordTimer;
  Timer? _controlsTimer;
  Timer? _statusMessageTimer;
  Timer? _subtitleSwitchOverlayTimer;
  Timer? _deferredSubtitleSelectionTimer;
  Timer? _videoLoadingOverlayTimer;
  Timer? _chapterRetryTimer;
  Timer? _centerPopupTimer;
  NasProvider? _nasProvider;
  bool _subtitleLoading = false;
  bool _subtitleSelectionRefreshInFlight = false;
  bool _controlsVisible = true;
  bool _controlsAnimatingOut = false;
  bool _resumeAfterLifecyclePause = false;
  bool _orientationChangeInProgress = false;
  bool _orientationTransitionMaskVisible = false;
  bool _episodeListLoading = false;
  bool _exitInProgress = false;
  bool _autoPlayEnabled = true;
  bool _autoRotateEnabled = true;
  bool _serverPlaybackManaged = false;
  bool _pendingSubtitleSelectionRefresh = false;
  bool _pendingReloadAutoplayRefresh = false;
  bool _qualitySwitchLoading = false;
  bool _videoLoadingOverlayVisible = false;
  bool _introOutroEnabled = false;
  bool _introOutroConfigLoaded = false;
  bool _introOutroSkipInFlight = false;
  bool _watchedMarkedForCurrentItem = false;
  bool _wasPaused = true;
  bool _chapterLoading = false;
  int _lastRecordedSecond = -1;
  int _skipPromptCountdownSeconds = 0;
  int? _introChapterIndex;
  int? _outroChapterIndex;
  int _officialIntroDurationSeconds = 0;
  int _officialOutroDurationSeconds = 0;
  int _introDurationSeconds = 180;
  int _outroDurationSeconds = 180;
  Duration? _draggingPosition;
  _ChapterSkipSegment? _inferredIntroSkip;
  _ChapterSkipSegment? _inferredOutroSkip;
  _ChapterSkipSegment? _activeChapterSkipPrompt;
  String? _pendingExternalSubtitlePath;
  String? _centerPopupMessage;
  String? _statusMessage;
  String? _subtitleSwitchMessage;
  String? _subtitleDeletingGuid;
  String _subtitleSearchLanguage = 'zh-CN';
  String? _subtitleSearchLoadingLanguage;
  String? _subtitleDownloadTrimId;
  String _decoderMode = _decoderModeHardware;
  String _displayAspectRatioMode = _displayAspectRatioFit;
  String _introOutroSourceMode = _introOutroSourceModeOff;
  String _chapterSkipMode = _chapterSkipModeAuto;
  String _introOutroMode = _introOutroModeAuto;
  String _introOutroConfigGuid = '';
  String _chapterMediaGuid = '';
  String _currentPosterPath = '';

  late String _currentItemGuid;
  late String _currentTitle;
  late String _currentSeasonGuid;
  late int _currentEpisodeNumber;
  late String _currentMediaGuid;
  late String _subtitleSourceMediaGuid;
  late String _currentVideoGuid;
  late int _currentVideoWidth;
  late int _currentVideoHeight;
  late String _currentVideoCodecName;
  late String _currentVideoProfile;
  late String _currentColorSpace;
  late String _currentColorTransfer;
  late String _currentColorPrimaries;
  late int _currentBitDepth;
  late String? _activeProxySessionId;
  late String? _activeSubtitleProxySessionId;
  late String? _currentPlayLink;
  late String _currentUrl;
  late Map<String, String> _currentHeaders;
  late bool _currentReliableSeek;
  late String? _currentSeekProbeSummary;
  late String? _currentAudioGuid;
  late String? _currentSubtitleGuid;
  late String _currentResolution;
  late int _currentBitrate;
  late int _durationSeconds;
  late double _playbackSpeed;
  late Duration _resumeStartPosition;
  late List<AudioTrackOption> _audioTracks;
  late List<SubtitleTrackOption> _subtitleTracks;
  late List<PlaybackQualityOption> _qualities;
  List<MediaLibraryItem> _episodeItems = const <MediaLibraryItem>[];
  List<MpvChapterItem> _chapters = const <MpvChapterItem>[];
  List<RemoteSubtitleSearchItem> _subtitleSearchResults =
      const <RemoteSubtitleSearchItem>[];
  double _subtitleDelaySeconds = 0;
  double _subtitlePositionFactor = 0;
  double _subtitleScaleFactor =
      (1.0 - _subtitleScaleMin) / (_subtitleScaleMax - _subtitleScaleMin);

  bool get _gestureSeekActive => _gestureController.gestureSeekActive;
  bool get _isSeekDragging =>
      _draggingPosition != null || _gestureController.isSeekDragging;
  bool get _speedBoostActive => _gestureController.speedBoostActive;
  bool get _autoPlayPromptVisible =>
      _completionController.autoPlayPromptVisible;
  bool get _playbackCompleted => _completionController.playbackCompleted;
  bool get _completionActionInFlight =>
      _completionController.completionActionInFlight;
  int get _autoPlayCountdownSeconds =>
      _completionController.autoPlayCountdownSeconds;
  PlayerAdjustmentOverlayData? get _gestureOverlayData =>
      _gestureController.gestureOverlayData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateFromSource(widget.source);
    unawaited(_gestureController.primeSystemSnapshot());
    unawaited(_loadAutoPlayPreference());
    unawaited(_loadAutoRotatePreference());
    unawaited(_loadDecoderModePreference());
    unawaited(_loadDisplayAspectRatioPreference());
    unawaited(_loadIntroOutroPreferences());
    _controller.value.addListener(_handlePlayerValueChanged);
    _recordTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_submitPlaybackRecord()),
    );
    _scheduleControlsAutoHide();
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
  void didChangeMetrics() {
    if (!mounted) return;
    final isLandscape = _isLandscapeViewport();
    unawaited(_applySystemUiForOrientation(isLandscape));
    if (_orientationChangeInProgress) {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        unawaited(_controller.refreshState());
        _showControls();
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          setState(() {
            _orientationChangeInProgress = false;
            _orientationTransitionMaskVisible = false;
          });
        });
      });
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
    _chapterRetryTimer?.cancel();
    _centerPopupTimer?.cancel();
    _controller.value.removeListener(_handlePlayerValueChanged);
    unawaited(_submitPlaybackRecord(force: true));
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
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _completionController.dispose();
    _gestureController.dispose();
    _overlayState.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (_orientationChangeInProgress) {
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
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        final playing = !_controller.value.value.paused;
        _resumeAfterLifecyclePause = playing;
        if (playing) {
          unawaited(_controller.pause());
        }
      case AppLifecycleState.detached:
        _resumeAfterLifecyclePause = false;
    }
  }

  @override
  Widget build(BuildContext context) {
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

    return _buildAndroidPlayerScaffold(context);
  }
}
