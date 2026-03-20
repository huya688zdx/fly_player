import 'package:flutter/material.dart';

import '../danmaku/models/danmaku_saved_source.dart';
import '../danmaku/models/danmaku_settings.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import 'danmaku_manager_screen.dart';

class DanmakuSettingsScreen extends StatefulWidget {
  const DanmakuSettingsScreen({super.key});

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
      _store.load(),
      _savedSourceStore.loadAll(),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = results[0] as DanmakuSettings;
      _savedSourceCount = (results[1] as List<DanmakuSavedSource>).length;
      _loading = false;
    });
  }

  Future<void> _save(DanmakuSettings next) async {
    setState(() => _settings = next);
    await _store.save(next);
  }

  String _speedLabel(double speed) {
    if (speed <= 0.85) return '慢';
    if (speed >= 1.55) return '快';
    if (speed >= 1.25) return '较快';
    return '正常';
  }

  String _areaLabel(double ratio) {
    if (ratio <= 0.10) return '1/10屏';
    if (ratio <= 0.25) return '1/4屏';
    if (ratio <= 0.5) return '半屏';
    if (ratio <= 0.75) return '3/4屏';
    return '全屏';
  }

  String _percentLabel(double value) => '${(value * 100).round()}%';

  String _fontScaleLabel(double value) {
    if (value < 0.8) return '较小';
    if (value < 0.95) return '偏小';
    if (value <= 1.05) return '标准';
    if (value < 1.2) return '偏大';
    return '较大';
  }

  Future<void> _openDanmakuManager() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        const DanmakuManagerScreen(),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        title: Text(
          '弹幕设置',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: colors.accent))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    const _DanmakuSectionTitle(
                      title: '来源管理',
                      subtitle: '统一管理网络弹幕和本地导入弹幕，支持按来源层级查看与手动删除。',
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: _DanmakuMenuTile(
                        title: '弹幕管理',
                        subtitle: _savedSourceCount <= 0
                            ? '还没有已保存弹幕来源'
                            : '当前已保存 $_savedSourceCount 个弹幕来源',
                        onTap: _openDanmakuManager,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _DanmakuSectionTitle(
                      title: '基础',
                      subtitle: '这些是全局默认值，不依赖当前播放页面。',
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Column(
                        children: <Widget>[
                          _DanmakuSwitchTile(
                            title: '默认开启弹幕',
                            subtitle: '进入播放器时默认带着弹幕设置启动。',
                            value: _settings.enabled,
                            onChanged: (value) {
                              _save(_settings.copyWith(enabled: value));
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSwitchTile(
                            title: '详情页预览弹幕',
                            subtitle: '在非播放页展示弹幕预览时使用这项默认值。',
                            value: _settings.previewEnabled,
                            onChanged: (value) {
                              _save(_settings.copyWith(previewEnabled: value));
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _DanmakuSectionTitle(
                      title: '来源优先',
                      subtitle: '控制本地弹幕和网络弹幕同时可用时的默认选择。',
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _DanmakuChoiceButton(
                              label: '本地优先',
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
                              label: '网络优先',
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
                    const _DanmakuSectionTitle(
                      title: '显示样式',
                      subtitle: '这些设置适合在非播放页提前调好，进播放器后直接沿用。',
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Column(
                        children: <Widget>[
                          _DanmakuSliderTile(
                            title: '显示区域',
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
                            title: '不透明度',
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
                            title: '弹幕密度',
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
                            title: '字体大小',
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
                            title: '弹幕速度',
                            valueLabel: _speedLabel(_settings.speed),
                            value: _settings.speed,
                            min: 0.7,
                            max: 1.55,
                            divisions: 4,
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
                    const _DanmakuSectionTitle(
                      title: '类型过滤',
                      subtitle: '控制默认显示哪些弹幕类型。',
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          _DanmakuTypeChip(
                            label: '固定',
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
                            label: '滚动',
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
                            label: '底部',
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
                            label: '彩色',
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
                    const _DanmakuSectionTitle(
                      title: '防遮挡',
                      subtitle: '这些默认规则更适合全局预先设定。',
                    ),
                    const SizedBox(height: 10),
                    _DanmakuCard(
                      child: Column(
                        children: <Widget>[
                          _DanmakuSwitchTile(
                            title: '隐藏重复弹幕',
                            subtitle: '减少同屏高频重复内容。',
                            value: _settings.hideDuplicate,
                            onChanged: (value) {
                              _save(_settings.copyWith(hideDuplicate: value));
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSwitchTile(
                            title: '避开字幕区域',
                            subtitle: '尽量避免弹幕压住底部字幕。',
                            value: _settings.avoidSubtitleArea,
                            onChanged: (value) {
                              _save(
                                _settings.copyWith(avoidSubtitleArea: value),
                              );
                            },
                          ),
                          const _DanmakuDivider(),
                          _DanmakuSwitchTile(
                            title: '避开画面中央',
                            subtitle: '优先保留主体区域的观看空间。',
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
