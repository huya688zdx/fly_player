import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_playback_chapters.dart';
import 'package:fly_player/desktop/playback/desktop_player_controls.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/services/fly_data/fly_oped.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Published response fixture and an in-memory player. No network, media decoding,
// native window or real publication is exercised by these widget tests.
const _durationMs = 1421005;
FlyOpedSet _published({String opPolicy = 'prompt_only'}) {
  const source = FlySourceRef(bindingId: 'fixture', remoteItemId: 'episode');
  return FlyOpedSet.parse(
    {
      'status': 'published',
      'playback_context_id': 'fixture-load',
      'generation': 1,
      'set_revision': 'fixture-publication-$opPolicy',
      'file_context': {
        'source_ref': source.toJson(),
        'identity_state': 'verified',
        'file_revision_id': 'fixture-file',
        'media_coordinate_id': 'fixture-coordinate',
        'duration_ms': _durationMs,
      },
      'segments': [
        {
          'id': 'op',
          'kind': 'op',
          'start_ms': 79876,
          'end_ms': 164876,
          'skip_policy': opPolicy,
        },
        {
          'id': 'recap',
          'kind': 'recap',
          'start_ms': 200000,
          'end_ms': 220000,
          'skip_policy': 'prompt_only',
        },
        {
          'id': 'ed',
          'kind': 'ed',
          'start_ms': 1330000,
          'end_ms': 1420000,
          'skip_policy': 'auto',
        },
      ],
      'protected_ranges': [
        {'start_ms': 1420000, 'end_ms': _durationMs},
      ],
    },
    source: source,
    contextId: 'fixture-load',
    generation: 1,
  )!;
}

class _MemoryPlayer extends PlatformPlayer {
  _MemoryPlayer() : super(configuration: const PlayerConfiguration()) {
    state = state.copyWith(
      duration: const Duration(milliseconds: _durationMs),
      position: const Duration(seconds: 120),
      buffer: const Duration(seconds: 600),
    );
  }
}

class _VideoState extends VideoState {
  @override
  bool isFullscreen() => false;
}

Widget _controls(
  Player player,
  FlyOpedSet? published, {
  Future<void> Function(Duration)? onSeek,
  List<MpvSeekThumbnail> seekThumbnails = const [],
  bool showSkipPrompt = false,
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        DesktopPlayerControls(
          player: player,
          videoState: _VideoState(),
          showBuffer: true,
          flyOpedSet: published,
          seekThumbnails: seekThumbnails,
          chapters: const [
            DesktopPlayerChapter(
              title: 'Chapter 1',
              position: Duration(seconds: 60),
            ),
            DesktopPlayerChapter(
              title: 'Chapter 2',
              position: Duration(seconds: 300),
            ),
          ],
          title: 'Fixture episode',
          resolution: '',
          playing: true,
          loading: false,
          volume: 100,
          rate: 1,
          nowPlayingLabel: '播放中',
          playTooltip: '播放',
          pauseTooltip: '暂停',
          muteTooltip: '静音',
          speedTooltip: '倍速',
          fullscreenTooltip: '全屏',
          settingsTooltip: '设置',
          prevTooltip: '上一集',
          bookmarkTooltip: '',
          episodeLabel: '选集',
          subtitleLabel: '字幕',
          audioTooltip: '音轨',
          screenshotLabel: '截图',
          danmakuEnabled: false,
          danmakuLabel: '弹幕',
          abRepeatLabel: 'AB',
          abRepeatTooltip: 'AB 循环',
          onBack: () {},
          onToggle: () {},
          onSeek: onSeek ?? (_) async {},
          onVolume: (_) {},
          onMute: () {},
          onRate: (_) {},
          onScreenshot: () {},
          onToggleDanmaku: () {},
          onSettings: () {},
          onAbRepeat: () {},
        ),
        if (showSkipPrompt)
          Positioned(
            right: 24,
            bottom: 110,
            child: SizedBox(
              key: const ValueKey('fixture-skip-prompt'),
              // Conservative footprint of the real right/bottom-anchored card.
              width: 280 * textScale,
              height: 54 * textScale,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
      ],
    ),
  ),
);

