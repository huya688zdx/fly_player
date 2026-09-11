import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../desktop_floating_panel.dart';

OverlayEntry? _externalPlaybackNoticeEntry;
Timer? _externalPlaybackNoticeTimer;
int _externalPlaybackNoticeToken = 0;

/// 在当前应用窗口上方显示单条提示，重复调用会替换上一条。
void showExternalPlaybackNotice(
  BuildContext context,
  Object message, {
  bool error = false,
}) {
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _removeExternalPlaybackNotice();
  final token = ++_externalPlaybackNoticeToken;
  final text = normalizeExternalPlaybackNotice(message);
  final overlayContext = overlay.context;
  final colors = overlayContext.appColors;
  final top = MediaQuery.paddingOf(overlayContext).top + 64;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      key: const ValueKey<String>('external-playback-notice'),
      top: top,
      left: 24,
      right: 24,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DesktopFloatingPanel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    error
                        ? Icons.error_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: error ? colors.danger : colors.accent,
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textPrimary, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey<String>(
                      'external-playback-notice-close',
                    ),
                    onPressed: () {
                      if (token == _externalPlaybackNoticeToken) {
                        _removeExternalPlaybackNotice();
                      }
                    },
                    tooltip: '关闭提示',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    color: colors.textSecondary,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _externalPlaybackNoticeEntry = entry;
  overlay.insert(entry);
  _externalPlaybackNoticeTimer = Timer(const Duration(seconds: 3), () {
    if (token == _externalPlaybackNoticeToken) {
      _removeExternalPlaybackNotice();
    }
  });
}

void _removeExternalPlaybackNotice() {
  _externalPlaybackNoticeTimer?.cancel();
  _externalPlaybackNoticeTimer = null;
  final entry = _externalPlaybackNoticeEntry;
  _externalPlaybackNoticeEntry = null;
  if (entry == null) return;
  try {
    entry.remove();
  } catch (_) {
    // 所属窗口已经销毁时无需再清理。
  } finally {
    entry.dispose();
  }
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
