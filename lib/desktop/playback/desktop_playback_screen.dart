import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../danmaku/models/danmaku_comment.dart';
import '../../danmaku/models/danmaku_settings.dart';
import '../../danmaku/settings/danmaku_settings_store.dart';
import '../../media_backend/playback/media_session_reload.dart';
import '../../models/playback_stream.dart';
import '../../playback/bookmarks/bookmark_store.dart';
import '../../playback/playback_source.dart';
import '../../playback/settings/mpv_settings_store.dart';
import '../../services/native_danmaku_prefetch.dart';
import 'desktop_danmaku_overlay.dart';
import 'desktop_mpv_runtime.dart';
import 'desktop_player_controls.dart';
import 'desktop_player_panels.dart';

const Duration _controlsHideDelay = Duration(milliseconds: 2800);
const Duration _controlsAnimationDuration = Duration(milliseconds: 220);

typedef DesktopResolvedEpisode = ({
  MpvMediaSource source,
  String? danmakuFilePath,
});

enum _PlayerHoverOverlayKind {
  speed,
  episodes,
  quality,
  subtitle,
  audio,
  settings,
}

/// Windows 桌面正式播放页。
///
/// 桌面媒体播放页：播放状态由 media_kit 持有，页面只负责桌面控制层和面板。
class DesktopPlaybackScreen extends StatefulWidget {
  const DesktopPlaybackScreen({
    super.key,
    required this.source,
    this.episodes,
    this.resolveEpisode,
    this.reloadSource,
    this.danmakuFilePath,
  });

  final MpvMediaSource source;
  final List<Map<String, dynamic>>? episodes;
  final Future<DesktopResolvedEpisode?> Function(Map<String, dynamic> episode)?
  resolveEpisode;
  final Future<MpvMediaSource?> Function(
    MpvMediaSource current,
    MediaSessionReloadIntent intent,
  )?
  reloadSource;
  final String? danmakuFilePath;

  @override
  State<DesktopPlaybackScreen> createState() => _DesktopPlaybackScreenState();
}

class _DesktopPlaybackScreenState extends State<DesktopPlaybackScreen> {
  static const String _autoPlayPrefKey = 'player_auto_play_enabled';
  static const String _nextEpisodePreloadPrefKey =
      'player_next_episode_preload_enabled';
  static const String _aspectRatioPrefKey = 'player_display_aspect_ratio';
  static const String _decoderModePrefKey = 'player_decoder_mode';
  static const String _cacheSizePrefKey = 'player_mpv_setting_cache_size_mb';

  late final Player _player;
  late final VideoController _videoController;
  late final FocusNode _focusNode;
  late MpvMediaSource _source;
  late final StreamSubscription<String> _errorSubscription;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<double> _volumeSubscription;
  late final StreamSubscription<bool> _bufferingSubscription;
  late final StreamSubscription<bool> _completedSubscription;

  Timer? _controlsHideTimer;
  Timer? _hoverOpenTimer;
  Timer? _hoverCloseTimer;
  Timer? _hoverClearTimer;
  Timer? _resumePromptTimer;
  Timer? _autoNextTimer;
  Timer? _toastTimer;
  String? _errorMessage;
  String? _toastMessage;
  bool _isLoading = true;
  bool _isBuffering = false;
  bool _isPlaying = false;
  bool _controlsVisible = true;
  bool _hoverOverlayVisible = false;
  _PlayerHoverOverlayKind? _hoverOverlayKind;
  Rect _hoverOverlayAnchor = Rect.zero;
  bool _takingScreenshot = false;
  bool _showResumePrompt = false;
  bool _playbackCompleted = false;
  int _autoNextSeconds = 0;
  bool _autoPlayEnabled = true;
  bool _nextEpisodePreloadEnabled = false;
  double _volume = 100;
  double _lastAudibleVolume = 100;
  double _playbackRate = 1;
  BoxFit _fit = BoxFit.contain;
  String _aspectRatioMode = 'fit';
  String _decoderMode = 'hardware';
  int _cacheSizeMb = 0;
  DanmakuSettings _danmakuSettings = DanmakuSettings.defaults;
  List<DanmakuComment> _danmakuComments = const <DanmakuComment>[];
  String _danmakuSourceLabel = '';
  bool _danmakuLoading = false;
  int _danmakuLoadGeneration = 0;
  Map<String, String> _mpvSettings = Map<String, String>.from(
    MpvSettingsCatalog.defaults,
  );
  Map<String, double> _videoAdjustments = Map<String, double>.from(
    MpvSettingsCatalog.videoAdjustmentDefaults,
  );
  double _audioDelaySeconds = 0;
  final BookmarkStore _bookmarkStore = const BookmarkStore();
  final DanmakuSettingsStore _danmakuSettingsStore =
      const DanmakuSettingsStore();
  final MpvSettingsStore _mpvSettingsStore = const MpvSettingsStore();
  List<PlayerBookmarkEntry> _bookmarks = const <PlayerBookmarkEntry>[];
  DesktopResolvedEpisode? _preloadedNextSource;
  String _preloadedNextItemGuid = '';

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _focusNode = FocusNode(debugLabel: 'desktop-playback');
    MediaKit.ensureInitialized();
    _player = Player();
    _videoController = VideoController(_player);
    _playbackRate = _validPlaybackRate(_source.playbackSpeed);
    _volume = _player.state.volume;
    if (_volume > 0) _lastAudibleVolume = _volume;

