import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_exception.dart';
import '../../utils/media_locale_text.dart';

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

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleText.text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (icon, title, tint) = switch (error.kind) {
      AppExceptionKind.noData => (
        Icons.folder_open_rounded,
        _t('layout.dataLayout.noData', '暂无数据'),
        colors.textMuted,
      ),
      AppExceptionKind.unauthorized => (
        Icons.lock_outline_rounded,
        _t('layout.dataLayout.noAccessLibrary', '没有可访问的媒体库，请联系管理员'),
        colors.warning,
      ),
      AppExceptionKind.transient => (
        Icons.cloud_off_rounded,
        _t('layout.dataLayout.loadFailed', '加载失败'),
        colors.danger,
      ),
      AppExceptionKind.fatal => (
        Icons.error_outline_rounded,
        _t('layout.dataLayout.loadFailed', '加载失败'),
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
                child: Text(_t('layout.globalError.refresh', '刷新重试')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
