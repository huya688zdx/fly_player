part of mpv_player_page;

class _DanmakuPanelCard extends StatelessWidget {
  final Widget child;

  const _DanmakuPanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _settingsCardDecoration(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: child,
      ),
    );
  }
}

class _DanmakuSliderRow extends StatelessWidget {
  final String label;
  final String trailing;
  final Widget slider;

  const _DanmakuSliderRow({
    required this.label,
    required this.trailing,
    required this.slider,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: slider),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            trailing,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DanmakuLineSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _DanmakuLineSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final colors = context.appColors;
    return SizedBox(
      height: 24,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: activeColor,
          inactiveTrackColor: colors.borderStrong,
          thumbColor: colors.textPrimary,
          overlayColor: activeColor.withValues(alpha: 0.16),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Slider(
          value: normalized,
          onChanged: (next) => onChanged(min + ((max - min) * next)),
        ),
      ),
    );
  }
}

class _DanmakuDiscreteDotsSlider extends StatelessWidget {
  final List<double> values;
  final double value;
  final ValueChanged<double> onChanged;

  const _DanmakuDiscreteDotsSlider({
    required this.values,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rawSelectedIndex = values.indexOf(value);
    final selectedIndex = rawSelectedIndex < 0 ? 0 : rawSelectedIndex;
    const double trackHeight = 4;
    const double trackInset = 7;
    const double selectedDotRadius = 7;
    const double normalDotRadius = 3.5;
    const double tapTargetSize = 24;

    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final availableWidth = width - (trackInset * 2);
          final safeWidth = availableWidth > 0 ? availableWidth : 0.0;
          final step = values.length <= 1
              ? 0.0
              : safeWidth / (values.length - 1);
          final selectedCenter = trackInset + (step * selectedIndex);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: trackInset,
                right: trackInset,
                top: (24 - trackHeight) / 2,
                child: Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: trackInset,
                top: (24 - trackHeight) / 2,
                width: selectedCenter - trackInset,
                child: Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              ...List<Widget>.generate(values.length, (index) {
                final selected = index == selectedIndex;
                final center = trackInset + (step * index);
                final radius = selected ? selectedDotRadius : normalDotRadius;
                final rawLeft = center - (tapTargetSize / 2);
                final maxLeft = width - tapTargetSize;
                final left = rawLeft < 0
                    ? 0.0
                    : (rawLeft > maxLeft ? maxLeft : rawLeft);

                return Positioned(
                  left: left,
                  top: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(values[index]),
                    child: SizedBox(
                      width: tapTargetSize,
                      height: 24,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: radius * 2,
                          height: radius * 2,
                          decoration: BoxDecoration(
                            color: colors.textPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? colors.accentSoft
                                  : Colors.transparent,
                            ),
                            boxShadow: selected
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: colors.overlayScrim.withValues(
                                        alpha: 0.16,
                                      ),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _DanmakuTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DanmakuTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectedBorderColor = colors.selection;
    final selectedBackgroundColor = colors.selectionSoft;
    final unselectedBackgroundColor = colors.surface.withValues(alpha: 0.58);
    final unselectedBorderColor = colors.borderSubtle;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 58,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected
                    ? selectedBackgroundColor
                    : unselectedBackgroundColor,
                border: Border.all(
                  color: selected ? selectedBorderColor : unselectedBorderColor,
                ),
              ),
              child: Icon(
                icon,
                color: selected ? selectedBorderColor : colors.textPrimary,
                size: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? selectedBorderColor : colors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DanmakuPriorityButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DanmakuPriorityButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final borderColor = selected ? colors.selection : colors.borderSubtle;
    final backgroundColor = selected
        ? colors.selectionSoft
        : colors.surface.withValues(alpha: 0.58);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: backgroundColor,
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.selectionStrong : colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DanmakuSwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DanmakuSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SettingsTextBlock(title: title, subtitle: subtitle),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colors.textPrimary,
          activeTrackColor: colors.accent,
          inactiveThumbColor: colors.textPrimary,
          inactiveTrackColor: colors.borderStrong,
        ),
      ],
    );
  }
}

class _DanmakuSearchButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _DanmakuSearchButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 88,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: colors.accentSoft,
          border: Border.all(color: colors.accent),
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textPrimary,
                  ),
                )
              : Text(
                  '鎼滅储',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
        ),
      ),
    );
  }
}

class _DanmakuSearchResultTile extends StatelessWidget {
  final DanDanPlayEpisodeSearchItem item;
  final bool loading;
  final VoidCallback onTap;

  const _DanmakuSearchResultTile({
    required this.item,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: _settingsCardDecoration(context),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.displaySubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: colors.accent,
                      ),
                    )
                  : Icon(Icons.chevron_right_rounded, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedDanmakuSourceTile extends StatelessWidget {
  final DanmakuSavedSource source;
  final bool loading;
  final bool deleting;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedDanmakuSourceTile({
    required this.source,
    required this.loading,
    required this.deleting,
    required this.active,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final sourceTypeLabel = source.isDanDanPlay ? '寮瑰脊play' : '鏈湴';
    final colors = context.appColors;
    final sourceTypeColor = source.isDanDanPlay
        ? colors.success
        : colors.accent;
    final detail = source.detail.trim().isNotEmpty
        ? source.detail.trim()
        : (source.isLocalFile
              ? source.sourceKey.split(Platform.pathSeparator).last
              : source.sourceKey);
    final subtitle = source.commentCount > 0
        ? '$sourceTypeLabel 路 ${source.commentCount} 鏉?路 $detail'
        : '$sourceTypeLabel 路 $detail';
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: (loading || deleting) ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: sourceTypeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: sourceTypeColor.withValues(alpha: 0.46),
                          ),
                        ),
                        child: Text(
                          sourceTypeLabel,
                          style: TextStyle(
                            color: sourceTypeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          source.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.selectionSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: colors.selection),
                          ),
                          child: Text(
                            '褰撳墠',
                            style: TextStyle(
                              color: colors.selectionStrong,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (loading || deleting)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          )
        else
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.delete_outline_rounded,
                color: colors.textSecondary,
                size: 20,
              ),
            ),
          ),
      ],
    );
  }
}
