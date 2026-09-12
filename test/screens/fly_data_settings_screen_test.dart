import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/screens/fly_data_settings_screen.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  testWidgets(
    'legacy history tools describe unified ownership and expose explicit login fallback',
    (tester) async {
      SecureCredentialStore.setBackendForTesting(
        MemorySecureCredentialBackend(),
      );
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FlyDataSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('飞翔数据服务'), findsOneWidget);
      expect(find.text('数据服务帐号'), findsOneWidget);
      expect(find.text('登录数据服务'), findsOneWidget);
      expect(find.textContaining('统一账号'), findsOneWidget);
      expect(find.text('立即同步'), findsNothing);
      SecureCredentialStore.resetBackendForTesting();
    },
  );
}
