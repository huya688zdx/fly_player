import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_weak_network_monitor.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/playback/playback_source.dart';

const _source = MpvMediaSource(
  itemGuid: 'item',
  mediaGuid: 'media',
  videoGuid: 'video',
  url: 'https://example.invalid/video',
  headers: {},
  title: '测试视频',
  bitrate: 8000000,
  resolution: '1080P',
  qualities: [
    PlaybackQualityOption(
      mediaGuid: 'media',
      videoGuid: 'video',
      resolution: '1080P',
      bitrate: 8000000,
      isDefault: 1,
      source: PlaybackQualitySource.originalProxy,
      directLinkQualityIndex: null,
    ),
    PlaybackQualityOption(
      mediaGuid: 'media',
      videoGuid: 'video',
      resolution: '720P',
      bitrate: 4000000,
      isDefault: 0,
      source: PlaybackQualitySource.serverSession,
      directLinkQualityIndex: null,
    ),
  ],
);

void main() {
  testWidgets('加载和跳转不算弱网，两次有效缓冲才推荐，忽略后不再提示', (tester) async {
    var now = DateTime(2026);
    var speed = '700000';
    final monitor = DesktopWeakNetworkMonitor(
      now: () => now,
      readProperty: (name) async => switch (name) {
        'cache-speed' => speed,
        'demuxer-cache-duration' => '0.5',
        _ => '2',
      },
    )..setSource(_source);
    void state({bool loading = false, bool buffering = false}) =>
        monitor.updatePlayback(
          loading: loading,
          paused: false,
          buffering: buffering,
          completed: false,
        );
    void progress(int seconds) {
      state();
      monitor.onPosition(Duration(seconds: seconds));
      monitor.onPosition(Duration(seconds: seconds + 1));
    }

    state(loading: true, buffering: true);
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.bytesPerSecond, 700000);
    expect(monitor.recommendation, isNull);
    progress(1);
    monitor.markSeek();
    progress(30);
    state(buffering: true);
    now = now.add(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    expect(monitor.recommendation, isNull);
    progress(31);
    state(buffering: true);
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.recommendation, isNull);
    now = now.add(const Duration(seconds: 10));
    progress(33);
    state(buffering: true);
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.bytesPerSecond, 700000);
    expect(monitor.estimatedResumeWait, const Duration(milliseconds: 2143));
    expect(monitor.recommendation?.sourceIndex, 1);
    speed = '0';
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.recommendation?.sourceIndex, 1);
    state();
    expect(monitor.recommendation, isNull);
    speed = '700000';
    await tester.pump(const Duration(seconds: 1));
    monitor.dismiss();
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.recommendation, isNull);
    monitor.dispose();
  });

  testWidgets('持续网速不足且缓存见底时建议降档，缓存充足或暂停时不提示', (tester) async {
    var now = DateTime(2026);
    var cachedSeconds = '20';
    final monitor = DesktopWeakNetworkMonitor(
      now: () => now,
      readProperty: (name) async => switch (name) {
        'cache-speed' => '700000',
        'demuxer-cache-duration' => cachedSeconds,
        _ => '2',
      },
    )..setSource(_source);
    void state({bool paused = false}) => monitor.updatePlayback(
      loading: false,
      paused: paused,
      buffering: false,
      completed: false,
    );
    Future<void> sample(int seconds) async {
      for (var i = 0; i < seconds; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    state();
    monitor.onPosition(const Duration(seconds: 1));
    monitor.onPosition(const Duration(seconds: 2));
    await sample(10);
    expect(monitor.recommendation, isNull);
    cachedSeconds = '0.5';
    state(paused: true);
    await sample(10);
    expect(monitor.recommendation, isNull);
    state();
    monitor.onPosition(const Duration(seconds: 3));
    monitor.onPosition(const Duration(seconds: 4));
    await sample(8);
    expect(monitor.recommendation, isNull);
    await sample(1);
    expect(monitor.recommendation?.sourceIndex, 1);
    monitor.markSeek();
    expect(monitor.recommendation, isNull);
    monitor.dispose();
  });

  testWidgets('采样不重叠，切成本地媒体后丢弃旧回包并停止采样', (tester) async {
    final pending = Completer<String>();
    var reads = 0;
    final monitor = DesktopWeakNetworkMonitor(
      readProperty: (_) {
        reads++;
        return pending.future;
      },
    )..setSource(_source);
    monitor.updatePlayback(
      loading: false,
      paused: false,
      buffering: false,
      completed: false,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 3);
    monitor.setSource(_source.copyWith(url: 'file:///C:/video.mp4'));
    pending.complete('700000');
    await tester.pump(const Duration(seconds: 5));
    expect(monitor.remote, isFalse);
    expect(monitor.bytesPerSecond, 0);
    expect(monitor.recommendation, isNull);
    expect(reads, 3);
    monitor.dispose();
  });
}
