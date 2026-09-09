import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_danmaku_clock.dart';

void main() {
  test('异步采样抖动不回跳，60Hz 刷新不丢成隔帧绘制', () {
    final clock = DesktopDanmakuClock(
      position: Duration.zero,
      advancing: true,
      rate: 1,
    );
    var frames = 0;
    for (var frame = 0; frame < 600; frame++) {
      final elapsed = Duration(microseconds: (frame * 1000000 / 60).round());
      final previous = clock.position;
      if (clock.tick(elapsed, frameRate: 60)) frames++;
      if (frame > 0) {
        expect(
          (clock.position - previous).inMicroseconds,
          inInclusiveRange(16332, 17001),
        );
      }
      if (frame % 3 == 0) {
        final beforeSample = clock.position;
        clock.synchronize(
          elapsed - Duration(milliseconds: frame.isEven ? 80 : 20),
        );
        expect(clock.position, beforeSample, reason: '采样不能瞬间改变弹幕位置');
      }
    }
    expect(frames, 600);
  });

  test('暂停冻结，恢复和跳转仍对齐播放时间', () {
    final clock = DesktopDanmakuClock(
      position: Duration.zero,
      advancing: true,
      rate: 1,
    );
    clock.tick(const Duration(seconds: 1), frameRate: 120);
    clock.advancing = false;
    clock.tick(const Duration(seconds: 3), frameRate: 120);
    expect(clock.position, const Duration(seconds: 1));
    clock.advancing = true;
    clock.tick(const Duration(seconds: 4), frameRate: 120);
    expect(clock.position, const Duration(seconds: 2));
    expect(clock.synchronize(const Duration(seconds: 30)), isTrue);
    expect(clock.position, const Duration(seconds: 30));
  });
}