    _errorSubscription = _player.stream.error.listen((_) {
      if (!mounted) return;
      _showGenericError(_l10n.desktopPlaybackErrorGeneric);
    });
    _playingSubscription = _player.stream.playing.listen(_onPlayingChanged);
    _volumeSubscription = _player.stream.volume.listen(_onVolumeChanged);
    _bufferingSubscription = _player.stream.buffering.listen(
      _onBufferingChanged,
    );
    _completedSubscription = _player.stream.completed.listen(
      _onCompletedChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _focusNode.requestFocus();
      await _loadDesktopPreferences();
      if (!mounted) return;
      await _loadBookmarks();
      if (!mounted) return;
      await _openSource();
    });
  }

  @override
  void dispose() {
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
    unawaited(_player.dispose());
    _focusNode.dispose();
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
    final cacheRaw = prefs.getString(_cacheSizePrefKey) ?? 'auto';
    final cacheSize = int.tryParse(cacheRaw) ?? 0;
    if (!mounted) return;
    setState(() {
      _autoPlayEnabled = prefs.getBool(_autoPlayPrefKey) ?? true;
      _nextEpisodePreloadEnabled =
          prefs.getBool(_nextEpisodePreloadPrefKey) ?? false;
      _aspectRatioMode = normalizedAspect;
      _fit = normalizedAspect == 'fill' ? BoxFit.cover : BoxFit.contain;
      _decoderMode = decoder == 'software' ? 'software' : 'hardware';
      _cacheSizeMb = cacheSize > 0 ? cacheSize : 0;
      _danmakuSettings = danmakuSettings;
      _mpvSettings = mpvBundle.settings;
      _videoAdjustments = mpvBundle.videoAdjustments;
    });
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await _bookmarkStore.loadForMedia(
      itemGuid: _source.itemGuid,
      mediaGuid: _source.mediaGuid,
    );
    if (mounted) setState(() => _bookmarks = bookmarks);
  }

  Future<void> _applyDesktopMpvProperties() async {
    await _setMpvProperty(
      'hwdec',
      _decoderMode == 'software' ? 'no' : 'auto-safe',
    );
    await _setMpvProperty('cache', 'auto');
    await _setMpvProperty(
      'demuxer-max-bytes',
      '${(_cacheSizeMb <= 0 ? 150 : _cacheSizeMb) * 1024 * 1024}',
    );
    await _setMpvProperty(
      'video-aspect-override',
      const <String>{'4:3', '16:9', '21:9'}.contains(_aspectRatioMode)
          ? _aspectRatioMode
          : 'no',
    );
    for (final entry in _videoAdjustments.entries) {
      await _setMpvProperty(entry.key, entry.value.toStringAsFixed(0));
    }
    await _applyDesktopAudioProperties();
    await _setMpvProperty('audio-delay', _audioDelaySeconds.toStringAsFixed(1));
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
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(name, value);
    }
  }

  Future<bool> _loadDanmakuForSource(
    String? preferredPath, {
    String sourceLabel = '',
  }) async {
    final generation = ++_danmakuLoadGeneration;
    if (mounted) {
      setState(() {
        _danmakuLoading = true;
        _danmakuComments = const <DanmakuComment>[];
        _danmakuSourceLabel = '';
      });
    }
    try {
      var path = preferredPath?.trim() ?? '';
      if (path.isEmpty) {
        path =
            await NativeDanmakuPrefetch.resolveToFile(
              seriesTitle: _source.seriesTitle,
              itemTitle: _source.title,
              seasonNumber: _source.seasonNumber,
              episodeNumber: _source.episodeNumber,
              tmdbId: _source.tmdbId,
              settings: _danmakuSettings,
              itemGuid: _source.itemGuid,
              mediaGuid: _source.mediaGuid,
              seasonGuid: _source.seasonGuid,
            ) ??
            '';
      }
      if (path.isEmpty) return false;
      final payload = await DesktopDanmakuPayload.load(path);
      if (!mounted || generation != _danmakuLoadGeneration) return false;
      setState(() {
        _danmakuComments = payload.comments;
        _danmakuSourceLabel = sourceLabel.trim().isNotEmpty
            ? sourceLabel.trim()
            : payload.sourceLabel;
      });
      return payload.comments.isNotEmpty;
    } catch (_) {
      if (!mounted || generation != _danmakuLoadGeneration) return false;
      setState(() {
        _danmakuComments = const <DanmakuComment>[];
        _danmakuSourceLabel = '';
      });
      return false;
    } finally {
      if (mounted && generation == _danmakuLoadGeneration) {
        setState(() => _danmakuLoading = false);
      }
    }
  }

  Future<void> _updateDanmakuSettings(DanmakuSettings settings) async {
    if (!mounted) return;
    setState(() => _danmakuSettings = settings);
    await _danmakuSettingsStore.save(settings);
    if (settings.enabled && _danmakuComments.isEmpty && !_danmakuLoading) {
      unawaited(_loadDanmakuForSource(null));
    }
  }

  Future<bool> _importDanmakuFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入弹幕文件',
      type: FileType.custom,
      allowedExtensions: const <String>['xml', 'json'],
      lockParentWindow: true,
    );
    final path = result?.files.single.path?.trim() ?? '';
    if (path.isEmpty) return false;
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
    final payloadPath = imported?['danmakuFile']?.toString().trim() ?? '';
    if (payloadPath.isEmpty) {
      _showPlayerMessage('弹幕文件无法识别');
      return false;
    }
    final loaded = await _loadDanmakuForSource(
      payloadPath,
      sourceLabel: result?.files.single.name ?? '',
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
      episodeNumber: _source.episodeNumber,
      seasonNumber: _source.seasonNumber,
      tmdbId: _source.tmdbId,
    );
  }

  Future<bool> _selectSavedDanmakuSource(Map<String, dynamic> source) async {
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
    final path = result?['danmakuFile']?.toString().trim() ?? '';
    if (path.isEmpty) {
      _showPlayerMessage('弹幕源加载失败');
      return false;
    }
    final label = '${source['label'] ?? sourceKey}'.trim();
    final loaded = await _loadDanmakuForSource(path, sourceLabel: label);
    if (loaded) _showPlayerMessage('已切换弹幕源');
    return loaded;
  }

  Future<bool> _selectDanmakuSearchResult(
    Map<String, dynamic> candidate,
  ) async {
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
    if (mounted) setState(() => _videoAdjustments = normalized);
    await _mpvSettingsStore.saveVideoAdjustments(normalized);
    await _setMpvProperty(key, (normalized[key] ?? 0).toStringAsFixed(0));
  }

  Future<void> _setMpvAudioSetting(String key, String value) async {
    if (!MpvSettingsCatalog.audioPresetKeys.contains(key)) return;
    final next = await _mpvSettingsStore.savePatch(<String, String>{
      key: value,
    });
    if (mounted) setState(() => _mpvSettings = next);
    await _applyDesktopAudioProperties(resetVolume: true);
  }

  Future<void> _setAudioDelay(double value) async {
    final normalized = value.clamp(-10.0, 10.0).toDouble();
    if (mounted) setState(() => _audioDelaySeconds = normalized);
    await _setMpvProperty('audio-delay', normalized.toStringAsFixed(1));
  }

  Future<void> _openSource() async {
    _resetPlaybackOverlays();
    if (_source.url.trim().isEmpty) {
      _showGenericError(_l10n.desktopPlaybackErrorSourceUnavailable);
      _finishLoading();
      return;
    }

    try {
      await _applyDesktopMpvProperties();
      await _player.open(
        Media(_source.url, httpHeaders: _source.headers),
        play: false,
      );
      await _applyDesktopMpvProperties();
      await _applyPreferredSubtitle(_source);
      if (_source.startPosition > Duration.zero) {
        await _player.seek(_source.startPosition);
        _showResumeFromPrompt(_source.startPosition);
      }
      await _player.setRate(_playbackRate);
      if (!_source.startPaused) {
        await _player.play();
      }
      unawaited(_loadDanmakuForSource(widget.danmakuFilePath));
      unawaited(_preloadNextEpisodeIfEnabled());
    } catch (_) {
      _showGenericError(_l10n.desktopPlaybackErrorStartFailed);
    } finally {
      _finishLoading();
    }
  }

  Future<void> _openEpisode(Map<String, dynamic> episode) async {
    final resolver = widget.resolveEpisode;
    if (resolver == null) return;
    final episodeGuid = '${episode['itemGuid'] ?? episode['guid'] ?? ''}'
        .trim();
    _resetPlaybackOverlays();
    _wakeControls(scheduleHide: false);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final cached =
          episodeGuid.isNotEmpty && episodeGuid == _preloadedNextItemGuid
          ? _preloadedNextSource
          : null;
      final resolved = cached ?? await resolver(episode);
      if (resolved == null || resolved.source.url.trim().isEmpty) {
        _showGenericError(_l10n.desktopPlaybackErrorEpisodeResolveFailed);
        return;
      }
      _preloadedNextSource = null;
      _preloadedNextItemGuid = '';
      _source = resolved.source;
      _playbackRate = _validPlaybackRate(resolved.source.playbackSpeed);
      await _player.open(
        Media(resolved.source.url, httpHeaders: resolved.source.headers),
      );
      await _applyDesktopMpvProperties();
      await _applyPreferredSubtitle(resolved.source);
      if (resolved.source.startPosition > Duration.zero) {
        await _player.seek(resolved.source.startPosition);
        _showResumeFromPrompt(resolved.source.startPosition);
      }
      await _player.setRate(_playbackRate);
      if (!resolved.source.startPaused) await _player.play();
      unawaited(_loadDanmakuForSource(resolved.danmakuFilePath));
      await _loadBookmarks();
      unawaited(_preloadNextEpisodeIfEnabled());
    } catch (_) {
      _showGenericError(_l10n.desktopPlaybackErrorEpisodeSwitchFailed);
    } finally {
      _finishLoading();
    }
  }

  Future<void> _reloadPlaybackSource({
    String? audioTrackId,
    String? subtitleTrackId,
    bool subtitleDisabled = false,
    int? qualityIndex,
  }) async {
    final resolver = widget.reloadSource;
    if (resolver == null) return;
    final wasPlaying = _isPlaying;
    _wakeControls(scheduleHide: false);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final resolved = await resolver(
        _source,
        MediaSessionReloadIntent(
          audioTrackId: audioTrackId,
          subtitleTrackId: subtitleTrackId,
          subtitleDisabled: subtitleDisabled,
          qualityIndex: qualityIndex,
          startPosition: _player.state.position,
        ),
      );
      if (resolved == null || resolved.url.trim().isEmpty) {
        _showGenericError(
          qualityIndex == null
              ? _l10n.desktopPlaybackErrorTrackSwitchFailed
              : _l10n.nativePlayerSwitchQualityUnavailable,
        );
        return;
      }
      _source = resolved;
      await _player.open(
        Media(resolved.url, httpHeaders: resolved.headers),
        play: false,
      );
      await _applyDesktopMpvProperties();
      await _applyPreferredSubtitle(resolved);
      if (resolved.startPosition > Duration.zero) {
        await _player.seek(resolved.startPosition);
      }
      await _player.setRate(_playbackRate);
      if (wasPlaying) await _player.play();
    } catch (_) {
      _showGenericError(
        qualityIndex == null
            ? _l10n.desktopPlaybackErrorTrackSwitchFailed
            : _l10n.nativePlayerSwitchQualityUnavailable,
      );
    } finally {
      _finishLoading();
      _focusNode.requestFocus();
    }
  }

  double _validPlaybackRate(double value) {
    return value.isFinite && value > 0 ? value : 1;
  }

  Future<void> _applyPreferredSubtitle(MpvMediaSource source) async {
    final selectedGuid = source.subtitleTrackGuid?.trim() ?? '';
    if (selectedGuid.isEmpty) return;
    final path = source.localSubtitleFiles[selectedGuid]?.trim() ?? '';
    if (path.isEmpty) return;
    String? title;
    String? language;
    for (final track in source.subtitleTracks) {
      if (track.guid != selectedGuid) continue;
      title = track.title.trim().isEmpty ? null : track.title.trim();
      language = track.language.trim().isEmpty ? null : track.language.trim();
      break;
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
    if (mounted) setState(() => _isLoading = false);
  }

  void _showGenericError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _onPlayingChanged(bool playing) {
    if (!mounted) return;
    setState(() {
      _isPlaying = playing;
      if (!playing) _controlsVisible = true;
    });
    if (playing) {
      _scheduleControlsHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  void _onVolumeChanged(double volume) {
    if (!mounted) return;
    setState(() {
      _volume = volume.clamp(0.0, 100.0).toDouble();
      if (_volume > 0) _lastAudibleVolume = _volume;
    });
  }

  void _onBufferingChanged(bool buffering) {
    if (!mounted || _isBuffering == buffering) return;
    setState(() => _isBuffering = buffering);
  }

  void _onCompletedChanged(bool completed) {
    if (!mounted || !completed || _playbackCompleted) return;
    _controlsHideTimer?.cancel();
    _resumePromptTimer?.cancel();
    setState(() {
      _playbackCompleted = true;
      _controlsVisible = false;
      _showResumePrompt = false;
    });
    _startAutoNextCountdown();
  }

  void _resetPlaybackOverlays() {
    _resumePromptTimer?.cancel();
    _autoNextTimer?.cancel();
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _playbackCompleted = false;
      _autoNextSeconds = 0;
      _showResumePrompt = false;
      _toastMessage = null;
    });
  }

  void _showResumeFromPrompt(Duration position) {
    if (!mounted || position < const Duration(seconds: 10)) return;
    _resumePromptTimer?.cancel();
    setState(() => _showResumePrompt = true);
    _resumePromptTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showResumePrompt = false);
    });
  }

  void _dismissResumePrompt() {
    _resumePromptTimer?.cancel();
    if (mounted) setState(() => _showResumePrompt = false);
  }

  Future<void> _restartFromBeginning() async {
    _dismissResumePrompt();
    await _player.seek(Duration.zero);
    if (!_isPlaying) await _player.play();
  }

  void _startAutoNextCountdown() {
    _autoNextTimer?.cancel();
    if (!_autoPlayEnabled || _nextEpisode == null) {
      if (mounted) setState(() => _autoNextSeconds = 0);
      return;
    }
    setState(() => _autoNextSeconds = 8);
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoNextSeconds <= 1) {
        timer.cancel();
        setState(() => _autoNextSeconds = 0);
        unawaited(_showNextEpisode());
        return;
      }
      setState(() => _autoNextSeconds -= 1);
    });
  }

  void _cancelAutoNext() {
    _autoNextTimer?.cancel();
    if (mounted) setState(() => _autoNextSeconds = 0);
  }

  Future<void> _replayCompleted() async {
    _autoNextTimer?.cancel();
    setState(() {
      _playbackCompleted = false;
      _autoNextSeconds = 0;
      _controlsVisible = true;
    });
    await _player.seek(Duration.zero);
    await _player.play();
  }

  void _wakeControls({bool scheduleHide = true}) {
    if (_hoverOverlayKind != null) scheduleHide = false;
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    _controlsHideTimer?.cancel();
    if (scheduleHide && _isPlaying) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(_controlsHideDelay, () {
      if (mounted && _isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    _wakeControls();
    await _player.playOrPause();
  }

  Future<void> _seekRelative(Duration offset) async {
    _wakeControls();
    var target = _player.state.position.inMicroseconds + offset.inMicroseconds;
    if (target < 0) target = 0;
    final duration = _player.state.duration.inMicroseconds;
    if (duration > 0 && target > duration) target = duration;
    await _player.seek(Duration(microseconds: target));
  }

  Future<void> _seekTo(Duration position) =>
      _player.seek(position < Duration.zero ? Duration.zero : position);

  Future<void> _setVolume(double value) async {
    _wakeControls();
    final next = value.clamp(0.0, 100.0).toDouble();
    setState(() {
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
    setState(() => _playbackRate = value);
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
      if (mounted) _focusNode.requestFocus();
    }
  }

  void _showPlayerMessage(String message) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _cycleFit() {
    _wakeControls();
    unawaited(_setAspectRatioMode(_aspectRatioMode == 'fit' ? 'fill' : 'fit'));
  }

  Future<void> _setAutoPlayEnabled(bool value) async {
    if (mounted) {
      setState(() {
        _autoPlayEnabled = value;
        if (!value) {
          _nextEpisodePreloadEnabled = false;
          _preloadedNextSource = null;
          _preloadedNextItemGuid = '';
        }
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPlayPrefKey, value);
  }

  Future<void> _setNextEpisodePreloadEnabled(bool value) async {
    if (!_autoPlayEnabled && value) return;
    if (mounted) setState(() => _nextEpisodePreloadEnabled = value);
    if (!value) {
      _preloadedNextSource = null;
      _preloadedNextItemGuid = '';
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
      setState(() {
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
    if (mounted) setState(() => _decoderMode = normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_decoderModePrefKey, normalized);
    await _setMpvProperty(
      'hwdec',
      normalized == 'software' ? 'no' : 'auto-safe',
    );
    await _reopenCurrentMedia();
  }

  Future<void> _setCacheSizeMb(int value) async {
    final normalized = value <= 0 ? 0 : value.clamp(64, 1984);
    if (mounted) setState(() => _cacheSizeMb = normalized);
    await _setMpvProperty('cache', 'auto');
    await _setMpvProperty(
      'demuxer-max-bytes',
      '${(normalized <= 0 ? 150 : normalized) * 1024 * 1024}',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheSizePrefKey,
      normalized <= 0 ? 'auto' : '$normalized',
    );
  }

  Future<void> _reopenCurrentMedia() async {
    if (_source.url.trim().isEmpty || _isLoading) return;
    final position = _player.state.position;
    final wasPlaying = _isPlaying;
    _wakeControls(scheduleHide: false);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _player.open(
        Media(_source.url, httpHeaders: _source.headers),
        play: false,
      );
      await _applyDesktopMpvProperties();
      await _applyPreferredSubtitle(_source);
      if (position > Duration.zero) await _player.seek(position);
      await _player.setRate(_playbackRate);
      if (wasPlaying) await _player.play();
    } catch (_) {
      _showGenericError(_l10n.desktopPlaybackErrorStartFailed);
    } finally {
      _finishLoading();
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

    final options = <DesktopPlayerPanelOption>[
      if (audio)
        for (var index = 0; index < _player.state.tracks.audio.length; index++)
          DesktopPlayerPanelOption(
            value: _player.state.tracks.audio[index],
            title: _mediaKitAudioTrackTitle(
              _player.state.tracks.audio[index],
              index,
            ),
            selected:
                _player.state.tracks.audio[index] ==
                    _player.state.track.audio ||
                _player.state.tracks.audio[index].id ==
                    _player.state.track.audio.id,
          )
      else
        for (
          var index = 0;
          index < _player.state.tracks.subtitle.length;
          index++
        )
          DesktopPlayerPanelOption(
            value: _player.state.tracks.subtitle[index],
            title: _mediaKitSubtitleTrackTitle(
              _player.state.tracks.subtitle[index],
              index,
            ),
            selected:
                _player.state.tracks.subtitle[index] ==
                    _player.state.track.subtitle ||
                _player.state.tracks.subtitle[index].id ==
                    _player.state.track.subtitle.id,
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
              await _player.setAudioTrack(track as AudioTrack);
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
              await _player.setAudioTrack(track as AudioTrack);
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
    _PlayerHoverOverlayKind kind,
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
      setState(() {
        _hoverOverlayKind = kind;
        _hoverOverlayAnchor = anchor;
        _hoverOverlayVisible = true;
      });
    });
  }

  void _scheduleHoverOverlayClose() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = Timer(const Duration(milliseconds: 210), () {
      if (!mounted || _hoverOverlayKind == null) return;
      setState(() => _hoverOverlayVisible = false);
      _hoverClearTimer?.cancel();
      _hoverClearTimer = Timer(const Duration(milliseconds: 190), () {
        if (!mounted || _hoverOverlayVisible) return;
        setState(() => _hoverOverlayKind = null);
        _wakeControls();
      });
    });
  }

  void _keepHoverOverlayOpen() {
    _hoverCloseTimer?.cancel();
    _hoverClearTimer?.cancel();
    if (mounted && _hoverOverlayKind != null && !_hoverOverlayVisible) {
      setState(() => _hoverOverlayVisible = true);
    }
    _wakeControls(scheduleHide: false);
  }

  void _dismissHoverOverlay() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _hoverClearTimer?.cancel();
    final closingKind = _hoverOverlayKind;
    if (!mounted || closingKind == null) return;
    setState(() => _hoverOverlayVisible = false);
    _hoverClearTimer = Timer(const Duration(milliseconds: 190), () {
      if (!mounted ||
          _hoverOverlayVisible ||
          _hoverOverlayKind != closingKind) {
        return;
      }
      setState(() => _hoverOverlayKind = null);
      _wakeControls();
    });
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
      return <DesktopPlayerPanelOption>[
        for (var index = 0; index < _player.state.tracks.audio.length; index++)
          DesktopPlayerPanelOption(
            value: _player.state.tracks.audio[index],
            title: _mediaKitAudioTrackTitle(
              _player.state.tracks.audio[index],
              index,
            ),
            selected:
                _player.state.tracks.audio[index] ==
                    _player.state.track.audio ||
                _player.state.tracks.audio[index].id ==
                    _player.state.track.audio.id,
          ),
      ];
    }
    return <DesktopPlayerPanelOption>[
      for (var index = 0; index < _player.state.tracks.subtitle.length; index++)
        DesktopPlayerPanelOption(
          value: _player.state.tracks.subtitle[index],
          title: _mediaKitSubtitleTrackTitle(
            _player.state.tracks.subtitle[index],
            index,
          ),
          selected:
              _player.state.tracks.subtitle[index] ==
                  _player.state.track.subtitle ||
              _player.state.tracks.subtitle[index].id ==
                  _player.state.track.subtitle.id,
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
        await _player.setAudioTrack(option.value as AudioTrack);
      } else {
        await _player.setSubtitleTrack(option.value as SubtitleTrack);
      }
    } catch (_) {
      _showGenericError(_l10n.desktopPlaybackErrorTrackSwitchFailed);
    }
  }

  Future<void> _disableHoverSubtitle() async {
    _dismissHoverOverlay();
    if (_source.serverPlaybackManaged && widget.reloadSource != null) {
      await _reloadPlaybackSource(subtitleDisabled: true);
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  List<DesktopPlayerPanelOption> _hoverQualityOptions() {
    return <DesktopPlayerPanelOption>[
      for (var index = 0; index < _source.qualities.length; index++)
        DesktopPlayerPanelOption(
          value: index,
          title: _qualityTitle(_source.qualities[index]),
          subtitle: _qualitySubtitle(_source.qualities[index]),
          selected: _isCurrentQuality(_source.qualities[index]),
        ),
    ];
  }

  Widget _buildHoverOverlayLayer() {
    final kind = _hoverOverlayKind;
    if (kind == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          late final Widget content;
          late final double width;
          late final Positioned positioned;
          final isSettings = kind == _PlayerHoverOverlayKind.settings;
          final isEpisodes = kind == _PlayerHoverOverlayKind.episodes;

          switch (kind) {
            case _PlayerHoverOverlayKind.speed:
              width = 164;
              content = _DesktopHoverOptionsPanel(
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
            case _PlayerHoverOverlayKind.quality:
              width = 254;
              content = _DesktopHoverOptionsPanel(
                title: _l10n.nativePlayerQualityPickerTitle,
                options: _hoverQualityOptions(),
                emptyLabel: _l10n.nativePlayerNoQuality,
                onSelected: (option) {
                  _dismissHoverOverlay();
                  unawaited(
                    _reloadPlaybackSource(qualityIndex: option.value as int),
                  );
                },
              );
              break;
            case _PlayerHoverOverlayKind.subtitle:
              width = 254;
              content = _DesktopHoverOptionsPanel(
                title: _l10n.nativePlayerSubtitleTrackPickerTitle,
                options: _hoverTrackOptions(false),
                emptyLabel: _l10n.desktopPlaybackNoSubtitleTracks,
                offLabel: _l10n.nativePlayerTrackOff,
                onOff: () => unawaited(_disableHoverSubtitle()),
                onSelected: (option) =>
                    unawaited(_selectHoverTrack(false, option)),
              );
              break;
            case _PlayerHoverOverlayKind.audio:
              width = 254;
              content = _DesktopHoverOptionsPanel(
                title: _l10n.nativePlayerAudioTrackPickerTitle,
                options: _hoverTrackOptions(true),
                emptyLabel: _l10n.desktopPlaybackNoAudioTracks,
                onSelected: (option) =>
                    unawaited(_selectHoverTrack(true, option)),
              );
              break;
            case _PlayerHoverOverlayKind.episodes:
              width = (size.width * 0.30).clamp(360.0, 430.0).toDouble();
              content = DesktopEpisodePanel(
                title: _source.seriesTitle.trim().isNotEmpty
                    ? '${_source.seriesTitle.trim()} · ${_l10n.playerEpisodeAction}'
                    : _l10n.nativePlayerEpisodePickerTitle,
                emptyLabel: _l10n.desktopPlaybackEpisodesEmpty,
                episodes: widget.episodes ?? const <Map<String, dynamic>>[],
                currentItemGuid: _source.itemGuid,
                seriesTitle: _subtitle,
                onSelected: widget.resolveEpisode == null
                    ? null
                    : (episode) {
                        _dismissHoverOverlay();
                        unawaited(_openEpisode(episode));
                      },
              );
              break;
            case _PlayerHoverOverlayKind.settings:
              width = (size.width * 0.30).clamp(360.0, 410.0).toDouble();
              content = DesktopPlaybackSettingsPanel(
                source: _source,
                position: _player.state.position,
                autoPlayEnabled: _autoPlayEnabled,
                nextEpisodePreloadEnabled: _nextEpisodePreloadEnabled,
                aspectRatioMode: _aspectRatioMode,
                decoderMode: _decoderMode,
                cacheSizeMb: _cacheSizeMb,
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
                onCacheSizeChanged: _setCacheSizeMb,
                onMpvAudioSettingChanged: _setMpvAudioSetting,
                onVideoAdjustmentChanged: _setVideoAdjustment,
                onAudioDelayChanged: _setAudioDelay,
                onAddBookmark: _addBookmark,
                onDeleteBookmark: _deleteBookmark,
                onSelectBookmark: (entry) async {
                  _dismissHoverOverlay();
                  await _selectBookmark(entry);
                },
                onOpenDanmakuSettings: () {
                  _dismissHoverOverlay();
                  unawaited(_showDanmakuSettingsPanel());
                },
                onOpenDanmakuSources: () {
                  _dismissHoverOverlay();
                  unawaited(_showDanmakuSourcePanel());
                },
              );
              break;
          }

          final panel = IgnorePointer(
            ignoring: !_hoverOverlayVisible,
            child: MouseRegion(
              onEnter: (_) => _keepHoverOverlayOpen(),
              onExit: (_) => _scheduleHoverOverlayClose(),
              child: AnimatedOpacity(
                opacity: _hoverOverlayVisible ? 1 : 0,
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                child: AnimatedSlide(
                  offset: _hoverOverlayVisible
                      ? Offset.zero
                      : isSettings || isEpisodes
                      ? const Offset(0.045, 0)
                      : const Offset(0, 0.08),
                  duration: const Duration(milliseconds: 190),
                  curve: Curves.easeOutCubic,
                  child: AnimatedScale(
                    scale: _hoverOverlayVisible ? 1 : 0.975,
                    duration: const Duration(milliseconds: 190),
                    curve: Curves.easeOutCubic,
                    alignment: isSettings || isEpisodes
                        ? Alignment.centerRight
                        : Alignment.bottomCenter,
                    child: _DesktopHoverGlass(
                      squareRightEdge: isSettings,
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          );

          if (isSettings) {
            positioned = Positioned(
              top: 12,
              right: 0,
              bottom: 12,
              width: width,
              child: panel,
            );
          } else if (isEpisodes) {
            positioned = Positioned(
              top: 76,
              right: 20,
              bottom: 84,
              width: width,
              child: panel,
            );
          } else {
            final left = (_hoverOverlayAnchor.center.dx - width / 2).clamp(
              14.0,
              size.width - width - 14,
            );
            final bottom = (size.height - _hoverOverlayAnchor.top + 10).clamp(
              78.0,
              size.height - 150,
            );
            positioned = Positioned(
              left: left.toDouble(),
              bottom: bottom.toDouble(),
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (_hoverOverlayAnchor.top - 86).clamp(
                    160.0,
                    size.height - 180,
                  ),
                ),
                child: panel,
              ),
            );
          }
          return Stack(
            children: <Widget>[
              positioned,
              if (isEpisodes)
                Positioned(
                  right: 20,
                  bottom: 70,
                  width: width,
                  height: 14,
                  child: IgnorePointer(
                    ignoring: !_hoverOverlayVisible,
                    child: MouseRegion(
                      onEnter: (_) => _keepHoverOverlayOpen(),
                      onExit: (_) => _scheduleHoverOverlayClose(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
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
    final title = track.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final language = track.language?.trim() ?? '';
    if (language.isNotEmpty) return language;
    return '${_l10n.nativePlayerTrackGeneric} ${index + 1}';
  }

  String _mediaKitSubtitleTrackTitle(SubtitleTrack track, int index) {
    final title = track.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final language = track.language?.trim() ?? '';
    if (language.isNotEmpty) return language;
    return '${_l10n.nativePlayerTrackGeneric} ${index + 1}';
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
    final currentId = _player.state.track.subtitle.id;
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
          title: title.isNotEmpty
              ? title
              : (language.isNotEmpty
                    ? language
                    : _l10n.nativePlayerTrackGeneric),
          subtitle: language,
          selected: currentId == uri,
        ),
      );
    }
    return options;
  }

  Future<void> _showQualities({Rect? anchor}) async {
    _wakeControls(scheduleHide: false);
    final qualities = _source.qualities;
    if (qualities.isEmpty || widget.reloadSource == null || !mounted) return;
    final options = <DesktopPlayerPanelOption>[
      for (var index = 0; index < qualities.length; index++)
        DesktopPlayerPanelOption(
          value: index,
          title: _qualityTitle(qualities[index]),
          subtitle: _qualitySubtitle(qualities[index]),
          selected: _isCurrentQuality(qualities[index]),
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

  String _qualityTitle(PlaybackQualityOption quality) {
    final resolution = quality.resolution.trim();
    if (quality.isOriginalProxy || resolution.isEmpty) {
      return _l10n.playerQualityOriginal;
    }
    return resolution;
  }

  String _qualitySubtitle(PlaybackQualityOption quality) {
    final parts = <String>[];
    if (quality.sourceFileName.trim().isNotEmpty) {
      parts.add(quality.sourceFileName.trim());
    }
    if (quality.bitrate > 0) {
      parts.add('${(quality.bitrate / 1000000).toStringAsFixed(1)} Mbps');
    }
    return parts.join(' · ');
  }

  bool _isCurrentQuality(PlaybackQualityOption quality) {
    if (_source.playbackMode.isOriginalQuality) {
      return quality.isOriginalProxy || quality.isDefault == 1;
    }
    if (quality.directLinkQualityIndex != null &&
        quality.directLinkQualityIndex == _source.directLinkQualityIndex) {
      return true;
    }
    return quality.resolution.trim() == _source.resolution.trim() &&
        (_source.bitrate <= 0 ||
            quality.bitrate <= 0 ||
            quality.bitrate == _source.bitrate);
  }

  Future<void> _showEpisodes() async {
    _wakeControls(scheduleHide: false);
    final episodes = widget.episodes;
    if (!mounted) return;
    await _showPlayerOverlayPanel(
      float: true,
      builder: (context) => DesktopEpisodePanel(
        title: _source.seriesTitle.trim().isNotEmpty
            ? '${_source.seriesTitle.trim()} · ${_l10n.playerEpisodeAction}'
            : _l10n.nativePlayerEpisodePickerTitle,
        emptyLabel: _l10n.desktopPlaybackEpisodesEmpty,
        episodes: episodes ?? const <Map<String, dynamic>>[],
        currentItemGuid: _source.itemGuid,
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
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return null;
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

  /// 上一集（与 [_nextEpisode] 同一定位规则，向前找一集）。
  Map<String, dynamic>? get _previousEpisode {
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return null;
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

  Future<void> _preloadNextEpisodeIfEnabled() async {
    final resolver = widget.resolveEpisode;
    final episode = _nextEpisode;
    if (!_autoPlayEnabled ||
        !_nextEpisodePreloadEnabled ||
        resolver == null ||
        episode == null) {
      return;
    }
    final itemGuid = '${episode['itemGuid'] ?? episode['guid'] ?? ''}'.trim();
    if (itemGuid.isEmpty ||
        (itemGuid == _preloadedNextItemGuid && _preloadedNextSource != null)) {
      return;
    }
    final currentItemGuid = _source.itemGuid;
    final resolved = await resolver(episode);
    if (!mounted ||
        currentItemGuid != _source.itemGuid ||
        !_nextEpisodePreloadEnabled ||
        resolved == null ||
        resolved.source.url.trim().isEmpty) {
      return;
    }
    _preloadedNextItemGuid = itemGuid;
    _preloadedNextSource = resolved;
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

  Future<void> _showDanmakuSettingsPanel() async {
    _wakeControls(scheduleHide: false);
    if (!mounted) return;
    await _showSidePanel(
      (context) => DesktopDanmakuSettingsPanel(
        settings: _danmakuSettings,
        onChanged: _updateDanmakuSettings,
      ),
    );
  }

  Future<void> _showDanmakuSourcePanel() async {
    _wakeControls(scheduleHide: false);
    if (!mounted) return;
    await _showSidePanel(
      (context) => DesktopDanmakuSourcePanel(
        currentSourceLabel: _danmakuSourceLabel,
        commentCount: _danmakuComments.length,
        loading: _danmakuLoading,
        initialKeyword: _source.seriesTitle.trim().isNotEmpty
            ? _source.seriesTitle
            : _source.title,
        onLoadSavedSources: _loadSavedDanmakuSources,
        onSearch: _searchDanmakuSources,
        onSelectSavedSource: _selectSavedDanmakuSource,
        onSelectSearchResult: _selectDanmakuSearchResult,
        onDeleteSavedSource: _deleteSavedDanmakuSource,
        onImportFile: _importDanmakuFile,
      ),
    );
  }

  Future<void> _showPlaybackSettingsPanel() async {
    _wakeControls(scheduleHide: false);
    if (!mounted) return;
    await _showSidePanel(
      (context) => DesktopPlaybackSettingsPanel(
        source: _source,
        position: _player.state.position,
        autoPlayEnabled: _autoPlayEnabled,
        nextEpisodePreloadEnabled: _nextEpisodePreloadEnabled,
        aspectRatioMode: _aspectRatioMode,
        decoderMode: _decoderMode,
        cacheSizeMb: _cacheSizeMb,
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
        onCacheSizeChanged: _setCacheSizeMb,
        onMpvAudioSettingChanged: _setMpvAudioSetting,
        onVideoAdjustmentChanged: _setVideoAdjustment,
        onAudioDelayChanged: _setAudioDelay,
        onAddBookmark: _addBookmark,
        onDeleteBookmark: _deleteBookmark,
        onSelectBookmark: (entry) async {
          Navigator.of(context).pop();
          await _selectBookmark(entry);
        },
        onOpenDanmakuSettings: () {
          Navigator.of(context).pop();
          unawaited(_showDanmakuSettingsPanel());
        },
        onOpenDanmakuSources: () {
          Navigator.of(context).pop();
          unawaited(_showDanmakuSourcePanel());
        },
      ),
    );
  }

  Future<void> _showSidePanel(WidgetBuilder builder) {
    return _showPlayerOverlayPanel(builder: builder, float: false);
  }

  /// 播放器浮层面板：`float: false` 为右侧全高抽屉（设置/弹幕/轨道），
  /// `float: true` 为选集悬浮卡（.pl-eps：顶栏下方右侧悬浮，底边悬于控制条上方，
  /// 列表/网格双视图由 DesktopEpisodePanel 自带）。
  Future<void> _showPlayerOverlayPanel({
    required WidgetBuilder builder,
    required bool float,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: _l10n.commonClose,
      barrierColor: float ? const Color(0x28000000) : const Color(0x70000000),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: float ? const Offset(0, 0.06) : const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        final size = MediaQuery.sizeOf(context);
        if (float) {
          // 选集悬浮卡：top 对齐顶栏下方、right 24、bottom 悬于控制条上方。
          final width = (size.width * 0.30).clamp(340.0, 430.0).toDouble();
          final bottomGap = (size.height * 0.16).clamp(112.0, 160.0).toDouble();
          return Padding(
            padding: EdgeInsets.only(top: 72, right: 24, bottom: bottomGap),
            child: Align(
              alignment: Alignment.topRight,
              child: Material(
                color: const Color(0x990B111C),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                elevation: 24,
                shadowColor: Colors.black,
                clipBehavior: Clip.antiAlias,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: SizedBox(
                      width: width,
                      height: double.infinity,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(child: builder(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        // 原型设置抽屉固定在约 400px，避免宽屏下膨胀成占据半屏的移动端大面板。
        final width = (size.width * 0.30).clamp(340.0, 400.0).toDouble();
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: const Color(0x990B111C),
            elevation: 28,
            shadowColor: Colors.black,
            shape: const Border(left: BorderSide(color: Color(0x1AFFFFFF))),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: SizedBox(
                  width: width,
                  height: double.infinity,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: builder(context)),
                      Positioned(
                        top: 14,
                        right: 16,
                        child: IconButton(
                          tooltip: _l10n.commonClose,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0x1FFFFFFF),
                            hoverColor: const Color(0x38FFFFFF),
                            fixedSize: const Size.square(36),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0x20FFFFFF)),
                            ),
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
    ).whenComplete(_focusNode.requestFocus);
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
        if (widget.episodes?.isNotEmpty == true)
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
    _focusNode.requestFocus();
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
    if (videoState.isFullscreen()) {
      await videoState.exitFullscreen();
      return;
    }
    if (mounted) await Navigator.of(context).maybePop();
  }

  KeyEventResult _handleKeyEvent(VideoState videoState, KeyEvent event) {
    final isInitialPress = event is KeyDownEvent;
    final isRepeatablePress = isInitialPress || event is KeyRepeatEvent;
    if (!isRepeatablePress) return KeyEventResult.ignored;

    final key = event.logicalKey;
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
          // 使用自建控制层，明确关闭 media_kit 的默认 controls。
          controls: _buildVideoControls,
        ),
      ),
    );
  }

  Widget _buildVideoControls(VideoState videoState) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _handleKeyEvent(videoState, event),
      child: MouseRegion(
        opaque: true,
        cursor: _controlsVisible
            ? SystemMouseCursors.basic
            : SystemMouseCursors.none,
        onEnter: (_) => _wakeControls(scheduleHide: _hoverOverlayKind == null),
        onHover: (_) => _wakeControls(scheduleHide: _hoverOverlayKind == null),
        child: Listener(
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            if (_hoverOverlayKind != null) return;
            final delta = event.scrollDelta.dy < 0 ? 5.0 : -5.0;
            unawaited(_setVolume(_volume + delta));
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focusNode.requestFocus();
              unawaited(_togglePlayback());
            },
            onDoubleTap: () {
              _wakeControls();
              unawaited(videoState.toggleFullscreen());
            },
            onSecondaryTapDown: (details) =>
                unawaited(_showContextMenu(details.globalPosition, videoState)),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _buildStatusLayer(),
                Positioned.fill(
                  child: DesktopDanmakuOverlay(
                    player: _player,
                    comments: _danmakuComments,
                    settings: _danmakuSettings,
                  ),
                ),
                IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: _controlsAnimationDuration,
                    curve: Curves.easeOutCubic,
                    child: DesktopPlayerControls(
                      player: _player,
                      videoState: videoState,
                      title: _source.title,
                      subtitle: _subtitle,
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
                      prevTooltip: _l10n.desktopPlaybackPrevEpisodeTooltip,
                      bookmarkTooltip: _l10n.playerBookmarkAddCurrent,
                      episodeLabel: _l10n.playerEpisodeAction,
                      subtitleLabel:
                          (_source.subtitleTrackGuid ?? '').trim().isEmpty
                          ? _l10n.playerSubtitleOffAction
                          : _l10n.playerSubtitleAction,
                      audioTooltip: _l10n.playerAudioTrackAction,
                      screenshotLabel: _l10n.desktopPlaybackScreenshotAction,
                      danmakuEnabled: _danmakuSettings.enabled,
                      danmakuLabel: _danmakuSettings.enabled
                          ? '弹幕设置 · 已开启'
                          : '弹幕设置 · 已关闭',
                      onBack: () => unawaited(_leavePlayer(videoState)),
                      onToggle: () => unawaited(_togglePlayback()),
                      onSeek: _seekTo,
                      onVolume: (value) => unawaited(_setVolume(value)),
                      onMute: () => unawaited(_toggleMute()),
                      onRate: (value) => unawaited(_setPlaybackRate(value)),
                      onScreenshot: () => unawaited(_captureScreenshot()),
                      onToggleDanmaku: _toggleDanmaku,
                      onSettings: () => unawaited(_showPlaybackSettingsPanel()),
                      onSettingsAt: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.settings,
                        anchor,
                        immediate: true,
                      ),
                      onNext: _nextEpisode == null
                          ? null
                          : () => unawaited(_showNextEpisode()),
                      onPrevious: _previousEpisode == null
                          ? null
                          : () => unawaited(_showPreviousEpisode()),
                      onEpisodes: widget.episodes?.isNotEmpty == true
                          ? () => unawaited(_showEpisodes())
                          : null,
                      onEpisodesAt: widget.episodes?.isNotEmpty == true
                          ? (anchor) => _openHoverOverlay(
                              _PlayerHoverOverlayKind.episodes,
                              anchor,
                              immediate: true,
                            )
                          : null,
                      onAudio: () => unawaited(_showTracks(audio: true)),
                      onSubtitle: () => unawaited(_showTracks(audio: false)),
                      onAudioAt: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.audio,
                        anchor,
                        immediate: true,
                      ),
                      onSubtitleAt: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.subtitle,
                        anchor,
                        immediate: true,
                      ),
                      onQuality:
                          _source.qualities.isEmpty ||
                              widget.reloadSource == null
                          ? null
                          : () => unawaited(_showQualities()),
                      onQualityAt: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.quality,
                        anchor,
                        immediate: true,
                      ),
                      onSpeedAt: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.speed,
                        anchor,
                        immediate: true,
                      ),
                      onHoverSpeed: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.speed,
                        anchor,
                      ),
                      onHoverEpisodes: widget.episodes?.isNotEmpty == true
                          ? (anchor) => _openHoverOverlay(
                              _PlayerHoverOverlayKind.episodes,
                              anchor,
                            )
                          : null,
                      onHoverQuality:
                          _source.qualities.isEmpty ||
                              widget.reloadSource == null
                          ? null
                          : (anchor) => _openHoverOverlay(
                              _PlayerHoverOverlayKind.quality,
                              anchor,
                            ),
                      onHoverSubtitle: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.subtitle,
                        anchor,
                      ),
                      onHoverAudio: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.audio,
                        anchor,
                      ),
                      onHoverSettings: (anchor) => _openHoverOverlay(
                        _PlayerHoverOverlayKind.settings,
                        anchor,
                      ),
                      onHoverExit: _scheduleHoverOverlayClose,
                      onAddBookmark: () => unawaited(_addBookmark()),
                    ),
                  ),
                ),
                _buildHoverOverlayLayer(),
                _buildResumePromptLayer(),
                _buildToastLayer(),
                if (_playbackCompleted)
                  _buildPlaybackCompletedLayer(videoState),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
              decoration: BoxDecoration(
                color: const Color(0xE817202C),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x24FFFFFF)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
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
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE817202C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x24FFFFFF)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x55000000), blurRadius: 20),
                  ],
                ),
                child: Text(
                  message ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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
    final nextEpisode = _nextEpisode;
    final autoNextLabel = _autoNextSeconds > 0
        ? _l10n.playerAutoPlayNextPrompt(_autoNextSeconds)
        : '';
    return Positioned.fill(
      child: Material(
        color: const Color(0xB8000000),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
              decoration: BoxDecoration(
                color: const Color(0xF219222E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x2BFFFFFF)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 46,
                    offset: Offset(0, 22),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0x226EA8FF),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: const Color(0x4D6EA8FF)),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF9CC4FF),
                      size: 31,
                    ),
                  ),
                  const SizedBox(height: 17),
                  Text(
                    _source.title.trim().isEmpty
                        ? _l10n.playerCurrentVideo
                        : _source.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (_subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      _subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (autoNextLabel.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x16FFFFFF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Color(0xFF9CC4FF),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            autoNextLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 5),
                          IconButton(
                            tooltip: _l10n.commonClose,
                            onPressed: _cancelAutoNext,
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white54,
                            iconSize: 15,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 26,
                              height: 26,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => unawaited(_replayCompleted()),
                          icon: const Icon(Icons.replay_rounded),
                          label: Text(_l10n.playerReplayAction),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x35FFFFFF)),
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      if (nextEpisode != null) ...<Widget>[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => unawaited(_showNextEpisode()),
                            icon: const Icon(Icons.skip_next_rounded),
                            label: Text(
                              _l10n.nativeNotificationActionNextEpisode,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6EA8FF),
                              foregroundColor: const Color(0xFF0B1119),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => unawaited(_leavePlayer(videoState)),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(_l10n.playerBackAction),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                    ),
                  ),
                ],
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
              Text(
                _isLoading
                    ? _l10n.playerLoadingOpeningSource
                    : _l10n.playerLoadingBuffering,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
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
    setState(() {
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
    final resolution = _source.resolution.trim();
    if (resolution.isNotEmpty) return resolution;
    if (_source.videoWidth > 0 && _source.videoHeight > 0) {
      return '${_source.videoWidth}×${_source.videoHeight}';
    }
    return _l10n.playerQualityOriginal;
  }
}

class _DesktopHoverGlass extends StatelessWidget {
  const _DesktopHoverGlass({required this.child, this.squareRightEdge = false});

  final Widget child;
  final bool squareRightEdge;

  @override
  Widget build(BuildContext context) {
    final radius = squareRightEdge
        ? const BorderRadius.horizontal(left: Radius.circular(18))
        : BorderRadius.circular(18);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x78070D16),
            borderRadius: radius,
            border: Border.all(color: const Color(0x2AFFFFFF)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x70000000),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Material(color: Colors.transparent, child: child),
        ),
      ),
    );
  }
}

class _DesktopHoverOptionsPanel extends StatelessWidget {
  const _DesktopHoverOptionsPanel({
    required this.title,
    required this.options,
    required this.emptyLabel,
    required this.onSelected,
    this.offLabel,
    this.onOff,
  });

  final String title;
  final List<DesktopPlayerPanelOption> options;
  final String emptyLabel;
  final ValueChanged<DesktopPlayerPanelOption> onSelected;
  final String? offLabel;
  final VoidCallback? onOff;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xBFFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 9),
          const Divider(height: 1, color: Color(0x24FFFFFF)),
          const SizedBox(height: 6),
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (onOff != null && offLabel != null)
                    _DesktopHoverOptionRow(
                      title: offLabel!,
                      leading: Icons.block_rounded,
                      onTap: onOff!,
                    ),
                  if (options.isEmpty && emptyLabel.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 18,
                      ),
                      child: Text(
                        emptyLabel,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    for (final option in options)
                      _DesktopHoverOptionRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        selected: option.selected,
                        onTap: () => onSelected(option),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopHoverOptionRow extends StatefulWidget {
  const _DesktopHoverOptionRow({
    required this.title,
    required this.onTap,
    this.subtitle = '',
    this.selected = false,
    this.leading,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final IconData? leading;
  final VoidCallback onTap;

  @override
  State<_DesktopHoverOptionRow> createState() => _DesktopHoverOptionRowState();
}

class _DesktopHoverOptionRowState extends State<_DesktopHoverOptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        offset: _hovered ? const Offset(0.015, 0) : Offset.zero,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0x2E4F9EFF)
                : _hovered
                ? const Color(0x1FFFFFFF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Row(
                  children: <Widget>[
                    AnimatedScale(
                      scale: _hovered ? 1.08 : 1,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        widget.leading ??
                            (widget.selected
                                ? Icons.check_rounded
                                : Icons.circle_outlined),
                        size: widget.selected ? 18 : 15,
                        color: widget.selected
                            ? const Color(0xFF83B5FF)
                            : const Color(0x8CFFFFFF),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.selected
                                  ? const Color(0xFFD9E9FF)
                                  : Colors.white,
                              fontSize: 13,
                              fontWeight: widget.selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          if (widget.subtitle.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0x80FFFFFF),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ],
                      ),
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
}
