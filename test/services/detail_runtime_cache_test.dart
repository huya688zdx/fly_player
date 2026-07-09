import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/detail_runtime_cache.dart';

Future<int> _failingRuntimeCacheLoader() async {
  try {
    throw StateError('from loader');
  } catch (error, stackTrace) {
    return Future<int>.error(error, stackTrace);
  }
}

void main() {
  setUp(() {
    DetailRuntimeCache.instance.clearAll();
  });

  test('loader 失败时保留原始堆栈', () async {
    try {
      await DetailRuntimeCache.instance.getOrLoad<int>(
        bucket: 'detail',
        key: 'item-1',
        loader: _failingRuntimeCacheLoader,
      );
      fail('loader should throw');
    } on StateError catch (error, stackTrace) {
      expect(error.message, 'from loader');
      expect(stackTrace.toString(), contains('_failingRuntimeCacheLoader'));
    }
  });
}
