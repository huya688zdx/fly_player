import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 继续观看整行后台补全（291cc42d 引入，曾于 55eb98aa 首屏性能优化时移除，
/// 2026-10-02 按产品要求恢复）：整行卡片无需点击即显示季海报。
/// 防回归要点：warmup 接线在位、首帧让路、限并发、焦点补全仍存在。
void main() {
  test('继续观看整行后台补全在位：首帧让路 + 限并发 + 焦点补全保留', () {
    final source = File(
      'lib/screens/poster_browse/poster_browse_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_warmContinueWatchingRow('));
    expect(source, contains('PosterBrowseRowArtworkWarmup(maxConcurrent: 2)'));
    // warmup 先让首帧绘制完成，避免挤占首屏加载。
    expect(source, contains('await WidgetsBinding.instance.endOfFrame;'));
    expect(source, contains('if (_enrichmentRunning) return;'));
    expect(
      source,
      contains('setState(() => _displayById[card.id] = enrichedDisplay);'),
    );
  });
}
