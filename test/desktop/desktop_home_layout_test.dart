import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';
import 'package:fly_player/media_backend/home_catalog_presentation.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/screens/home/widgets/home_catalog_section.dart';
import 'package:fly_player/screens/home/widgets/home_continue_watching_section.dart';
import 'package:fly_player/screens/home/widgets/home_horizontal_shelf.dart';
import 'package:fly_player/screens/home/widgets/home_landscape_media_section.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/layout_adaptive.dart';

MediaLayoutProfile? _capturedProfile;

/// 1400 档桌面窗口测试宿主：显式指定 MediaQuery size，使
/// MediaLayoutProfile.of / HoverLift / 右键包装按桌面档生效。
Widget desktopApp({required double width, required Widget child}) =>
    MaterialApp(
      theme: AppThemeBuilder.build(AppThemePreset.midnight),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

Future<MediaLayoutProfile> profileAt(WidgetTester tester, double width) async {
  _capturedProfile = null;
  await tester.pumpWidget(
    desktopApp(
      width: width,
      child: Builder(
        builder: (context) {
          _capturedProfile = MediaLayoutProfile.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return _capturedProfile!;
}

const _emptyImage = MediaImageRequest.empty;

List<HomeCatalogCardData> catalogItems(int count) =>
    List<HomeCatalogCardData>.generate(
      count,
      (index) => HomeCatalogCardData(
        id: 'lib-$index',
        title: '媒体库 $index',
        mediaType: HomeCatalogMediaType.series,
        imageRequests: const <MediaImageRequest>[
          _emptyImage,
          _emptyImage,
          _emptyImage,
        ],
      ),
    );

List<HomeContinueCardData> continueItems(int count) =>
    List<HomeContinueCardData>.generate(
      count,
      (index) => HomeContinueCardData(
        id: 'c-$index',
        title: '续看 $index',
        contextText: '第 1 季 · 第 ${index + 1} 集',
        progress: .3,
        imageRequest: _emptyImage,
        downloaded: false,
      ),
    );

List<HomeLandscapeCardData> landscapeItems(int count) =>
    List<HomeLandscapeCardData>.generate(
      count,
      (index) => HomeLandscapeCardData(
        id: 'l-$index',
        title: '下一集 $index',
        contextText: '第 1 季 · 第 ${index + 1} 集',
        imageRequest: _emptyImage,
      ),
    );

Widget shelfForTest({required int itemCount, required double width}) =>
    desktopApp(
      width: width,
      child: SizedBox(
        height: 220,
        child: HomeHorizontalShelf<int>(
          storageKey: 'desktop-test',
          items: List<int>.generate(itemCount, (index) => index),
          idealItemWidth: 210,
          minItemWidth: 176,
          maxItemWidth: 210,
          itemAspectRatio: 16 / 10,
          textLinesHeight: 44,
          gap: 12,
          itemBuilder: (context, item, cardWidth) => SizedBox(
            key: ValueKey<int>(item),
            width: cardWidth,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );

double arrowOpacityOf(WidgetTester tester, IconData icon) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byIcon(icon),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

Future<void> hoverAt(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: tester.getCenter(finder));
  addTearDown(gesture.removePointer);
  await tester.pumpAndSettle();
}

void main() {
  group('MediaLayoutProfile 桌面密度档', () {
    testWidgets('1400px 视口命中桌面档且数值符合桌面公式', (tester) async {
      final profile = await profileAt(tester, 1400);

      expect(profile.isDesktopTier, isTrue);
      expect(profile.pageHorizontalPadding, 28.0);
      expect(profile.sectionGap, 18.0);
      expect(profile.itemGap, 12.0);
      expect(profile.categoryGridColumns, 7);
      expect(profile.homePosterCardWidth, closeTo(1400 / 7.8, .001));
      // 固定物理解码/请求宽度常量不得随桌面档变化。
      expect(profile.homePosterDecodeWidth, 352);
      expect(profile.homeCatalogDecodeWidth, 440);
      expect(profile.continueDecodeWidth, 520);
      expect(profile.homeCatalogRequestWidth, 440);
      expect(profile.homeContinueRequestWidth, 520);
    });

    testWidgets('1700px 视口启用 8 列宽档', (tester) async {
      final profile = await profileAt(tester, 1700);

      expect(profile.isDesktopTier, isTrue);
      expect(profile.categoryGridColumns, 8);
      expect(profile.pageHorizontalPadding, 28.0);
      expect(profile.sectionGap, 18.0);
      expect(profile.itemGap, 12.0);
      // 1700 / 8.8 = 193.2 超上界，收到 190。
      expect(profile.homePosterCardWidth, 190.0);
    });

    testWidgets('1600px 视口恰好命中 8 列宽档', (tester) async {
      final profile = await profileAt(tester, 1600);

      expect(profile.categoryGridColumns, 8);
      expect(profile.homePosterCardWidth, closeTo(1600 / 8.8, .001));
    });

    testWidgets('800px 视口保持旧公式（防回归）', (tester) async {
      final profile = await profileAt(tester, 800);

      expect(profile.isDesktopTier, isFalse);
      expect(profile.pageHorizontalPadding, 12.0);
      expect(profile.sectionGap, 14.0);
      expect(profile.itemGap, 10.0);
      expect(profile.categoryGridColumns, 4);
      expect(profile.homePosterCardWidth, closeTo(800 / 4.8, .001));
      expect(profile.homePosterCardWidth, lessThanOrEqualTo(176.0));
    });

    testWidgets('360px 手机档保持旧公式（防回归）', (tester) async {
      final profile = await profileAt(tester, 360);

      expect(profile.isDesktopTier, isFalse);
      expect(profile.pageHorizontalPadding, 8.0);
      expect(profile.sectionGap, 12.0);
      expect(profile.itemGap, 8.0);
      expect(profile.categoryGridColumns, 3);
      expect(profile.homePosterCardWidth, 115.0);
    });
  });

  group('三后端目录卡桌面表现（1400px 视口）', () {
    // 桌面档货架卡宽：0.28 系数在 1400px 下超出各表现的 clamp 上限，分别收到
    // collage 120 / backdrop 196 / gallery 160。
    final expectedCardWidth = <HomeCatalogPresentation, double>{
      HomeCatalogPresentation.officialCollage: 120.0,
      HomeCatalogPresentation.cinematicBackdrop: 196.0,
      HomeCatalogPresentation.clearGallery: 160.0,
    };

    for (final presentation in HomeCatalogPresentation.values) {
      testWidgets('${presentation.name} 目录卡构建无异常且卡片存在', (tester) async {
        await tester.pumpWidget(
          desktopApp(
            width: 1400,
            child: HomeCatalogSection(
              presentation: presentation,
              items: catalogItems(6),
              onTap: (_) {},
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: presentation.name);
        expect(
          find.byKey(const ValueKey<String>('catalog-card-lib-0')),
          findsOneWidget,
          reason: presentation.name,
        );
        expect(
          find.byKey(const ValueKey<String>('catalog-title-lib-0')),
          findsOneWidget,
          reason: presentation.name,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('catalog-card-lib-0')))
              .width,
          closeTo(expectedCardWidth[presentation]!, .01),
          reason: presentation.name,
        );
      });
    }
  });

  group('桌面档货架与卡片', () {
    testWidgets('1400px 下续看/横版区块构建无溢出且卡片包裹 HoverLift', (tester) async {
      await tester.pumpWidget(
        desktopApp(
          width: 1400,
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                // 只放 3 个条目保证全部在视口内被构建（ListView 懒构建）。
                HomeContinueWatchingSection(
                  items: continueItems(3),
                  onOpenDetail: (_) {},
                  onPlay: (_) {},
                  onLongPress: (_) {},
                ),
                HomeLandscapeMediaSection(
                  title: '下一集',
                  items: landscapeItems(3),
                  onOpenDetail: (_) {},
                  onLongPress: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('continue-card-c-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('landscape-card-l-0')),
        findsOneWidget,
      );
      expect(find.byType(HoverLift), findsNWidgets(6));
    });

    testWidgets('非桌面档不出现 HoverLift 与滚动箭头', (tester) async {
      await tester.pumpWidget(
        desktopApp(
          width: 800,
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                // 只放 3 个条目保证全部在视口内被构建（ListView 懒构建）。
                HomeContinueWatchingSection(
                  items: continueItems(3),
                  onOpenDetail: (_) {},
                  onPlay: (_) {},
                  onLongPress: (_) {},
                ),
                HomeLandscapeMediaSection(
                  title: '下一集',
                  items: landscapeItems(3),
                  onOpenDetail: (_) {},
                  onLongPress: (_) {},
                ),
                SizedBox(
                  height: 220,
                  child: HomeHorizontalShelf<int>(
                    storageKey: 'non-desktop',
                    items: List<int>.generate(10, (index) => index),
                    idealItemWidth: 210,
                    minItemWidth: 176,
                    maxItemWidth: 210,
                    itemAspectRatio: 16 / 10,
                    itemBuilder: (context, item, cardWidth) =>
                        const ColoredBox(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await hoverAt(tester, find.byType(ListView).first);

      expect(tester.takeException(), isNull);
      expect(find.byType(HoverLift), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('桌面档悬停出现滚动箭头且点击按 0.8 视口翻页', (tester) async {
      await tester.pumpWidget(shelfForTest(itemCount: 30, width: 1400));
      await tester.pumpAndSettle();

      // 未悬停：箭头淡出。
      expect(arrowOpacityOf(tester, Icons.chevron_right), 0);
      expect(arrowOpacityOf(tester, Icons.chevron_left), 0);

      await hoverAt(tester, find.byType(ListView));

      // 起点可右滚不可左滚。
      expect(arrowOpacityOf(tester, Icons.chevron_right), 1);
      expect(arrowOpacityOf(tester, Icons.chevron_left), 0);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.pixels, closeTo(position.viewportDimension * 0.8, .5));
      expect(arrowOpacityOf(tester, Icons.chevron_left), 1);
    });

    testWidgets('桌面档无溢出内容时箭头保持隐藏', (tester) async {
      await tester.pumpWidget(shelfForTest(itemCount: 1, width: 1400));
      await tester.pumpAndSettle();
      await hoverAt(tester, find.byType(ListView));

      expect(arrowOpacityOf(tester, Icons.chevron_right), 0);
      expect(arrowOpacityOf(tester, Icons.chevron_left), 0);
    });

    testWidgets('桌面档续看卡右键触发回调且非桌面档不触发', (tester) async {
      final rightTaps = <double>[];
      Widget section(double width) => desktopApp(
        width: width,
        child: HomeContinueWatchingSection(
          items: continueItems(1),
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
          onSecondaryTap: (item, globalPosition) =>
              rightTaps.add(globalPosition.dx),
        ),
      );

      await tester.pumpWidget(section(1400));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('continue-card-c-0')),
        ),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(rightTaps, hasLength(1));

      await tester.pumpWidget(section(800));
      await tester.pumpAndSettle();
      final plainGesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('continue-card-c-0')),
        ),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await plainGesture.up();
      await tester.pumpAndSettle();

      // 非桌面档没有右键包装，不新增回调。
      expect(rightTaps, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });
}
