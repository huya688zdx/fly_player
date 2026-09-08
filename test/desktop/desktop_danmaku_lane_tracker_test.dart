import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/desktop/playback/desktop_danmaku_lane_tracker.dart';
import 'package:fly_player/danmaku/models/danmaku_comment.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';

DanmakuComment _comment(
  int timeMs, {
  DanmakuCommentType type = DanmakuCommentType.scroll,
  String? text,
}) {
  return DanmakuComment(
    id: '$timeMs-${text ?? ''}',
    timeMs: timeMs,
    text: text ?? '弹幕 $timeMs',
    type: type,
    color: Colors.white,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DanmakuLaneTracker', () {
    test('车道出生时分配一次，之后帧保持不变', () {
      final tracker = DanmakuLaneTracker();
      final comments = <DanmakuComment>[_comment(0), _comment(500)];
      tracker.beginFrame(
        comments: comments,
        settings: DanmakuSettings.defaults,
        laneCount: 4,
      );
      final laneA = tracker.laneForScroll(
        comment: comments[0],
        nowMs: 0,
        width: 200,
        canvasWidth: 1000,
        lifetimeMs: 9000,
      );
      final laneB = tracker.laneForScroll(
        comment: comments[1],
        nowMs: 500,
        width: 200,
        canvasWidth: 1000,
        lifetimeMs: 9000,
      );
      expect(laneA, 0);
      expect(laneB, greaterThan(0), reason: 'A 尚未完全进屏，B 不应挤进同车道');

      // 数帧后重复查询：已分配的弹幕车道必须原样返回。
      for (var nowMs = 1000; nowMs <= 4000; nowMs += 500) {
        expect(
          tracker.laneForScroll(
            comment: comments[0],
            nowMs: nowMs,
            width: 200,
            canvasWidth: 1000,
            lifetimeMs: 9000,
          ),
          laneA,
          reason: 'nowMs=$nowMs 时 A 不应换道',
        );
        expect(
          tracker.laneForScroll(
            comment: comments[1],
            nowMs: nowMs,
            width: 200,
            canvasWidth: 1000,
            lifetimeMs: 9000,
          ),
          laneB,
          reason: 'nowMs=$nowMs 时 B 不应换道',
        );
      }
    });

    test('前一条完全进屏并留出间距后，同车道才允许跟进', () {
      final tracker = DanmakuLaneTracker();
      final leader = _comment(0);
      final follower = _comment(1000);
      final third = _comment(6200);
      tracker.beginFrame(
        comments: <DanmakuComment>[leader, follower, third],
        settings: DanmakuSettings.defaults,
        laneCount: 2,
      );
      final leaderLane = tracker.laneForScroll(
        comment: leader,
        nowMs: 0,
        width: 200,
        canvasWidth: 1000,
        lifetimeMs: 9000,
      );
      // 领头出发 1 秒：只移动 1200/9 ≈ 133px，未到「宽 200 + 间距 20」，
      // 同车道不可用，跟进者拿下一车道。
      final followerLane = tracker.laneForScroll(
        comment: follower,
        nowMs: 1000,
        width: 200,
        canvasWidth: 1000,
        lifetimeMs: 9000,
      );
      expect(followerLane, isNot(leaderLane));
      // 6.2 秒出生的：领头已移动 1200/9*6.2 ≈ 826px > 220，同车道可跟进。
      expect(
        tracker.laneForScroll(
          comment: third,
          nowMs: 6200,
          width: 200,
          canvasWidth: 1000,
          lifetimeMs: 9000,
        ),
        leaderLane,
      );
    });

    test('出生即淘汰的弹幕不会在后续帧复活', () {
      final tracker = DanmakuLaneTracker();
      final occupants = <DanmakuComment>[_comment(0), _comment(10)];
      tracker.beginFrame(
        comments: occupants,
        settings: DanmakuSettings.defaults,
        laneCount: 1,
      );
      tracker.laneForScroll(
        comment: occupants[0],
        nowMs: 0,
        width: 200,
        canvasWidth: 1000,
        lifetimeMs: 9000,
      );
      expect(
        tracker.laneForScroll(
          comment: occupants[1],
          nowMs: 10,
          width: 200,
          canvasWidth: 1000,
          lifetimeMs: 9000,
        ),
        -1,
      );
      expect(
        tracker.laneForScroll(
          comment: occupants[1],
          nowMs: 5000,
          width: 200,
          canvasWidth: 1000,
          lifetimeMs: 9000,
        ),
        -1,
        reason: '淘汰结果应被记住，不能过几帧又冒出来',
      );
    });

    test('过滤的重复项在前一条到期后仍不允许半途入场', () {
      final tracker = DanmakuLaneTracker();
      final comments = [_comment(0, text: '重复'), _comment(3000, text: '重复')];
      void begin(int oldestTimeMs) => tracker.beginFrame(
        comments: comments,
        settings: DanmakuSettings.defaults,
        laneCount: 1,
        oldestTimeMs: oldestTimeMs,
      );
      begin(-6000);
      tracker.reject(comments[1]);
      begin(1); // 第一条已到期，重复项还剩三秒寿命。
      expect(tracker.isRejected(comments[1]), isTrue);
      expect(
        tracker.laneForScroll(
          comment: comments[1],
          nowMs: 9001,
          width: 200,
          canvasWidth: 1000,
          lifetimeMs: 9000,
        ),
        -1,
      );
    });

    test('顶部/底部在同一物理行互斥，到期后复用', () {
      final tracker = DanmakuLaneTracker();
      final topA = _comment(0, type: DanmakuCommentType.top);
      final bottomA = _comment(100, type: DanmakuCommentType.bottom);
      final topB = _comment(200, type: DanmakuCommentType.top);
      final topC = _comment(4200, type: DanmakuCommentType.top);
      tracker.beginFrame(
        comments: <DanmakuComment>[topA, bottomA, topB, topC],
        settings: DanmakuSettings.defaults,
        laneCount: 1,
      );
      expect(
        tracker.laneForFixed(comment: topA, nowMs: 0, lifetimeMs: 4200),
        0,
      );
      expect(
        tracker.laneForFixed(comment: bottomA, nowMs: 100, lifetimeMs: 4200),
        -1,
        reason: '只有一行时，底部不能与顶部重叠',
      );
      expect(
        tracker.laneForFixed(comment: topB, nowMs: 200, lifetimeMs: 4200),
        -1,
        reason: 'A 未到期，唯一车道应不可用',
      );
      // 淘汰结果被记住：topB 即使过了到期时间也不会复活。
      expect(
        tracker.laneForFixed(comment: topB, nowMs: 4200, lifetimeMs: 4200),
        -1,
      );
      // 同一数据源里晚出生的弹幕在 A 到期后复用其车道。
      expect(
        tracker.laneForFixed(comment: topC, nowMs: 4200, lifetimeMs: 4200),
        0,
        reason: 'A 到期后车道应被新弹幕复用',
      );
    });

    test('长弹幕不得追尾短弹幕，延迟入帧也按弹幕时间分配', () {
      final tracker = DanmakuLaneTracker();
      final comments = [_comment(0), _comment(1800), _comment(6000)];
      tracker.beginFrame(
        comments: comments,
        settings: DanmakuSettings.defaults,
        laneCount: 1,
      );
      final lanes = <int>[];
      for (var i = 0; i < comments.length; i++) {
        lanes.add(
          tracker.laneForScroll(
            comment: comments[i],
            nowMs: 6500,
            width: i == 0 ? 100 : 700,
            canvasWidth: 1000,
            lifetimeMs: 9000,
          ),
        );
      }
      expect(lanes, [0, -1, 0]);
      // 对实际放行的一对逐帧检查：直到前车离屏，间距始终足够。
      for (var time = 6000; time < 9000; time += 16) {
        final leaderRight = 1000 - time / 9000 * 1100 + 100;
        final followerLeft = 1000 - (time - 6000) / 9000 * 1700;
        expect(followerLeft - leaderRight, greaterThanOrEqualTo(20));
      }
    });

    test('数据源、设置或车道数变化时整体重排', () {
      final tracker = DanmakuLaneTracker();
      final comments = <DanmakuComment>[_comment(0)];
      tracker.beginFrame(
        comments: comments,
        settings: DanmakuSettings.defaults,
        laneCount: 4,
      );
      expect(
        tracker.laneForScroll(
          comment: comments[0],
          nowMs: 0,
          width: 200,
          canvasWidth: 1000,
          lifetimeMs: 9000,
        ),
        0,
      );

      // 设置对象换了实例（如调字号）→ 重排，允许重新分配。
      tracker.beginFrame(
        comments: comments,
        settings: DanmakuSettings.defaults.copyWith(speed: 1.5),
        laneCount: 4,
      );
      expect(
        tracker.laneForScroll(
          comment: comments[0],
          nowMs: 100,
          width: 200,
          canvasWidth: 1000,
          lifetimeMs: 9000,
        ),
        0,
        reason: '设置变化重排后仍应能分到车道',
      );

      // seek 触发的手动 reset 同样不能让车道池失效。
      tracker.reset();
      expect(
        tracker.laneForScroll(
          comment: comments[0],
          nowMs: 200,
          width: 200,
          canvasWidth: 1000,
          lifetimeMs: 9000,
        ),
        0,
        reason: '手动 reset 后车道池应按 laneCount 重建',
      );
    });
  });
}