Finder get _timeline => find
    .byWidgetPredicate(
      (widget) =>
          widget is GestureDetector &&
          widget.onHorizontalDragUpdate != null &&
          widget.onTapUp != null,
    )
    .first;

Future<TestGesture> _mouseAt(WidgetTester tester, int positionMs) async {
  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await _moveTo(tester, mouse, positionMs);
  return mouse;
}

Future<void> _moveTo(
  WidgetTester tester,
  TestGesture mouse,
  int positionMs,
) async {
  final rect = tester.getRect(_timeline);
  await mouse.moveTo(
    Offset(rect.left + rect.width * positionMs / _durationMs, rect.center.dy),
  );
  await tester.pump();
}

Future<List<int>> _timelinePixels(
  WidgetTester tester, {
  int width = 14210,
}) async {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: _timeline, matching: find.byType(CustomPaint)).first,
  );
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    paint.painter!.paint(Canvas(recorder), Size(width.toDouble(), 26));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, 26);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = List<int>.from(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    return result;
  }))!;
}

void main() {
  testWidgets('悬停区分片头片尾和策略，精确结束点后不再属于区间', (tester) async {
    final player = Player(platformPlayer: _MemoryPlayer());
    Duration? sought;
    await tester.pumpWidget(
      _controls(player, _published(), onSeek: (value) async => sought = value),
    );
    final mouse = await _mouseAt(tester, 79876);
    expect(find.text('片头 · 仅提示'), findsOneWidget);
    expect(find.text('01:19.876–02:44.876'), findsOneWidget);
    await _moveTo(tester, mouse, 164876);
    expect(find.textContaining('片头 ·'), findsNothing);
    await _moveTo(tester, mouse, 1330000);
    expect(find.text('片尾 · 自动跳过'), findsOneWidget);
    expect(find.text('22:10–23:40'), findsOneWidget);
    await _moveTo(tester, mouse, 1420000);
    expect(find.textContaining('片尾 ·'), findsNothing);
    expect(sought, isNull);
    // A timeline click remains a normal exact seek; the marker creates no skip.
    final rect = tester.getRect(_timeline);
    await tester.tapAt(
      Offset(rect.left + rect.width * 1400000 / _durationMs, rect.center.dy),
    );
    expect(sought, const Duration(milliseconds: 1400000));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await player.dispose();
  });

  testWidgets('关闭或上下文失效传 null 即清除；never 与非 OPED 不标成可跳', (tester) async {
    final player = Player(platformPlayer: _MemoryPlayer());
    await tester.pumpWidget(_controls(player, null));
    final mouse = await _mouseAt(tester, 100000);
    final baseline = await _timelinePixels(tester);
    await tester.pumpWidget(_controls(player, _published()));
    await tester.pump();
    expect(find.textContaining('片头 ·'), findsOneWidget);
    await tester.pumpWidget(_controls(player, null));
    await tester.pump();
    expect(find.textContaining('片头 ·'), findsNothing);
    final empty = await _timelinePixels(tester);
    expect(empty, orderedEquals(baseline));
    await tester.pumpWidget(_controls(player, _published(opPolicy: 'never')));
    await tester.pump();
    expect(find.textContaining('片头 ·'), findsNothing);
    final suppressed = await _timelinePixels(tester);
    final opX = (14210 * 100000 / _durationMs).round();
    expect(suppressed[(6 * 14210 + opX) * 4 + 3], 0);
    await _moveTo(tester, mouse, 210000);
    expect(find.textContaining('片头 ·'), findsNothing);
    await _moveTo(tester, mouse, 1350000);
    expect(find.textContaining('片尾 ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await player.dispose();
  });

  testWidgets('区间色带准确止于 ED end，保留缓冲进度和原章节绘制', (tester) async {
    final player = Player(platformPlayer: _MemoryPlayer());
    await tester.pumpWidget(_controls(player, null));
    await _mouseAt(tester, 120000);
    final baseline = await _timelinePixels(tester);
    await tester.pumpWidget(_controls(player, _published()));
    final marked = await _timelinePixels(tester);
    int alphaAt(int milliseconds) =>
        marked[(6 * 14210 + (14210 * milliseconds / _durationMs).round()) * 4 +
            3];
    expect(alphaAt(100000), greaterThan(0));
    expect(alphaAt(1350000), greaterThan(0));
    expect(alphaAt(79000), 0);
    expect(alphaAt(165000), 0);
    expect(alphaAt(1420300), 0);
    // The real 1005 ms tail is under one pixel at a normal window width. The
    // end cap must not extend beyond endMs and fully color that final pixel.
    final normalWidth = await _timelinePixels(tester, width: 760);
    expect(normalWidth[(6 * 760 + 759) * 4 + 3], lessThan(200));
    // Color rails stay above the existing track, chapter lines and playhead.
    expect(
      marked.skip(11 * 14210 * 4),
      orderedEquals(baseline.skip(11 * 14210 * 4)),
    );
    final thumbPixel = (7 * 14210 + (14210 * 120000 / _durationMs).round()) * 4;
    expect(marked.sublist(thumbPixel, thumbPixel + 4), [255, 255, 255, 255]);
    final opPixel = (6 * 14210 + (14210 * 100000 / _durationMs).round()) * 4;
    final edPixel = (6 * 14210 + (14210 * 1350000 / _durationMs).round()) * 4;
    expect(
      marked.sublist(opPixel, opPixel + 3),
      isNot(orderedEquals(marked.sublist(edPixel, edPixel + 3))),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await player.dispose();
  });

  for (final physicalSize in [
    const Size(1920, 1080),
    const Size(1600, 900),
    const Size(1200, 900), // 600 logical pixels at 200% with larger text.
  ]) {
    testWidgets('右端缩略图及 ED 信息避开跳过卡：$physicalSize 和桌面缩放', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = Player(platformPlayer: _MemoryPlayer());
      const thumbnailUrl = 'https://fixture.invalid/oped-preview';
      const provider = NetworkImage(thumbnailUrl, headers: {});
      // Supply the image cache directly: this exercises the real thumbnail
      // layout without making HTTP/BIF requests or decoding a media source.
      final fixtureImage = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blueGrey, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 9);
        picture.dispose();
        return image;
      }))!;
      tester.binding.imageCache.putIfAbsent(
        provider,
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: fixtureImage.clone())),
        ),
      );
      addTearDown(() {
        tester.binding.imageCache.evict(provider);
        fixtureImage.dispose();
      });
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final deviceScales = physicalSize.width == 1200
          ? [2.0]
          : [1.0, 1.25, 1.5, 2.0];
      for (final deviceScale in deviceScales) {
        tester.view.physicalSize = physicalSize;
        tester.view.devicePixelRatio = deviceScale;
        await tester.pumpWidget(
          _controls(
            player,
            _published(),
            seekThumbnails: const [
              MpvSeekThumbnail(positionMs: 0, url: thumbnailUrl),
            ],
            showSkipPrompt: true,
            textScale: deviceScale == 2 ? 1.3 : 1,
          ),
        );
        await _moveTo(tester, mouse, 1350000);
        final preview = tester.getRect(
          find.byKey(const ValueKey('desktop-timeline-preview')),
        );
        final prompt = tester.getRect(
          find.byKey(const ValueKey('fixture-skip-prompt')),
        );
        expect(preview.overlaps(prompt), isFalse, reason: 'DPR $deviceScale');
        expect(preview.right, lessThanOrEqualTo(prompt.left - 7.9));
        expect(preview.left, greaterThanOrEqualTo(0));
        expect(preview.top, greaterThanOrEqualTo(0));
        expect(preview.bottom, lessThan(tester.getRect(_timeline).top));
        expect(find.text('片尾 · 自动跳过'), findsOneWidget);
        expect(find.text('22:10–23:40'), findsOneWidget);
        expect(
          tester.getSize(find.byType(Image).first).height,
          greaterThan(80),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await player.dispose();
    });
  }
}
