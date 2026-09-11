import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/desktop/playback/external_playback_host.dart';
import 'package:fly_player/desktop/playback/external_playback_screen.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  testWidgets('就绪设置同步到控制页，进度更新保留未应用草稿，窄窗口不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() async {
      ExternalPlaybackHost.status.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    void publish(DanmakuSettings settings, {bool ready = true}) {
      ExternalPlaybackHost.status.value = ExternalPlaybackStatus(
        source: const MpvMediaSource(
          itemGuid: 'item',
          mediaGuid: 'media',
          videoGuid: 'video',
          url: 'local.mkv',
          headers: {},
          title: '外部播放',
          subtitleTrackGuid: '',
        ),
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 20),
        paused: true,
        danmakuEnabled: settings.enabled,
        danmakuLabel: '本地弹幕',
        danmakuCount: 2,
        danmakuSettings: settings,
        phase: ready
            ? ExternalPlaybackPhase.ready
            : ExternalPlaybackPhase.preparing,
      );
    }

    publish(DanmakuSettings.defaults, ready: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.ocean),
        home: const ExternalPlaybackScreen(),
      ),
    );
    final applied = DanmakuSettings.defaults.copyWith(fontScale: 1.2);
    publish(applied);
    await tester.pump();
    Slider fontSlider() => tester.widget<Slider>(find.byType(Slider).at(1));
    expect(fontSlider().value, 1.2);
    fontSlider().onChanged!(1.3);
    await tester.pump();
    publish(applied);
    await tester.pump();
    expect(fontSlider().value, 1.3);
    expect(find.text('有尚未应用的更改'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(640, 1400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('片源与字幕'));
    await tester.pumpAndSettle();
    expect(find.text('关闭字幕'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
