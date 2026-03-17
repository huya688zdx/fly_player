import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppTopTip {
  OverlayEntry? _entry;

  void dispose() {
    _entry?.remove();
    _entry = null;
  }

  void show(
    BuildContext context, {
    required String message,
    required Color color,
  }) {
    _entry?.remove();
    _entry = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    final top = MediaQuery.of(context).padding.top + 54;
    final colors = context.appColors;
    _entry = OverlayEntry(
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
    overlay.insert(_entry!);
    Future<void>.delayed(const Duration(milliseconds: 1300)).then((_) {
      if (_entry != null) {
        _entry!.remove();
        _entry = null;
      }
    });
  }
}
