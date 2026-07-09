import 'package:flutter/foundation.dart';

import '../services/app_log_service.dart';

/// 记录允许降级但不能无迹吞掉的异常。
Future<void> logSwallowedError({
  required String action,
  required Object error,
  StackTrace? stackTrace,
  String source = 'app',
  String? id,
  String? details,
}) async {
  final detailParts = <String>[
    if (action.trim().isNotEmpty) 'action=${action.trim()}',
    if (id != null && id.trim().isNotEmpty) 'id=${id.trim()}',
    if (details != null && details.trim().isNotEmpty) details.trim(),
  ];
  try {
    await AppLogService.instance.recordWarning(
      error: error,
      stackTrace: stackTrace,
      source: source,
      details: detailParts.join(' | '),
    );
  } catch (loggingError, loggingStackTrace) {
    debugPrint(
      'Failed to record swallowed error: $loggingError\n$loggingStackTrace',
    );
  }
}
