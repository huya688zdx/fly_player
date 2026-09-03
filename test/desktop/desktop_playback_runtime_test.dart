import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_danmaku_overlay.dart';
import 'package:fly_player/desktop/playback/desktop_mpv_runtime.dart';
import 'package:fly_player/desktop/playback/desktop_player_hover_overlays.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/playback/bookmarks/bookmark_store.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/playback/settings/mpv_settings_store.dart';
import 'package:media_kit/media_kit.dart';

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

  test('播放器右键菜单在按键释放后打开', () {
    final source = File(
      'lib/desktop/playback/desktop_playback_screen.dart',
    ).readAsStringSync();

    expect(source, contains('onSecondaryTapUp: (details)'));
    expect(source, isNot(contains('onSecondaryTapDown: (details)')));
  });

  test('全屏控制层单独监听播放状态变化', () {
    final source = File(
      'lib/desktop/playback/desktop_playback_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ValueNotifier<bool> _playingNotifier'));
    expect(source, contains('Listenable.merge(<Listenable>['));
    expect(source, contains('_playingNotifier,'));
  });

  test('窗口与全屏控制层各自持有快捷键焦点', () {
    final source = File(
      'lib/desktop/playback/desktop_playback_screen.dart',
    ).readAsStringSync();
    final screenStateSource = source.substring(
      source.indexOf('class _DesktopPlaybackScreenState'),
      source.indexOf('class _DesktopPlaybackKeyboardFocus'),
    );

    expect(source, contains('descendantsAreFocusable: false'));
    expect(screenStateSource, isNot(contains('FocusNode _focusNode')));
    expect(source, contains('class _DesktopPlaybackKeyboardFocus'));
  });

  test('Windows 播放路由不使用会触发无障碍崩溃的 Material Slider', () {
    for (final path in <String>[
      'lib/desktop/playback/desktop_player_controls.dart',
      'lib/desktop/playback/desktop_player_panels.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(matches(RegExp(r'\bSlider\('))), reason: path);
    }
  });

  test('播放设置对齐安卓层级并接入章节与片头片尾跳过', () {
    final source = File(
      'lib/desktop/playback/desktop_playback_screen.dart',
    ).readAsStringSync();
    final panelSource = File(
      'lib/desktop/playback/desktop_player_panels.dart',
    ).readAsStringSync();

    // 章节来自 mpv chapter-list；入口常显，无章节时展示空态。
    expect(source, contains("getProperty('chapter-list')"));
    expect(panelSource, contains('当前视频没有章节信息'));

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

  test('Windows 播放媒体把续播位置交给 media_kit 起播', () {
    const source = MpvMediaSource(
      itemGuid: 'item',
      mediaGuid: 'media',
      videoGuid: 'video',
      url: 'https://example.invalid/video',
      headers: <String, String>{'Authorization': 'test'},
      title: '测试视频',
      startPosition: Duration(minutes: 11, seconds: 20),
    );

    final media = DesktopMpvRuntime.mediaFor(source);

    expect(media.start, source.startPosition);
    expect(media.httpHeaders, source.headers);
  });

  test('Windows 音轨列表不显示 media_kit 的自动和禁用控制项', () {
    final tracks = <AudioTrack>[
      AudioTrack.auto(),
      AudioTrack.no(),
      const AudioTrack('3', '日语', 'jpn'),
    ];

    final selectable = DesktopMpvRuntime.selectableAudioTracks(tracks);

    expect(selectable.map((track) => track.id), <String>['3']);
  });

  test('Windows 自动音轨状态选中实际默认音轨', () {
    const track = AudioTrack('3', null, 'jpn', isDefault: true);

    final selected = DesktopMpvRuntime.selectedAudioTrack(<AudioTrack>[
      track,
    ], AudioTrack.auto());

    expect(selected, track);
  });

  test('Windows 音轨标题复用语言映射而不是显示原始代码', () {
    const track = AudioTrack('3', null, 'jpn');

    final title = DesktopMpvRuntime.audioTrackTitle(track, '轨道 1');

    expect(title, '日语');
  });

  test('Windows 自动字幕状态选中实际默认字幕', () {
    const track = SubtitleTrack('3', null, 'jpn', isDefault: true);

    final selected = DesktopMpvRuntime.selectedSubtitleTrack(<SubtitleTrack>[
      track,
    ], SubtitleTrack.auto());

    expect(selected, track);
  });

  test('Windows 字幕标题复用语言映射而不是显示原始代码', () {
    const track = SubtitleTrack('3', null, 'jpn');

    final title = DesktopMpvRuntime.subtitleTrackTitle(track, '轨道 1');

    expect(title, '日语');
  });

  test('Windows 画质按当前模式过滤并在主面板合并同分辨率档', () {
    final source = _qualitySource();

    final menu = DesktopMpvRuntime.qualityMenu(source);

    expect(menu.mainChoices.map((choice) => choice.displayTier), <String>[
      '1080P',
      '720P',
      '480P',
    ]);
    expect(menu.mainChoices.first.isOriginal, isTrue);
    expect(menu.customGroups['480P'], hasLength(2));
    expect(
      menu.customGroups['1080P']!.map((choice) => choice.quality.source),
      <PlaybackQualitySource>[PlaybackQualitySource.originalProxy],
    );
  });

  test('Windows 原画态入口显示原画且低码率使用 Kbps', () {
    final source = _qualitySource();

    expect(DesktopMpvRuntime.currentQualityLabel(source, '原画'), '原画');
    expect(DesktopMpvRuntime.qualityBitrateLabel(894000), '894 Kbps');
  });

  testWidgets('Windows 画质面板使用主档与自定义两级结构', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 430,
              height: 520,
              child: Material(
                child: DesktopHoverQualityPanel(
                  source: _qualitySource(),
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('原画'), findsOneWidget);
    expect(find.text('1080P'), findsNothing);
    expect(find.text('1080P 894 Kbps'), findsOneWidget);
    expect(find.text('720P'), findsOneWidget);
    expect(find.text('480P'), findsOneWidget);
    expect(find.text('1080P SDR'), findsNothing);

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('自定义视频质量'), findsOneWidget);
  });

  test('有悬停面板的控制按钮不再叠加系统 Tooltip', () {
    final source = File(
      'lib/desktop/playback/desktop_player_controls.dart',
    ).readAsStringSync();

    expect(source, contains('Widget _tooltipOrChild('));
    expect(source, contains('enabled: onHoverEnter == null'));
    expect(source, contains('enabled: false'));
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

MpvMediaSource _qualitySource() {
  PlaybackQualityOption quality({
    required String resolution,
    required int bitrate,
    required PlaybackQualitySource source,
    int isDefault = 0,
  }) => PlaybackQualityOption(
    mediaGuid: 'media',
    videoGuid: 'video',
    resolution: resolution,
    bitrate: bitrate,
    isDefault: isDefault,
    source: source,
    directLinkQualityIndex: source == PlaybackQualitySource.directLink
        ? 0
        : null,
  );

  return MpvMediaSource(
    itemGuid: 'item',
    mediaGuid: 'media',
    videoGuid: 'video',
    url: 'https://example.invalid/video',
    headers: const <String, String>{},
    title: '测试视频',
    resolution: '1080P SDR',
    bitrate: 894000,
    qualities: <PlaybackQualityOption>[
      quality(
        resolution: 'Original',
        bitrate: 894000,
        source: PlaybackQualitySource.originalProxy,
        isDefault: 1,
      ),
      quality(
        resolution: '1080P SDR',
        bitrate: 894000,
        source: PlaybackQualitySource.serverSession,
      ),
      quality(
        resolution: '720p',
        bitrate: 850000,
        source: PlaybackQualitySource.serverSession,
      ),
      quality(
        resolution: '480',
        bitrate: 800000,
        source: PlaybackQualitySource.serverSession,
      ),
      quality(
        resolution: '480P',
        bitrate: 500000,
        source: PlaybackQualitySource.serverSession,
      ),
    ],
  );
}
