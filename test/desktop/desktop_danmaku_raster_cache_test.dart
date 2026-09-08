import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/desktop/playback/desktop_danmaku_raster_cache.dart';

DanmakuRasterKey _key(String text, {int fillColor = 0xFFFFFFFF}) {
  return DanmakuRasterKey(
    text: text,
    fontSize: 22,
    maxWidthPx: 1280,
    fillColor: fillColor,
    strokeWidth: 2.2,
    bold: false,
    fontFamily: null,
    devicePixelRatio: 1000,
  );
}

DanmakuRasterEntry _buildFor(
  DanmakuRasterKey key, {
  double devicePixelRatio = 1.0,
}) {
  return DanmakuRasterCache.build(
    text: key.text,
    fontSize: key.fontSize,
    maxWidthPx: key.maxWidthPx,
    fillColor: key.fillColor,
    strokeWidth: key.strokeWidth,
    bold: key.bold,
    fontFamily: key.fontFamily,
    devicePixelRatio: devicePixelRatio,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DanmakuRasterCache', () {
    test('同一键命中缓存，不重复构建', () {
      final cache = DanmakuRasterCache();
      final key = _key('你好弹幕');
      expect(cache.lookup(key), isNull);

      final built = _buildFor(key);
      cache.put(key, built);

      expect(identical(cache.lookup(key), built), isTrue);
      expect(identical(cache.lookup(key), built), isTrue);
      cache.dispose();
    });

    test('样式因子任一不同即为不同键', () {
      final base = _key('同一文本');
      final variants = <DanmakuRasterKey>[
        DanmakuRasterKey(
          text: base.text,
          fontSize: 24,
          maxWidthPx: base.maxWidthPx,
          fillColor: base.fillColor,
          strokeWidth: base.strokeWidth,
          bold: base.bold,
          fontFamily: base.fontFamily,
          devicePixelRatio: base.devicePixelRatio,
        ),
        DanmakuRasterKey(
          text: base.text,
          fontSize: base.fontSize,
          maxWidthPx: 640,
          fillColor: base.fillColor,
          strokeWidth: base.strokeWidth,
          bold: base.bold,
          fontFamily: base.fontFamily,
          devicePixelRatio: base.devicePixelRatio,
        ),
        DanmakuRasterKey(
          text: base.text,
          fontSize: base.fontSize,
          maxWidthPx: base.maxWidthPx,
          fillColor: 0x80FFFFFF,
          strokeWidth: base.strokeWidth,
          bold: base.bold,
          fontFamily: base.fontFamily,
          devicePixelRatio: base.devicePixelRatio,
        ),
        DanmakuRasterKey(
          text: base.text,
          fontSize: base.fontSize,
          maxWidthPx: base.maxWidthPx,
          fillColor: base.fillColor,
          strokeWidth: 4.4,
          bold: base.bold,
          fontFamily: base.fontFamily,
          devicePixelRatio: base.devicePixelRatio,
        ),
        DanmakuRasterKey(
          text: base.text,
          fontSize: base.fontSize,
          maxWidthPx: base.maxWidthPx,
          fillColor: base.fillColor,
          strokeWidth: base.strokeWidth,
          bold: true,
          fontFamily: base.fontFamily,
          devicePixelRatio: base.devicePixelRatio,
        ),
        DanmakuRasterKey(
          text: base.text,
          fontSize: base.fontSize,
          maxWidthPx: base.maxWidthPx,
          fillColor: base.fillColor,
          strokeWidth: base.strokeWidth,
          bold: base.bold,
          fontFamily: base.fontFamily,
          devicePixelRatio: 2000,
        ),
      ];

      for (final key in variants) {
        expect(key == base, isFalse, reason: '$key 不应等于基准键');
        expect(key.hashCode == base.hashCode, isFalse, reason: '$key 哈希不应撞基准');
      }
    });

    test('LRU 淘汰最久未使用的条目', () {
      final cache = DanmakuRasterCache(capacity: 2);
      final keyA = _key('弹幕A');
      final keyB = _key('弹幕B');
      final keyC = _key('弹幕C');
      for (final key in [keyA, keyB, keyC]) {
        cache.put(key, _buildFor(key));
      }
      expect(cache.lookup(keyA), isNull, reason: 'A 最旧，应被淘汰');
      expect(cache.lookup(keyB), isNotNull);
      expect(cache.lookup(keyC), isNotNull);
      cache.dispose();
    });

    test('触碰会把条目移到 LRU 尾部，免于淘汰', () {
      final cache = DanmakuRasterCache(capacity: 2);
      final keyA = _key('弹幕A');
      final keyB = _key('弹幕B');
      final keyC = _key('弹幕C');
      cache.put(keyA, _buildFor(keyA));
      cache.put(keyB, _buildFor(keyB));
      expect(cache.lookup(keyA), isNotNull, reason: '先触碰 A，让 B 变成 LRU 头');
      cache.put(keyC, _buildFor(keyC));
      expect(cache.lookup(keyA), isNotNull, reason: 'A 被触碰过，B 才是被淘汰者');
      expect(cache.lookup(keyB), isNull);
      cache.dispose();
    });

    test('build 产出的位图按 DPR 栅格化并留描边出血边', () {
      final entry = _buildFor(_key('弹幕渲染'), devicePixelRatio: 2.0);
      addTearDown(entry.image.dispose);
      expect(entry.width, greaterThan(0));
      expect(entry.height, greaterThan(0));
      expect(entry.padding, greaterThan(0));
      expect(entry.image, isA<ui.Image>());
      // 位图尺寸 = (文本 + 2*出血边) * DPR，向上取整。
      final expectedW = ((entry.width + entry.padding * 2) * 2.0).ceil();
      final expectedH = ((entry.height + entry.padding * 2) * 2.0).ceil();
      expect(entry.image.width, expectedW);
      expect(entry.image.height, expectedH);
    });
  });
}
