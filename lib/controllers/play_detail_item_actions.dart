import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';

/// 表示详情页动作执行后的结果。
class PlayDetailActionResult {
  final bool state;
  final String message;
  final bool needRefresh;

  /// 根据动作结果状态构造对象。
  const PlayDetailActionResult({
    required this.state,
    required this.message,
    required this.needRefresh,
  });
}

/// 封装详情页常用的收藏与观看状态操作。
class PlayDetailItemActions {
  final FeiniuApi api;
  final AppLocalizations l10n;

  /// 根据 API 实例与本地化文案构造动作执行器。
  const PlayDetailItemActions(this.api, {required this.l10n});

  /// 切换条目的收藏状态。
  Future<PlayDetailActionResult> toggleFavorite({
    required String itemGuid,
    required bool currentLiked,
  }) async {
    final target = !currentLiked;
    final liked = await api.setFavorite(itemGuid, favorite: target);
    return PlayDetailActionResult(
      state: liked,
      message: liked ? l10n.actionFavoriteAdded : l10n.actionFavoriteRemoved,
      needRefresh: false,
    );
  }

  /// 切换条目的观看状态。
  Future<PlayDetailActionResult> toggleWatched({
    required String itemGuid,
    required bool currentWatched,
  }) async {
    final target = !currentWatched;
    final watched = await api.setWatched(itemGuid, watched: target);
    return PlayDetailActionResult(
      state: watched,
      message: watched
          ? l10n.actionMarkedAsWatched
          : l10n.actionMarkedAsUnwatched,
      needRefresh: true,
    );
  }
}
