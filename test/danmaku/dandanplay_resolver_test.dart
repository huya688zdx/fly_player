import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/api/dandanplay_resolver.dart';
import 'package:fly_player/danmaku/models/dandanplay_episode_search_item.dart';

void main() {
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
}
