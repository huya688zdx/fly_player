import 'dart:async';
import 'dart:io';

import '../../api/feiniu_api.dart';
import '../../controllers/local_download_source_resolver.dart';
import '../../media_backend/media_backend.dart';
import '../../models/download_task_record.dart';
import '../../playback/playback_source.dart';
import '../../providers/nas_provider.dart';
import '../../services/download_task_service.dart';
import '../../services/native_reentry_support.dart';

class ExternalPlaylistEpisode {
  const ExternalPlaylistEpisode({
    required this.itemGuid,
    required this.title,
    required this.seasonNumber,
    required this.episodeNumber,
    this.seasonGuid = '',
  });

  final String itemGuid;
  final String title;
  final int seasonNumber;
  final int episodeNumber;
  final String seasonGuid;
}

/// 只加载剧集目录；播放地址、字幕和弹幕在选中该集时再解析。
class ExternalPlayerPlaylist {
  /// 各集字幕 GUID 不同，按当前外挂字幕的语言和格式继承选择。
  static MpvMediaSource inheritSubtitleSelection(
    MpvMediaSource current,
    MpvMediaSource next,
  ) {
    if (current.subtitleTrackGuid == '') {
      return next.copyWith(
        subtitleTrackGuid: '',
        clearSubtitleTrackIndex: true,
        preferExternalSubtitle: false,
      );
    }
    final selected = current.subtitleTracks
        .where((track) => track.guid == current.subtitleTrackGuid)
        .firstOrNull;
    if (selected == null ||
        (selected.isExternal != 1 && selected.extraFile != 1)) {
      return next;
    }
    final matches = next.subtitleTracks.where(
      (track) =>
          (track.isExternal == 1 || track.extraFile == 1) &&
          track.format.trim().toLowerCase() ==
              selected.format.trim().toLowerCase() &&
          track.language.trim().toLowerCase() ==
              selected.language.trim().toLowerCase(),
    );
    final matching =
        matches
            .where((track) => track.guid == next.subtitleTrackGuid)
            .firstOrNull ??
        matches.firstOrNull;
    if (matching == null) return next;
    return next.copyWith(
      subtitleTrackGuid: matching.guid,
      clearSubtitleTrackIndex: true,
      preferExternalSubtitle: true,
    );
  }

  static Future<List<ExternalPlaylistEpisode>> loadEpisodes({
    required MpvMediaSource source,
    required MediaBackend backend,
    required NasProvider nas,
    List<Map<String, dynamic>>? fallback,
    bool offline = false,
    required void Function(String) onWarning,
  }) async {
    final entries = <String, ExternalPlaylistEpisode>{};
    final fallbackEpisodes = fallback ?? <Map<String, dynamic>>[];
    final isEpisode =
        source.mediaType.toLowerCase() == 'episode' ||
        (source.seasonGuid.trim().isNotEmpty && source.episodeNumber > 0);
    if (isEpisode) {
      for (final episode in fallbackEpisodes) {
        final id = '${episode['itemGuid'] ?? episode['guid'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        final seasonNumber =
            (episode['seasonNumber'] as num?)?.toInt() ?? source.seasonNumber;
        entries.putIfAbsent(
          id,
          () => ExternalPlaylistEpisode(
            itemGuid: id,
            title:
                '第$seasonNumber季 第${episode['episodeNumber'] ?? ''}集 '
                '${episode['title'] ?? ''}',
            seasonNumber: seasonNumber,
            episodeNumber: (episode['episodeNumber'] as num?)?.toInt() ?? 0,
            seasonGuid: '${episode['seasonGuid'] ?? source.seasonGuid}',
          ),
        );
      }
      if (offline || source.isDownloadedFile) {
        for (final episode in _downloadedEpisodesForSource(
          source,
          fallbackEpisodes,
        )) {
          entries.putIfAbsent(episode.itemGuid, () => episode);
        }
      }
    }
    if (!offline && isEpisode) {
      Future<void> loadRemoteEpisodes() async {
        final deadline = Stopwatch()..start();
        Future<T> readMetadata<T>(Future<T> Function() read) {
          if (!source.isDownloadedFile) return read();
          final remaining = localDownloadMetadataTimeout - deadline.elapsed;
          if (remaining <= Duration.zero) {
            throw TimeoutException('本地播放的在线目录查询超时');
          }
          return read().timeout(remaining);
        }

        final seriesGuid = await readMetadata(() async {
          if (backend.capabilities.usesLegacyFeiniuFlow) {
            return NativeReentrySupport.resolveSeriesGuid(
              FeiniuApi(nas),
              source.toMap(),
              source.seasonGuid,
            );
          }
          return source.seriesGuid.isNotEmpty
              ? source.seriesGuid
              : (await backend.getItemDetail(source.itemGuid)).seriesId;
        });
        final seasons = [
          ...await readMetadata(() => backend.getItemSeasons(seriesGuid)),
        ]..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
        for (final season in seasons) {
          final episodes = [
            ...await readMetadata(() => backend.getSeasonEpisodes(season.id)),
          ]..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
          final label = season.seasonNumber == 0
              ? '特别篇'
              : '第${season.seasonNumber}季';
          for (final episode in episodes) {
            if (episode.id.isEmpty) continue;
            entries[episode.id] = ExternalPlaylistEpisode(
              itemGuid: episode.id,
              title: '$label 第${episode.episodeNumber}集 ${episode.title}',
              seasonNumber: season.seasonNumber,
              episodeNumber: episode.episodeNumber,
              seasonGuid: season.id,
            );
          }
        }
      }

      try {
        final loading = loadRemoteEpisodes();
        await (source.isDownloadedFile
            ? loading.timeout(localDownloadMetadataTimeout)
            : loading);
      } catch (_) {
        onWarning('部分季的播放列表未能加载，本次保留已获取的剧集');
      }
    }
    entries.putIfAbsent(
      source.itemGuid,
      () => ExternalPlaylistEpisode(
        itemGuid: source.itemGuid,
        title: source.title,
        seasonNumber: source.seasonNumber,
        episodeNumber: source.episodeNumber,
        seasonGuid: source.seasonGuid,
      ),
    );
    return entries.values.toList()..sort((a, b) {
      final season = a.seasonNumber.compareTo(b.seasonNumber);
      if (season != 0) return season;
      final episode = a.episodeNumber.compareTo(b.episodeNumber);
      if (episode != 0) return episode;
      return a.itemGuid.compareTo(b.itemGuid);
    });
  }

