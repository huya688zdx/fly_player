import 'dart:io';

import '../../api/feiniu_api.dart';
import '../../media_backend/media_backend.dart';
import '../../playback/playback_source.dart';
import '../../providers/nas_provider.dart';
import '../../services/native_reentry_support.dart';

typedef ExternalPlaylistEpisode = ({String itemGuid, String title});

/// 只加载剧集目录；播放地址、字幕和弹幕在选中该集时再解析。
class ExternalPlayerPlaylist {
  static Future<List<ExternalPlaylistEpisode>> loadEpisodes({
    required MpvMediaSource source,
    required MediaBackend backend,
    required NasProvider nas,
    List<Map<String, dynamic>>? fallback,
    required void Function(String) onWarning,
  }) async {
    final entries = <String, ExternalPlaylistEpisode>{};
    try {
      final seriesGuid = await NativeReentrySupport.resolveSeriesGuid(
        FeiniuApi(nas),
        source.toMap(),
        source.seasonGuid,
      );
      final seasons = [...await backend.getItemSeasons(seriesGuid)]
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      for (final season in seasons) {
        final episodes = [...await backend.getSeasonEpisodes(season.id)]
          ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
        final label = season.seasonNumber == 0
            ? '特别篇'
            : '第${season.seasonNumber}季';
        for (final episode in episodes) {
          if (episode.id.isEmpty) continue;
          entries[episode.id] = (
            itemGuid: episode.id,
            title: '$label 第${episode.episodeNumber}集 ${episode.title}',
          );
        }
      }
    } catch (_) {
      onWarning('部分季的播放列表未能加载，本次保留已获取的剧集');
    }
    for (final episode in fallback ?? <Map<String, dynamic>>[]) {
      final id = '${episode['itemGuid'] ?? episode['guid'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      entries.putIfAbsent(
        id,
        () => (
          itemGuid: id,
          title:
              '第${source.seasonNumber}季 第${episode['episodeNumber'] ?? ''}集 '
              '${episode['title'] ?? ''}',
        ),
      );
    }
    entries.putIfAbsent(
      source.itemGuid,
      () => (itemGuid: source.itemGuid, title: source.title),
    );
    return entries.values.toList();
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
