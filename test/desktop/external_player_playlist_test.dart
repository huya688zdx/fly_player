import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/external_player_playlist.dart';
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/models/download_task_record.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/download_task_service.dart';

class _NoNetworkBackend implements MediaBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('离线目录不应访问后端：${invocation.memberName}');
  }
}

class _NoNetworkNas implements NasProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('离线目录不应访问 NAS：${invocation.memberName}');
  }
}

void main() {
  test('离线目录合并 fallback 与同组已下载剧集，并排除电影和其他系列', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fly_external_playlist_',
    );
    final service = DownloadTaskService.instance;
    DownloadTaskRecord record({
      required String id,
      required String itemGuid,
      required String groupId,
      required String groupTitle,
      required int season,
      required int episode,
    }) {
      final file = File('${directory.path}/$id.mkv')
        ..writeAsBytesSync(<int>[0]);
      return DownloadTaskRecord(
        id: id,
        remoteTaskId: '',
        itemGuid: itemGuid,
        mediaGuid: 'media-$id',
        groupId: groupId,
        groupTitle: groupTitle,
        title: '标题$id',
        durationText: '',
        posterUrls: const <String>[],
        groupPosterUrls: const <String>[],
        resolution: '1080P',
        fileName: '$id.mkv',
        filePath: file.path,
        totalBytes: 1,
        downloadedBytes: 1,
        status: DownloadTaskStatus.downloaded,
        errorMessage: '',
        createdAtMs: 1,
        updatedAtMs: 1,
        seasonNumber: season,
        episodeNumber: episode,
      );
    }

    final current = record(
      id: 'a-s1e2',
      itemGuid: 'episode-2',
      groupId: 'season-a-1',
      groupTitle: '系列 A',
      season: 1,
      episode: 2,
    );
    service.debugReplaceRecordsForTesting(<DownloadTaskRecord>[
      record(
        id: 'a-s2e1',
        itemGuid: 'episode-4',
        groupId: 'season-a-2',
        groupTitle: '系列 A',
        season: 2,
        episode: 1,
      ),
      current,
      record(
        id: 'a-s1e1',
        itemGuid: 'episode-1',
        groupId: 'season-a-1',
        groupTitle: '系列 A',
        season: 1,
        episode: 1,
      ),
      record(
        id: 'movie',
        itemGuid: 'movie-1',
        groupId: 'movie-1',
        groupTitle: '系列 A',
        season: 0,
        episode: 0,
      ),
      record(
        id: 'b-s1e1',
        itemGuid: 'other-series',
        groupId: 'season-b-1',
        groupTitle: '系列 B',
        season: 1,
        episode: 1,
      ),
    ]);
    addTearDown(() async {
      service.debugReplaceRecordsForTesting(const <DownloadTaskRecord>[]);
      await directory.delete(recursive: true);
    });

    final result = await ExternalPlayerPlaylist.loadEpisodes(
      source: MpvMediaSource.localFile(
        filePath: current.filePath,
        itemGuid: current.itemGuid,
        mediaGuid: current.mediaGuid,
        videoGuid: current.mediaGuid,
        title: current.title,
        seasonGuid: current.groupId,
        seasonNumber: current.seasonNumber,
        episodeNumber: current.episodeNumber,
      ),
      backend: _NoNetworkBackend(),
      nas: _NoNetworkNas(),
      fallback: const <Map<String, dynamic>>[
        <String, dynamic>{
          'itemGuid': 'episode-2',
          'seasonGuid': 'season-a-1',
          'seasonNumber': 1,
          'episodeNumber': 2,
          'title': 'fallback 当前集',
        },
        <String, dynamic>{
          'itemGuid': 'episode-3',
          'seasonGuid': 'season-a-1',
          'seasonNumber': 1,
          'episodeNumber': 3,
          'title': 'fallback 第三集',
        },
      ],
      offline: true,
      onWarning: (_) => fail('离线目录不应产生网络告警'),
    );

    expect(result.map((episode) => episode.itemGuid), <String>[
      'episode-1',
      'episode-2',
      'episode-3',
      'episode-4',
    ]);
    expect(
      result.where((episode) => episode.itemGuid == 'episode-2'),
      hasLength(1),
    );
  });
}
