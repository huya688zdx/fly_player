import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_window_frame.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets('标题栏跟随主题，全屏往返保留页面状态与可用尺寸', (tester) async {
    const channel = MethodChannel('window_manager');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final pageKey = GlobalKey();

    Widget host(AppThemePreset preset) => MaterialApp(
      theme: AppThemeBuilder.build(preset),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => DesktopWindowFrame(child: child!),
      home: Scaffold(body: TextField(key: pageKey)),
    );

    await tester.pumpWidget(host(AppThemePreset.midnight));
    await tester.pumpAndSettle();
    final caption = tester.widget<WindowCaption>(find.byType(WindowCaption));
    expect(caption.brightness, Brightness.dark);
    expect(
      caption.backgroundColor,
      pageKey.currentContext!.appColors.backgroundBase,
    );
    expect(tester.getTopLeft(find.byType(Scaffold)).dy, 36);
    await tester.enterText(find.byType(TextField), '保留页面');

    await tester.pumpWidget(host(AppThemePreset.latte));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WindowCaption>(find.byType(WindowCaption)).brightness,
      Brightness.light,
    );

    Future<void> event(String name) async {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onEvent', {'eventName': name}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    final pageElement = pageKey.currentContext;
    await event(kWindowEventEnterFullScreen);
    expect(find.byType(WindowCaption), findsNothing);
    expect(tester.getTopLeft(find.byType(Scaffold)).dy, 0);
    expect(pageKey.currentContext, same(pageElement));
    expect(find.text('保留页面'), findsOneWidget);
    await event(kWindowEventLeaveFullScreen);
    expect(find.byType(WindowCaption), findsOneWidget);
    expect(tester.getTopLeft(find.byType(Scaffold)).dy, 36);
    expect(pageKey.currentContext, same(pageElement));
    expect(find.text('保留页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
