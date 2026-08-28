import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_detail_variant.dart';
import 'package:fly_player/media_backend/detail/media_source_info.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/pages/long_text_overlay_page.dart';
import 'package:fly_player/pages/media_detail_overlay_page.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_modal_surface.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';
import 'package:fly_player/widgets/detail/file_info_section.dart';
import 'package:fly_player/widgets/detail/link_section.dart';
import 'package:fly_player/widgets/detail/video_info_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({
  required WidgetBuilder builder,
  AppThemePreset preset = AppThemePreset.midnight,
}) => MediaQuery(
  data: const MediaQueryData(size: Size(390, 800)),
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppThemeBuilder.build(preset),
    home: Builder(builder: builder),
  ),
);

Widget _runtimeApp({required AppThemeColors colors, required Widget child}) =>
    MaterialApp(
      theme: AppThemeBuilder.build(AppThemePreset.midnight),
      home: AppRuntimeColorScope(
        colors: colors,
        hasRuntimeColors: true,
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('轨道选择使用统一面板背景和独立圆角选中态', (tester) async {
    await tester.pumpWidget(
      _app(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => TrackOptionSheet.show(
              context,
              title: '选择字幕',
              selectedId: 'default',
              items: const <TrackOptionSheetItem>[
                TrackOptionSheetItem(id: 'off', title: '字幕关'),
                TrackOptionSheetItem(
                  id: 'default',
                  title: '未知语言-默认',
                  subtitle: 'SUP',
                ),
                TrackOptionSheetItem(
                  id: 'one',
                  title: '未知语言',
                  subtitle: 'SUP 1',
                ),
              ],
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-modal-surface-track-options')),
      findsOneWidget,
    );
    final group = find.byKey(const ValueKey<String>('track-option-group'));
    expect(group, findsOneWidget);
    expect(tester.widget(group), isA<ListView>());
    expect(
      find.descendant(of: group, matching: find.byType(Divider)),
      findsNothing,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('track-selection-default')),
      ),
      const Size.square(22),
    );
    final unselectedIndicator = tester.widget<Container>(
      find.byKey(const ValueKey<String>('track-selection-off')),
    );
    final unselectedDecoration =
        unselectedIndicator.decoration! as BoxDecoration;
    final unselectedBorder = unselectedDecoration.border! as Border;
    expect(unselectedBorder.top.color.a, 1);
    final selectedTile = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('track-option-tile-default')),
    );
    final unselectedTile = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('track-option-tile-off')),
    );
    final decoration = selectedTile.decoration as BoxDecoration;
    final unselectedTileDecoration = unselectedTile.decoration as BoxDecoration;
    final colors = Theme.of(
      tester.element(find.text('未知语言-默认')),
    ).extension<AppThemeColors>()!;
    expect(decoration.color, isNot(colors.surfaceSubtle));
    expect(decoration.borderRadius, BorderRadius.circular(14));
    expect(decoration.border, isNotNull);
    expect(unselectedTileDecoration.color, Colors.transparent);
    expect(unselectedTileDecoration.borderRadius, BorderRadius.circular(14));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长文本弹层显示所属条目并使用适合阅读的正文排版', (tester) async {
    await tester.pumpWidget(
      _app(
        builder: (_) => const Scaffold(
          body: LongTextOverlayPage(
            title: '莉兹与青鸟',
            sectionTitle: '简介',
            content: '第一段简介。\n\n第二段简介。',
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('app-modal-surface-long-text')),
      findsOneWidget,
    );
    expect(find.text('莉兹与青鸟'), findsOneWidget);
    final sectionTitle = tester.widget<Text>(find.text('简介'));
    expect(sectionTitle.style?.fontSize, 18);
    expect(sectionTitle.style?.fontWeight, FontWeight.w700);
    final body = tester.widget<Text>(
      find.byKey(const ValueKey<String>('long-text-content')),
    );
    expect(body.style?.fontSize, 16);
    expect(body.style?.fontWeight, FontWeight.w400);
    expect(body.style?.height, 1.65);
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹层表面使用页面运行时取色生成多层低饱和渐变', (tester) async {
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;
    const runtimeAccent = Color(0xFFE06755);
    final runtimeColors = baseColors.copyWith(accent: runtimeAccent);

    await tester.pumpWidget(
      _runtimeApp(
        colors: runtimeColors,
        child: const AppModalSurface(
          key: ValueKey<String>('runtime-modal'),
          floating: true,
          child: SizedBox(width: 240, height: 180),
        ),
      ),
    );

    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('runtime-modal')),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = decorated.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, hasLength(3));
    expect(gradient.colors.first, isNot(runtimeColors.backgroundElevated));
    expect(gradient.colors.toSet(), hasLength(3));
    expect(decoration.border, isNotNull);
  });

  testWidgets('文件媒体信息在亮暗主题下使用连续背景且不再套描边卡', (tester) async {
    const variant = MediaDetailVariant(
      key: 'source-0',
      title: '1080P SDR',
      video: MediaInfoCard(
        header: '1080p H264 SDR',
        fields: <MediaInfoField>[
          MediaInfoField(MediaInfoFieldKey.encoder, 'h264'),
          MediaInfoField(MediaInfoFieldKey.profile, 'High'),
        ],
      ),
    );

    for (final preset in <AppThemePreset>[
      AppThemePreset.latte,
      AppThemePreset.midnight,
    ]) {
      await tester.pumpWidget(
        _app(
          preset: preset,
          builder: (_) => const Scaffold(
            body: MediaDetailOverlayPage(
              variants: <MediaDetailVariant>[variant],
              initialIndex: 0,
            ),
          ),
        ),
      );
      await tester.pump();

      final infoFinder = find.byKey(
        const ValueKey<String>('media-detail-info-video-0'),
      );
      final info = tester.widget<Container>(infoFinder);
      final decoration = info.decoration! as BoxDecoration;
      expect(decoration.color, Colors.transparent);
      expect(decoration.border, isNull);
      expect(decoration.borderRadius, BorderRadius.circular(14));

      final colors = Theme.of(
        tester.element(find.text('High')),
      ).extension<AppThemeColors>()!;
      final value = tester.widget<Text>(find.text('High'));
      expect(value.style?.color, colors.textPrimary);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('文件媒体信息从顶部向下拖动超过阈值后关闭', (tester) async {
    const variant = MediaDetailVariant(
      key: 'source-0',
      title: '1080P SDR',
      video: MediaInfoCard(
        header: '1080p H264 SDR',
        fields: <MediaInfoField>[
          MediaInfoField(MediaInfoFieldKey.encoder, 'h264'),
        ],
      ),
    );

    await tester.pumpWidget(
      _app(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => MediaDetailOverlayPage.show(
              context,
              variants: const <MediaDetailVariant>[variant],
            ),
            child: const Text('打开媒体信息'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开媒体信息'));
    await tester.pumpAndSettle();
    final dragHandle = find.byKey(
      const ValueKey<String>('media-detail-drag-handle'),
    );
    expect(dragHandle, findsOneWidget);

    await tester.drag(dragHandle, const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(find.text('文件媒体信息'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情文件与视频信息共用带层次的柔和表面并在手机宽度压缩为两列', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const file = StreamFileInfo(
      mediaGuid: 'media-1',
      path: '/vol4/1000/movie.m2ts',
      fileName: 'movie.m2ts',
      size: 1073741824,
      fileBirthTime: 1768499520000,
      createTime: 1782022620000,
      updateTime: 0,
    );

    for (final preset in <AppThemePreset>[
      AppThemePreset.latte,
      AppThemePreset.midnight,
    ]) {
      await tester.pumpWidget(
        _app(
          preset: preset,
          builder: (_) => const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  FileInfoSection(file: file, showPathToggle: false),
                  SizedBox(height: 24),
                  VideoInfoSection(
                    lines: VideoInfoLines(
                      video: '1080p H264 41.93 mbps 8 bit',
                      audio: 'DTS 5.1(side) 48000 Hz',
                      subtitle: 'SUP',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surfaceFinder = find.byKey(
        const ValueKey<String>('file-info-surface'),
      );
      final fileSurface = tester.widget<DecoratedBox>(
        find
            .descendant(of: surfaceFinder, matching: find.byType(DecoratedBox))
            .first,
      );
      final videoSurfaceFinder = find.byKey(
        const ValueKey<String>('video-info-surface'),
      );
      final videoSurface = tester.widget<DecoratedBox>(
        find.descendant(
          of: videoSurfaceFinder,
          matching: find.byType(DecoratedBox),
        ),
      );
      final decoration = fileSurface.decoration as BoxDecoration;
      final videoDecoration = videoSurface.decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
      expect(videoDecoration.gradient, decoration.gradient);
      expect(decoration.border, isNotNull);
      expect(videoDecoration.border, decoration.border);
      expect(decoration.boxShadow, isNotEmpty);
      expect(videoDecoration.boxShadow, decoration.boxShadow);
      expect(decoration.borderRadius, BorderRadius.circular(24));
      expect(videoDecoration.borderRadius, BorderRadius.circular(24));

      final sizeLabel = find.text('文件大小');
      final createdLabel = find.text('文件创建日期');
      final addedLabel = find.text('添加日期');
      expect(
        tester.getTopLeft(sizeLabel).dy,
        tester.getTopLeft(createdLabel).dy,
      );
      expect(
        tester.getTopLeft(addedLabel).dy,
        greaterThan(tester.getTopLeft(sizeLabel).dy),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('详情外部链接复用柔和主题表面而不是通用深色块', (tester) async {
    await tester.pumpWidget(
      _app(
        preset: AppThemePreset.latte,
        builder: (_) => const Scaffold(body: LinkSection(imdbId: 'tt0123456')),
      ),
    );

    final surfaceFinder = find.byKey(
      const ValueKey<String>('detail-link-surface-IMDB'),
    );
    final surface = tester.widget<DecoratedBox>(
      find
          .descendant(of: surfaceFinder, matching: find.byType(DecoratedBox))
          .first,
    );
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.gradient, isA<LinearGradient>());
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
