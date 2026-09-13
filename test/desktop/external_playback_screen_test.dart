import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/desktop/desktop_floating_panel.dart';
import 'package:fly_player/desktop/desktop_hover_dropdown.dart';
import 'package:fly_player/desktop/playback/external_playback_host.dart';
import 'package:fly_player/desktop/playback/external_playback_screen.dart';
import 'package:fly_player/desktop/playback/external_player_playlist.dart';
import 'package:fly_player/desktop/playback/desktop_player_hover_overlays.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/desktop/playback/external_playback_notice.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/widgets/app_atmospheric_background.dart';
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
          title: '轻音少女 第1季 第3集 特训！',
          seriesTitle: '轻音少女',
          seasonNumber: 1,
          episodeNumber: 3,
          posterPath: '/v/poster.jpg',
          playbackMode: PlayerPlaybackMode.serverSession,
          resolution: '720',
          bitrate: 1000000,
          subtitleTracks: [
            SubtitleTrackOption.fromJson({
              'guid': 'ass',
              'language': 'zh',
              'title': 'zh',
              'format': 'ass',
              'is_external': 1,
            }),
            SubtitleTrackOption.fromJson({
              'guid': 'vtt',
              'language': 'zh',
              'format': 'vtt',
              'title': '默认字幕',
              'is_external': 1,
              'is_default': 1,
            }),
          ],
          qualities: [
            PlaybackQualityOption.fromJson({
              'media_guid': 'media',
              'video_guid': 'video',
              'resolution': '1080',
              'bitrate': 1020000,
            }, source: PlaybackQualitySource.originalProxy),
            for (final resolution in ['1080', '720'])
              PlaybackQualityOption.fromJson({
                'media_guid': 'media',
                'video_guid': 'video',
                'resolution': resolution,
                'bitrate': 1000000,
              }, source: PlaybackQualitySource.serverSession),
            PlaybackQualityOption.fromJson({
              'media_guid': 'media',
              'video_guid': 'video',
              'resolution': '720',
              'bitrate': 500000,
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
        playlist: const [
          ExternalPlaylistEpisode(
            itemGuid: 'item',
            title: '第1季 第3集 特训！',
            seasonNumber: 1,
            episodeNumber: 3,
          ),
          ExternalPlaylistEpisode(
            itemGuid: 's2e1',
            title: '第2季 第1集 高三！',
            seasonNumber: 2,
            episodeNumber: 1,
          ),
        ],
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
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ExternalPlaybackScreen(),
        ),
      ),
    );
    final applied = DanmakuSettings.defaults.copyWith(fontScale: 1.2);
    publish(applied);
    await tester.pump();
    expect(find.byType(AppAtmosphericBackground), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.transparent,
    );
    expect(find.text('特训！'), findsNWidgets(2));
    expect(find.text('第1季 第3集 特训！'), findsNothing);
    await tester.tap(find.text('第 1 季'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    await tester.tap(find.text('第 2 季'));
    await tester.pumpAndSettle();
    expect(find.text('高三！'), findsOneWidget);
    expect(find.byType(DesktopFloatingPanel), findsNothing);
    await tester.tap(find.text('第 2 季'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 季'));
    await tester.pumpAndSettle();
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
    expect(find.text('由 PotPlayer 选择'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(DesktopHoverDropdown).first,
        matching: find.byType(OutlinedButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    expect(find.byType(DesktopHoverQualityPanel), findsOneWidget);
    expect(find.text('原画'), findsOneWidget);
    expect(find.text('720P'), findsOneWidget);
    expect(find.text('1080P'), findsNothing);
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('自定义视频质量'), findsOneWidget);
    expect(find.text('1 Mbps'), findsOneWidget);
    expect(find.text('500 Kbps'), findsOneWidget);
    await tester.tap(find.text('1080P'));
    await tester.pumpAndSettle();
    expect(find.text('1.02 Mbps · 原画'), findsOneWidget);
    await tester.tap(find.text('自定义视频质量'));
    await tester.pumpAndSettle();
    expect(find.text('原画'), findsOneWidget);
    final qualityPanel = tester.getRect(find.byType(DesktopFloatingPanel));
    await tester.tapAt(Offset(qualityPanel.right + 8, qualityPanel.top + 8));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsNothing);
    await tester.tap(find.text('由 PotPlayer 选择'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    expect(tester.getSize(find.byType(DesktopFloatingPanel)).width, 360);
    expect(find.text('中文-外挂'), findsOneWidget);
    expect(find.text('中文-默认'), findsOneWidget);
    expect(find.text('ASS  zh'), findsOneWidget);
    await tester.tap(find.text('字幕关'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsNothing);
    publish(applied);
    await tester.pump();
    expect(find.text('字幕关'), findsOneWidget);
    await tester.tap(find.text('字幕关'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('由 PotPlayer 选择'));
    await tester.pumpAndSettle();
    expect(find.text('由 PotPlayer 选择'), findsOneWidget);
    expect(find.text('字幕关'), findsNothing);
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
