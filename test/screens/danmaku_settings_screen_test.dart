import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/danmaku/models/danmaku_saved_source.dart';
import 'package:fly_player/screens/danmaku_settings_screen.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/app_atmospheric_background.dart';
import 'package:fly_player/widgets/common/app_ambient_page.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlyDataService.instance.session = null;
    await PlayStatsService.instance.database.bindOwnerScope('');
  });
  tearDown(() async {
    FlyDataService.instance.session = null;
    await PlayStatsService.instance.database.bindOwnerScope('');
  });

  testWidgets('外部设置切换弹幕来源优先顺序后立即保存', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _flyBinding();
    DanmakuSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DanmakuSettingsScreen(
          flyReadinessLoader: () async => {
            'available': true,
            'source_ready': true,
            'auto_danmaku_enabled': false,
            'workflow_enabled': true,
          },
          saveSettings: (value) async {
            saved = value;
          },
          settingsLoader: () async => DanmakuSettings.defaults,
          savedSourceLoader: () async => const <DanmakuSavedSource>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('弹幕来源优先顺序'), findsOneWidget);
    final dandan = find.text(DanmakuSourceStrategy.original.label);
    await tester.scrollUntilVisible(dandan, 180);
    await tester.pumpAndSettle();
    await tester.tap(dandan);
    await tester.pumpAndSettle();
    expect(saved?.sourceStrategy, DanmakuSourceStrategy.original);
    final fly = find.text('飞翔后端优先');
    await tester.ensureVisible(fly);
    await tester.pumpAndSettle();
    await tester.tap(fly);
    await tester.pumpAndSettle();
    expect(saved?.sourceStrategy, DanmakuSourceStrategy.nasPreferred);
    final entry = find.text('仅飞翔后端');
    expect(entry, findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(saved?.sourceStrategy, DanmakuSourceStrategy.nasOnly);
    expect(
      find.text(DanmakuSourceStrategy.nasOnly.description),
      findsOneWidget,
    );
    FlyDataService.instance.session = null;
    await tester.pumpAndSettle();
    expect(find.text('仅飞翔后端'), findsNothing);
    expect(find.text(DanmakuSourceStrategy.nasOnly.description), findsNothing);
    await tester.scrollUntilVisible(find.text('本地优先'), -160);
    expect(find.text('本地优先'), findsOneWidget);
  });

  for (final scope in ['legacy-emby', 'legacy-feiniu']) {
    testWidgets('$scope 保留飞翔会话和仅NAS设置时隐藏服务策略并保留普通来源', (tester) async {
      await _flyBinding();
      await PlayStatsService.instance.database.bindOwnerScope(scope);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DanmakuSettingsScreen(
            settingsLoader: () async => DanmakuSettings.defaults.copyWith(
              sourceStrategy: DanmakuSourceStrategy.nasOnly,
            ),
            savedSourceLoader: () async => const <DanmakuSavedSource>[],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(FlyDataService.instance.session, isNotNull);
      expect(find.text('仅飞翔后端'), findsNothing);
      expect(
        find.text(DanmakuSourceStrategy.nasOnly.description),
        findsNothing,
      );
      expect(find.text('本地优先'), findsOneWidget);
      expect(find.text('弹幕管理'), findsOneWidget);
    });
  }

  testWidgets('Android 弹幕设置使用沉浸卡片且保存失败时恢复原值', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.buildFromColors(
          AppThemePalette.fallback,
        ).copyWith(platform: TargetPlatform.android),
        home: DanmakuSettingsScreen(
          saveSettings: (_) async => throw StateError('save failed'),
          settingsLoader: () async => DanmakuSettings.defaults,
          savedSourceLoader: () async => const <DanmakuSavedSource>[],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final card = tester.widget<Material>(
      find
          .ancestor(of: find.text('弹幕管理'), matching: find.byType(Material))
          .first,
    );
    expect(card.color!.a, closeTo(0.16, 0.01));
    final backButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
    );
    expect(backButton.style!.backgroundColor!.resolve({})!.a, lessThan(0.2));
    expect(find.byType(AppAtmosphericBackground), findsOneWidget);
    expect(
      AppAmbientPage.sharesBackgroundOf(tester.element(find.byType(Scaffold))),
      isFalse,
    );

    final before = tester.widget<Switch>(find.byType(Switch).first).value;
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<Switch>(find.byType(Switch).first).value, before);
  });
}

Future<void> _flyBinding() async {
  final service = FlyDataService.instance;
  service.session = FlyDataSession(
    serverUrl: 'https://fixture.invalid',
    userId: 'alice',
    username: 'alice',
    deviceId: 'device',
    deviceName: 'fixture',
    token: 'fixture-token',
    installationId: 'installation',
  );
  final database =
      PlayStatsService.instance.database as SqflitePlayStatsDatabase;
  await database.bindOwnerScope(
    PlayStatsService.scopeForBinding(service.session!.accountKey, 'binding'),
  );
  database.bindingReference = {'binding_id': 'binding'};
}
