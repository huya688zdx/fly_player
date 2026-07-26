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
        Icons.cloud_off_rounded,
        l10n.globalLoadFailed,
        colors.danger,
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
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 116,
              height: 88,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 52, color: tint),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (showRetry) ...[
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onRetry,
                child: Text(l10n.commonRefreshRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
