import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/main.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/connection_screen.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/widgets/common/app_error_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首次凭据迁移写入失败时显示可重试错误', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'token': 'legacy-token',
    });
    final backend = _SwitchableCredentialBackend()..failWrite = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await tester.pumpWidget(const FlyPlayerApp());
    await backend.writeAttempt.future;
    await _pumpUntilFound(tester, find.byType(AppErrorState));

    _expectRetryableGateError(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首次凭据清理失败时显示可重试错误', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'remember_password': false,
    });
    final backend = _SwitchableCredentialBackend()..failDelete = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await tester.pumpWidget(const FlyPlayerApp());
    await backend.deleteAttempt.future;
    await _pumpUntilFound(tester, find.byType(AppErrorState));

    _expectRetryableGateError(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首次会话加载不可用时显示重试并在恢复后进入登录页', (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _SwitchableCredentialBackend()..unavailable = true;
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await tester.pumpWidget(const FlyPlayerApp());
    await backend.readAttempt.future;
    await _pumpUntilFound(tester, find.byType(AppErrorState));

    expect(tester.takeException(), isNull);
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ConnectionScreen), findsNothing);

    backend.unavailable = false;
    await tester.tap(find.byType(ElevatedButton));
    await _pumpUntilFound(tester, find.byType(ConnectionScreen));

    expect(tester.takeException(), isNull);
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ConnectionScreen), findsOneWidget);

    final nas = Provider.of<NasProvider>(
      tester.element(find.byType(ConnectionScreen)),
      listen: false,
    );
    await nas.updateSettings(
      baseUrl: 'http://nas.example.test',
      userName: 'alice',
      password: 'secret',
      token: 'active-token',
    );
    await _pumpUntilFound(tester, find.byType(MainNavigation));
    expect(find.byType(MainNavigation), findsOneWidget);

    backend
      ..unavailable = true
      ..resetReadAttempt();
    nas.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await backend.readAttempt.future;
    await _pumpUntil(tester, () => nas.hasLoadFailure);

    expect(nas.isReady, isTrue);
    expect(nas.hasLoadFailure, isTrue);
    expect(find.byType(MainNavigation), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _expectRetryableGateError(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byType(AppErrorState), findsOneWidget);
  expect(find.byType(ElevatedButton), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byType(ConnectionScreen), findsNothing);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _SwitchableCredentialBackend implements SecureCredentialBackend {
  bool unavailable = false;
  bool failWrite = false;
  bool failDelete = false;
  Completer<void> readAttempt = Completer<void>();
  final Completer<void> writeAttempt = Completer<void>();
  final Completer<void> deleteAttempt = Completer<void>();

  void resetReadAttempt() {
    readAttempt = Completer<void>();
  }

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    if (!readAttempt.isCompleted) readAttempt.complete();
    return unavailable
        ? const SecureCredentialReadResult.unavailable()
        : const SecureCredentialReadResult.missing();
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
