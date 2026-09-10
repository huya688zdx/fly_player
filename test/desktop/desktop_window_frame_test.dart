import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_window_frame.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets('透明窗口控制区不含标识，全屏往返保留页面状态与安全区', (tester) async {
    const channel = MethodChannel('window_manager');
    final messenger = tester.binding.defaultBinaryMessenger;
    var fullscreen = false;
    var maximized = false;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'isFullScreen' => fullscreen,
        'isMaximized' => maximized,
        _ => false,
      },
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final pageKey = GlobalKey();

    Widget host(AppThemePreset preset) => MaterialApp(
      theme: AppThemeBuilder.build(preset),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => DesktopWindowFrame(child: child!),
      home: Scaffold(
        body: SafeArea(child: TextField(key: pageKey)),
      ),
    );

    await tester.pumpWidget(host(AppThemePreset.midnight));
    await tester.pumpAndSettle();
    final caption = tester.widget<WindowCaption>(find.byType(WindowCaption));
    expect(caption.brightness, Brightness.dark);
    expect(caption.backgroundColor, Colors.transparent);
    expect(caption.title, isNull);
    expect(find.byType(Image), findsNothing);
    expect(tester.getTopLeft(find.byType(Scaffold)).dy, 0);
    expect(tester.getTopLeft(find.byType(TextField)).dy, 32);
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
    fullscreen = true;
    await event(kWindowEventEnterFullScreen);
    expect(find.byType(WindowCaption), findsNothing);
    expect(tester.getTopLeft(find.byType(Scaffold)).dy, 0);
    expect(tester.getTopLeft(find.byType(TextField)).dy, 0);
    expect(pageKey.currentContext, same(pageElement));
    expect(find.text('保留页面'), findsOneWidget);
    // 最大化窗口退出播放全屏时，原生插件可能只改变尺寸而漏发退出事件。
    fullscreen = false;
    maximized = true;
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(find.byType(WindowCaption), findsOneWidget);
    expect(tester.getTopLeft(find.byType(TextField)).dy, 32);
    expect(pageKey.currentContext, same(pageElement));
    expect(
      tester
          .widget<DragToResizeArea>(find.byType(DragToResizeArea))
          .enableResizeEdges,
      isEmpty,
    );
    maximized = false;
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    await event(kWindowEventLeaveFullScreen);
    expect(find.byType(WindowCaption), findsOneWidget);
    expect(tester.getTopLeft(find.byType(TextField)).dy, 32);
    expect(pageKey.currentContext, same(pageElement));
    expect(find.text('保留页面'), findsOneWidget);
    expect(
      tester
          .widget<DragToResizeArea>(find.byType(DragToResizeArea))
          .enableResizeEdges,
      contains(ResizeEdge.top),
    );
    expect(tester.takeException(), isNull);
  });
}
