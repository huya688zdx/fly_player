import 'dart:async';

import 'package:fly_player/screens/poster_browse/poster_browse_catalog_load_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A、B 逆序完成时只有最后选择的 B 可应用选择副作用', () async {
    final coordinator = PosterBrowseCatalogLoadCoordinator<int>();
    final a = Completer<int>();
    final b = Completer<int>();

    final aTicket = coordinator.acquire(
      catalogId: 'a',
      selectWhenReady: true,
      load: () => a.future,
    );
    final bTicket = coordinator.acquire(
      catalogId: 'b',
      selectWhenReady: true,
      load: () => b.future,
    );

    a.complete(1);
    expect(await aTicket.future, 1);
    expect(coordinator.shouldSelect('a'), isFalse);

    b.complete(2);
    expect(await bTicket.future, 2);
    expect(coordinator.shouldSelect('b'), isTrue);
  });

  test('后台加载期间重复点击只保留一个完成状态提交者并更新选择意图', () {
    final coordinator = PosterBrowseCatalogLoadCoordinator<int>();
    final completer = Completer<int>();
    var loadCalls = 0;

    final backgroundTicket = coordinator.acquire(
      catalogId: 'a',
      selectWhenReady: false,
      load: () {
        loadCalls += 1;
        return completer.future;
      },
    );
    final firstTapTicket = coordinator.acquire(
      catalogId: 'a',
      selectWhenReady: true,
      load: () => throw StateError('不应再次加载'),
    );
    final secondTapTicket = coordinator.acquire(
      catalogId: 'a',
      selectWhenReady: true,
      load: () => throw StateError('不应再次加载'),
    );

    expect(backgroundTicket.ownsCompletion, isTrue);
    expect(firstTapTicket.ownsCompletion, isFalse);
    expect(secondTapTicket.ownsCompletion, isFalse);
    expect(firstTapTicket.future, same(backgroundTicket.future));
    expect(secondTapTicket.future, same(backgroundTicket.future));
    expect(loadCalls, 1);
    expect(coordinator.shouldSelect('a'), isTrue);
  });

  test('释放唯一提交者后同一目录可开始新的重试任务', () async {
    final coordinator = PosterBrowseCatalogLoadCoordinator<int>();
    final first = coordinator.acquire(
      catalogId: 'a',
      selectWhenReady: true,
      load: () async => 1,
    );

    expect(await first.future, 1);
    coordinator.release(first);
    final retry = coordinator.acquire(
      catalogId: 'a',
      selectWhenReady: true,
      load: () async => 2,
    );

    expect(retry.ownsCompletion, isTrue);
    expect(await retry.future, 2);
  });
}
