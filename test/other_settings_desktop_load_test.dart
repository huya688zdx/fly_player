import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/screens/screenshot_settings_screen.dart';
import 'package:fly_player/services/storage_access_host.dart';
import 'package:fly_player/services/storage_access_service.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全方法抛平台异常的宿主桩，用于验证加载路径的单项容错。
Never _unavailable() => throw PlatformException(code: 'unavailable');

class _ThrowingStorageAccessHost implements StorageAccessHost {
  const _ThrowingStorageAccessHost();

  @override
  Future<bool?> hasFileAccess() async => _unavailable();

  @override
  Future<bool?> requestFileAccess() async => _unavailable();

  @override
  Future<Map<Object?, Object?>?> getScreenshotCustomDirectory() async =>
      _unavailable();

  @override
  Future<Map<Object?, Object?>?> requestScreenshotCustomDirectory() async =>
      _unavailable();

  @override
  Future<bool?> clearScreenshotCustomDirectory() async => _unavailable();

  @override
  Future<List<Object?>?> listScreenshotLibrary() async => _unavailable();

  @override
  Future<Uint8List?> readScreenshotFileBytes({
    required String sourceKind,
    required String pathOrIdentifier,
  }) async => _unavailable();

  @override
  Future<Map<Object?, Object?>?> deleteScreenshotFiles(
    List<Map<String, String>> items,
  ) async => _unavailable();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'CN'),
        home: screen,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('桌面宿主下「其他」设置页正常加载并渲染三项入口', (WidgetTester tester) async {
    // 回归背景：桌面端无 fly_player/storage 通道，此前首个加载调用
    // 抛 MissingPluginException，页面永久卡在加载态。
    StorageAccessService.setHostForTesting(const DesktopStorageAccessHost());
    addTearDown(() => StorageAccessService.setHostForTesting(null));

    await pumpScreen(tester, const OtherSettingsScreen());

    expect(find.byType(BirdLoader), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));
    expect(find.text(l10n.settingsBookmarkManagerTitle), findsOneWidget);
    expect(find.text(l10n.settingsDanmakuTitle), findsOneWidget);
    expect(find.text(l10n.settingsScreenshotTitle), findsOneWidget);
  });

  testWidgets('加载依赖抛异常时「其他」页单项降级，不再卡加载态', (WidgetTester tester) async {
    // 用抛错的宿主桩模拟真实设备上的平台异常（如通道不可用）：
    // 页面应按默认值渲染，而不是把整页永久卡在加载态。
    StorageAccessService.setHostForTesting(const _ThrowingStorageAccessHost());
    addTearDown(() => StorageAccessService.setHostForTesting(null));

    await pumpScreen(tester, const OtherSettingsScreen());

    expect(find.byType(BirdLoader), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('桌面宿主下截图设置页正常加载并渲染四项入口', (WidgetTester tester) async {
    StorageAccessService.setHostForTesting(const DesktopStorageAccessHost());
    addTearDown(() => StorageAccessService.setHostForTesting(null));

    await pumpScreen(tester, const ScreenshotSettingsScreen());

    expect(find.byType(BirdLoader), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));
    expect(
      find.text(l10n.settingsScreenshotIncludeSubtitlesTitle),
      findsOneWidget,
    );
    expect(find.text(l10n.settingsScreenshotSavePathTitle), findsOneWidget);
    expect(find.text(l10n.settingsScreenshotPreviewTitle), findsOneWidget);
    expect(
      find.text(l10n.settingsScreenshotCustomDirectoryTitle),
      findsOneWidget,
    );
  });
}
