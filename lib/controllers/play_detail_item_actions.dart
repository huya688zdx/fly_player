import '../api/feiniu_api.dart';
import '../utils/media_locale_store.dart';

class PlayDetailActionResult {
  final bool state;
  final String message;
  final bool needRefresh;

  const PlayDetailActionResult({
    required this.state,
    required this.message,
    required this.needRefresh,
  });
}

class PlayDetailItemActions {
  final FeiniuApi api;
  final Map<String, dynamic> localeMap;

  const PlayDetailItemActions(
    this.api, {
    this.localeMap = const <String, dynamic>{},
  });

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<PlayDetailActionResult> toggleFavorite({
    required String itemGuid,
    required bool currentLiked,
  }) async {
    final target = !currentLiked;
    final liked = await api.setFavorite(itemGuid, favorite: target);
    return PlayDetailActionResult(
      state: liked,
      message: liked
          ? _t('common.actions.favorite.favorited', '已加入收藏')
          : _t('common.actions.favorite.notFavorited', '已取消收藏'),
      needRefresh: false,
    );
  }

  Future<PlayDetailActionResult> toggleWatched({
    required String itemGuid,
    required bool currentWatched,
  }) async {
    final target = !currentWatched;
    final watched = await api.setWatched(itemGuid, watched: target);
    return PlayDetailActionResult(
      state: watched,
      message: watched
          ? _t('common.actions.watched.markedAsWatched', '已标记为已观看')
          : _t('common.actions.watched.markedAsUnwatched', '已标记为未观看'),
      needRefresh: true,
    );
  }
}
