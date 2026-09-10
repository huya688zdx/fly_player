import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/screens/storage_management_screen.dart';
import 'package:fly_player/services/storage_management_service.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_error_state.dart';

void main() {
  testWidgets('存储概览加载失败时退出 loading 并显示可重试错误态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
        home: StorageManagementScreen(
          overviewLoader: (_) =>
              Future<StorageOverview>.error(StateError('storage unavailable')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
