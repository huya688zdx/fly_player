import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/utils/private_network_http_overrides.dart';

/// 海报图加载的三处修复（实测：424 部电影的库，一屏约一半海报卡在占位图，
/// 而同一 NAS 用别的客户端正常）。
///
/// 三条叠加导致请求量被放大并容易失败：
/// 1. 网格 `cacheExtent` 取屏高 0.7~1.0 倍（1080p 下 ~700-900px），等于上下各多建
///    4~5 行，请求量放大 4 倍以上；
/// 2. 图片请求没有并发上限（dart:io 默认不限，`NetworkImage` 又共用一个 static
///    HttpClient），几十上百个请求同时打到 NAS 的按需缩图服务；
/// 3. 最终失败后不重试，一次瞬时失败就永久占位。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('图片 HttpClient 限制每 host 并发连接数为 6', () {
    final client = PrivateNetworkHttpOverrides().createHttpClient(null);
    addTearDown(() => client.close(force: true));
    expect(
      client.maxConnectionsPerHost,
      6,
      reason: 'dart:io 默认不限并发，海报网格会把 NAS 缩图服务打满',
    );
  });

  test('网格预建距离降到接近 Flutter 默认量级', () {
    final source = File(
      'lib/screens/category_items_screen.dart',
    ).readAsStringSync();
    // 原实现是 min(屏高 * factor, 900)。
    expect(
      source,
      isNot(contains('900.0')),
      reason: '预建距离又回到 900px，请求量会被放大 4 倍以上',
    );
    expect(source, contains('double get _viewportCacheExtent'));
    expect(source, contains('widget.secondaryHost ? 220.0 : 300.0'));
  });

  test('海报最终失败后会重试一次，不再永久占位', () {
    final source = File('lib/ui/media_poster_card.dart').readAsStringSync();
    expect(source, contains('_scheduleRetry();'), reason: '失败分支没有接重试');
    expect(source, contains('static const int _maxRetries = 1;'));
    expect(source, contains('void _scheduleRetry()'), reason: '缺少重试实现');
    // 换图源时要复位重试计数，否则同一 widget 复用新图后不再重试。
    expect(source, contains('_retryCount = 0;'));
  });
}
