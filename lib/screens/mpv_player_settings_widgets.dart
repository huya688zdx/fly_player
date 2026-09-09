part of 'mpv_player_settings_screen.dart';

/// 页面顶部的方案/摘要状态条：图标 + 「小标 方案名」+ 一行摘要 +
/// 右侧计数胶囊。替代原先 130px 高、无操作、状态重复三次的大卡。
class _SchemeStatusBar extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final String? scheme;
  final String? summary;
  final String? pillText;
  final bool pillHot;

  const _SchemeStatusBar({
    this.icon,
    this.label,
    this.scheme,
    this.summary,
    this.pillText,
    this.pillHot = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.surfaceSubtle, colors.surface],
        ),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.accentStrong, size: 19),
            ),
            const SizedBox(width: 13),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (label != null || scheme != null)
                  Row(
                    children: <Widget>[
                      if (label != null)
                        Text(
                          label!,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: AdaptiveText.roleSize(11.5),
                          ),
                        ),
                      if (label != null && scheme != null)
                        const SizedBox(width: 8),
                      if (scheme != null)
                        Flexible(
                          child: Text(
                            scheme!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.accentStrong,
                              fontSize: AdaptiveText.roleSize(15),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (summary != null) ...<Widget>[
                  if (label != null || scheme != null)
                    const SizedBox(height: 4),
                  Text(
                    summary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (pillText != null) ...<Widget>[
            const SizedBox(width: 12),
            _MiniPill(text: pillText!, hot: pillHot),
          ],
        ],
      ),
    );
  }
}

/// 轻量状态胶囊：有变化用强调色，无变化弱化。
class _MiniPill extends StatelessWidget {
  final String text;
  final bool hot;

  const _MiniPill({required this.text, this.hot = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: hot ? colors.accentSoft : colors.surfaceStrong,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: hot ? colors.accentStrong : colors.textMuted,
          fontSize: AdaptiveText.roleSize(11),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 区块标题（可带一行弱化副标）。
class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionTitle({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(14.5),
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(width: 10),
          Text(
            subtitle!,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: AdaptiveText.roleSize(11.5),
            ),
          ),
        ],
      ],
    );
  }
}

/// 快速预设紧凑卡：标题 + 右侧选中实心勾点（已保存卡为 ⋯ 菜单）+
/// 两行描述。选中 = 底色 + 文字变色，不加框。
class _PresetChipCard extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onTap;
  final List<PopupMenuEntry<String>> Function(BuildContext)? menuBuilder;
  final ValueChanged<String>? onMenuSelected;

  const _PresetChipCard({
    required this.title,
    required this.description,
    required this.selected,
    this.onTap,
    this.menuBuilder,
    this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? colors.accentStrong
                          : colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(13.5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                if (menuBuilder != null)
                  PopupMenuButton<String>(
                    onSelected: onMenuSelected,
                    itemBuilder: menuBuilder!,
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: colors.textMuted,
                      size: 16,
                    ),
                  )
                else
                  _CheckDot(selected: selected),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AdaptiveText.roleSize(11),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「另存当前」虚线卡：空状态也有行动点，取代原先整块“暂无已保存”提示。
class _SavePresetGhostChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SavePresetGhostChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.borderStrong.withValues(alpha: 0.6),
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.add_rounded, color: colors.textSecondary, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(12.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 深入调节入口卡：分类图标 + 标题 + 两行描述 + 变化数胶囊。
class _TuneEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String pillText;
  final bool pillHot;
  final VoidCallback onTap;

  const _TuneEntryCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.pillText,
    required this.pillHot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 14, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.surfaceStrong,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: colors.textPrimary, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(13.5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textMuted,
                  size: 17,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AdaptiveText.roleSize(11),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 10),
            _MiniPill(text: pillText, hot: pillHot),
          ],
        ),
      ),
    );
  }
}

/// 自定义管理细长入口行。
class _MgmtEntryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MgmtEntryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 16, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.surfaceStrong,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.textPrimary, size: 17),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(13.5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(11.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中态实心勾点：未选中为细圈。
class _CheckDot extends StatelessWidget {
  final bool selected;

  const _CheckDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (!selected) {
      return Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.textMuted, width: 1.5),
        ),
      );
    }
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accent),
      alignment: Alignment.center,
      child: Icon(Icons.check_rounded, size: 10, color: colors.backgroundBase),
    );
  }
}

/// 通用卡片容器。
class _CardBlock extends StatelessWidget {
  final Widget child;

  const _CardBlock({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: child,
    );
  }
}

/// 菜单行：图标 + 标题/副标 + 当前值 + 箭头。
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.surfaceStrong,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.textPrimary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(15.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(13.2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(12.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单选行：左侧勾选圈 + 标题/描述，可带帮助按钮。
class _ChoiceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onInfoTap;

  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
            ),
            color: selected ? colors.accentSoft : colors.surface,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? colors.accentStrong : colors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: AdaptiveText.roleSize(15.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (onInfoTap != null) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onInfoTap,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: colors.accent),
                                color: colors.accentSoft,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.help_outline_rounded,
                                color: colors.accentStrong,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(12.8),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 即时调节滑杆卡。
class _VideoAdjustmentSliderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _VideoAdjustmentSliderCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final safeValue = value.clamp(_videoAdjustmentMin, _videoAdjustmentMax);
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(15.5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                MpvSettingsCatalog.formatVideoAdjustmentValue(safeValue),
                style: TextStyle(
                  color: colors.accentStrong,
                  fontSize: AdaptiveText.roleSize(13.4),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13.1),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.borderStrong,
              thumbColor: colors.textPrimary,
              overlayColor: colors.accentSoft,
              trackHeight: 4,
            ),
            child: Slider(
              min: _videoAdjustmentMin,
              max: _videoAdjustmentMax,
              divisions: (_videoAdjustmentMax - _videoAdjustmentMin).round(),
              value: safeValue,
              label: MpvSettingsCatalog.formatVideoAdjustmentValue(safeValue),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Row(
            children: <Widget>[
              Text(
                '-100',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(12),
                ),
              ),
              const Spacer(),
              Text(
                '+100',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.appColors.borderSubtle);
  }
}
