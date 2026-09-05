import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../../media_backend/media_item_card.dart';
import 'poster_browse_artwork_enricher.dart';
import 'poster_browse_artwork_priority.dart';

typedef PosterBrowsePrewarmLoad =
    Future<PosterBrowseEnrichment> Function(MediaItemCard card);

/// 首屏需要在展示前补全的封面数量。
///
/// 竖屏弧形列表只会突出中心和左右邻居；横屏一行会同时露出更多卡片，
/// 但最多等待八张，避免弱性能设备因素材请求过多拖慢首次进入。
abstract final class PosterBrowseInitialArtworkPolicy {
  static const int _portraitVisibleCount = 3;
  static const int _landscapeVisibleCount = 8;

  static int visibleCountFor({required double width, required double height}) {
    return width <= height ? _portraitVisibleCount : _landscapeVisibleCount;
  }

  /// 竖屏是以第 0 项为中心的循环轮盘；横屏是从第 0 项开始的线性列表。
  static int? centerIndexFor({required double width, required double height}) {
    return width <= height ? 0 : null;
  }
}

/// 首页与海报浏览页共享的少量素材预热缓存。
///
/// 缓存键包含后端会话，避免不同服务器或账号串用；仅保存有限条成功结果，失败立即移除。
/// 进行中的 Future 也可被海报页复用，防止用户在预热尚未完成时进入页面产生重复请求。
class PosterBrowseArtworkPrewarmCache {
  PosterBrowseArtworkPrewarmCache({this.maxEntries = 12})
    : assert(maxEntries >= 0);

  static final PosterBrowseArtworkPrewarmCache shared =
      PosterBrowseArtworkPrewarmCache();

  final int maxEntries;
  final LinkedHashMap<String, _PrewarmEntry> _entries =
      LinkedHashMap<String, _PrewarmEntry>();

  PosterBrowseEnrichment? peek({
    required String sessionKey,
    required String itemId,
  }) {
    final key = _cacheKey(sessionKey, itemId);
    final entry = _touch(key);
    return entry?.result;
  }

  Future<PosterBrowseEnrichment>? futureFor({
    required String sessionKey,
    required String itemId,
  }) {
    final key = _cacheKey(sessionKey, itemId);
    return _touch(key)?.future;
  }

  Future<void> warmFirst({
    required String sessionKey,
    required List<MediaItemCard> items,
    required PosterBrowsePrewarmLoad load,
    required bool Function() isActive,
    int? centerIndex,
    int limit = 4,
    int maxConcurrent = 1,
  }) async {
    await resolveVisible(
      sessionKey: sessionKey,
      items: items,
      load: load,
      isActive: isActive,
      centerIndex: centerIndex,
      limit: limit,
      maxConcurrent: maxConcurrent,
    );
  }

  /// 补全当前可见窗口，并复用首页已经开始的请求。
  Future<Map<String, PosterBrowseEnrichment>> resolveVisible({
    required String sessionKey,
    required List<MediaItemCard> items,
    required PosterBrowsePrewarmLoad load,
    required bool Function() isActive,
    int? centerIndex,
    required int limit,
    int maxConcurrent = 2,
  }) async {
    if (limit <= 0 || maxConcurrent <= 0 || items.isEmpty || !isActive()) {
      return const <String, PosterBrowseEnrichment>{};
    }

    final queue = prioritizePosterBrowseArtworkItems(
      items: items,
      centerIndex: centerIndex,
      limit: limit,
    );
    final resolved = <String, PosterBrowseEnrichment>{};
    var nextIndex = 0;

    Future<void> worker() async {
      while (isActive() && nextIndex < queue.length) {
        final card = queue[nextIndex];
        nextIndex += 1;
        try {
          final enrichment = await _loadOrReuse(
            sessionKey: sessionKey,
            card: card,
            load: load,
          );
          if (isActive()) resolved[card.id] = enrichment;
        } catch (_) {
          // 预热是旁路优化，单项失败不阻断首页和后续条目。
        }
      }
    }

    await Future.wait<void>(
      List<Future<void>>.generate(
        math.min(maxConcurrent, queue.length),
        (_) => worker(),
      ),
    );
    return resolved;
  }

  Future<PosterBrowseEnrichment> _loadOrReuse({
    required String sessionKey,
    required MediaItemCard card,
    required PosterBrowsePrewarmLoad load,
  }) {
    final key = _cacheKey(sessionKey, card.id);
    final existing = _touch(key);
    if (existing != null) return existing.future;

    late final _PrewarmEntry entry;
    final future = Future<PosterBrowseEnrichment>.sync(() => load(card))
        .then((result) {
          if (!identical(_entries[key], entry)) return result;
          if (result.isFailure) {
            _entries.remove(key);
          } else {
            entry.result = result;
            _touch(key);
          }
          return result;
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (identical(_entries[key], entry)) {
            _entries.remove(key);
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
    entry = _PrewarmEntry(future);
    _entries[key] = entry;
    _trim();
    return future;
  }

  _PrewarmEntry? _touch(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _entries[key] = entry;
    return entry;
  }

  void _trim() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  String _cacheKey(String sessionKey, String itemId) =>
      '${sessionKey.trim()}|${itemId.trim()}';
}

class _PrewarmEntry {
  _PrewarmEntry(this.future);

  final Future<PosterBrowseEnrichment> future;
  PosterBrowseEnrichment? result;
}
