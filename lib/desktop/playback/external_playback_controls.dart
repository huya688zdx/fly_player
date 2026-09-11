import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../playback/playback_source.dart';
import '../../services/native_danmaku_prefetch.dart';
import '../../theme/app_theme.dart';
import 'desktop_player_dialogs.dart';
import 'desktop_player_panels.dart';
import 'external_playback_host.dart';

void _externalPlaybackMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

bool _isCurrentExternalSource(MpvMediaSource source) {
  final active = ExternalPlaybackHost.status.value?.source;
  return active?.itemGuid == source.itemGuid &&
      active?.mediaGuid == source.mediaGuid;
}

/// 详情卡和独立控制页共用同一套弹幕搜索、导入与应用流程。
Future<void> showExternalDanmakuSources(
  BuildContext context,
  ExternalPlaybackStatus status,
) {
  final source = status.source;

  Future<bool> applyPayload(
    Future<Map<String, dynamic>?> Function() resolve,
    String label,
  ) async {
    try {
      if (!_isCurrentExternalSource(source)) return false;
      final result = await resolve();
      if (!_isCurrentExternalSource(source)) {
        if (context.mounted) {
          _externalPlaybackMessage(context, '播放内容已切换，请重新选择当前影片的弹幕');
        }
        return false;
      }
      final path = result?['danmakuFile']?.toString().trim() ?? '';
      if (path.isEmpty) {
        if (context.mounted) {
          _externalPlaybackMessage(context, '弹幕源加载失败，请重试或选择其他来源');
        }
        return false;
      }
      final applied = await ExternalPlaybackHost.applyDanmaku(
        itemGuid: source.itemGuid,
        path: path,
        label: label,
        enabled: true,
      );
      if (context.mounted) {
        _externalPlaybackMessage(
          context,
          applied ? '弹幕已应用到 PotPlayer' : '弹幕未能应用，请确认当前影片和字幕选项',
        );
      }
      return applied;
    } catch (_) {
      if (context.mounted) _externalPlaybackMessage(context, '弹幕源加载失败，请重试');
      return false;
    }
  }

  Future<bool> importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入弹幕文件',
        type: FileType.custom,
        allowedExtensions: const ['xml', 'json'],
        lockParentWindow: true,
      );
      final path = result?.files.single.path?.trim() ?? '';
      if (path.isEmpty || !_isCurrentExternalSource(source)) return false;
      return applyPayload(
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
      if (context.mounted) _externalPlaybackMessage(context, '弹幕文件无法读取，请重新选择');
      return false;
    }
  }

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
        if (results.isEmpty && context.mounted) {
          _externalPlaybackMessage(context, '未找到弹幕，请检查关键词或网络后重试');
        }
        return results;
      },
      onSelectSavedSource: (saved) => applyPayload(
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
      onSelectSearchResult: (candidate) => applyPayload(
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
        if (!_isCurrentExternalSource(source)) return;
        final removed = await NativeDanmakuPrefetch.removeSavedSource(
          sourceKey: '${saved['sourceKey'] ?? ''}',
          itemGuid: source.itemGuid,
          mediaGuid: source.mediaGuid,
          seasonGuid: source.seasonGuid,
          seasonNumber: source.seasonNumber,
          episodeNumber: source.episodeNumber,
          seriesTitle: source.seriesTitle,
        );
        if (!removed && context.mounted) {
          _externalPlaybackMessage(context, '弹幕源删除失败，请重试');
        }
      },
      onImportFile: importFile,
    ),
  );
}

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
  bool _busy = false;

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
                    'PotPlayer · ${switch (status.phase) {
                      ExternalPlaybackPhase.preparing => '正在连接',
                      ExternalPlaybackPhase.ready => status.paused ? '已暂停' : '播放中',
                      ExternalPlaybackPhase.disconnected => '连接已断开',
                      ExternalPlaybackPhase.ended => '播放已结束',
                    }}',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ),
                Text(
                  '${_time(status.position)} / ${_time(status.duration)}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy || !status.canControl
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
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamed('/screen/external-playback'),
                  icon: const Icon(
                    Icons.dashboard_customize_outlined,
                    size: 18,
                  ),
                  label: const Text('打开控制页'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
