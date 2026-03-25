import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/player/widgets/player_controls_chrome.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  ThemeData _theme() =>
      AppThemeBuilder.buildFromColors(AppThemePalette.fallback);

  Finder _listenVideoAsset() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is SvgPicture &&
          widget.bytesLoader.toString().contains(
            'assets/icons/listen_video.svg',
          ),
    );
  }

  Finder _fitModeButton() {
    return find.byIcon(Icons.fit_screen_outlined);
  }

  Finder _pictureInPictureButton() {
    return find.byIcon(Icons.picture_in_picture_alt_outlined);
  }

  Finder _captureButton() {
    return find.byIcon(Icons.photo_camera_outlined);
  }

  Finder _moreButton() {
    return find.byIcon(Icons.more_horiz_rounded);
  }

  testWidgets('renders listen video action when enabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: PlayerControlsTopBar(
            visible: true,
            compactUi: false,
            titleFontSize: 14,
            title: 'Test',
            danmakuEnabled: false,
            showListenVideoAction: true,
            onBack: () {},
            onToggleListenVideo: () {},
            onFitMode: () {},
            onDanmakuSettings: () {},
            onMore: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_listenVideoAsset(), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(4));
  });

  testWidgets('highlights listen video action when active', (
    WidgetTester tester,
  ) async {
    final theme = _theme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: PlayerControlsTopBar(
            visible: true,
            compactUi: false,
            titleFontSize: 14,
            title: 'Test',
            danmakuEnabled: false,
            showListenVideoAction: true,
            listenVideoActive: true,
            onBack: () {},
            onToggleListenVideo: () {},
            onFitMode: () {},
            onDanmakuSettings: () {},
            onMore: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buttonFinder = find.ancestor(
      of: _listenVideoAsset(),
      matching: find.byType(TextButton),
    );
    final button = tester.widget<TextButton>(buttonFinder);
    final background = button.style?.backgroundColor?.resolve(
      const <WidgetState>{},
    );

    expect(background, AppThemePalette.fallback.accentSoft);
  });

  testWidgets('hides fit mode action when disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: PlayerControlsTopBar(
            visible: true,
            compactUi: false,
            titleFontSize: 14,
            title: 'Test',
            danmakuEnabled: false,
            showListenVideoAction: true,
            showFitModeAction: false,
            onBack: () {},
            onToggleListenVideo: () {},
            onFitMode: () {},
            onDanmakuSettings: () {},
            onMore: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_listenVideoAsset(), findsOneWidget);
    expect(_fitModeButton(), findsNothing);
  });

  testWidgets('keeps only pip listen-video and more in compact action mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: PlayerControlsTopBar(
            visible: true,
            compactUi: true,
            titleFontSize: 14,
            title: 'Test',
            danmakuEnabled: true,
            collapseActionsToSubtitleAndMore: true,
            showPictureInPictureAction: true,
            showListenVideoAction: true,
            showFitModeAction: true,
            onBack: () {},
            onPictureInPicture: () {},
            onToggleListenVideo: () {},
            onFitMode: () {},
            onCaptureFrame: () {},
            abLoopLabel: 'AB',
            onAbLoop: () {},
            onDanmakuSettings: () {},
            showCacheDownloadAction: true,
            onCacheDownload: () {},
            onMore: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_pictureInPictureButton(), findsOneWidget);
    expect(_listenVideoAsset(), findsOneWidget);
    expect(_moreButton(), findsOneWidget);
    expect(_captureButton(), findsNothing);
    expect(_fitModeButton(), findsNothing);
    expect(find.text('AB'), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(find.byType(TextButton), findsNWidgets(4));
  });
}
