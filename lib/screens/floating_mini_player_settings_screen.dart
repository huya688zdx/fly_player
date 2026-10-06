import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/common/app_ambient_page.dart';

/// 悬浮小窗设置：独立二级页面（不寄生在平行窗口设置页——该页为平板专属，
/// 手机端入口按能力隐藏，而悬浮小窗需要在手机上可达）。
/// 开关与平行窗口二选一：互斥落在 [ParallelWindowSettingsProvider]
/// （开启一侧自动关闭另一侧，关闭不反向联动）。
class FloatingMiniPlayerSettingsScreen extends StatelessWidget {
  const FloatingMiniPlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = context.watch<ParallelWindowSettingsProvider>();
    final l10n = AppLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < 720;

    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(
            l10n.settingsFloatingMiniTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(17, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 24,
              12,
              compact ? 14 : 24,
              28,
            ),
            children: <Widget>[
              _SettingsCard(
                children: <Widget>[
                  _SwitchRow(
                    title: l10n.settingsFloatingMiniTitle,
                    subtitle: settings.floatingMiniPlayerEnabled
                        ? l10n.floatingMiniOnSubtitle
                        : l10n.floatingMiniOffSubtitle,
                    value: settings.floatingMiniPlayerEnabled,
                    onChanged: settings.isReady
                        ? (value) =>
                              settings.setFloatingMiniPlayerEnabled(value)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置卡：surface 底 + 发丝边框（与平行窗口设置页同款式）。
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppAmbientPage.cardColorOf(context, colors.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(children: children),
    );
  }
}

/// 开关行：标题 + 动态副标题 + 行尾开关（与设置首页行尾开关同色制）。
class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(15),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(12.5),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.selection,
            activeTrackColor: colors.selection.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }
}
