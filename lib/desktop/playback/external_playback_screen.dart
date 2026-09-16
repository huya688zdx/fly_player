import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../danmaku/models/danmaku_settings.dart';
import '../../controllers/play_detail_sheet_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_image_ref.dart';
import '../../models/stream_track_data.dart';
import '../../playback/playback_source.dart';
import '../../providers/media_backend_provider.dart';
import '../../providers/nas_provider.dart';
import '../../screens/settings_destination_routes.dart';
import '../../services/playback_progress_offline_queue.dart';
import '../../theme/app_theme.dart';
import '../../ui/detail_artwork_resolver.dart';
import '../../ui/media_detail_components.dart';
import '../../widgets/common/app_ambient_page.dart';
import '../../widgets/common/track_option_sheet.dart';
import '../desktop_hover_dropdown.dart';
import 'desktop_mpv_runtime.dart';
import 'desktop_player_hover_overlays.dart';
import 'external_playback_controls.dart';
import 'external_playback_host.dart';
import 'external_playback_mini_controller.dart';
import 'external_playback_notice.dart';
import 'external_player_playlist.dart';
import 'external_player_subtitles.dart';

/// 外部播放器会话的独立控制页，只展示宿主实际回报的状态。
class ExternalPlaybackScreen extends StatefulWidget {
  const ExternalPlaybackScreen({super.key});

  static const String routeName = '/screen/external-playback';

  @override
  State<ExternalPlaybackScreen> createState() => _ExternalPlaybackScreenState();
}

class _ExternalPlaybackScreenState extends State<ExternalPlaybackScreen> {
  static const _externalPlayerSubtitleId = 'external-player-default';
  final _qualityDropdownKey = GlobalKey<DesktopHoverDropdownState>();
  final _subtitleDropdownKey = GlobalKey<DesktopHoverDropdownState>();
  final _seasonDropdownKey = GlobalKey<DesktopHoverDropdownState>();
  DanmakuSettings? _draft;
  DanmakuSettings? _applied;
  String? _draftSubtitleGuid;
  String? _appliedSubtitleGuid;
  String? _mediaIdentity;
  int _tabIndex = 0;
  int? _seasonNumber;
  double? _dragPosition;
  bool _busy = false;

  void _syncMedia(ExternalPlaybackStatus status) {
    final source = status.source;
    final identity = '${source.itemGuid}\u0000${source.mediaGuid}';
    if (_mediaIdentity == identity) {
      final keepDraft = _dirty;
      _applied = status.danmakuSettings;
      _appliedSubtitleGuid = _selectableSubtitleGuid(source);
      if (!keepDraft) {
        _draft = _applied;
        _draftSubtitleGuid = _appliedSubtitleGuid;
      }
      return;
    }
    _mediaIdentity = identity;
    _draft = status.danmakuSettings;
    _applied = status.danmakuSettings;
    _draftSubtitleGuid = _selectableSubtitleGuid(source);
    _appliedSubtitleGuid = _draftSubtitleGuid;
    _seasonNumber = source.seasonNumber;
    _dragPosition = null;
  }

  String? _selectableSubtitleGuid(MpvMediaSource source) {
    return source.subtitleTrackGuid;
  }

  List<SubtitleTrackOption> _textSubtitles(MpvMediaSource source) {
    return ExternalPlayerSubtitles.selectableTracks(source);
  }

  MediaImageRequest _posterRequest(
    BuildContext context,
    MpvMediaSource source,
  ) {
    final path = source.posterPath.trim();
    if (path.isEmpty) return MediaImageRequest.empty;
    final uri = Uri.tryParse(path);
    final isLocal =
        uri?.scheme == 'file' ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
        path.startsWith(r'\\') ||
        path.startsWith('//');
    if (isLocal) return MediaImageRequest(urls: <String>[path]);

    final backendProvider = context.read<MediaBackendProvider?>();
    final nas = context.read<NasProvider?>();
    final usesNas =
        backendProvider?.backend.capabilities.usesLegacyFeiniuFlow ?? true;
    return DetailArtworkResolver(
      baseUrl: usesNas ? nas?.baseUrl ?? '' : '',
      token: usesNas ? nas?.token ?? '' : '',
      accessCode: usesNas ? nas?.accessCode ?? '' : '',
    ).resolveRef(MediaImageRef(url: path), width: 320);
  }

