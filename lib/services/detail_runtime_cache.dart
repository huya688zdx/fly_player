import 'dart:collection';
import 'dart:async';

/// 提供按业务桶隔离的详情页运行时内存缓存。
class DetailRuntimeCache {
  DetailRuntimeCache._();

  static const int _maxEntriesPerBucket = 48;

  static final DetailRuntimeCache instance = DetailRuntimeCache._();

  final Map<String, LinkedHashMap<String, Object?>> _cache =
      <String, LinkedHashMap<String, Object?>>{};
  final Map<String, Future<Object?>> _inflight = <String, Future<Object?>>{};

  /// 按键读取缓存；若不存在则执行加载器并回填缓存。
  Future<T> getOrLoad<T>({
    required String bucket,
    required String key,
    required Future<T> Function() loader,
  }) async {
    final normalizedBucket = bucket.trim();
    final normalizedKey = key.trim();
    if (normalizedBucket.isEmpty || normalizedKey.isEmpty) {
      return loader();
    }

    final bucketCache = _cache.putIfAbsent(
      normalizedBucket,
      () => LinkedHashMap<String, Object?>(),
    );
    final cached = bucketCache.remove(normalizedKey);
    if (cached is T) {
      bucketCache[normalizedKey] = cached;
      return cached;
    }

    final inflightKey = '$normalizedBucket::$normalizedKey';
    final pending = _inflight[inflightKey];
    if (pending != null) {
      return (await pending) as T;
    }

    final future = loader().then<Object?>(
      (value) {
        bucketCache.remove(normalizedKey);
        bucketCache[normalizedKey] = value;
        while (bucketCache.length > _maxEntriesPerBucket) {
          bucketCache.remove(bucketCache.keys.first);
        }
        _inflight.remove(inflightKey);
        return value;
      },
      onError: (Object error, StackTrace stackTrace) {
        _inflight.remove(inflightKey);
        throw error;
      },
    );

    _inflight[inflightKey] = future;
    return (await future) as T;
  }

  /// 使指定桶中的单个缓存项失效。
  void invalidate(String bucket, String key) {
    final normalizedBucket = bucket.trim();
    final normalizedKey = key.trim();
    if (normalizedBucket.isEmpty || normalizedKey.isEmpty) return;
    _cache[normalizedBucket]?.remove(normalizedKey);
    _inflight.remove('$normalizedBucket::$normalizedKey');
  }

  /// 清空指定缓存桶及其进行中的加载任务。
  void clearBucket(String bucket) {
    final normalizedBucket = bucket.trim();
    if (normalizedBucket.isEmpty) return;
    _cache.remove(normalizedBucket);
    _inflight.removeWhere((key, _) => key.startsWith('$normalizedBucket::'));
  }

  /// 清空全部缓存桶与进行中的加载任务。
  void clearAll() {
    _cache.clear();
    _inflight.clear();
  }
}
