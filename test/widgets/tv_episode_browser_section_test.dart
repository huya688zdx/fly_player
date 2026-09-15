import 'package:flutter/gestures.dart';
import 'package:fly_player/desktop/desktop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/models/tv_episode_browser_models.dart';
import 'package:fly_player/models/tv_episode_picker_mode.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/detail/tv_episode_browser_section.dart';
import 'package:fly_player/widgets/detail/tv_episode_picker_sheet.dart';

void main() {
  testWidgets('桌面选集打开时定位当前集且手动滚动不被重置', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    addTearDown(() => DesktopEnvironment.debugOverridePlatform = null);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2110, 1431);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final episodes = List.generate(
      13,
      (index) => TvEpisodeCardData(
        guid: 'episode-${index + 1}',
        shortLabel: '${index + 1}',
        title: '第 ${index + 1} 集',
        summary: '',
        durationText: '24 分钟',
        statusLabel: '',
        imageUrls: const <String>[],
        resolutions: const <String>[],
        selected: index == 12,
        playing: false,
        completed: false,
        progress: 0,
      ),
    );
    TvEpisodePickerSheetResult? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await TvEpisodePickerSheet.show(
                  context,
                  title: '选集',
                  seasons: const <TvEpisodeSeasonOptionData>[],
                  initialSeasonGuid: 'season-1',
                  initialEpisodeGuid: 'episode-13',
                  initialMode: TvEpisodePickerMode.list,
                  rangeSize: 30,
                  emptyText: '暂无',
                  token: '',
                  accessCode: '',
                  baseUrl: '',
                  loader: (_) async => TvEpisodePickerPayload(
                    totalCount: episodes.length,
                    entries: episodes,
                  ),
                  onModeChanged: (_) async {},
                );
              },
              child: const Text('打开选集'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开选集'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    final panel = tester.getRect(find.byType(DesktopFloatingPanel));
    expect(panel.center.dx, closeTo(527.5, 0.01));
    expect(panel.center.dy, closeTo(357.75, 0.01));
    expect(panel.width, closeTo(1055 * 0.80, 0.01));
    expect(panel.height, closeTo(715.5 * 0.78, 0.01));
    expect(panel.left, greaterThan(100));
    expect(panel.top, greaterThan(70));
    expect(tester.takeException(), isNull);
    final list = tester.widget<GridView>(find.byType(GridView));
    expect(list.controller!.offset, greaterThan(0));
    final viewport = tester.getRect(find.byType(GridView));
    final current = tester.getRect(find.text('第 13 集'));
    expect(current.top, greaterThanOrEqualTo(viewport.top));
    expect(current.bottom, lessThanOrEqualTo(viewport.bottom));
    final scrollbarTheme = ScrollbarTheme.of(
      tester.element(find.byType(Scrollbar)),
    );
    expect(scrollbarTheme.trackVisibility!.resolve({}), isFalse);
    expect(scrollbarTheme.thickness!.resolve({}), 3);
    list.controller!.jumpTo(0);
    tester.view.physicalSize = const Size(2108, 1431);
    await tester.pumpAndSettle();
    expect(list.controller!.offset, 0);
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('13'));
    await tester.pumpAndSettle();
    expect(result?.seasonGuid, 'season-1');
    expect(result?.episodeGuid, 'episode-13');
    expect(result?.mode, TvEpisodePickerMode.grid);
    expect(result?.openDetail, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('桌面窄栏选集定位到续看集后仍可左右翻页', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    addTearDown(() => DesktopEnvironment.debugOverridePlatform = null);
    final episodes = List<TvEpisodeCardData>.generate(
      9,
      (index) => TvEpisodeCardData(
        guid: 'episode-${index + 1}',
        shortLabel: '${index + 1}',
        title: '${index + 1}.测试',
        summary: '',
        durationText: '24 分钟',
        statusLabel: '',
        imageUrls: const <String>[],
        resolutions: const <String>[],
        selected: index == 8,
        playing: false,
        completed: false,
        progress: 0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: TvEpisodeBrowserSection(
              title: '选集',
              totalLabel: '共 9 集',
              seasons: const <TvEpisodeSeasonOptionData>[],
              episodes: episodes,
              selectedRangeIndex: 0,
              rangeSize: 30,
              previewCount: 4,
              emptyText: '暂无',
              detailText: '详情',
              token: '',
              accessCode: '',
              baseUrl: '',
              mode: TvEpisodePickerMode.list,
              onSeasonSelected: (_) {},
              onRangeSelected: (_) {},
              onEpisodeSelected: (_) {},
              onEpisodeLongPress: (_) {},
              onEpisodeDetailTap: (_) {},
              onOpenPicker: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, greaterThan(0));
    final end = position.pixels;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(ListView)));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    expect(find.byType(HoverScrollArrows), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(end));
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(end, 0.5));
  });
}
