import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';

void main() {
  test('并发请求共享同一个打开 Future，完成后允许下一轮打开', () async {
    final gate = FutureOpenGate<int>();
    final firstCompleter = Completer<int>();
    var openCount = 0;

    Future<int> open() {
      openCount += 1;
      return firstCompleter.future;
    }

    final first = gate.run(open);
    final second = gate.run(open);
    expect(identical(first, second), isTrue);
    expect(openCount, 1);

    firstCompleter.complete(1);
    expect(await first, 1);

    final next = gate.run(() async {
      openCount += 1;
      return 2;
    });
    expect(await next, 2);
    expect(openCount, 2);
  });

  test('打开失败后清理门闩，后续请求可以重试', () async {
    final gate = FutureOpenGate<int>();
    var openCount = 0;

    Future<int> open() async {
      openCount += 1;
      throw StateError('open failed');
    }

    await expectLater(gate.run(open), throwsStateError);
    await expectLater(gate.run(open), throwsStateError);
    expect(openCount, 2);
  });
}
