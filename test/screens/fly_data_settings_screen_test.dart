import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/fly_account_screen.dart';
import 'package:fly_player/screens/fly_data_settings_screen.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_data_sync_store.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  late _Service service;
  late _Account account;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    service = _Service();
    account = _Account(service);
  });
  tearDown(() {
    account.dispose();
    account.nas.dispose();
    account.backendSession.dispose();
    SecureCredentialStore.resetBackendForTesting();
  });
  testWidgets('未登录只保留现有账号页入口，没有重复登录或迁移表单', (tester) async {
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    expect(find.text('同步记录'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('登录飞翔'), findsOneWidget);
    expect(find.textContaining('旧'), findsNothing);
    expect(service.store.reads, isEmpty);
    await tester.tap(find.text('登录飞翔'));
    await tester.pumpAndSettle();
    expect(find.byType(FlyBindingsScreen), findsOneWidget);
    expect(find.byType(FlyLoginScreen), findsOneWidget);
  });
  testWidgets('只显示账号和同步状态，同步成功更新时间且不触发历史认领', (tester) async {
    service.session = _session('alice');
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('尚未同步'), findsOneWidget);
    expect(find.textContaining('数据集'), findsNothing);
    expect(find.textContaining('确认归属'), findsNothing);
    expect(find.textContaining('scope'), findsNothing);
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(service.syncCalls, 1);
    expect(service.ownershipCalls, 0);
    expect(find.text('同步完成'), findsOneWidget);
    expect(find.textContaining('最近同步：'), findsOneWidget);
    expect(find.text('尚未同步'), findsNothing);
    expect(find.textContaining('快照'), findsNothing);
  });
  testWidgets('失败只给简短重试，不暴露内部错误且重试仍走安全同步', (tester) async {
    service.session = _session('alice');
    service.syncError = StateError('旧历史 scope snapshot #123 必须确认归属');
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(find.text('同步未完成，请重试。'), findsOneWidget);
    expect(find.textContaining('scope'), findsNothing);
    expect(find.textContaining('旧历史'), findsNothing);
    service.syncError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(service.syncCalls, 2);
    expect(service.ownershipCalls, 0);
    expect(find.text('同步完成'), findsOneWidget);
  });
  testWidgets('账号切换后丢弃旧同步结果和旧按钮回调', (tester) async {
    service.session = _session('alice');
    final pending = Completer<Map<String, dynamic>>();
    service.pendingSync = pending.future;
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    final oldAction = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '立即同步'))
        .onPressed!;
    await tester.tap(find.text('立即同步'));
    await tester.pump();
    account.changeSession(_session('bob'));
    await tester.pumpAndSettle();
    expect(find.text('bob'), findsOneWidget);
    oldAction();
    pending.completeError(StateError('alice private failure'));
    await tester.pumpAndSettle();
    expect(service.syncCalls, 1);
    expect(find.textContaining('alice'), findsNothing);
    expect(find.textContaining('private failure'), findsNothing);
    expect(find.text('同步未完成，请重试。'), findsNothing);
    expect(find.text('尚未同步'), findsOneWidget);
  });
  testWidgets('来源切换后丢弃迟到状态，未有记录不要求认领', (tester) async {
    service.session = _session('alice');
    final oldRead = Completer<Map<String, Object?>?>();
    service.store.pendingRead = oldRead.future;
    await tester.pumpWidget(_app(account));
    await tester.pump();
    service.store.pendingRead = null;
    service.scope = 'binding-second:2';
    account.changed();
    await tester.pumpAndSettle();
    oldRead.complete({'last_success_ms': 1, 'pending_json': 'private-packet'});
    await tester.pumpAndSettle();
    expect(find.text('尚未同步'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
    service.syncError = FlyNoFactsToSync();
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(find.text('暂无待同步记录'), findsOneWidget);
    expect(service.ownershipCalls, 0);
  });

  testWidgets('未选择媒体来源属于正常状态，不读取或认领本地历史', (tester) async {
    service.session = _session('alice');
    account.activeBindingId = '';
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    expect(find.text('选择媒体来源'), findsOneWidget);
    expect(find.text('立即同步'), findsNothing);
    expect(service.store.reads, isEmpty);
    expect(service.syncCalls, 0);
    expect(service.ownershipCalls, 0);
    await tester.tap(find.text('选择媒体来源'));
    await tester.pumpAndSettle();
    expect(find.byType(FlyBindingsScreen), findsOneWidget);
  });
}

Widget _app(_Account account) =>
    ChangeNotifierProvider<FlyAccountController>.value(
      value: account,
      child: MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FlyDataSettingsScreen(service: account.service),
      ),
    );
FlyDataSession _session(String user) => FlyDataSession(
  serverUrl: 'https://fly.example.test',
  userId: user,
  username: user,
  deviceId: 'device',
  deviceName: 'device',
  token: 'fixture',
  installationId: 'installation',
  serviceInstanceId: 'instance',
);

class _Account extends FlyAccountController {
  _Account(_Service service)
    : super(
        service: service,
        nas: NasProvider(),
        backendSession: BackendSessionProvider(autoLoad: false),
        autoLoad: false,
      ) {
    ready = true;
    activeBindingId = 'source';
  }
  void changeSession(FlyDataSession session) {
    service.session = session;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

class _Service extends FlyDataService {
  _Service()
    : super(database: SqflitePlayStatsDatabase(), drainWrites: () async {});
  @override
  final _Store store = _Store();
  String scope = 'binding-first:1';
  @override
  String get scopeIdentity => scope;
  int syncCalls = 0, ownershipCalls = 0;
  Object? syncError;
  Future<Map<String, dynamic>>? pendingSync;
  @override
  Future<void> restoreSession() async {}
  @override
  Future<Map<String, dynamic>> syncNow() async {
    syncCalls++;
    if (pendingSync != null) return pendingSync!;
    if (syncError != null) throw syncError!;
    store.value = {
      'last_success_ms': DateTime(2026, 9, 13, 12, 30).millisecondsSinceEpoch,
    };
    return {'snapshot_seq': 123};
  }

  @override
  Future<void> confirmCurrentScope() async {
    ownershipCalls++;
  }

  @override
  Future<int> adopt(Map<String, dynamic> dataset) async {
    ownershipCalls++;
    return 0;
  }
}

class _Store extends FlyDataSyncStore {
  _Store() : super(SqflitePlayStatsDatabase());
  Map<String, Object?>? value;
  Future<Map<String, Object?>?>? pendingRead;
  final reads = <String>[];
  @override
  Future<Map<String, Object?>?> state(String accountKey) async {
    reads.add(accountKey);
    return pendingRead == null ? value : pendingRead!;
  }

  @override
  Future<List<Map<String, Object?>>> localDatasets() async => [];
}
