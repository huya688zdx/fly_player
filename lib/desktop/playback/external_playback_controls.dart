import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../playback/playback_source.dart';
import '../../services/native_danmaku_prefetch.dart';
import '../../theme/app_theme.dart';
import 'desktop_player_dialogs.dart';
import 'desktop_player_panels.dart';
import 'external_playback_host.dart';

/// 详情页只控制当前影片的外部会话，进度始终来自播放器实测。
class ExternalPlaybackControls extends StatefulWidget {
  const ExternalPlaybackControls({
    super.key,
    required this.itemGuid,
    required this.onApplySelection,
  });

  final String itemGuid;
  final Future<void> Function() onApplySelection;

  @override
  State<ExternalPlaybackControls> createState() =>
      _ExternalPlaybackControlsState();
}

class _ExternalPlaybackControlsState extends State<ExternalPlaybackControls> {
  double? _dragPosition;
  bool _busy = false;

  @override
  void didUpdateWidget(ExternalPlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemGuid != widget.itemGuid) _dragPosition = null;
  }

  bool _isCurrent(MpvMediaSource source) {
    final active = ExternalPlaybackHost.status.value?.source;
    return mounted &&
        widget.itemGuid == source.itemGuid &&
        active?.itemGuid == source.itemGuid &&
        active?.mediaGuid == source.mediaGuid;
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _control(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await action()) _message('操作未能完成，请确认这部影片仍在 PotPlayer 中播放');
    } catch (_) {
      _message('外部播放器操作失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _applyPayload(
    MpvMediaSource source,
    Future<Map<String, dynamic>?> Function() resolve,
    String label,
  ) async {
    try {
      if (!_isCurrent(source)) return false;
      final result = await resolve();
      if (!_isCurrent(source)) {
        _message('播放内容已切换，请重新选择当前影片的弹幕');
        return false;
      }
      final path = result?['danmakuFile']?.toString().trim() ?? '';
      if (path.isEmpty) {
        _message('弹幕源加载失败，请重试或选择其他来源');
        return false;
      }
      final applied = await ExternalPlaybackHost.applyDanmaku(
        itemGuid: source.itemGuid,
        path: path,
        label: label,
        enabled: true,
      );
      if (applied) {
        _message('弹幕已应用到 PotPlayer');
      } else {
        _message('弹幕未能应用，请确认当前影片和字幕选项');
      }
      return applied;
    } catch (_) {
      _message('弹幕源加载失败，请重试');
      return false;
    }
  }

  Future<bool> _importFile(MpvMediaSource source) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入弹幕文件',
        type: FileType.custom,
        allowedExtensions: const ['xml', 'json'],
        lockParentWindow: true,
      );
      final path = result?.files.single.path?.trim() ?? '';
      if (path.isEmpty || !_isCurrent(source)) return false;
      return _applyPayload(
        source,
        () => NativeDanmakuPrefetch.importLocalFileToFile(
          path,
          itemGuid: source.itemGuid,
          mediaGuid: source.mediaGuid,
          seasonGuid: source.seasonGuid,
          seasonNumber: source.seasonNumber,
          episodeNumber: source.episodeNumber,
          seriesTitle: source.seriesTitle,
          itemTitle: source.title,
          mediaType: source.mediaType,
        ),
        result!.files.single.name,
      );
    } catch (_) {
      _message('弹幕文件无法读取，请重新选择');
      return false;
    }
  }

  Future<void> _showSources(ExternalPlaybackStatus status) {
    final source = status.source;
    return showPlayerOverlayPanel(
      context,
      style: PlayerOverlayPanelStyle.centeredDialog,
      barrierLabel: '关闭弹幕源',
      closeTooltip: '关闭',
      builder: (dialogContext) => DesktopDanmakuSourcePanel(
        currentSourceLabel: status.danmakuLabel,
        commentCount: status.danmakuCount,
        loading: false,
        initialKeyword: source.seriesTitle.trim().isNotEmpty
            ? source.seriesTitle
            : source.title,
        currentTmdbId: source.tmdbId,
        onLoadSavedSources: () => NativeDanmakuPrefetch.listSavedSources(
          itemGuid: source.itemGuid,
          mediaGuid: source.mediaGuid,
          seasonGuid: source.seasonGuid,
          seasonNumber: source.seasonNumber,
          episodeNumber: source.episodeNumber,
          seriesTitle: source.seriesTitle,
        ),
        onSearch: (keyword) async {
          final results = await NativeDanmakuPrefetch.searchCandidates(
            keyword: keyword,
            currentEpisodeNumber: source.episodeNumber,
            seasonNumber: source.seasonNumber,
          );
          if (results.isEmpty) _message('未找到弹幕，请检查关键词或网络后重试');
          return results;
        },
        onSelectSavedSource: (saved) => _applyPayload(
          source,
          () => NativeDanmakuPrefetch.loadSavedSourceToFile(
            sourceKey: '${saved['sourceKey'] ?? ''}',
            itemGuid: source.itemGuid,
            mediaGuid: source.mediaGuid,
            seasonGuid: source.seasonGuid,
            seasonNumber: source.seasonNumber,
            episodeNumber: source.episodeNumber,
            seriesTitle: source.seriesTitle,
          ),
          '${saved['label'] ?? saved['sourceKey'] ?? ''}',
        ),
        onSelectSearchResult: (candidate) => _applyPayload(
          source,
          () => NativeDanmakuPrefetch.importEpisodeToFile(
            episodeId: (candidate['episodeId'] as num?)?.toInt() ?? 0,
            animeTitle: '${candidate['animeTitle'] ?? ''}',
            episodeTitle: '${candidate['episodeTitle'] ?? ''}',
            episodeNumber: (candidate['episodeNumber'] as num?)?.toInt() ?? 0,
            itemGuid: source.itemGuid,
            mediaGuid: source.mediaGuid,
            seasonGuid: source.seasonGuid,
            seasonNumber: source.seasonNumber,
            currentEpisodeNumber: source.episodeNumber,
            seriesTitle: source.seriesTitle,
            mediaItemTitle: source.title,
          ),
          '${candidate['title'] ?? candidate['episodeTitle'] ?? ''}',
        ),
        onDeleteSavedSource: (saved) async {
          if (!_isCurrent(source)) return;
          final removed = await NativeDanmakuPrefetch.removeSavedSource(
            sourceKey: '${saved['sourceKey'] ?? ''}',
            itemGuid: source.itemGuid,
            mediaGuid: source.mediaGuid,
            seasonGuid: source.seasonGuid,
            seasonNumber: source.seasonNumber,
            episodeNumber: source.episodeNumber,
            seriesTitle: source.seriesTitle,
          );
          if (!removed) _message('弹幕源删除失败，请重试');
        },
        onImportFile: () => _importFile(source),
      ),
    );
  }

  static String _time(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<ExternalPlaybackStatus?>(
    valueListenable: ExternalPlaybackHost.status,
    builder: (context, status, _) {
      if (status == null || status.source.itemGuid != widget.itemGuid) {
        return const SizedBox.shrink();
      }
      final colors = context.appColors;
      final itemGuid = status.source.itemGuid;
      final durationMs = status.duration.inMilliseconds.toDouble();
      final positionMs =
          (_dragPosition ?? status.position.inMilliseconds.toDouble()).clamp(
            0.0,
            durationMs > 0 ? durationMs : 1.0,
          );
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.open_in_new_rounded, size: 18, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PotPlayer · ${status.paused ? '已暂停' : '播放中'}',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ),
                Text(
                  '${_time(Duration(milliseconds: positionMs.round()))} / ${_time(status.duration)}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            Slider(
              value: positionMs,
              max: durationMs > 0 ? durationMs : 1,
              activeColor: colors.accent,
              semanticFormatterCallback: (value) =>
                  _time(Duration(milliseconds: value.round())),
              onChanged: _busy || durationMs <= 0
                  ? null
                  : (value) => setState(() => _dragPosition = value),
              onChangeEnd: (value) async {
                await _control(
                  () => ExternalPlaybackHost.seek(
                    Duration(milliseconds: value.round()),
                    itemGuid: itemGuid,
                  ),
                );
                if (mounted) setState(() => _dragPosition = null);
              },
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => _control(
                          () => ExternalPlaybackHost.setPaused(
                            !status.paused,
                            itemGuid: itemGuid,
                          ),
                        ),
                  icon: Icon(
                    status.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  label: Text(status.paused ? '继续' : '暂停'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _control(
                          () => ExternalPlaybackHost.activateCurrent(
                            itemGuid: itemGuid,
                          ),
                        ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('回到播放器'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _control(() async {
                          if (!_isCurrent(status.source)) return false;
                          await widget.onApplySelection();
                          return true;
                        }),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('应用片源与字幕'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: status.danmakuEnabled,
                      onChanged: _busy
                          ? null
                          : (value) => _control(
                              () => ExternalPlaybackHost.applyDanmaku(
                                itemGuid: itemGuid,
                                enabled: value,
                              ),
                            ),
                    ),
                    Text('弹幕', style: TextStyle(color: colors.textPrimary)),
                  ],
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _showSources(status),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('搜索弹幕源'),
                ),
              ],
            ),
            if (status.danmakuEnabled) ...[
              const SizedBox(height: 6),
              Text(
                '${status.danmakuLabel.isEmpty ? '当前弹幕' : status.danmakuLabel}'
                '${status.danmakuCount > 0 ? ' · ${status.danmakuCount} 条' : ''}',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '片源与外挂字幕选好后点击应用；音轨和内封字幕请在 PotPlayer 菜单切换。',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}
