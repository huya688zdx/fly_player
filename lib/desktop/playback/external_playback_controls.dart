import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../playback/playback_source.dart';
import '../../services/native_danmaku_prefetch.dart';
import 'desktop_player_dialogs.dart';
import 'desktop_player_panels.dart';
import 'external_playback_host.dart';
import 'external_playback_notice.dart';

void _externalPlaybackMessage(BuildContext context, String message) {
  showExternalPlaybackNotice(context, message);
}

bool _isCurrentExternalSource(MpvMediaSource source) {
  final active = ExternalPlaybackHost.status.value?.source;
  return active?.itemGuid == source.itemGuid &&
      active?.mediaGuid == source.mediaGuid;
}

/// 外部播放控制页的弹幕搜索、导入与应用流程。
Future<void> showExternalDanmakuSources(
  BuildContext context,
  ExternalPlaybackStatus status,
) {
  if (!status.player.supportsSubtitles) {
    _externalPlaybackMessage(
      context,
      '${status.player.displayName} 暂不支持由 Fly Player 编辑字幕或弹幕。',
    );
    return Future<void>.value();
  }
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
          applied
              ? '弹幕已应用到 ${status.player.displayName}'
              : '弹幕未能应用，请确认当前影片和字幕选项',
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
