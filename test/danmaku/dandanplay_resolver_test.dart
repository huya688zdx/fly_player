import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/api/dandanplay_api.dart';
import 'package:fly_player/danmaku/api/dandanplay_resolver.dart';
import 'package:fly_player/danmaku/cache/dandanplay_comment_cache_store.dart';
import 'package:fly_player/danmaku/models/dandanplay_episode_search_item.dart';

void main() {
  test('剧名归一化可移除中文数字季度后缀', () {
    expect(DanDanPlayResolver.normalizeSeriesTitle('总之就是非常可爱 第二季'), '总之就是非常可爱');
  });

  test('手动候选把当前季度放在前面且不丢弃其他季度', () {
    final sorted = DanDanPlayResolver.sortCandidatesForSeason(
      <DanDanPlayEpisodeSearchItem>[
        const DanDanPlayEpisodeSearchItem(
          episodeId: 154210002,
          animeTitle: '总之就是非常可爱',
          episodeTitle: '第2话',
          episodeNumber: 2,
        ),
        const DanDanPlayEpisodeSearchItem(
          episodeId: 169610002,
          animeTitle: '总之就是非常可爱 第二季',
          episodeTitle: '第2话',
          episodeNumber: 2,
        ),
      ],
      seasonNumber: 2,
    );

    expect(sorted.map((item) => item.episodeId), <int>[169610002, 154210002]);
  });

  test('跨季同集号候选只标记当前季度', () {
    const firstSeason = DanDanPlayEpisodeSearchItem(
      episodeId: 134570001,
      animeTitle: '轻音少女',
      episodeTitle: '第1话 废部！',
      episodeNumber: 1,
    );
    const secondSeason = DanDanPlayEpisodeSearchItem(
      episodeId: 142670001,
      animeTitle: '轻音少女 第二季',
      episodeTitle: '第1话 高三！',
      episodeNumber: 1,
    );

    expect(
      DanDanPlayResolver.candidateMatchesSeason(firstSeason, seasonNumber: 2),
      isFalse,
    );
    expect(
      DanDanPlayResolver.candidateMatchesSeason(secondSeason, seasonNumber: 2),
      isTrue,
    );
  });

  test('缺少当前季度信息时不猜测候选季度', () {
    const candidate = DanDanPlayEpisodeSearchItem(
      episodeId: 134570001,
      animeTitle: '轻音少女',
      episodeTitle: '第1话 废部！',
      episodeNumber: 1,
    );

    expect(
      DanDanPlayResolver.candidateMatchesSeason(candidate, seasonNumber: 0),
      isFalse,
    );
  });

  test('playback candidate prefers episode title over numeric episode', () {
    final candidates = <DanDanPlayEpisodeSearchItem>[
      const DanDanPlayEpisodeSearchItem(
        episodeId: 9,
        animeTitle: 'Test Anime',
        episodeTitle: '第9话 旧编号',
        episodeNumber: 9,
      ),
      const DanDanPlayEpisodeSearchItem(
        episodeId: 101,
        animeTitle: 'Test Anime',
        episodeTitle: '第1话 青春百万円',
        episodeNumber: 1,
      ),
    ];

    final picked = DanDanPlayResolver.pickPlaybackCandidateForTest(
      candidates,
      itemTitle: '青春百万円',
      episodeNumber: 9,
    );

    expect(picked?.episodeId, 101);
  });

  test('播放候选先按季度区分重复集号', () {
    final candidates = <DanDanPlayEpisodeSearchItem>[
      const DanDanPlayEpisodeSearchItem(
        episodeId: 154210002,
        animeTitle: '总之就是非常可爱',
        episodeTitle: '第2话',
        episodeNumber: 0,
      ),
      const DanDanPlayEpisodeSearchItem(
        episodeId: 169610002,
        animeTitle: '总之就是非常可爱 第二季',
        episodeTitle: '第2话',
        episodeNumber: 0,
      ),
    ];

    final picked = DanDanPlayResolver.pickPlaybackCandidateForTest(
      candidates,
      seriesTitle: '总之就是非常可爱',
      seasonNumber: 2,
      itemTitle: '第2集',
      episodeNumber: 2,
    );

    expect(picked?.episodeId, 169610002);
  });

  test('播放候选遇到季度歧义时拒绝直接取第一项', () {
    final candidates = <DanDanPlayEpisodeSearchItem>[
      const DanDanPlayEpisodeSearchItem(
        episodeId: 1001,
        animeTitle: '测试动画',
        episodeTitle: '第1话',
        episodeNumber: 0,
      ),
      const DanDanPlayEpisodeSearchItem(
        episodeId: 2001,
        animeTitle: '测试动画 续篇',
        episodeTitle: '第1话',
        episodeNumber: 0,
      ),
    ];

    final picked = DanDanPlayResolver.pickPlaybackCandidateForTest(
      candidates,
      seriesTitle: '测试动画',
      seasonNumber: 3,
      itemTitle: '第1集',
      episodeNumber: 1,
    );

    expect(picked, isNull);
  });

  test('季度未识别时不能被单集标题诱导到其他作品', () {
    final candidates = <DanDanPlayEpisodeSearchItem>[
      const DanDanPlayEpisodeSearchItem(
        episodeId: 1001,
        animeTitle: '测试动画',
        episodeTitle: '第1话 开始',
        episodeNumber: 1,
      ),
      const DanDanPlayEpisodeSearchItem(
        episodeId: 2001,
        animeTitle: '测试动画 续篇',
        episodeTitle: '第1话 重逢',
        episodeNumber: 1,
      ),
    ];

    final picked = DanDanPlayResolver.pickPlaybackCandidateForTest(
      candidates,
      seriesTitle: '测试动画',
      seasonNumber: 3,
      itemTitle: '开始',
      episodeNumber: 1,
    );

    expect(picked, isNull);
  });

  test('搜索第一次请求保留明确的季度关键词', () async {
    final requestedAnime = <String>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedAnime.add(
            options.queryParameters['anime']?.toString() ?? '',
          );
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: const <String, dynamic>{'animes': <dynamic>[]},
            ),
          );
        },
      ),
    );
    final resolver = DanDanPlayResolver(
      DanDanPlayApi(dio: dio, appId: 'test', appSecret: 'secret'),
    );

    await resolver.searchEpisodeCandidates(
      keyword: '测试动画 Season 2',
      episodeNumber: 2,
      tmdbId: '',
    );

    expect(requestedAnime.first, '测试动画 Season 2');
  });

  test('搜索启用弹弹play新版搜索引擎', () async {
    Object? requestedV2;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedV2 ??= options.queryParameters['v2'];
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: const <String, dynamic>{'animes': <dynamic>[]},
            ),
          );
        },
      ),
    );
    final resolver = DanDanPlayResolver(
      DanDanPlayApi(dio: dio, appId: 'test', appSecret: 'secret'),
    );

    await resolver.searchEpisodeCandidates(
      keyword: '测试动画',
      episodeNumber: 1,
      tmdbId: '',
    );

    expect(requestedV2, isTrue);
  });

  test('评论缓存不可用时仍回源并返回弹幕', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data:
                  '{"count":1,"comments":[{"cid":1,"p":"1.5,1,16777215,test","m":"测试弹幕"}]}',
            ),
          );
        },
      ),
    );
    final resolver = DanDanPlayResolver(
      DanDanPlayApi(dio: dio, appId: 'test', appSecret: 'secret'),
      cacheStore: const _UnavailableCommentCacheStore(),
    );

    final result = await resolver.importEpisodeById(
      const DanDanPlayEpisodeSearchItem(
        episodeId: 186100011,
        animeTitle: '他国日记',
        episodeTitle: '第11话 解放',
        episodeNumber: 11,
      ),
    );

    expect(result?.comments.single.text, '测试弹幕');
  });
}

class _UnavailableCommentCacheStore extends DanDanPlayCommentCacheStore {
  const _UnavailableCommentCacheStore();

  @override
  Future<String?> loadComments(int episodeId) =>
      Future<String?>.error(StateError('databaseFactory not initialized'));

  @override
  Future<void> saveComments({
    required int episodeId,
    required String content,
  }) => Future<void>.error(StateError('databaseFactory not initialized'));
}
