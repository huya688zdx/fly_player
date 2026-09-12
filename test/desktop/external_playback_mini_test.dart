import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/external_playback_host.dart';
import 'package:fly_player/desktop/playback/external_playback_mini_controller.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  testWidgets('极简模式置顶、展开和退出保留页面；置顶失败恢复窗口', (tester) async {
    const window = MethodChannel('window_manager');
    const screen = MethodChannel('dev.leanflutter.plugins/screen_retriever');
    const original = Rect.fromLTWH(100, 80, 1200, 800);
    var bounds = original;
    var top = false;
    var resizable = true;
    var maximized = true;
    var failPin = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(window, (call) async {
      final args = call.arguments as Map? ?? {};
      switch (call.method) {
        case 'isFullScreen':
          return false;
        case 'isMaximized':
          return maximized;
        case 'isResizable':
          return resizable;
        case 'isAlwaysOnTop':
          return top;
        case 'unmaximize':
          maximized = false;
        case 'maximize':
          maximized = true;
        case 'getBounds':
          return {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          };
        case 'setBounds':
          bounds = Rect.fromLTWH(
            args['x'] ?? bounds.left,
            args['y'] ?? bounds.top,
            args['width'] ?? bounds.width,
            args['height'] ?? bounds.height,
          );
        case 'setResizable':
          resizable = args['isResizable'];
        case 'setAlwaysOnTop':
          if (failPin && args['isAlwaysOnTop'] == true) {
            throw PlatformException(code: 'pin-failed');
          }
          top = args['isAlwaysOnTop'];
      }
      return null;
    });
    final display = {
      'id': 'main',
      'size': {'width': 1920.0, 'height': 1080.0},
      'visiblePosition': {'dx': 0.0, 'dy': 0.0},
      'visibleSize': {'width': 1920.0, 'height': 1040.0},
    };
    messenger.setMockMethodCallHandler(
      screen,
      (call) async => switch (call.method) {
        'getPrimaryDisplay' => display,
        'getAllDisplays' => {
          'displays': [display],
        },
        'getCursorScreenPoint' => {'dx': 900.0, 'dy': 900.0},
        _ => null,
      },
    );
    addTearDown(() async {
      ExternalPlaybackHost.status.value = null;
      messenger.setMockMethodCallHandler(window, null);
      messenger.setMockMethodCallHandler(screen, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    ExternalPlaybackHost.status.value = const ExternalPlaybackStatus(
      source: MpvMediaSource(
        itemGuid: 'mini',
        mediaGuid: 'media',
        videoGuid: 'video',
        url: 'movie.mkv',
        headers: {},
        title: '轻音少女 第 1 季 第 2 集 乐器！',
      ),
      position: Duration(minutes: 3),
      duration: Duration(minutes: 24),
      paused: true,
      danmakuEnabled: false,
      danmakuLabel: '',
      danmakuCount: 0,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = original.size;
    final field = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.ocean),
        builder: (_, child) => ExternalPlaybackMiniHost(child: child!),
        home: Scaffold(body: TextField(key: field)),
      ),
    );
    await tester.enterText(find.byType(TextField), '保留原页面输入');
    final element = field.currentContext;
    final entering = ExternalPlaybackMiniController.enter();
    await tester.pumpAndSettle();
    await entering;
    expect(top, isTrue);
    expect(resizable, isFalse);
    expect(maximized, isFalse);
    expect(bounds, const Rect.fromLTWH(780, 12, 360, 64));
    tester.view.physicalSize = bounds.size;
    await tester.pumpAndSettle();
    expect(MediaQuery.sizeOf(field.currentContext!), original.size);
    expect(find.text('保留原页面输入'), findsNothing);
    expect(tester.takeException(), isNull);
    // 模拟拖到工作区底边后展开，操作区必须仍然全部可见。
    bounds = const Rect.fromLTWH(550, 950, 360, 64);
    await tester.tap(find.byTooltip('展开操作'));
    await tester.pumpAndSettle();
    expect(bounds.left, 550);
    expect(bounds.bottom, 1040);
    tester.view.physicalSize = bounds.size;
    await tester.pumpAndSettle();
    expect(find.byTooltip('前进 10 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('返回完整界面'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = original.size;
    await tester.pumpAndSettle();
    expect(bounds, original);
    expect(top, isFalse);
    expect(resizable, isTrue);
    expect(maximized, isTrue);
    expect(field.currentContext, same(element));
    expect(find.text('保留原页面输入'), findsOneWidget);
    failPin = true;
    final failedEntry = expectLater(
      ExternalPlaybackMiniController.enter(),
      throwsA(isA<PlatformException>()),
    );
    await tester.pumpAndSettle();
    await failedEntry;
    expect(ExternalPlaybackMiniController.active.value, isFalse);
    expect(bounds, original);
    expect(resizable, isTrue);
    expect(find.text('保留原页面输入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
