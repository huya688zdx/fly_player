import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_exception.dart';

class AppErrorState extends StatelessWidget {
  final AppException error;
  final Map<String, dynamic> localeMap;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry padding;

  const AppErrorState({
    super.key,
    required this.error,
    this.localeMap = const <String, dynamic>{},
    this.onRetry,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final (icon, title, tint) = switch (error.kind) {
      AppExceptionKind.noData => (
        Icons.folder_open_rounded,
        l10n.commonNoData,
        colors.textMuted,
      ),
      AppExceptionKind.unauthorized => (
        Icons.lock_outline_rounded,
        l10n.commonNoAccessLibrary,
        colors.warning,
      ),
      AppExceptionKind.transient => (
        Icons.sync_problem_rounded,
        l10n.globalLoadFailed,
        colors.selectionStrong,
      ),
      AppExceptionKind.fatal => (
        Icons.error_outline_rounded,
        l10n.globalLoadFailed,
        colors.danger,
      ),
    };
    final showRetry =
        onRetry != null &&
        error.kind != AppExceptionKind.noData &&
        error.kind != AppExceptionKind.unauthorized;

    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint.withValues(alpha: 0.14),
                    tint.withValues(alpha: 0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: tint.withValues(alpha: 0.16)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 34, color: tint),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showRetry) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: colors.selectionSoft,
                  foregroundColor: colors.selectionStrong,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                child: Text(l10n.commonRefreshRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
