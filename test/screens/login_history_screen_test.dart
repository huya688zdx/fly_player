import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/screens/login_history_screen.dart';
import 'package:fly_player/services/login_history_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  const feiniuEntry = LoginHistoryEntry(
    baseUrl: 'https://aliyun.bffss.cn',
    userName: 'geqian688',
    password: 'pw',
    rememberPassword: true,
    updatedAtMillis: 2,
  );
  const embyEntry = LoginHistoryEntry(
    kind: MediaBackendKind.emby,
    baseUrl: 'http://100.125.130.96:8096',
    userName: 'geqian688',
    password: 'pw',
    rememberPassword: true,
    updatedAtMillis: 1,
  );

  Widget host(List<LoginHistoryEntry> entries) {
    return MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
      home: LoginHistoryScreen(entries: entries),
    );
  }

  testWidgets('统一列表同时渲染飞牛与 Emby 历史，各带后端 logo', (tester) async {
    await tester.pumpWidget(host(<LoginHistoryEntry>[feiniuEntry, embyEntry]));
    await tester.pumpAndSettle();

    expect(find.text('https://aliyun.bffss.cn'), findsOneWidget);
    expect(find.text('http://100.125.130.96:8096'), findsOneWidget);
    expect(find.byType(BackendLogo), findsNWidgets(2));
  });

  testWidgets('点击历史条目回传该条目', (tester) async {
    LoginHistoryEntry? popped;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<LoginHistoryEntry>(
                    MaterialPageRoute(
                      builder: (_) => const LoginHistoryScreen(
                        entries: <LoginHistoryEntry>[embyEntry],
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('http://100.125.130.96:8096'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.kind, MediaBackendKind.emby);
    expect(popped!.baseUrl, 'http://100.125.130.96:8096');
  });

  testWidgets('删除历史时安全存储抛异常，提示失败且列表条目不减少', (tester) async {
    SecureCredentialStore.setBackendForTesting(
      const _FailingDeleteCredentialBackend(),
    );
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    await tester.pumpWidget(host(<LoginHistoryEntry>[feiniuEntry, embyEntry]));
    await tester.pumpAndSettle();

    // 点开第一条历史的删除按钮，走确认弹窗后触发实际删除。
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    // 弹窗退出动画的 ticker 在下一帧才建立起点，需要先空 pump 启动，
    // 再按时长推进才能真正走完转场并移除路由。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 让删除失败后的 AppTopTip（postFrameCallback 插入 Overlay）完成插入。
    await tester.pump();
    await tester.pump();

    expect(find.text('操作失败，请稍后重试'), findsOneWidget);
    expect(find.text('https://aliyun.bffss.cn'), findsOneWidget);
    expect(find.text('http://100.125.130.96:8096'), findsOneWidget);

    // 推进虚拟时钟让 AppTopTip 的自动消失计时器触发，避免遗留 pending timer。
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
  });
}

/// 用于测试的安全凭据后端：delete 恒定抛出 [SecureCredentialOperationException]，
/// 模拟真实安全存储（如 Keystore）不可用时的失败场景。
class _FailingDeleteCredentialBackend implements SecureCredentialBackend {
  const _FailingDeleteCredentialBackend();

  @override
  Future<SecureCredentialReadResult> read(String key) async =>
      const SecureCredentialReadResult.missing();

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {
    throw const SecureCredentialOperationException('delete', 'password');
  }
}
