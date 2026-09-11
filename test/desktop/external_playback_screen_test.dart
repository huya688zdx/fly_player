import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/desktop/playback/external_playback_host.dart';
import 'package:fly_player/desktop/playback/external_playback_screen.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/desktop/playback/external_playback_notice.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/ui/media_detail_components.dart';
import 'package:provider/provider.dart';

class _ArtworkNas extends ChangeNotifier implements NasProvider {
  @override
  String get baseUrl => 'https://nas.invalid';
  @override
  String get token => 'test-token';
  @override
  String get accessCode => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('就绪设置同步到控制页，进度更新保留未应用草稿，窄窗口不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    final nas = _ArtworkNas();
    addTearDown(() async {
      nas.dispose();
      ExternalPlaybackHost.status.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    void publish(DanmakuSettings settings, {bool ready = true}) {
      ExternalPlaybackHost.status.value = ExternalPlaybackStatus(
        source: MpvMediaSource(
          itemGuid: 'item',
          mediaGuid: 'media',
          videoGuid: 'video',
          url: 'local.mkv',
          headers: {},
          title: '外部播放',
          subtitleTrackGuid: '',
          posterPath: '/v/poster.jpg',
          playbackMode: PlayerPlaybackMode.serverSession,
          resolution: '720',
          bitrate: 1000000,
          qualities: [
            for (final resolution in ['1080', '720'])
              PlaybackQualityOption.fromJson({
                'media_guid': 'media',
                'video_guid': 'video',
                'resolution': resolution,
                'bitrate': 1000000,
              }, source: PlaybackQualitySource.serverSession),
          ],
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
      ChangeNotifierProvider<NasProvider>.value(
        value: nas,
        child: MaterialApp(
          theme: AppThemeBuilder.build(AppThemePreset.ocean),
          home: const ExternalPlaybackScreen(),
        ),
      ),
    );
    final applied = DanmakuSettings.defaults.copyWith(fontScale: 1.2);
    publish(applied);
    await tester.pump();
    final artwork = tester
        .widget<DetailHeroImage>(find.byType(DetailHeroImage))
        .images;
    expect(Uri.parse(artwork.urls.first).host, 'nas.invalid');
    expect(
      artwork.headers.values.any((value) => value.contains('test-token')),
      isTrue,
    );
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
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected)
        .single;
    expect((selected.label as Text).data, startsWith('720'));
    showExternalPlaybackNotice(
      tester.element(find.byType(ExternalPlaybackScreen)),
      'Bad state: 播放失败',
      error: true,
    );
    showExternalPlaybackNotice(
      tester.element(find.byType(ExternalPlaybackScreen)),
      '第二条提示',
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('external-playback-notice')),
      findsOneWidget,
    );
    expect(find.text('播放失败'), findsNothing);
    expect(find.text('第二条提示'), findsOneWidget);
    final notice = tester.widget<Positioned>(
      find.byKey(const ValueKey<String>('external-playback-notice')),
    );
    expect(notice.top, greaterThan(40));
    expect(notice.bottom, isNull);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('external-playback-notice')),
      findsNothing,
    );
    showExternalPlaybackNotice(
      tester.element(find.byType(ExternalPlaybackScreen)),
      '自动消失',
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('自动消失'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
