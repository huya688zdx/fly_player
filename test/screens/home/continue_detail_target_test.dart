import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/screens/home/continue_detail_target.dart';
import 'package:flutter_test/flutter_test.dart';

MediaLibraryItem episode({String ancestorGuid = 'series-1'}) {
  return MediaLibraryItem(
    guid: 'episode-1',
    title: '第一集',
    tvTitle: '系列副标题',
    type: 'episode',
    poster: 'poster.jpg',
    releaseDate: '',
    firstAirDate: '',
    lastAirDate: '',
    voteAverage: '',
    overview: '',
    watched: 0,
    watchedTs: 120,
    ts: 0,
    duration: 1200,
    seasonNumber: 1,
    episodeNumber: 1,
    numberOfSeasons: 0,
    numberOfEpisodes: 0,
    localNumberOfSeasons: 0,
    localNumberOfEpisodes: 0,
    parentGuid: 'season-1',
    parentTitle: '第 1 季',
    ancestorGuid: ancestorGuid,
    ancestorName: '系列名称',
    path: 'poster.jpg',
    backdropUrl: 'backdrop.jpg',
  );
}

void main() {
  for (final kind in <MediaBackendKind>[
    MediaBackendKind.emby,
    MediaBackendKind.jellyfin,
  ]) {
    test('$kind 的续看单集打开系列详情', () {
      final source = episode();

      final target = continueDetailTarget(source, kind);

      expect(target.guid, 'series-1');
      expect(target.type, 'tv');
      expect(target.title, '系列名称');
      expect(target.tvTitle, '系列名称');
      expect(target.poster, source.poster);
      expect(target.backdropUrl, source.backdropUrl);
    });
  }

  test('飞牛续看单集保持打开当前条目详情', () {
    final source = episode();

    final target = continueDetailTarget(source, MediaBackendKind.feiniu);

    expect(identical(target, source), isTrue);
  });

  test('服务器族单集缺少系列 ID 时回退当前条目', () {
    final source = episode(ancestorGuid: '  ');

    final target = continueDetailTarget(source, MediaBackendKind.emby);

    expect(identical(target, source), isTrue);
  });
}
