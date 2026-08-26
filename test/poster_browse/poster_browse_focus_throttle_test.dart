import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_focus_throttle.dart';

void main() {
  test('连续调度只触发最后一次，且在 300ms 后', () {
    fakeAsync((async) {
      final settled = <String>[];
      final throttle = PosterBrowseFocusThrottle(onSettle: settled.add);
      throttle.schedule('a');
      async.elapse(const Duration(milliseconds: 100));
      throttle.schedule('b');
      async.elapse(const Duration(milliseconds: 100));
      throttle.schedule('c');
      expect(settled, isEmpty);
      async.elapse(const Duration(milliseconds: 300));
      expect(settled, ['c']);
      throttle.dispose();
    });
  });

  test('dispose 后不再触发', () {
    fakeAsync((async) {
      final settled = <String>[];
      PosterBrowseFocusThrottle(onSettle: settled.add)
        ..schedule('a')
        ..dispose();
      async.elapse(const Duration(seconds: 1));
      expect(settled, isEmpty);
    });
  });

  test('dispose 后调用 schedule 不再排新定时器、不触发', () {
    fakeAsync((async) {
      final settled = <String>[];
      final throttle = PosterBrowseFocusThrottle(onSettle: settled.add);
      throttle.dispose();
      throttle.schedule('a');
      async.elapse(const Duration(seconds: 1));
      expect(settled, isEmpty);
    });
  });
}
