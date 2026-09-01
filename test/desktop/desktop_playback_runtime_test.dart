import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_danmaku_overlay.dart';
import 'package:fly_player/desktop/playback/desktop_mpv_runtime.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/playback/bookmarks/bookmark_store.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/playback/settings/mpv_settings_store.dart';

void main() {
  test('主动暂停与媒体切换期间的 MPV 日志错误不升级为致命弹层', () {
    final source = File(
      'lib/desktop/playback/desktop_playback_screen.dart',
    ).readAsStringSync();

    expect(source, contains('void _onPlayerError(String error)'));
    expect(source, contains('_pausedByUser || _isLoading'));
  });

  test('悬停弹层不以全屏手势层遮挡触发按钮', () {
    final source = File(
      'lib/desktop/playback/desktop_playback_screen.dart',
    ).readAsStringSync();
    final overlaySource = source.substring(
      source.indexOf('Widget _buildHoverOverlayLayer()'),
      source.indexOf('String _formatPlaybackRate'),
    );

    expect(overlaySource, isNot(contains('onTap: _dismissHoverOverlay')));
  });

  test('播放设置对齐安卓层级并接入章节与片头片尾跳过', () {
    final source = File(
      'lib/desktop/playback/desktop_playback_screen.dart',
    ).readAsStringSync();
    final panelSource = File(
      'lib/desktop/playback/desktop_player_panels.dart',
    ).readAsStringSync();

    // 章节来自 mpv chapter-list，播放分组内条件显示。
    expect(source, contains("getProperty('chapter-list')"));
    expect(panelSource, contains('if (widget.chapters.isNotEmpty)'));

    // 片头片尾跳过：时长窗口逻辑 + 右下角提示卡。
    expect(source, contains('_computeSkipPromptKind'));
    expect(source, contains('_buildSkipPromptLayer'));
    expect(panelSource, contains('片头片尾跳过'));

    // 音轨「调节」在原悬浮卡上放大，不另开独立窗口。
    expect(source, contains('_expandHoverOverlayToSettings'));
  });

  test('Windows 弹幕层能读取原生预取的 compact payload', () async {
    final directory = await Directory.systemTemp.createTemp(
      'desktop-danmaku-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/payload.json');
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'sourceKey': 'dandan:42',
        'commentsCompact': <List<Object?>>[
          <Object?>['a', 1250, '滚动', 0, 0xFFFFFFFF],
          <Object?>['b', 2100, '顶部', 1, 0xFFFF0000],
        ],
      }),
    );

    final payload = await DesktopDanmakuPayload.load(file.path);

    expect(payload.sourceLabel, 'dandan:42');
    expect(payload.comments.map((item) => item.text), <String>['滚动', '顶部']);
    expect(payload.comments.last.timeMs, 2100);
  });

  test('Windows 音频滤镜沿用 MPV 设置中的 EQ 与限幅参数', () {
    final settings = <String, String>{
      ...MpvSettingsCatalog.defaults,
      MpvSettingsCatalog.audioEqKey: 'clarity',
      MpvSettingsCatalog.audioLimiterKey: 'light',
    };

    final filters = DesktopMpvRuntime.audioFilters(settings);

    expect(filters, contains('equalizer=f=2800'));
    expect(filters, contains('alimiter=limit=0.95'));
  });

  testWidgets('Windows 弹幕显示设置与弹幕源分开呈现', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopDanmakuSettingsPanel(
          settings: DanmakuSettings.defaults,
          onChanged: (_) async {},
        ),
      ),
    );

    expect(find.text('滚动弹幕'), findsOneWidget);
    expect(find.text('导入本地弹幕'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopDanmakuSourcePanel(
          currentSourceLabel: 'dandan:42',
          commentCount: 120,
          loading: false,
          initialKeyword: '测试作品',
          onLoadSavedSources: () async => const <Map<String, dynamic>>[],
          onSearch: (_) async => const <Map<String, dynamic>>[],
          onSelectSavedSource: (_) async => false,
          onSelectSearchResult: (_) async => false,
          onDeleteSavedSource: (_) async {},
          onImportFile: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('弹幕源'), findsOneWidget);
    expect(find.text('导入本地弹幕'), findsOneWidget);
    expect(find.text('在线搜索'), findsOneWidget);
  });

  testWidgets('弹幕源在播放器设置面板内部打开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SizedBox(
          width: 410,
          height: 760,
          child: DesktopPlaybackSettingsPanel(
            source: const MpvMediaSource(
              itemGuid: 'item',
              mediaGuid: 'media',
              videoGuid: 'video',
              url: 'https://example.invalid/video',
              headers: <String, String>{},
              title: '测试视频',
            ),
            position: Duration.zero,
            autoPlayEnabled: true,
            nextEpisodePreloadEnabled: false,
            aspectRatioMode: 'fit',
            decoderMode: 'hardware',
            mpvSettings: MpvSettingsCatalog.defaults,
            videoAdjustments: MpvSettingsCatalog.videoAdjustmentDefaults,
            audioDelaySeconds: 0,
            bookmarks: const <PlayerBookmarkEntry>[],
            chapters: const <DesktopPlayerChapter>[],
            introOutroEnabled: true,
            introMaxMinutes: 2,
            outroMaxMinutes: 2,
            skipCountdownSeconds: 5,
            subtitleDelaySeconds: 0,
            subtitlePosition: 92,
            subtitleScale: 1,
            onSubtitleStyleChanged:
                ({
                  required delaySeconds,
                  required position,
                  required scale,
                }) async {},
            onIntroOutroChanged:
                ({
                  required enabled,
                  required introMaxMinutes,
                  required outroMaxMinutes,
                  required skipCountdownSeconds,
                }) async {},
            onSelectChapter: (_) async {},
            danmakuEnabled: true,
            danmakuSourceLabel: '',
            danmakuCommentCount: 0,
            onAutoPlayChanged: (_) async {},
            onNextEpisodePreloadChanged: (_) async {},
            onAspectRatioChanged: (_) async {},
            onDecoderChanged: (_) async {},
            onMpvAdvancedChanged: (_, __) async {},
            onLoadSavedPresets: (_) async => const <SavedMpvPreset>[],
            onApplySavedPreset: (_) async {},
            onVideoAdjustmentChanged: (_, __) async {},
            onAudioDelayChanged: (_) async {},
            onAddBookmark: () async => const <PlayerBookmarkEntry>[],
            onDeleteBookmark: (_) async => const <PlayerBookmarkEntry>[],
            onSelectBookmark: (_) async {},
            danmakuSettingsPageBuilder: (_) => const Text('弹幕设置内页'),
            danmakuSourcesPageBuilder: (_) => const Text('弹幕源内页'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('弹幕源'));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopPlaybackSettingsPanel), findsOneWidget);
    expect(find.text('弹幕源内页'), findsOneWidget);
  });
}
