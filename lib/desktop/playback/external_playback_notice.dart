import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 外部播放共用的紧凑提示，避免把异常类型前缀直接展示给用户。
void showExternalPlaybackNotice(
  BuildContext context,
  Object message, {
  bool error = false,
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final colors = context.appColors;
  final availableWidth = MediaQuery.sizeOf(context).width - 32;
  final width = availableWidth < 240
      ? availableWidth
      : availableWidth.clamp(240.0, 420.0);
  final text = normalizeExternalPlaybackNotice(message);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        width: width,
        behavior: SnackBarBehavior.floating,
        elevation: 12,
        backgroundColor: colors.surfaceStrong,
        showCloseIcon: true,
        closeIconColor: colors.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: (error ? colors.danger : colors.accent).withValues(
              alpha: 0.42,
            ),
          ),
        ),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              size: 18,
              color: error ? colors.danger : colors.accent,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
}

String normalizeExternalPlaybackNotice(Object message) {
  var text = '$message'.trim();
  text = text.replaceFirst(
    RegExp(
      r'^(?:(?:Bad state|StateError|Exception):\s*)+',
      caseSensitive: false,
    ),
    '',
  );
  return text.isEmpty ? '操作未能完成，请稍后重试' : text;
}
