import 'package:flutter/material.dart';
import 'dart:async';

import '../theme/app_theme.dart';

class AppTopTip {
  static OverlayEntry? _entry;
  static Timer? _dismissTimer;
  static int _showToken = 0;

  void dispose() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _removeEntry();
  }

  void show(
    BuildContext context, {
    required String message,
    required Color color,
  }) {
    if (!context.mounted) return;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _removeEntry();
    _showToken += 1;
    final token = _showToken;

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayContext = overlay.context;
    final top = MediaQuery.of(overlayContext).padding.top + 54;
    final colors = overlayContext.appColors;
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: 24,
        right: 24,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (token != _showToken) return;
      if (!overlay.mounted) return;
      _entry = entry;
      overlay.insert(entry);
    });
    _dismissTimer = Timer(const Duration(milliseconds: 1300), () {
      if (token != _showToken) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (token != _showToken) return;
        dispose();
      });
    });
  }

  static void _removeEntry() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    try {
      entry.remove();
    } catch (_) {
      // Ignore already removed or deactivated overlay states.
    }
  }
}