  bool get _dirty {
    final draft = _draft;
    final applied = _applied;
    if (draft == null || applied == null) return false;
    return draft.enabled != applied.enabled ||
        draft.fontScale != applied.fontScale ||
        draft.opacity != applied.opacity ||
        draft.density != applied.density ||
        draft.speed != applied.speed ||
        draft.displayAreaRatio != applied.displayAreaRatio ||
        draft.scrollEnabled != applied.scrollEnabled ||
        draft.topEnabled != applied.topEnabled ||
        draft.bottomEnabled != applied.bottomEnabled ||
        draft.avoidSubtitleArea != applied.avoidSubtitleArea ||
        _draftSubtitleGuid != _appliedSubtitleGuid;
  }

  bool _canApply(ExternalPlaybackStatus status) {
    if (_draft?.enabled != true || _draftSubtitleGuid?.isEmpty != false) {
      return true;
    }
    return _textSubtitles(
      status.source,
    ).any((track) => track.guid == _draftSubtitleGuid);
  }

  void _message(String message) {
    if (!mounted) return;
    showExternalPlaybackNotice(context, message);
  }

  Future<void> _run(
    Future<bool?> Function() action, {
    String failure = '操作未能完成，请确认外部播放器会话仍然有效',
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (await action() == false) _message(failure);
    } catch (_) {
      _message(failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(ExternalPlaybackStatus status) async {
    final draft = _draft;
    if (draft == null) return;
    final itemGuid = status.source.itemGuid;
    final mediaGuid = status.source.mediaGuid;
    await _run(() async {
      final applied = await ExternalPlaybackHost.applySettings(
        itemGuid: itemGuid,
        settings: draft,
        subtitleGuid: _draftSubtitleGuid == _appliedSubtitleGuid
            ? null
            : _draftSubtitleGuid,
      );
      if (applied &&
          mounted &&
          ExternalPlaybackHost.status.value?.source.itemGuid == itemGuid &&
          ExternalPlaybackHost.status.value?.source.mediaGuid == mediaGuid) {
        setState(() {
          _applied = draft;
          _appliedSubtitleGuid =
              ExternalPlaybackHost.status.value!.source.subtitleTrackGuid;
        });
        _message('设置已应用到 ${status.player.displayName}');
      }
      return applied;
    });
  }

  Future<void> _showSources(ExternalPlaybackStatus status) async {
    final hadDirtyDraft = _dirty;
    await showExternalDanmakuSources(context, status);
    if (!mounted) return;
    final latest = ExternalPlaybackHost.status.value;
    if (latest == null ||
        latest.source.itemGuid != status.source.itemGuid ||
        latest.source.mediaGuid != status.source.mediaGuid) {
      return;
    }
    setState(() {
      _applied = latest.danmakuSettings;
      if (!hadDirtyDraft) _draft = latest.danmakuSettings;
    });
  }

  void _resetDraft() {
    setState(() {
      _draft = _applied;
      _draftSubtitleGuid = _appliedSubtitleGuid;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeBuilder.buildFromColors(
      AppAmbientPage.controlColorsOf(context),
      baseTheme: Theme.of(context),
    );
    final content = Scaffold(
      backgroundColor: Colors.transparent,
      body: SliderTheme(
        data: theme.sliderTheme.copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 7,
            disabledThumbRadius: 7,
          ),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: SafeArea(
          child: ValueListenableBuilder<ExternalPlaybackStatus?>(
            valueListenable: ExternalPlaybackHost.status,
            builder: (context, status, _) {
              if (status == null) return _buildIdle(context);
              _syncMedia(status);
              return LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 980;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 28,
                      18,
                      compact ? 16 : 28,
                      28,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPageHeader(context, status),
                            const SizedBox(height: 16),
                            _buildNowPlaying(context, status),
                            const SizedBox(height: 16),
                            if (compact) ...[
                              _buildControlPanel(context, status),
                              const SizedBox(height: 14),
                              _buildPlaylist(context, status),
                            ] else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildControlPanel(context, status),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 296,
                                    child: _buildPlaylist(context, status),
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
            },
          ),
        ),
      ),
    );
    return AppAmbientPage(
      shareBackground: true,
      child: Theme(data: theme, child: content),
    );
  }

  Widget _buildIdle(BuildContext context) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.12),
                  ),
                ),
                child: Icon(
                  Icons.open_in_new_rounded,
                  size: 28,
                  color: colors.accentStrong,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '当前没有外部播放',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  '从媒体详情页使用外部播放器播放，\n即可在这里管理进度、弹幕、字幕与剧集。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: buttonShape,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('返回媒体库'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed(SettingsDestinationRoutes.externalPlayer),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      backgroundColor: colors.surface.withValues(alpha: 0.24),
                      side: BorderSide(color: colors.borderSubtle),
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      shape: buttonShape,
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('外部播放器设置'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageHeader(BuildContext context, ExternalPlaybackStatus status) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final phase = _phaseLabel(status);
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '外部播放',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${status.player.displayName} 会话控制与片源设置',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: _phaseColor(colors, status).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _phaseColor(colors, status).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _phaseColor(colors, status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                phase,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildMiniModeButton(),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => Navigator.of(
            context,
          ).pushNamed(SettingsDestinationRoutes.externalPlayer),
          tooltip: '外部播放器设置',
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _buildMiniModeButton() {
    final compact = MediaQuery.sizeOf(context).width < 680;
    return ValueListenableBuilder<bool>(
      valueListenable: ExternalPlaybackMiniController.available,
      builder: (context, available, _) => ValueListenableBuilder<bool>(
        valueListenable: ExternalPlaybackMiniController.active,
        builder: (context, active, _) {
          final VoidCallback? action =
              available &&
                  ExternalPlaybackHost
                          .status
                          .value
                          ?.player
                          .supportsMiniPlayer ==
                      true
              ? () async {
                  try {
                    await ExternalPlaybackMiniController.enter();
                  } catch (_) {
                    _message('无法打开极简模式，请重试');
                  }
                }
              : null;
          final icon = active
              ? Icons.picture_in_picture_alt
              : Icons.push_pin_outlined;
          return compact
              ? IconButton(
                  onPressed: action,
                  tooltip: active ? '极简模式已开启' : '打开极简模式',
                  icon: Icon(icon, size: 18),
                )
              : TextButton.icon(
                  onPressed: action,
                  icon: Icon(icon, size: 17),
                  label: Text(active ? '极简模式中' : '极简模式'),
                );
        },
      ),
    );
  }

  Widget _buildNowPlaying(BuildContext context, ExternalPlaybackStatus status) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final source = status.source;
    final poster = _posterRequest(context, source);
    final durationMs = status.duration.inMilliseconds.toDouble();
    final positionMs =
        (_dragPosition ?? status.position.inMilliseconds.toDouble()).clamp(
          0.0,
          durationMs > 0 ? durationMs : 1.0,
        );
    final currentIndex = status.playlist.indexWhere(
      (episode) => episode.itemGuid == source.itemGuid,
    );
    final previous = currentIndex > 0
        ? status.playlist[currentIndex - 1]
        : null;
    final next = currentIndex >= 0 && currentIndex + 1 < status.playlist.length
        ? status.playlist[currentIndex + 1]
        : null;
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 128,
                height: 80,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: DetailHeroImage(images: poster),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.seriesTitle.isEmpty ? '正在播放' : source.seriesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 11,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      currentIndex >= 0
                          ? status.playlist[currentIndex].episodeTitle
                          : source.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        if (source.seasonNumber > 0)
                          '第 ${source.seasonNumber} 季',
                        if (source.episodeNumber > 0)
                          '第 ${source.episodeNumber} 集',
                        if (source.resolution.isNotEmpty) source.resolution,
                        if (source.isDownloadedFile ||
                            source.externalLocalSource)
                          '本地文件',
                      ].join('  ·  '),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: !_busy && status.canControl
                    ? () => _run(
                        () => ExternalPlaybackHost.setPaused(
                          !status.paused,
                          itemGuid: source.itemGuid,
                        ),
                      )
                    : null,
                icon: Icon(
                  status.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
                label: Text(status.paused ? '继续' : '暂停'),
              ),
              IconButton.filledTonal(
                onPressed: !_busy && status.canControl && previous != null
                    ? () => _playEpisode(status, previous)
                    : null,
                tooltip: '上一集',
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton.filledTonal(
                onPressed: !_busy && status.canControl && next != null
                    ? () => _playEpisode(status, next)
                    : null,
                tooltip: '下一集',
                icon: const Icon(Icons.skip_next_rounded),
              ),
              TextButton.icon(
                onPressed: !_busy && status.canControl
                    ? () => _run(
                        () => ExternalPlaybackHost.activateCurrent(
                          itemGuid: source.itemGuid,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text('回到 ${status.player.displayName}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  _time(Duration(milliseconds: positionMs.round())),
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  value: positionMs,
                  max: durationMs > 0 ? durationMs : 1,
                  onChanged: !_busy && status.canControl && durationMs > 0
                      ? (value) => setState(() => _dragPosition = value)
                      : null,
                  onChangeEnd: (value) async {
                    await _run(
                      () => ExternalPlaybackHost.seek(
                        Duration(milliseconds: value.round()),
                        itemGuid: source.itemGuid,
                      ),
                    );
                    if (mounted) setState(() => _dragPosition = null);
                  },
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  _time(status.duration),
                  textAlign: TextAlign.end,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          if (status.progressMessage.isNotEmpty || status.error != null) ...[
            const SizedBox(height: 8),
            _buildSessionMessage(context, status),
          ],
          const SizedBox(height: 8),
          if (status.lastSyncedAt != null &&
              status.progressMessage.isEmpty &&
              status.error == null)
            Text(
              '最近一次服务器同步：${_clock(status.lastSyncedAt!)}',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionMessage(
    BuildContext context,
    ExternalPlaybackStatus status,
  ) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final message = normalizeExternalPlaybackNotice(
      status.error ?? status.progressMessage,
    );
    final failed =
        status.error != null ||
        status.progressResult == PlaybackProgressResult.failed;
    final requiresAction =
        failed ||
        status.progressResult == PlaybackProgressResult.queued ||
        status.phase == ExternalPlaybackPhase.disconnected ||
        status.phase == ExternalPlaybackPhase.ended;
    final synced = status.progressResult == PlaybackProgressResult.synced;
    final messageColor = failed
        ? colors.danger
        : synced
        ? colors.success
        : colors.textSecondary;
    final displayMessage = !requiresAction && status.lastSyncedAt != null
        ? '$message · ${_clock(status.lastSyncedAt!)}'
        : message;
    final content = Row(
      children: [
        Icon(
          failed
              ? Icons.error_outline_rounded
              : synced
              ? Icons.check_circle_outline_rounded
              : Icons.info_outline_rounded,
          size: requiresAction ? 18 : 15,
          color: messageColor,
        ),
        SizedBox(width: requiresAction ? 10 : 7),
        Expanded(
          child: Text(
            displayMessage,
            style: TextStyle(
              color: requiresAction ? colors.textPrimary : colors.textSecondary,
              fontSize: requiresAction ? null : 11,
            ),
          ),
        ),
        if (status.phase == ExternalPlaybackPhase.disconnected ||
            status.phase == ExternalPlaybackPhase.ended)
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ExternalPlaybackHost(context).reconnect(),
                    failure: '重新连接外部播放器失败',
                  ),
            child: const Text('重新连接'),
          )
        else if (status.canControl &&
            (status.progressResult == PlaybackProgressResult.failed ||
                status.progressResult == PlaybackProgressResult.queued))
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(
                    ExternalPlaybackHost.retryProgress,
                    failure: '重试进度回报失败',
                  ),
            child: const Text('重试回报'),
          ),
      ],
    );
    if (!requiresAction) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: content,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: messageColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: content,
    );
  }

  Widget _buildControlPanel(
    BuildContext context,
    ExternalPlaybackStatus status,
  ) {
    final colors = AppAmbientPage.controlColorsOf(context);
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                _TabButton(
                  selected: _tabIndex == 0,
                  icon: Icons.subtitles_rounded,
                  label: '弹幕',
                  onTap: () => setState(() => _tabIndex = 0),
                ),
                const SizedBox(width: 20),
                _TabButton(
                  selected: _tabIndex == 1,
                  icon: Icons.video_settings_rounded,
                  label: '片源与字幕',
                  onTap: () => setState(() => _tabIndex = 1),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: _tabIndex == 0
                ? _buildDanmaku(context, status)
                : _buildTracks(context, status),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: colors.borderSubtle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  _dirty
                      ? Icons.edit_note_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 17,
                  color: _dirty ? colors.warning : colors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _dirty && !_canApply(status)
                        ? '启用弹幕前，请关闭内封/位图字幕或改选外挂文本字幕'
                        : (_dirty ? '有尚未应用的更改' : '设置已与当前会话同步'),
                    style: TextStyle(
                      color: _dirty ? colors.warning : colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy && _dirty
                      ? null
                      : (_dirty ? _resetDraft : null),
                  child: const Text('撤销'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed:
                      !_busy &&
                          status.canControl &&
                          status.player.supportsSubtitles &&
                          _dirty &&
                          _canApply(status)
                      ? () => _apply(status)
                      : null,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: Text('应用到 ${status.player.displayName}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDanmaku(BuildContext context, ExternalPlaybackStatus status) {
    final colors = AppAmbientPage.controlColorsOf(context);
    if (!status.player.supportsSubtitles) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '${status.player.displayName} 暂不支持由 Fly Player 编辑字幕或弹幕。',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      );
    }
    final draft = _draft!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.danmakuLabel.isEmpty
                        ? '未选择弹幕源'
                        : status.danmakuLabel,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status.danmakuCount > 0
                        ? '${status.danmakuCount} 条弹幕'
                        : '没有已加载的弹幕',
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: status.canControl ? () => _showSources(status) : null,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('搜索或导入'),
            ),
            const SizedBox(width: 8),
            Switch(
              value: draft.enabled,
              onChanged: status.canControl
                  ? (value) =>
                        setState(() => _draft = draft.copyWith(enabled: value))
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _buildPreview(context, draft),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final oneColumn = constraints.maxWidth < 660;
            final settings = <Widget>[
              _SettingSlider(
                label: '字号',
                value: draft.fontScale,
                min: 0.6,
                max: 1.4,
                display: '${(draft.fontScale * 100).round()}%',
                onChanged: (value) =>
                    setState(() => _draft = draft.copyWith(fontScale: value)),
              ),
              _SettingSlider(
                label: '不透明度',
                value: draft.opacity,
                min: 0.2,
                max: 1,
                display: '${(draft.opacity * 100).round()}%',
                onChanged: (value) =>
                    setState(() => _draft = draft.copyWith(opacity: value)),
              ),
              _SettingSlider(
                label: '密度',
                value: draft.density,
                min: 0.2,
                max: 1,
                display: '${draft.density.toStringAsFixed(1)}×',
                onChanged: (value) =>
                    setState(() => _draft = draft.copyWith(density: value)),
              ),
              _SettingSlider(
                label: '速度',
                value: draft.speed,
                min: 0.5,
                max: 2,
                display: '${draft.speed.toStringAsFixed(1)}×',
                onChanged: (value) =>
                    setState(() => _draft = draft.copyWith(speed: value)),
              ),
            ];
            return oneColumn
                ? Column(children: settings)
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: settings[0]),
                          const SizedBox(width: 24),
                          Expanded(child: settings[1]),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: settings[2]),
                          const SizedBox(width: 24),
                          Expanded(child: settings[3]),
                        ],
                      ),
                    ],
                  );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '显示区域 ${(draft.displayAreaRatio * 100).round()}%',
          style: TextStyle(color: colors.textPrimary, fontSize: 12),
        ),
        Slider(
          value: draft.displayAreaRatio,
          min: 0.25,
          max: 1,
          divisions: 3,
          onChanged: (value) =>
              setState(() => _draft = draft.copyWith(displayAreaRatio: value)),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            FilterChip(
              selected: draft.scrollEnabled,
              label: const Text('滚动'),
              onSelected: (value) =>
                  setState(() => _draft = draft.copyWith(scrollEnabled: value)),
            ),
            FilterChip(
              selected: draft.topEnabled,
              label: const Text('顶部'),
              onSelected: (value) =>
                  setState(() => _draft = draft.copyWith(topEnabled: value)),
            ),
            FilterChip(
              selected: draft.bottomEnabled,
              label: const Text('底部'),
              onSelected: (value) =>
                  setState(() => _draft = draft.copyWith(bottomEnabled: value)),
            ),
            FilterChip(
              selected: draft.avoidSubtitleArea,
              avatar: const Icon(Icons.subtitles_off_rounded, size: 16),
              label: const Text('避让字幕区域'),
              onSelected: (value) => setState(
                () => _draft = draft.copyWith(avoidSubtitleArea: value),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context, DanmakuSettings draft) {
    final colors = AppAmbientPage.controlColorsOf(context);
    return Container(
      height: 154,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.backgroundElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.35, 0.1),
                  radius: 1.2,
                  colors: [
                    colors.accentSoft.withValues(alpha: 0.48),
                    colors.backgroundElevated,
                  ],
                ),
              ),
            ),
          ),
          if (draft.enabled) ...[
            if (draft.scrollEnabled)
              Positioned(
                top: 25,
                left: 28,
                child: _PreviewText('这一幕的配乐太棒了', draft: draft),
              ),
            if (draft.topEnabled)
              Positioned(
                top: 62,
                right: 42,
                child: _PreviewText(
                  '前方高能',
                  draft: draft,
                  color: colors.accentStrong,
                ),
              ),
            if (draft.bottomEnabled)
              Positioned(
                bottom: 38,
                left: 90,
                child: _PreviewText('细节满分', draft: draft),
              ),
          ] else
            Center(
              child: Text('弹幕已关闭', style: TextStyle(color: colors.textMuted)),
            ),
          Positioned(
            left: 12,
            bottom: 10,
            child: Text(
              '样式预览',
              style: TextStyle(color: colors.textMuted, fontSize: 10),
            ),
          ),
          if (draft.avoidSubtitleArea)
            Positioned(
              right: 12,
              bottom: 10,
              child: Text(
                '字幕避让区',
                style: TextStyle(color: colors.textMuted, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTracks(BuildContext context, ExternalPlaybackStatus status) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final l10n = AppLocalizations.of(context);
    final source = status.source;
    final subtitles = _textSubtitles(source);
    final qualityMenu = DesktopMpvRuntime.qualityMenu(source);
    final currentQuality = qualityMenu.customGroups.values
        .expand((choices) => choices)
        .where((choice) => DesktopMpvRuntime.isCurrentQuality(source, choice))
        .firstOrNull;
    final selectedTrackIsUnavailable =
        source.subtitleTrackGuid?.trim().isNotEmpty == true &&
        !subtitles.any((track) => track.guid == source.subtitleTrackGuid);
    final subtitleItems = [
      if (source.subtitleTrackGuid == null)
        TrackOptionSheetItem(
          id: _externalPlayerSubtitleId,
          title: '由 ${status.player.displayName} 选择',
        ),
      ...PlayDetailSheetController.subtitleItems(
        subtitleTracks: subtitles,
        l10n: l10n,
      ),
    ];
    final subtitleOptions = {
      for (final item in subtitleItems) item.id: item.title,
    };
    final selectedSubtitleId = _draftSubtitleGuid == null
        ? _externalPlayerSubtitleId
        : PlayDetailSheetController.subtitleSelectedIdOf(_draftSubtitleGuid);
    final subtitleLabel =
        subtitleOptions[selectedSubtitleId] ??
        (source.subtitleTracks.any(
              (track) =>
                  track.guid == source.subtitleTrackGuid && track.isBitmap == 1,
            )
            ? '当前位图字幕（在 ${status.player.displayName} 中切换）'
            : '当前内封字幕（在 ${status.player.displayName} 中切换）');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '视频质量',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (source.qualities.isEmpty)
          Text(
            '当前媒体没有其他可切换片源',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          )
        else
          _buildTrackDropdown(
            dropdownKey: _qualityDropdownKey,
            valueLabel: currentQuality == null
                ? '选择视频质量'
                : _qualityLabel(currentQuality),
            spec: !_busy && status.canControl
                ? DesktopHoverDropdownSpec.custom(
                    width: 420,
                    contentBuilder: (_) => DesktopHoverQualityPanel(
                      source: source,
                      onSelected: (index) {
                        _qualityDropdownKey.currentState?.hide();
                        _run(
                          () => ExternalPlaybackHost(context).changeQuality(
                            itemGuid: source.itemGuid,
                            quality: source.qualities[index],
                          ),
                          failure: '画质切换失败，请稍后重试',
                        );
                      },
                    ),
                  )
                : null,
          ),
        if (!status.player.supportsSubtitles) ...[
          const SizedBox(height: 26),
          Text(
            '${status.player.displayName} 暂不支持由 Fly Player 编辑字幕或弹幕。',
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
        ] else ...[
          const SizedBox(height: 26),
          Text(
            '外挂字幕',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '启用弹幕时，Fly Player 会将外挂 ASS、SRT、VTT 与弹幕合成为一条临时 ASS；关闭字幕只关闭影片字幕。',
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          _buildTrackDropdown(
            dropdownKey: _subtitleDropdownKey,
            valueLabel: subtitleLabel,
            spec: status.canControl && status.player.supportsSubtitles
                ? DesktopHoverDropdownSpec.single(
                    title: l10n.playerSubtitleSelectTitle,
                    width: 360,
                    items: subtitleItems,
                    selectedId: selectedSubtitleId,
                    onSelected: (id) => setState(
                      () => _draftSubtitleGuid = id == _externalPlayerSubtitleId
                          ? null
                          : PlayDetailSheetController.subtitleResultOf(id),
                    ),
                  )
                : null,
          ),
          if (selectedTrackIsUnavailable) ...[
            const SizedBox(height: 10),
            Text(
              source.subtitleTracks.any(
                    (track) =>
                        track.guid == source.subtitleTrackGuid &&
                        track.isBitmap == 1,
                  )
                  ? '当前是位图字幕，请在 ${status.player.displayName} 菜单中切换；这里可关闭或改用外挂文本字幕。'
                  : '当前是内封字幕，请在 ${status.player.displayName} 菜单中切换；这里可关闭或改用外挂文本字幕。',
              style: TextStyle(
                color: colors.warning,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.volume_up_outlined,
                  color: colors.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '音轨和内封字幕由 ${status.player.displayName} 管理，请在播放器菜单中切换。',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrackDropdown({
    required GlobalKey<DesktopHoverDropdownState> dropdownKey,
    required String valueLabel,
    required DesktopHoverDropdownSpec? spec,
  }) {
    return DesktopHoverDropdown(
      key: dropdownKey,
      activation: DesktopDropdownActivation.tap,
      spec: spec,
      child: OutlinedButton(
        onPressed: spec == null
            ? null
            : () => dropdownKey.currentState?.toggle(),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          side: BorderSide(color: context.appColors.borderSubtle),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylist(BuildContext context, ExternalPlaybackStatus status) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final seasons =
        status.playlist.map((episode) => episode.seasonNumber).toSet().toList()
          ..sort();
    final season = seasons.contains(_seasonNumber)
        ? _seasonNumber
        : (seasons.isEmpty ? null : seasons.first);
    final episodes = status.playlist
        .where((episode) => season == null || episode.seasonNumber == season)
        .toList();
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '播放列表',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${episodes.length} 集',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (season != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _buildTrackDropdown(
                dropdownKey: _seasonDropdownKey,
                valueLabel: season == 0 ? '特别篇' : '第 $season 季',
                spec: seasons.length > 1
                    ? DesktopHoverDropdownSpec.single(
                        title: '选择季',
                        width: 280,
                        items: [
                          for (final number in seasons)
                            TrackOptionSheetItem(
                              id: '$number',
                              title: number == 0 ? '特别篇' : '第 $number 季',
                            ),
                        ],
                        selectedId: '$season',
                        onSelected: (value) =>
                            setState(() => _seasonNumber = int.parse(value)),
                      )
                    : null,
              ),
            ),
          Divider(height: 1, color: colors.borderSubtle),
          if (episodes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                '当前会话没有剧集目录',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              // ListTile 的选中背景与水波纹也必须裁剪在列表视口内。
              child: Material(
                color: Colors.transparent,
                clipBehavior: Clip.hardEdge,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    final active = episode.itemGuid == status.source.itemGuid;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                      child: ListTile(
                        selected: active,
                        selectedTileColor: colors.selectionSoft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: Text(
                          episode.episodeNumber > 0
                              ? '${episode.episodeNumber}'
                              : '·',
                          style: TextStyle(
                            color: active ? colors.accent : colors.textMuted,
                          ),
                        ),
                        title: Text(
                          episode.episodeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: active
                            ? Icon(
                                Icons.graphic_eq_rounded,
                                color: colors.accent,
                                size: 18,
                              )
                            : null,
                        onTap: !active && !_busy && status.canControl
                            ? () => _playEpisode(status, episode)
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(
              status.player.supportsPlaylist
                  ? '切集后会重新解析该集的片源、字幕和弹幕；连续播放由 ${status.player.displayName} 的播放列表设置控制。'
                  : '切集后会重新解析该集的片源、字幕和弹幕。',
              style: TextStyle(color: colors.textMuted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  void _playEpisode(
    ExternalPlaybackStatus status,
    ExternalPlaylistEpisode episode,
  ) {
    _run(
      () => ExternalPlaybackHost(context).playEpisode(
        itemGuid: status.source.itemGuid,
        episodeGuid: episode.itemGuid,
      ),
      failure: '剧集切换失败，请稍后重试',
    );
  }

  String _phaseLabel(ExternalPlaybackStatus status) => switch (status.phase) {
    ExternalPlaybackPhase.preparing => '正在连接',
    ExternalPlaybackPhase.ready => status.paused ? '已暂停' : '播放中',
    ExternalPlaybackPhase.disconnected => '连接已断开',
    ExternalPlaybackPhase.ended => '播放已结束',
  };

  Color _phaseColor(AppThemeColors colors, ExternalPlaybackStatus status) =>
      switch (status.phase) {
        ExternalPlaybackPhase.ready => colors.success,
        ExternalPlaybackPhase.preparing => colors.warning,
        ExternalPlaybackPhase.disconnected => colors.danger,
        ExternalPlaybackPhase.ended => colors.textMuted,
      };

  static String _time(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600 ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$remainder' : '$minutes:$remainder';
  }

  static String _clock(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }

  static String _qualityLabel(DesktopQualityChoice choice) => [
    if (choice.isOriginal) '原画',
    choice.displayTier,
    DesktopMpvRuntime.qualityBitrateLabel(choice.quality.bitrate),
  ].where((part) => part.isNotEmpty).join(' · ');
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppAmbientPage.controlColorsOf(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppAmbientPage.cardColorOf(context, colors.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppAmbientPage.controlColorsOf(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? colors.accent : colors.textMuted,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? colors.accent : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppAmbientPage.controlColorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                ),
              ),
              Text(
                display,
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PreviewText extends StatelessWidget {
  const _PreviewText(this.text, {required this.draft, this.color});

  final String text;
  final DanmakuSettings draft;
  final Color? color;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: draft.opacity,
    child: Text(
      text,
      style: TextStyle(
        color: color ?? context.appColors.textPrimary,
        fontSize: 15 * draft.fontScale,
        fontWeight: FontWeight.w700,
        shadows: const [
          Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(1, 1)),
        ],
      ),
    ),
  );
}