  static Iterable<ExternalPlaylistEpisode> _downloadedEpisodesForSource(
    MpvMediaSource source,
    List<Map<String, dynamic>>? fallback,
  ) {
    final service = DownloadTaskService.instance;
    var current = service.downloadedRecordForItem(
      source.itemGuid,
      mediaGuid: source.mediaGuid,
    );
    current ??= service.downloadedRecordForItem(source.itemGuid);
    final sourceUri = Uri.tryParse(source.url);
    if (current == null && sourceUri?.scheme == 'file') {
      current = service.downloadedRecordForFilePath(
        sourceUri!.toFilePath(windows: Platform.isWindows),
      );
    }

    final groupIds = <String>{
      source.seasonGuid.trim(),
      for (final episode in fallback ?? <Map<String, dynamic>>[])
        '${episode['seasonGuid'] ?? episode['groupId'] ?? ''}'.trim(),
    }..remove('');
    for (final group in service.groupsByStatus(DownloadTaskStatus.downloaded)) {
      final containsCurrent =
          current != null &&
          group.records.any((record) => record.id == current!.id);
      final matchesFallbackGroup =
          current == null &&
          source.episodeNumber > 0 &&
          group.records.any(
            (record) =>
                groupIds.contains(record.groupId.trim()) &&
                (record.itemGuid == source.itemGuid ||
                    record.episodeNumber == source.episodeNumber),
          );
      if (!containsCurrent && !matchesFallbackGroup) continue;
      return group.records
          .where(
            (record) =>
                record.episodeNumber > 0 && record.itemGuid.trim().isNotEmpty,
          )
          .map(
            (record) => ExternalPlaylistEpisode(
              itemGuid: record.itemGuid.trim(),
              title:
                  '第${record.seasonNumber}季 第${record.episodeNumber}集 '
                  '${service.displayTitleForRecord(record)}',
              seasonNumber: record.seasonNumber,
              episodeNumber: record.episodeNumber,
              seasonGuid: record.groupId.trim(),
            ),
          );
    }
    return const <ExternalPlaylistEpisode>[];
  }

  static Future<String> write({
    required Directory directory,
    required String currentUrl,
    required Map<String, String> titlesByUrl,
  }) async {
    String line(String value) => value.replaceAll(RegExp(r'[\r\n]'), ' ');
    final lines = <String>[
      '\uFEFFDAUMPLAYLIST',
      'playname=${line(currentUrl)}',
      'playtime=0',
      'topindex=0',
    ];
    var index = 1;
    for (final entry in titlesByUrl.entries) {
      lines.add('$index*file*${line(entry.key)}');
      lines.add('$index*title*${line(entry.value)}');
      index++;
    }
    final file = File('${directory.path}/playlist.dpl');
    await file.writeAsString(lines.join('\r\n'), flush: true);
    return file.path;
  }
}
