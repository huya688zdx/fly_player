import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../ui/adaptive_text.dart';

class ThemeSettingsPresetCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final AppThemeColors previewColors;
  final bool selected;
  final VoidCallback onTap;

  const ThemeSettingsPresetCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.previewColors,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentColors = context.appColors;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 232,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? currentColors.selectionSoft : currentColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? currentColors.selection
                : currentColors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 94,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    previewColors.surfaceStrong,
                    previewColors.surface,
                    previewColors.backgroundBase,
                  ],
                ),
                border: Border.all(color: previewColors.borderSubtle),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      width: 64,
                      height: 10,
                      decoration: BoxDecoration(
                        color: previewColors.textPrimary.withValues(
                          alpha: 0.88,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Container(
                      width: 58,
                      height: 30,
                      decoration: BoxDecoration(
                        color: previewColors.selectionSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: previewColors.selection),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: previewColors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: currentColors.textPrimary,
                      fontSize: AdaptiveText.roleSize(15),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? currentColors.selectionStrong
                      : currentColors.textMuted,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: currentColors.textSecondary,
                fontSize: AdaptiveText.roleSize(13.2),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
