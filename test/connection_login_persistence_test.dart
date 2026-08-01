import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/connection_screen.dart';
import 'package:fly_player/services/login_history_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  group('effectivePersistedBaseUrlForLogin', () {
    test('FN Connect 登录成功后运行时地址保存 resolvedBaseUrl', () {
      const result = LoginWithBaseUrlResult(
        token: 'token',
        resolvedBaseUrl: 'https://geqian688.fnos.net',
        usedFnConnect: true,
      );

      expect(
        effectivePersistedBaseUrlForLogin(
          sourceBaseUrl: 'geqian688',
          loginResult: result,
        ),
        'https://geqian688.fnos.net',
      );
    });

    test('普通直连登录继续保存用户输入地址', () {
      const result = LoginWithBaseUrlResult(
        token: 'token',
        resolvedBaseUrl: 'https://nas.example.com:5667',
      );

      expect(
        effectivePersistedBaseUrlForLogin(
          sourceBaseUrl: 'nas.example.com:5667',
          loginResult: result,
        ),
        'nas.example.com:5667',
      );
    });

    test('普通直连登录保存源地址，作为飞牛兼容基线', () {
      const result = LoginWithBaseUrlResult(
        token: 'fake-feiniu-token',
        resolvedBaseUrl: 'https://nas.example.test:5667',
      );

      expect(
        effectivePersistedBaseUrlForLogin(
          sourceBaseUrl: 'nas.example.test:5667',
          loginResult: result,
        ),
        'nas.example.test:5667',
      );
    });
  });

  testWidgets('记住登录时屏幕提交会保存访问码到运行态和安全历史', (tester) async {
    final harness = await _pumpPersistenceScreen(tester);

    await tester.enterText(
      find.byKey(const Key('feiniuAccessCodeField')),
      'screen-access-code',
    );
    await _submitSuccessfulFeiniuLogin(tester);

    expect(harness.provider.accessCode, 'screen-access-code');
    expect(
      (await LoginHistoryStore.load()).single.accessCode,
      'screen-access-code',
    );
    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getStringList('login_history_v1')!.single;
    expect(rawHistory, isNot(contains('screen-access-code')));
    expect(jsonDecode(rawHistory), isNot(containsPair('accessCode', anything)));
  });

  testWidgets('不记住登录时屏幕提交仅保留当前运行态访问码', (tester) async {
    final harness = await _pumpPersistenceScreen(tester);

    await tester.enterText(
      find.byKey(const Key('feiniuAccessCodeField')),
      'runtime-only-access-code',
    );
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await _submitSuccessfulFeiniuLogin(tester);

    expect(harness.provider.accessCode, 'runtime-only-access-code');
    expect((await LoginHistoryStore.load()).single.accessCode, isEmpty);
    expect(
      harness.backend.values.values,
      isNot(contains('runtime-only-access-code')),
    );
  });
}

Future<_PersistenceHarness> _pumpPersistenceScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'base_url': 'https://nas.example.test',
    'user_name': 'alice',
    'password': 'secret',
    'remember_password': true,
  });
  final backend = _TrackingCredentialBackend();
  SecureCredentialStore.setBackendForTesting(backend);
  addTearDown(SecureCredentialStore.resetBackendForTesting);
  final provider = NasProvider();
  addTearDown(provider.dispose);
  await provider.reloadSettingsForTesting();
  await LoginHistoryStore.clear();
  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider<NasProvider>.value(value: provider)],
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
        home: ConnectionScreen(
          feiniuLogin:
              ({
                required baseUrl,
                required userName,
                required password,
                required accessCode,
              }) async => LoginWithBaseUrlResult(
                token: 'token',
                resolvedBaseUrl: baseUrl,
              ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _PersistenceHarness(provider: provider, backend: backend);
}

Future<void> _submitSuccessfulFeiniuLogin(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
}

class _PersistenceHarness {
  const _PersistenceHarness({required this.provider, required this.backend});

  final NasProvider provider;
  final _TrackingCredentialBackend backend;
}

class _TrackingCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    final value = values[key];
    return value == null
        ? const SecureCredentialReadResult.missing()
        : SecureCredentialReadResult.found(value);
  }

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }
}
