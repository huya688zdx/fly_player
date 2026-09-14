import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/playback/widgets/touch_player_controls.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('touch playback actions and seeking fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final padding = size.width > size.height
          ? const FakeViewPadding(left: 44, right: 44, bottom: 21)
          : const FakeViewPadding(top: 59, bottom: 34);
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      var toggles = 0;
      var settingsOpened = 0;
      var nextEpisodes = 0;
      Duration? seek;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: TouchPlayerControls(
              title: 'A movie with a long title that fits a narrow screen',
              playing: false,
              loading: false,
              position: const Duration(seconds: 10),
              duration: const Duration(seconds: 100),
              rate: 1,
              isFullscreen: false,
              danmakuEnabled: true,
              onBack: () {},
              onToggle: () => toggles++,
              onSeek: (value) => seek = value,
              onFullscreen: () {},
              onSettings: () => settingsOpened++,
              onSpeed: () {},
              onDanmaku: () {},
              onAudio: () {},
              onSubtitle: () {},
              onScreenshot: () {},
              onEpisodes: () {},
              onPrevious: () {},
              onNext: () => nextEpisodes++,
              onQuality: () {},
              qualityLabel: '1080P',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      expect(toggles, 1);
      expect(settingsOpened, 1);
      expect(nextEpisodes, 1);
      final slider = tester.getRect(find.byType(Slider));
      await tester.tapAt(
        Offset(slider.left + slider.width * 0.75, slider.center.dy),
      );
      await tester.pump();
      expect(seek, isNotNull);
      expect(seek!.inSeconds, inInclusiveRange(65, 90));
      expect(
        tester
            .getSize(find.widgetWithIcon(IconButton, Icons.play_arrow_rounded))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
