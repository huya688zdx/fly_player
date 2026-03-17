import 'package:flutter/material.dart';

import '../services/app_log_service.dart';
import '../theme/app_theme.dart';
import 'app_exception.dart';
import 'app_top_tip.dart';

class AppErrorReporter {
  AppErrorReporter._();

  static AppException normalize(
    Object error, {
    required String action,
    StackTrace? stackTrace,
    AppExceptionKind fallbackKind = AppExceptionKind.fatal,
  }) {
    return AppException.from(
      error,
      action: action,
      fallbackKind: fallbackKind,
      stackTrace: stackTrace,
    );
  }

  static Future<AppException> report(
    Object error, {
    required String action,
    required String source,
    StackTrace? stackTrace,
    AppExceptionKind fallbackKind = AppExceptionKind.fatal,
    AppLogLevel level = AppLogLevel.error,
    String? details,
  }) async {
    final appError = normalize(
      error,
      action: action,
      stackTrace: stackTrace,
      fallbackKind: fallbackKind,
    );
    await AppLogService.instance.record(
      level: level,
      error: appError,
      stackTrace: appError.stackTrace ?? stackTrace,
      source: source,
      details: details,
    );
    return appError;
  }

  static Future<AppException> showTopTip(
    BuildContext context,
    AppTopTip topTip, {
    required Object error,
    required String action,
    required String source,
    StackTrace? stackTrace,
    AppExceptionKind fallbackKind = AppExceptionKind.transient,
    AppLogLevel level = AppLogLevel.error,
    String? prefix,
    String? details,
  }) async {
    final appError = await report(
      error,
      action: action,
      source: source,
      stackTrace: stackTrace,
      fallbackKind: fallbackKind,
      level: level,
      details: details,
    );
    if (!context.mounted) return appError;
    topTip.show(
      context,
      message: messageFor(appError, prefix: prefix),
      color: colorFor(context, appError),
    );
    return appError;
  }

  static String messageFor(AppException error, {String? prefix}) {
    final message = error.message.trim().isEmpty
        ? '操作失败'
        : error.message.trim();
    if (prefix == null || prefix.trim().isEmpty) return message;
    return '${prefix.trim()}: $message';
  }

  static Color colorFor(BuildContext context, AppException error) {
    final colors = context.appColors;
    return switch (error.kind) {
      AppExceptionKind.noData => colors.warning,
      AppExceptionKind.unauthorized => colors.warning,
      AppExceptionKind.transient => colors.danger,
      AppExceptionKind.fatal => colors.danger,
    };
  }
}
