import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_danmaku_overlay.dart';
import 'package:fly_player/desktop/playback/desktop_mpv_runtime.dart';
import 'package:fly_player/desktop/playback/desktop_playback_chapters.dart';
import 'package:fly_player/desktop/playback/desktop_playback_reporter.dart';
import 'package:fly_player/desktop/playback/desktop_player_hover_overlays.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';
import 'package:fly_player/desktop/playback/desktop_player_controls.dart';
import 'package:fly_player/desktop/playback/desktop_player_motion_icon.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/playback/bookmarks/bookmark_store.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/playback/settings/mpv_settings_store.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  testWidgets('透明图标进入退出及播放暂停切换后停止调度帧', (tester) async {
    Widget icon(bool selected, {String? playback}) => MaterialApp(
      home: Center(
        child: DesktopPlayerMotionIcon(
          kind: playback == null
              ? DesktopPlayerMotionKind.danmaku
              : DesktopPlayerMotionKind.playPause,
          selected: selected,
          label: playback ?? '',
        ),
      ),
    );
    Future<List<int>> pixels() async {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(DesktopPlayerMotionIcon),
          matching: find.byType(CustomPaint),
        ),
      );
      return (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        paint.painter!.paint(Canvas(recorder), const Size(130, 130));
        final picture = recorder.endRecording();
        final image = await picture.toImage(130, 130);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final alpha = [
          for (var i = 3; i < bytes!.lengthInBytes; i += 4) bytes.getUint8(i),
        ];
        image.dispose();
        picture.dispose();
        return alpha;
      }))!;
    }

    await tester.pumpWidget(icon(false));
    final initial = await pixels();
    expect(initial.first, 0);
    expect(initial[65 * 130], 0);
    await tester.pumpWidget(icon(true));
    await tester.pump(const Duration(milliseconds: 120));
    expect(await pixels(), isNot(orderedEquals(initial)));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(icon(false));
    await tester.pump(const Duration(milliseconds: 120));
    expect(await pixels(), isNot(orderedEquals(initial)));
    await tester.pumpAndSettle();
    expect(await pixels(), orderedEquals(initial));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(icon(false, playback: 'pause'));
    await tester.pumpAndSettle();
    final paused = await pixels();
    await tester.pumpWidget(icon(false, playback: 'play'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(await pixels(), isNot(orderedEquals(paused)));
    // 动画还未完成时再暂停，最终必须恢复暂停轮廓并停止刷新。
    await tester.pumpWidget(icon(false, playback: 'pause'));
    await tester.pumpAndSettle();
    expect(await pixels(), orderedEquals(paused));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('选集缩略图显示观看状态，下载文字独立且零续播值不遮掉观看进度', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopEpisodePanel(
            title: '选集',
            emptyLabel: '暂无剧集',
            episodes: const [
              {
                'itemGuid': '1',
                'title': '已看并下载',
                'watched': 1,
                'downloaded': true,
                'duration': 100,
                'ts': 100,
              },
              {
                'itemGuid': '2',
                'title': '未看完',
                'duration': 100,
                'ts': 0,
                'watchedTs': 25,
              },
            ],
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final posters = find.byType(DesktopEpisodePoster);
    expect(
      find.descendant(of: posters.first, matching: find.text('已观看')),
      findsOneWidget,
    );
    expect(find.text('已下载'), findsOneWidget);
    final progress = find.descendant(
      of: posters.last,
      matching: find.byType(LinearProgressIndicator),
    );
    expect(tester.widget<LinearProgressIndicator>(progress).value, .25);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选集打开定位当前集，按需切季且旧回包不覆盖失败重试', (tester) async {
    tester.view.physicalSize = const Size(430, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final snapshot = ValueNotifier(
      const PlayerHoverOverlaySnapshot(
        kind: PlayerHoverOverlayKind.episodes,
        visible: true,
        anchor: Rect.fromLTWH(320, 500, 40, 30),
      ),
    );
    Timer? closeTimer;
    addTearDown(() {
      closeTimer?.cancel();
      snapshot.dispose();
    });
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);
    Future<void> click(Finder target) async {
      await mouse.moveTo(tester.getCenter(target));
      await mouse.down(tester.getCenter(target));
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    final calls = <String>[];
    final pendingSecond = Completer<List<Map<String, dynamic>>>();
    var failThird = true;
    String? selected;
    List<Map<String, dynamic>> episodes(String season, int count) => [
      for (var i = 1; i <= count; i++)
        {
          'itemGuid': '$season-$i',
          'seasonGuid': season,
          'episodeNumber': i,
          'title': '$season 剧集 $i',
          'duration': 1400,
        },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PlayerHoverOverlayLayer(
                snapshot: snapshot,
                onPanelEnter: () => closeTimer?.cancel(),
                onPanelExit: () =>
                    closeTimer = Timer(const Duration(milliseconds: 210), () {
                      snapshot.value = snapshot.value.copyWith(visible: false);
                    }),
                contentBuilder: (_, __, ___) => PlayerHoverOverlayContent(
                  width: 390,
                  child: DesktopEpisodePanel(
                    title: '测试剧 · 选集',
                    emptyLabel: '暂无剧集',
                    currentItemGuid: 's1-13',
                    currentSeasonGuid: 's1',
                    episodes: episodes('s1', 30),
                    onSelected: (episode) =>
                        selected = episode['itemGuid'] as String,
                    loadSeasons: () async => [
                      for (var i = 1; i <= 3; i++)
                        MediaSeasonSummary(
                          id: 's$i',
                          title: '第$i季',
                          seasonNumber: i,
                          primaryImage: MediaImageRef.empty,
                        ),
                    ],
                    loadSeasonEpisodes: (season) async {
                      calls.add(season);
                      if (season == 's2') return pendingSecond.future;
                      if (failThird) throw StateError('模拟网络失败');
                      return episodes(season, 2);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('第13集 · s1 剧集 13').hitTestable(), findsOneWidget);
    expect(calls, isEmpty);
    await click(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('13').hitTestable(), findsOneWidget);
    await click(find.byIcon(Icons.view_list_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('第13集 · s1 剧集 13').hitTestable(), findsOneWidget);
    await click(find.text('第2季'));
    // 第二季仍在请求时选择第三季，第三季失败后第二季回包不得覆盖它。
    await click(find.text('第3季'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    pendingSecond.complete(episodes('s2', 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('剧集加载失败，点击重试'), findsOneWidget);
    expect(find.text('第1集 · s2 剧集 1'), findsNothing);
    failThird = false;
    await click(find.text('剧集加载失败，点击重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await click(find.text('第1集 · s3 剧集 1'));
    expect(snapshot.value.visible, isTrue);
    expect(selected, 's3-1');
    expect(calls, ['s2', 's3', 's3']);
    expect(tester.takeException(), isNull);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 220));
    expect(snapshot.value.visible, isFalse);
  });

  testWidgets('控制条工具可点击，Emby 缩略图随进度条悬停和拖动显示', (tester) async {
    final platformPlayer = _ControlsPlayer();
    platformPlayer.state = platformPlayer.state.copyWith(
      duration: const Duration(minutes: 2),
    );
    final player = Player(platformPlayer: platformPlayer);
    final calls = <String>[];
    Duration? sought;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopPlayerControls(
            player: player,
            videoState: _ControlsVideoState(),
            showBuffer: false,
            seekThumbnails: const [
              MpvSeekThumbnail(
                positionMs: 0,
                url: 'https://emby.test/chapter/0',
              ),
              MpvSeekThumbnail(
                positionMs: 60000,
                url: 'https://emby.test/chapter/1',
              ),
            ],
            thumbnailHeaders: const {'Cookie': 'entry-token=test-token'},
            title: '异国日记 第1季 第13集 明日将至',
            resolution: '原画',
            playing: true,
            loading: false,
            volume: 100,
            rate: 1,
            nowPlayingLabel: '正在播放',
            playTooltip: '播放',
            pauseTooltip: '暂停',
            muteTooltip: '静音',
            speedTooltip: '倍速',
            fullscreenTooltip: '全屏',
            settingsTooltip: '设置',
            prevTooltip: '上一集',
            bookmarkTooltip: '书签',
            episodeLabel: '选集',
            subtitleLabel: '字幕',
            audioTooltip: '音轨',
            screenshotLabel: '截图',
            danmakuEnabled: true,
            danmakuLabel: '弹幕开关',
            abRepeatLabel: 'AB',
            abRepeatTooltip: '设置 A 点',
            onBack: () => calls.add('返回'),
            onToggle: () => calls.add('播放暂停'),
            onPrevious: () => calls.add('上一集'),
            onNext: () => calls.add('下一集'),
            onSeek: (position) async => sought = position,
            onVolume: (_) {},
            onMute: () => calls.add('静音'),
            onRate: (_) {},
            onScreenshot: () => calls.add('截图'),
            onAddBookmark: () => calls.add('书签'),
            onToggleDanmaku: () => calls.add('弹幕'),
            onEpisodes: () => calls.add('选集'),
            onQuality: () => calls.add('画质'),
            onSubtitle: () => calls.add('字幕'),
            onAudio: () => calls.add('音轨'),
            onSpeedAt: (_) => calls.add('倍速'),
            onAbRepeat: () => calls.add('AB'),
            onSettings: () => calls.add('设置'),
          ),
        ),
      ),
    );
    final back = find.byIcon(Icons.arrow_back_rounded);
    final title = find.text('异国日记 第1季 第13集 明日将至');
    expect(title, findsOneWidget);
    expect(find.text('异国日记 · S01E13'), findsNothing);
    final topY = tester.getCenter(back).dy;
    expect(tester.getCenter(title).dy, topY);
    expect(find.byTooltip('弹幕设置'), findsNothing);
    final tools = ['书签', '截图', '设置 A 点', '设置'];
    var lastX = tester.getRect(title).right;
    for (final label in tools) {
      final button = find.byTooltip(label);
      expect(button, findsOneWidget);
      final center = tester.getCenter(button);
      expect(center.dy, topY);
      expect(center.dx, greaterThan(lastX));
      lastX = center.dx;
      await tester.tap(button);
    }
    await tester.tap(back);
    expect(calls, ['书签', '截图', 'AB', '设置', '返回']);
    for (final label in ['弹幕开关', '倍速 · 1.0×', '选集', '原画', '字幕', '音轨']) {
      await tester.tap(find.byTooltip(label).last);
    }
    expect(calls.skip(5), ['弹幕', '倍速', '选集', '画质', '字幕', '音轨']);
    expect(find.text('选集'), findsNothing);
    expect(find.text('原画'), findsNothing);
    await tester.tap(find.byTooltip('静音'));
    expect(calls.last, '静音');
    await tester.tap(find.byTooltip('暂停'));
    await tester.tap(find.byTooltip('上一集'));
    await tester.tap(find.byTooltip('选集').first);
    expect(calls.skip(12), ['播放暂停', '上一集', '下一集']);
    expect(find.byType(DesktopPlayerMotionIcon), findsNWidgets(15));
    final timeline = find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector &&
          widget.onHorizontalDragUpdate != null &&
          widget.onTapUp != null,
    );
    // 控件树中进度条在音量滑块之前。
    final rect = tester.getRect(timeline.first);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(rect.left + rect.width * 0.25, rect.center.dy));
    await tester.pump();
    NetworkImage preview() =>
        tester.widget<Image>(find.byType(Image).first).image as NetworkImage;
    expect(preview().url, 'https://emby.test/chapter/0');
    expect(preview().headers, {'Cookie': 'entry-token=test-token'});
    expect(find.text('00:30'), findsOneWidget);
    final drag = await tester.startGesture(
      Offset(rect.left + 2, rect.center.dy),
    );
    await drag.moveTo(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump();
    expect(preview().url, 'https://emby.test/chapter/1');
    expect(find.text('01:30'), findsOneWidget);
    await drag.up();
    expect(sought, const Duration(seconds: 90));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await player.dispose();
  });

  testWidgets('弹幕快捷填入片名或 TMDB 后仍可编辑，点击搜索才发起查询', (tester) async {
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopDanmakuSourcePanel(
            currentSourceLabel: '',
            commentCount: 0,
            loading: false,
            initialKeyword: '轻音少女 剧场版',
            currentTmdbId: 'tt100049',
            onLoadSavedSources: () async => [],
            onSearch: (query) async {
              queries.add(query);
              return [];
            },
            onSelectSavedSource: (_) async => true,
            onSelectSearchResult: (_) async => true,
            onDeleteSavedSource: (_) async {},
            onImportFile: () async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byType(TextField);
    await tester.enterText(input, '其他作品');
    await tester.tap(find.text('填入当前片名'));
    expect(tester.widget<TextField>(input).controller!.text, '轻音少女 剧场版');
    await tester.tap(find.text('填入当前 TMDB'));
    expect(tester.widget<TextField>(input).controller!.text, 'TMDB:100049');
    expect(queries, isEmpty);
    await tester.enterText(input, '轻音少女');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(queries, ['轻音少女']);
  });

  testWidgets('无章节最多补读一次，换源后旧读取失效并保留零秒章节', (tester) async {
    var reads = 0;
    final pending = Completer<String>();
    final chapters = DesktopPlaybackChapters(() {
      reads++;
      return reads <= 2 ? Future.value('[]') : pending.future;
    });
    addTearDown(chapters.dispose);
    chapters.load(const Duration(minutes: 20));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 2);
    chapters.reset();
    chapters.load(const Duration(minutes: 20));
    chapters.reset();
    pending.complete('[{"title":"旧章节","time":0}]');
    await tester.pump();
    expect(chapters.value, isEmpty);
    chapters.load(const Duration(minutes: 20));
    await tester.pump();
    expect(chapters.value.single.position, Duration.zero);
  });

  testWidgets('章节首次未就绪时仍补读，并用 OP 和 ED 的实际边界跳过', (tester) async {
    var reads = 0;
    final chapters = DesktopPlaybackChapters(
      () async => ++reads == 1
          ? ''
          : '[{"title":"序幕","time":0},{"title":"OP","time":30},'
                '{"title":"正片","time":125},{"title":"ED","time":1290}]',
    );
    addTearDown(chapters.dispose);
    chapters.load(const Duration(minutes: 24));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(chapters.value.length, 4);
    expect(
      desktopChapterSkipBounds(chapters.value, const Duration(minutes: 24)),
      (
        introStart: const Duration(seconds: 30),
        introEnd: const Duration(seconds: 125),
        outroStart: const Duration(seconds: 1290),
      ),
    );
  });

  test('普通编号章节不猜测片头片尾范围', () {
    expect(
      desktopChapterSkipBounds(const [
        DesktopPlayerChapter(title: 'Chapter 01', position: Duration.zero),
        DesktopPlayerChapter(
          title: 'Chapter 02',
          position: Duration(seconds: 90),
        ),
      ], const Duration(minutes: 24)),
      (introStart: null, introEnd: null, outroStart: null),
    );
  });

  test('固定时长需单独开启，章节识别可独立关闭', () {
    const chapters = [
      DesktopPlayerChapter(title: 'OP', position: Duration(seconds: 30)),
      DesktopPlayerChapter(title: '正片', position: Duration(seconds: 125)),
    ];
    final noFallback = desktopPlaybackSkipBounds(
      const [],
      const Duration(minutes: 24),
      chapterEnabled: true,
      fixedDurationEnabled: false,
      introMinutes: 2,
      outroMinutes: 2,
    );
    expect(noFallback.introEnd, isNull);
    expect(noFallback.outroStart, isNull);
    final mixed = desktopPlaybackSkipBounds(
      chapters,
      const Duration(minutes: 24),
      chapterEnabled: true,
      fixedDurationEnabled: true,
      introMinutes: 2,
      outroMinutes: 2,
    );
    expect(mixed.introStart, const Duration(seconds: 30));
    expect(mixed.introEnd, const Duration(seconds: 125));
    expect(mixed.introFromChapter, isTrue);
    expect(mixed.outroStart, const Duration(minutes: 22));
    expect(mixed.outroFromChapter, isFalse);
    final fixedOnly = desktopPlaybackSkipBounds(
      chapters,
      const Duration(minutes: 24),
      chapterEnabled: false,
      fixedDurationEnabled: true,
      introMinutes: 2,
      outroMinutes: 2,
    );
    expect(fixedOnly.introStart, Duration.zero);
    expect(fixedOnly.introEnd, const Duration(minutes: 2));
    expect(fixedOnly.introFromChapter, isFalse);
  });

  test('进度固定采样媒体身份，最终上报完成后再释放服务端会话', () async {
    final firstReport = Completer<void>();
    final released = Completer<void>();
    final events = <String>[];
    final reporter = DesktopPlaybackReporter(
      reportProgress: (progress) async {
        events.add('${progress['itemGuid']}:${progress['ts']}');
        if (events.length == 1) await firstReport.future;
      },
      releaseServerSession: (link) async {
        events.add('释放:$link');
        released.complete();
      },
    );
    final source = _qualitySource().copyWith(playLink: '旧会话');
    for (final sample in [
      (source, 10),
      (source.copyWith(itemGuid: '下一集'), 20),
    ]) {
      reporter.recordServer(
        sample.$1,
        position: Duration(seconds: sample.$2),
        duration: const Duration(minutes: 20),
        paused: false,
        completed: false,
      );
    }
    reporter.release(source);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['item:10']);
    firstReport.complete();
    await released.future;
    expect(events, ['item:10', '下一集:20', '释放:旧会话']);
    await reporter.dispose();
  });

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
    expect(source, contains('_viewRevision,'));
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
    expect(
      DesktopMpvRuntime.audioTrackTitle(
        const AudioTrack('3', 'Japanese Audio', 'jpn'),
        '轨道 1',
      ),
      '日语',
    );
    expect(
      DesktopMpvRuntime.audioTrackTitle(
        const AudioTrack('4', 'Japanese Commentary', 'jpn'),
        '轨道 2',
      ),
      'Japanese Commentary',
    );
  });

  test('本地切音轨按原文件流索引更新上报 GUID，未知索引不沿用旧选择', () {
    final source = _qualitySource().copyWith(
      audioTrackGuid: '旧音轨',
      audioTracks: [
        AudioTrackOption.fromJson({
          'media_guid': 'media',
          'guid': '新音轨',
          'index': 4,
        }),
      ],
    );
    final selected = DesktopMpvRuntime.sourceWithAudioStream(source, 4);
    expect(selected.toMap()['audioTrackGuid'], '新音轨');
    expect(selected.audioTrackIndex, 4);
    expect(
      DesktopMpvRuntime.sourceWithAudioStream(selected, null).audioTrackGuid,
      isNull,
    );
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

  test('Windows 原画态入口显示原画，码率省略末尾零且低码率使用 Kbps', () {
    final source = _qualitySource();

    expect(DesktopMpvRuntime.currentQualityLabel(source, '原画'), '原画');
    expect(DesktopMpvRuntime.qualityBitrateLabel(894000), '894 Kbps');
    expect(DesktopMpvRuntime.qualityBitrateLabel(2100000), '2.1 Mbps');
    expect(DesktopMpvRuntime.qualityBitrateLabel(2000000), '2 Mbps');
    expect(DesktopMpvRuntime.qualityBitrateLabel(1020000), '1.02 Mbps');
  });

  testWidgets('Windows 画质面板使用主档与自定义两级结构', (tester) async {
    final theme = AppThemeBuilder.build(AppThemePreset.latte);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
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

    // 浅色外壳下，未选中的画质文字也必须清晰可读。
    final surface = theme.extension<AppThemeColors>()!.surface;
    final text = tester.widget<Text>(find.text('720P')).style!.color!;
    expect(
      (surface.computeLuminance() + 0.05) / (text.computeLuminance() + 0.05),
      greaterThanOrEqualTo(4.5),
    );

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

  testWidgets('播放器设置内部切页，固定时长开关更新依据和跳转目标', (tester) async {
    var fixedEnabled = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(top: 32)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) => SizedBox(
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
              duration: const Duration(minutes: 24),
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
              fixedDurationSkipEnabled: fixedEnabled,
              hasNextEpisode: true,
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
                    required bool fixedDurationEnabled,
                  }) async {
                    setState(() => fixedEnabled = fixedDurationEnabled);
                  },
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
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byType(DesktopPlaybackSettingsPanel);
    final title = find.text(
      AppLocalizations.of(tester.element(panel)).playerSettingsTitle,
    );
    expect(title, findsOneWidget);
    expect(
      tester.getTopLeft(title) - tester.getTopLeft(panel),
      const Offset(18, 16),
    );
    await tester.tap(find.text('弹幕源'));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopPlaybackSettingsPanel), findsOneWidget);
    expect(find.text('弹幕源内页'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('片头片尾跳过'));
    await tester.pumpAndSettle();
    expect(find.text('不提示跳过'), findsNWidgets(2));
    expect(find.text('固定片头时长'), findsNothing);
    expect(find.text('跳过倒计时'), findsNothing);
    await tester.tap(find.text('固定时长跳过'));
    await tester.pumpAndSettle();
    expect(find.text('固定片头时长'), findsOneWidget);
    await tester.ensureVisible(find.text('当前片头'));
    await tester.pumpAndSettle();
    expect(find.text('固定时长 · 00:00–02:00'), findsOneWidget);
    expect(find.text('点击后跳到 02:00。'), findsOneWidget);
    await tester.ensureVisible(find.text('当前片尾'));
    await tester.pumpAndSettle();
    expect(find.text('固定时长 · 22:00–24:00'), findsOneWidget);
    expect(find.text('点击后播放下一集，片尾起点之后的内容会一并跳过。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ControlsPlayer extends PlatformPlayer {
  _ControlsPlayer() : super(configuration: const PlayerConfiguration());
}

class _ControlsVideoState extends VideoState {
  @override
  bool isFullscreen() => false;
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
