import 'package:flutter/material.dart';

String themeSettingsColorHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color themeSettingsVisibleBorderFor(Color color) {
  return color.computeLuminance() >= 0.72
      ? Colors.black.withValues(alpha: 0.16)
      : Colors.white.withValues(alpha: 0.14);
}

Color themeSettingsForegroundOn(Color background) {
  return background.computeLuminance() >= 0.54
      ? const Color(0xFF172030)
      : Colors.white;
}
