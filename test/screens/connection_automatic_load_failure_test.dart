import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/connection_screen.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('后端会话凭据暂不可用时连接页仍可操作', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MediaBackendConnectionStore.connectionsKey: jsonEncode(<Object?>[
        <String, Object?>{
          'kind': 'emby',
          'serverUrl': 'https://emby.example.test',
          'hasAccessToken': true,
        },
      ]),
      MediaBackendConnectionStore.activeKindKey: 'emby',
    });
    final backend = _FailingCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final nas = NasProvider();
    addTearDown(nas.dispose);
    await nas.reloadSettingsForTesting();
    backend.readUnavailable = true;

    await tester.pumpWidget(_connectionScreen(nas));
    await backend.readAttempt.future;
    await tester.pump();

    _expectPageRemainsOperable(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('登录历史迁移写入失败时连接页仍可操作', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'http://nas.example.test',
          'userName': 'alice',
          'password': 'legacy-password',
          'rememberPassword': true,
          'updatedAtMillis': 1,
        }),
      ],
    });
    final backend = _FailingCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final nas = NasProvider();
    addTearDown(nas.dispose);
    await nas.reloadSettingsForTesting();
    backend.failWrite = true;

    await tester.pumpWidget(_connectionScreen(nas));
    await backend.writeAttempt.future;
    await tester.pump();

    _expectPageRemainsOperable(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('登录历史凭据清理失败时连接页仍可操作', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_history_v1': <String>[
        jsonEncode(<String, Object?>{
          'kind': 'feiniu',
          'baseUrl': 'http://nas.example.test',
          'userName': 'alice',
          'rememberPassword': false,
          'updatedAtMillis': 1,
        }),
      ],
    });
    final backend = _FailingCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);
    final nas = NasProvider();
    addTearDown(nas.dispose);
    await nas.reloadSettingsForTesting();
    backend.failDelete = true;

    await tester.pumpWidget(_connectionScreen(nas));
    await backend.deleteAttempt.future;
    await tester.pump();

    _expectPageRemainsOperable(tester);
    expect(tester.takeException(), isNull);
  });
}

Widget _connectionScreen(NasProvider nas) {
  return ChangeNotifierProvider<NasProvider>.value(
    value: nas,
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
      home: const ConnectionScreen(),
    ),
  );
}

void _expectPageRemainsOperable(WidgetTester tester) {
  expect(find.text('登录'), findsOneWidget);
  final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
  expect(button.onPressed, isNotNull);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

class _FailingCredentialBackend implements SecureCredentialBackend {
  bool readUnavailable = false;
  bool failWrite = false;
  bool failDelete = false;
  final Completer<void> readAttempt = Completer<void>();
  final Completer<void> writeAttempt = Completer<void>();
  final Completer<void> deleteAttempt = Completer<void>();

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    if (readUnavailable) {
      if (!readAttempt.isCompleted) readAttempt.complete();
      return const SecureCredentialReadResult.unavailable();
    }
    return const SecureCredentialReadResult.missing();
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) {
      if (!writeAttempt.isCompleted) writeAttempt.complete();
      throw SecureCredentialOperationException('write', key);
    }
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) {
      if (!deleteAttempt.isCompleted) deleteAttempt.complete();
      throw SecureCredentialOperationException('delete', key);
    }
  }
}
