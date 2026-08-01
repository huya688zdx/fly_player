import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/theme/dynamic_theme_runtime_controller.dart';
import 'package:fly_player/theme/dynamic_theme_seed_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fly_player/theme_sampler');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await DynamicThemeSeedExtractor.clearCache();
    await DynamicThemeRuntimeController.instance.clearCachedSeeds();
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await DynamicThemeSeedExtractor.clearCache();
    await DynamicThemeRuntimeController.instance.clearCachedSeeds();
  });

  test('Android 原生取色通道接收完整图片请求头', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return _samplePixels;
    });
    const headers = <String, String>{
      'Authorization': 'NAS_TOKEN',
      'Trim-MC-token': 'NAS_TOKEN',
      'x-access-code': 'BASE64_ACCESS_CODE',
      'x-access-source': 'app',
    };

    final seed = await DynamicThemeSeedExtractor.extract(
      imageUrl: 'https://nas.example/image-theme-test.jpg',
      imageHeaders: headers,
    );

    expect(seed, isNotNull);
    expect(capturedCall?.method, 'sampleImagePixels');
    final arguments = capturedCall?.arguments as Map<Object?, Object?>;
    expect(arguments['imageUrl'], 'https://nas.example/image-theme-test.jpg');
    expect(arguments['headers'], headers);
    expect(arguments, isNot(contains('token')));
  });

  test('同 URL 仅在规范化 headers 相同时复用提取缓存', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return _samplePixels;
    });
    const url = 'https://nas.example/cache-scope.jpg';

    await DynamicThemeSeedExtractor.extract(
      imageUrl: url,
      imageHeaders: const <String, String>{
        'Authorization': ' token-a ',
        'X-Access-Source': 'app',
      },
    );
    await DynamicThemeSeedExtractor.extract(
      imageUrl: url,
      imageHeaders: const <String, String>{
        'x-access-source': 'app',
        'authorization': 'token-a',
      },
    );
    await DynamicThemeSeedExtractor.extract(
      imageUrl: url,
      imageHeaders: const <String, String>{'Authorization': 'token-b'},
    );

    expect(calls, 2);
  });

  test('同 URL 不同 headers 不合并 inflight，相同 headers 会合并', () async {
    var calls = 0;
    final gate = Completer<Map<String, Object>>();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls++;
      return gate.future;
    });
    const url = 'https://nas.example/inflight-scope.jpg';

    final first = DynamicThemeSeedExtractor.extract(
      imageUrl: url,
      imageHeaders: const <String, String>{'Authorization': 'token-a'},
    );
    final equivalent = DynamicThemeSeedExtractor.extract(
      imageUrl: url,
      imageHeaders: const <String, String>{'authorization': ' token-a '},
    );
    final different = DynamicThemeSeedExtractor.extract(
      imageUrl: url,
      imageHeaders: const <String, String>{'Authorization': 'token-b'},
    );
    await Future<void>.delayed(Duration.zero);

    expect(calls, 2);
    gate.complete(_samplePixels);
    await Future.wait(<Future<DynamicThemeSeed?>>[
      first,
      equivalent,
      different,
    ]);
  });

  test('带 headers 的缓存仅驻留内存且不落确定性摘要', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => _samplePixels);
    const secret = 'plain-secret-must-not-persist';
    const url = 'https://nas.example/persistent-scope.jpg';

    await DynamicThemeSeedExtractor.extract(
      imageUrl: url,
      imageHeaders: const <String, String>{'Authorization': secret},
    );
    final prefs = await SharedPreferences.getInstance();
    await DynamicThemeSeedExtractor.flushPendingWrites(prefs: prefs);

    expect(DynamicThemeSeedExtractor.countPersistentCacheEntries(prefs), 0);
    final deterministicDigest = sha256
        .convert(
          utf8.encode(
            jsonEncode(<List<String>>[
              <String>['authorization', secret],
            ]),
          ),
        )
        .toString();
    expect(prefs.getKeys(), isNotEmpty);
    for (final key in prefs.getKeys()) {
      expect(prefs.get(key).toString(), isNot(contains(secret)));
      expect(prefs.get(key).toString(), isNot(contains(deterministicDigest)));
    }
  });

  test('空 headers 的公开图片缓存仍可持久化', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => _samplePixels);

    await DynamicThemeSeedExtractor.extract(
      imageUrl: 'https://public.example/poster.jpg',
    );
    final prefs = await SharedPreferences.getInstance();
    await DynamicThemeSeedExtractor.flushPendingWrites(prefs: prefs);

    expect(DynamicThemeSeedExtractor.countPersistentCacheEntries(prefs), 1);
  });

  test('页面运行时缓存同样按 headers 隔离', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return _samplePixels;
    });
    const url = 'https://nas.example/runtime-scope.jpg';
    const firstHeaders = <String, String>{'Authorization': 'runtime-a'};
    const secondHeaders = <String, String>{'Authorization': 'runtime-b'};

    final first = await DynamicThemeRuntimeController.instance.getOrResolve(
      key: 'same-page',
      imageUrl: url,
      imageHeaders: firstHeaders,
    );
    expect(first, isNotNull);
    expect(
      DynamicThemeRuntimeController.instance.cachedSeedFor(
        'same-page',
        imageUrl: url,
        imageHeaders: firstHeaders,
      ),
      same(first),
    );
    expect(
      DynamicThemeRuntimeController.instance.cachedSeedFor(
        'same-page',
        imageUrl: url,
        imageHeaders: secondHeaders,
      ),
      isNull,
    );

    final second = await DynamicThemeRuntimeController.instance.getOrResolve(
      key: 'same-page',
      imageUrl: url,
      imageHeaders: secondHeaders,
    );
    expect(second, isNotNull);
    expect(calls, 2);

    final prefs = await SharedPreferences.getInstance();
    await DynamicThemeRuntimeController.instance.flushPendingWrites(
      prefs: prefs,
    );
    expect(
      DynamicThemeRuntimeController.instance.countPersistentCacheEntries(prefs),
      0,
    );
    for (final key in prefs.getKeys()) {
      expect(prefs.get(key).toString(), isNot(contains('runtime-a')));
      expect(prefs.get(key).toString(), isNot(contains('runtime-b')));
    }
  });

  test('primePageSeed 仅在相同图片 headers 作用域可达', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => _samplePixels);
    const url = 'https://nas.example/episode-prime.jpg';
    const headers = <String, String>{'Authorization': 'episode-token'};

    final source = await DynamicThemeSeedExtractor.extract(
      imageUrl: url,
      imageHeaders: headers,
    );
    expect(source, isNotNull);
    DynamicThemeRuntimeController.instance.primePageSeed(
      key: 'episode-id',
      imageUrl: url,
      imageHeaders: headers,
    );

    expect(
      DynamicThemeRuntimeController.instance.cachedSeedFor(
        'episode-id',
        imageUrl: url,
        imageHeaders: headers,
      ),
      same(source),
    );
    expect(
      DynamicThemeRuntimeController.instance.cachedSeedFor(
        'episode-id',
        imageUrl: url,
      ),
      isNull,
    );
  });

  test('mapCachedOrNull 按传入图片 headers 选择页面缓存', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => _samplePixels);
    const url = 'https://nas.example/map-scope.jpg';
    const headers = <String, String>{'Authorization': 'map-token'};
    await DynamicThemeRuntimeController.instance.getOrResolve(
      key: 'map-page',
      imageUrl: url,
      imageHeaders: headers,
    );

    final scoped = DynamicThemeRuntimeController.instance.mapCachedOrNull(
      key: 'map-page',
      imageHeaders: headers,
      baseColors: AppThemePalette.fallback,
      intensity: AppDynamicThemeIntensity.medium,
    );
    final unscoped = DynamicThemeRuntimeController.instance.mapCachedOrNull(
      key: 'map-page',
      baseColors: AppThemePalette.fallback,
      intensity: AppDynamicThemeIntensity.medium,
    );

    expect(scoped, isNot(same(AppThemePalette.fallback)));
    expect(unscoped, same(AppThemePalette.fallback));
  });
}

final Map<String, Object> _samplePixels = <String, Object>{
  'pixels': Int32List.fromList(<int>[
    0xFFFF0000,
    0xFF00FF00,
    0xFF0000FF,
    0xFFFFFFFF,
  ]),
};
