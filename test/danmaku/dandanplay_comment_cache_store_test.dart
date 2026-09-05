import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/cache/dandanplay_comment_cache_store.dart';

void main() {
  test('六小时内的弹弹play评论缓存仍然有效', () {
    const nowMs = 10 * 60 * 60 * 1000;
    final fetchedAtMs = nowMs - const Duration(hours: 6).inMilliseconds + 1;

    expect(
      DanDanPlayCommentCacheStore.isFresh(
        fetchedAtMs: fetchedAtMs,
        nowMs: nowMs,
      ),
      isTrue,
    );
  });

  test('超过六小时的弹弹play评论缓存必须刷新', () {
    const nowMs = 10 * 60 * 60 * 1000;
    final fetchedAtMs = nowMs - const Duration(hours: 6).inMilliseconds - 1;

    expect(
      DanDanPlayCommentCacheStore.isFresh(
        fetchedAtMs: fetchedAtMs,
        nowMs: nowMs,
      ),
      isFalse,
    );
  });
}
