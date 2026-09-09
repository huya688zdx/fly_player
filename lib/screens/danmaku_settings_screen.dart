import 'dart:async';

import 'package:flutter/material.dart';

import '../danmaku/models/danmaku_saved_source.dart';
import '../danmaku/models/danmaku_settings.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../utils/swallowed_error_logger.dart';
import '../widgets/common/app_ambient_page.dart';
import 'danmaku_manager_screen.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

class DanmakuSettingsScreen extends StatefulWidget {
  final Future<void> Function(DanmakuSettings settings)? saveSettings;
  final Future<DanmakuSettings> Function()? settingsLoader;
  final Future<List<DanmakuSavedSource>> Function()? savedSourceLoader;

  const DanmakuSettingsScreen({
    super.key,
    this.saveSettings,
    this.settingsLoader,
    this.savedSourceLoader,
  });

  @override
  State<DanmakuSettingsScreen> createState() => _DanmakuSettingsScreenState();
}

class _DanmakuSettingsScreenState extends State<DanmakuSettingsScreen> {
  final DanmakuSettingsStore _store = const DanmakuSettingsStore();
  final DanmakuSavedSourceStore _savedSourceStore =
      const DanmakuSavedSourceStore();
  DanmakuSettings _settings = DanmakuSettings.defaults;
  int _savedSourceCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _savedSourceStore.changes.addListener(_handleSavedSourceChanged);
    _load();
  }

  @override
  void dispose() {
    _savedSourceStore.changes.removeListener(_handleSavedSourceChanged);
    super.dispose();
  }

  void _handleSavedSourceChanged() {
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object>(<Future<Object>>[
      (widget.settingsLoader ?? _store.load)(),
      (widget.savedSourceLoader ?? _savedSourceStore.loadAll)(),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = results[0] as DanmakuSettings;
      _savedSourceCount = (results[1] as List<DanmakuSavedSource>).length;
      _loading = false;
    });
  }

  Future<void> _save(DanmakuSettings next) async {
    try {
      await (widget.saveSettings ?? _store.save)(next);
      if (!mounted) return;
      setState(() => _settings = next);
    } catch (error, stackTrace) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).globalLoadFailed),
          ),
        );
      }
      unawaited(
        logSwallowedError(
          action: 'save danmaku settings',
          error: error,
          stackTrace: stackTrace,
          source: 'danmaku_settings_screen',
        ),
      );
    }
  }

  String _speedLabel(double speed) {
    final l10n = AppLocalizations.of(context);
    final preset = nearestDanmakuSpeedPreset(speed);
    if (preset <= danmakuSpeedPresets.first + 0.0001) {
      return l10n.danmakuSpeedSlow;
    }
    if (preset >= danmakuSpeedPresets.last - 0.0001) {
      return l10n.danmakuSpeedFast;
    }
    if (preset >= danmakuSpeedPresets[3] - 0.0001) {
      return l10n.danmakuSpeedFaster;
    }
    return l10n.danmakuSpeedNormal;
  }

  String _areaLabel(double ratio) {
    final l10n = AppLocalizations.of(context);
    if (ratio <= 0.10) return l10n.danmakuAreaOneTenth;
    if (ratio <= 0.25) return l10n.danmakuAreaOneQuarter;
    if (ratio <= 0.5) return l10n.danmakuAreaHalf;
    if (ratio <= 0.75) return l10n.danmakuAreaThreeQuarters;
    return l10n.danmakuAreaFull;
  }

  String _percentLabel(double value) => '${(value * 100).round()}%';

  String _fontScaleLabel(double value) {
    final l10n = AppLocalizations.of(context);
    if (value < 0.8) return l10n.danmakuFontSmall;
    if (value < 0.95) return l10n.danmakuFontSlightlySmall;
    if (value <= 1.05) return l10n.danmakuFontStandard;
    if (value < 1.2) return l10n.danmakuFontSlightlyLarge;
    return l10n.danmakuFontLarge;
  }

  Future<void> _openDanmakuManager() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        const DanmakuManagerScreen(),
      ),
    );
    // 不在 pop 返回时重新 _load()：push 返回的 Future 在 pop 动画第一帧前就
    // resolve，整库反序列化+整页 setState 会砸进 380ms 退场转场；管理页内的
    // 任何增删已通过 _savedSourceStore.changes 监听触发过 _load，无需兜底。
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            l10n.danmakuSettingsTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _DanmakuSectionTitle(
                      title: l10n.danmakuSourceManagementTitle,
                      subtitle: l10n.danmakuSourceManagementSubtitle,
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: _DanmakuMenuTile(
                        title: l10n.danmakuManagementTitle,
                        subtitle: _savedSourceCount <= 0
                            ? l10n.danmakuNoSavedSources
                            : l10n.danmakuSavedSourceCount(_savedSourceCount),
                        onTap: _openDanmakuManager,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DanmakuSectionTitle(
                      title: l10n.danmakuBasicSectionTitle,
                      subtitle: l10n.danmakuBasicSectionSubtitle,
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Column(
                        children: <Widget>[
                          _DanmakuSwitchTile(
                            title: l10n.danmakuDefaultEnabledTitle,
                            subtitle: l10n.danmakuDefaultEnabledSubtitle,
                            value: _settings.enabled,
                            onChanged: (value) {
                              _save(_settings.copyWith(enabled: value));
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSwitchTile(
                            title: l10n.danmakuPreviewEnabledTitle,
                            subtitle: l10n.danmakuPreviewEnabledSubtitle,
                            value: _settings.previewEnabled,
                            onChanged: (value) {
                              _save(_settings.copyWith(previewEnabled: value));
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DanmakuSectionTitle(
                      title: l10n.danmakuSourcePriorityTitle,
                      subtitle: l10n.danmakuSourcePrioritySubtitle,
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _DanmakuChoiceButton(
                              label: l10n.danmakuPreferLocal,
                              selected: _settings.preferLocalSource,
                              onTap: () {
                                _save(
                                  _settings.copyWith(preferLocalSource: true),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DanmakuChoiceButton(
                              label: l10n.danmakuPreferNetwork,
                              selected: !_settings.preferLocalSource,
                              onTap: () {
                                _save(
                                  _settings.copyWith(preferLocalSource: false),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DanmakuSectionTitle(
                      title: l10n.danmakuDisplayStyleTitle,
                      subtitle: l10n.danmakuDisplayStyleSubtitle,
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Column(
                        children: <Widget>[
                          _DanmakuSliderTile(
                            title: l10n.danmakuDisplayAreaTitle,
                            valueLabel: _areaLabel(_settings.displayAreaRatio),
                            value: _settings.displayAreaRatio,
                            min: 0.1,
                            max: 1.0,
                            divisions: 4,
                            onChanged: (value) {
                              setState(() {
                                _settings = _settings.copyWith(
                                  displayAreaRatio: value,
                                );
                              });
                            },
                            onChangeEnd: (value) {
                              _save(
                                _settings.copyWith(displayAreaRatio: value),
                              );
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSliderTile(
                            title: l10n.danmakuOpacityTitle,
                            valueLabel: _percentLabel(_settings.opacity),
                            value: _settings.opacity,
                            min: 0.2,
                            max: 1.0,
                            divisions: 8,
                            onChanged: (value) {
                              setState(() {
                                _settings = _settings.copyWith(opacity: value);
                              });
                            },
                            onChangeEnd: (value) {
                              _save(_settings.copyWith(opacity: value));
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSliderTile(
                            title: l10n.danmakuDensityTitle,
                            valueLabel: _percentLabel(_settings.density),
                            value: _settings.density,
                            min: 0.2,
                            max: 1.0,
                            divisions: 8,
                            onChanged: (value) {
                              setState(() {
                                _settings = _settings.copyWith(density: value);
                              });
                            },
                            onChangeEnd: (value) {
                              _save(_settings.copyWith(density: value));
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSliderTile(
                            title: l10n.danmakuFontSizeTitle,
                            valueLabel: _fontScaleLabel(_settings.fontScale),
                            value: _settings.fontScale,
                            min: 0.6,
                            max: 1.4,
                            divisions: 8,
                            onChanged: (value) {
                              setState(() {
                                _settings = _settings.copyWith(
                                  fontScale: value,
                                );
                              });
                            },
                            onChangeEnd: (value) {
                              _save(_settings.copyWith(fontScale: value));
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSliderTile(
                            title: l10n.danmakuSpeedTitle,
                            valueLabel: _speedLabel(_settings.speed),
                            value: _settings.speed,
                            min: danmakuSpeedMin,
                            max: danmakuSpeedMax,
                            divisions: danmakuSpeedDivisions,
                            onChanged: (value) {
                              setState(() {
                                _settings = _settings.copyWith(speed: value);
                              });
                            },
                            onChangeEnd: (value) {
                              _save(_settings.copyWith(speed: value));
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DanmakuSectionTitle(
                      title: l10n.danmakuTypeFilterTitle,
                      subtitle: l10n.danmakuTypeFilterSubtitle,
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          _DanmakuTypeChip(
                            label: l10n.danmakuTypeFixed,
                            icon: Icons.vertical_align_top_rounded,
                            selected: _settings.topEnabled,
                            onTap: () {
                              _save(
                                _settings.copyWith(
                                  topEnabled: !_settings.topEnabled,
                                ),
                              );
                            },
                          ),
                          _DanmakuTypeChip(
                            label: l10n.danmakuTypeScroll,
                            icon: Icons.swap_horiz_rounded,
                            selected: _settings.scrollEnabled,
                            onTap: () {
                              _save(
                                _settings.copyWith(
                                  scrollEnabled: !_settings.scrollEnabled,
                                ),
                              );
                            },
                          ),
                          _DanmakuTypeChip(
                            label: l10n.danmakuTypeBottom,
                            icon: Icons.vertical_align_bottom_rounded,
                            selected: _settings.bottomEnabled,
                            onTap: () {
                              _save(
                                _settings.copyWith(
                                  bottomEnabled: !_settings.bottomEnabled,
                                ),
                              );
                            },
                          ),
                          _DanmakuTypeChip(
                            label: l10n.danmakuTypeColor,
                            icon: Icons.palette_outlined,
                            selected: _settings.colorEnabled,
                            onTap: () {
                              _save(
                                _settings.copyWith(
                                  colorEnabled: !_settings.colorEnabled,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DanmakuSectionTitle(
                      title: l10n.danmakuAvoidanceTitle,
                      subtitle: l10n.danmakuAvoidanceSubtitle,
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Column(
                        children: <Widget>[
                          _DanmakuSwitchTile(
                            title: l10n.danmakuHideDuplicateTitle,
                            subtitle: l10n.danmakuHideDuplicateSubtitle,
                            value: _settings.hideDuplicate,
                            onChanged: (value) {
                              _save(_settings.copyWith(hideDuplicate: value));
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSwitchTile(
                            title: l10n.danmakuAvoidSubtitleTitle,
                            subtitle: l10n.danmakuAvoidSubtitleSubtitle,
                            value: _settings.avoidSubtitleArea,
                            onChanged: (value) {
                              _save(
                                _settings.copyWith(avoidSubtitleArea: value),
                              );
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSwitchTile(
                            title: l10n.danmakuAvoidCenterTitle,
                            subtitle: l10n.danmakuAvoidCenterSubtitle,
                            value: _settings.avoidCenterArea,
                            onChanged: (value) {
                              _save(_settings.copyWith(avoidCenterArea: value));
                            },
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

class _DanmakuSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _DanmakuSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(16, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(12, role: AdaptiveFontRole.body),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DanmakuCard extends StatelessWidget {
  final Widget child;

  const _DanmakuCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surfaceSubtle,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: child,
      ),
    );
  }
}

class _DanmakuDivider extends StatelessWidget {
  const _DanmakuDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: context.appColors.borderSubtle,
    );
  }
}

class _DanmakuSwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DanmakuSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(
                      15,
                      role: AdaptiveFontRole.title,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(
                      12,
                      role: AdaptiveFontRole.body,
                    ),
                    height: 1.4,
                  ),
                ),
              ],
            ),
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
      ),
    );
  }
}

class _DanmakuSliderTile extends StatelessWidget {
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _DanmakuSliderTile({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                    fontSize: AdaptiveText.roleSize(
                      15,
                      role: AdaptiveFontRole.title,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  color: colors.accent,
                  fontSize: AdaptiveText.roleSize(
                    13,
                    role: AdaptiveFontRole.body,
                  ),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.borderStrong,
              thumbColor: colors.textPrimary,
              overlayColor: colors.accent.withValues(alpha: 0.16),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _DanmakuChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DanmakuChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? colors.selectionSoft : colors.surfaceStrong,
          border: Border.all(
            color: selected ? colors.selection : colors.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.selectionStrong : colors.textPrimary,
              fontSize: AdaptiveText.roleSize(13, role: AdaptiveFontRole.body),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 72,
        child: Column(
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 58,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected ? colors.selectionSoft : colors.surfaceStrong,
                border: Border.all(
                  color: selected ? colors.selection : colors.borderSubtle,
                ),
              ),
              child: Icon(
                icon,
                color: selected ? colors.selectionStrong : colors.textPrimary,
                size: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? colors.selectionStrong : colors.textSecondary,
                fontSize: AdaptiveText.roleSize(
                  12,
                  role: AdaptiveFontRole.body,
                ),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DanmakuMenuTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DanmakuMenuTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
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
                      fontSize: AdaptiveText.roleSize(
                        15,
                        role: AdaptiveFontRole.title,
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(
                        12,
                        role: AdaptiveFontRole.body,
                      ),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
