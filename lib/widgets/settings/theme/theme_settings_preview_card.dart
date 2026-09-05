import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../ui/adaptive_text.dart';
import 'theme_settings_helpers.dart';

/// 紧凑英雄预览：色板簇 + 主题名摘要 + mini 应用示意（海报排 / 主按钮 /
/// 选中标签 / 进度 / 更多）。示意内容取传入的 [colors]（预览主题色，
/// 随选中主题实时变化）；卡片外壳取 context.appColors（页面通用取色）。
class ThemeSettingsPreviewCard extends StatelessWidget {
  final String themeTitle;
  final String themeSubtitle;
  final AppThemeColors colors;

  const ThemeSettingsPreviewCard({
    super.key,
    required this.themeTitle,
    required this.themeSubtitle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chrome = context.appColors;
    final swatches = <Color>[
      colors.backgroundBase,
      colors.surfaceStrong,
      colors.accent,
      colors.selection,
      colors.link,
    ];

    final meta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final swatch in swatches) ...<Widget>[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: chrome.textPrimary.withValues(alpha: 0.16),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          themeTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: chrome.textPrimary,
            fontSize: AdaptiveText.roleSize(17, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          themeSubtitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: chrome.textSecondary,
            fontSize: AdaptiveText.roleSize(12),
            height: 1.5,
          ),
        ),
      ],
    );

    final mock = Container(
      decoration: BoxDecoration(
        color: colors.backgroundBase,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var i = 0; i < 5; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.themePreviewPrimaryButton,
                  style: TextStyle(
                    color: themeSettingsForegroundOn(colors.accent),
                    fontSize: AdaptiveText.roleSize(10.5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5.5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.selection),
                ),
                child: Text(
                  l10n.themePreviewSelectedTab,
                  style: TextStyle(
                    color: colors.selectionStrong,
                    fontSize: AdaptiveText.roleSize(10.5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.62,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.themePreviewMore,
                style: TextStyle(
                  color: colors.link,
                  fontSize: AdaptiveText.roleSize(10.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackVertically = constraints.maxWidth < 560;
          if (stackVertically) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                meta,
                const SizedBox(height: 12),
                SizedBox(height: 138, width: double.infinity, child: mock),
              ],
            );
          }
          return Row(
            children: <Widget>[
              SizedBox(width: 188, child: meta),
              const SizedBox(width: 16),
              Expanded(child: SizedBox(height: 148, child: mock)),
            ],
          );
        },
      ),
    );
  }
}
