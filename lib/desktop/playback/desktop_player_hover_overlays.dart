import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../desktop_floating_panel.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../playback/playback_source.dart';
import 'desktop_mpv_runtime.dart';
import 'desktop_player_panels.dart';

/// 播放器悬停弹层种类。
enum PlayerHoverOverlayKind {
  speed,
  episodes,
  quality,
  subtitle,
  audio,
  settings,
  previousEpisode,
  nextEpisode,
}

/// 弹层底边统一内边距：所有 kind 与底部控制条/进度条保持同一间距。
const double panelBottomInset = 78;

/// 悬停弹层快照：[kind] 为空表示当前没有弹层。
class PlayerHoverOverlaySnapshot {
  const PlayerHoverOverlaySnapshot({
    this.kind,
    this.visible = false,
    this.anchor = Rect.zero,
    this.initialPage,
  });

  final PlayerHoverOverlayKind? kind;
  final bool visible;
  final Rect anchor;

  /// 设置卡打开时直达的子页（如音轨弹层「调节」→ 音频调整）。
  final DesktopPlaybackSettingsPage? initialPage;

  PlayerHoverOverlaySnapshot copyWith({
    PlayerHoverOverlayKind? kind,
    bool? visible,
    Rect? anchor,
    DesktopPlaybackSettingsPage? initialPage,
  }) {
    return PlayerHoverOverlaySnapshot(
      kind: kind ?? this.kind,
      visible: visible ?? this.visible,
      anchor: anchor ?? this.anchor,
      initialPage: initialPage ?? this.initialPage,
    );
  }
}

/// 弹层内容：由宿主页面按 [PlayerHoverOverlayKind] 构建，层本身只负责定位与外观。
class PlayerHoverOverlayContent {
  const PlayerHoverOverlayContent({required this.child, required this.width});

  final Widget child;
  final double width;
}

/// 播放器悬停弹层。
///
/// 由 [ValueListenable] 驱动而不是宿主 setState：media_kit 全屏是独立路由上的
/// 另一个 `Video`，宿主 setState 刷不到它，全屏下悬停会完全无响应；两条路由的
/// 控制层都监听同一个通知源，谁可见谁响应。
class PlayerHoverOverlayLayer extends StatefulWidget {
  const PlayerHoverOverlayLayer({
    super.key,
    required this.snapshot,
    required this.contentBuilder,
    required this.onPanelEnter,
    required this.onPanelExit,
  });

  final ValueListenable<PlayerHoverOverlaySnapshot> snapshot;
  final PlayerHoverOverlayContent? Function(
    PlayerHoverOverlayKind kind,
    Size size,
    PlayerHoverOverlaySnapshot snapshot,
  )
  contentBuilder;
  final VoidCallback onPanelEnter;
  final VoidCallback onPanelExit;

  @override
  State<PlayerHoverOverlayLayer> createState() =>
      _PlayerHoverOverlayLayerState();
}

class _PlayerHoverOverlayLayerState extends State<PlayerHoverOverlayLayer> {
  // 弹层内容键（kind+子页）：弹出首帧不做切换动画，弹层间切换（音轨小窗→设置大卡）才播放。
  String? _contentKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerHoverOverlaySnapshot>(
      valueListenable: widget.snapshot,
      builder: (context, value, _) {
        final kind = value.kind;
        if (kind == null) {
          _contentKey = null;
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final content = widget.contentBuilder(kind, size, value);
              if (content == null) return const SizedBox.shrink();

              final isSettings = kind == PlayerHoverOverlayKind.settings;
              final isEpisodes = kind == PlayerHoverOverlayKind.episodes;

              final isEpisodePreview =
                  kind == PlayerHoverOverlayKind.previousEpisode ||
                  kind == PlayerHoverOverlayKind.nextEpisode;
              // 上/下一集是同一个小窗的两种内容：共用内容键，跨方向切换不重建
              // 玻璃外壳（整窗交叉淡入会叠加位置滑动产生抖动感），海报与文字
              // 的过渡由预览卡内部动画完成。
              final nextKey =
                  '${isEpisodePreview ? 'episode-preview' : kind.name}:'
                  '${value.initialPage?.name ?? 'root'}';
              final morphing = _contentKey != null && _contentKey != nextKey;
              _contentKey = nextKey;

              final panel = IgnorePointer(
                ignoring: !value.visible,
                child: MouseRegion(
                  onEnter: (_) => widget.onPanelEnter(),
                  onExit: (_) => widget.onPanelExit(),
                  child: AnimatedOpacity(
                    opacity: value.visible ? 1 : 0,
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSlide(
                      // 入场/退场所有 kind 统一：从控制条方向（底部）升起，
                      // 不再按分支区分右侧滑入与底部升起两套动效。
                      offset: value.visible
                          ? Offset.zero
                          : const Offset(0, 0.08),
                      duration: const Duration(milliseconds: 190),
                      curve: Curves.easeOutCubic,
                      child: AnimatedScale(
                        scale: value.visible ? 1 : 0.975,
                        duration: const Duration(milliseconds: 190),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: AnimatedSwitcher(
                          // 弹层之间切换只做交叉淡入（底边对齐、旧内容脱离布局流），
                          // 不加位移/缩放：容器位置由 AnimatedPositioned 平滑滑动，
                          // 窗口级动效叠加会产生抖动感；内容级动画归各面板内部自理。
                          duration: morphing
                              ? const Duration(milliseconds: 220)
                              : Duration.zero,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          // 新旧内容底边对齐交叉：默认垂直居中会让矮面板
                          // （字幕/音轨）在高面板退场时先悬在高处再坠落。
                          // 旧内容脱离布局流（Positioned 挂底边）：容器尺寸
                          // 立即取新内容，不被退场中的旧内容撑高再塌缩——
                          // 字幕↔音轨这类高度不等的切换否则会顶边抖动。
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.bottomCenter,
                                children: <Widget>[
                                  for (final child in previousChildren)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: child,
                                    ),
                                  if (currentChild != null) currentChild,
                                ],
                              ),
                          child: KeyedSubtree(
                            key: ValueKey<String>(nextKey),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {},
                              child: DesktopFloatingPanel(child: content.child),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );

              // 设置卡：在触发弹层的锚点位置原位放大（水平对齐锚点、钳制留边），
              // 垂直方向上下留边全高，不盖住顶部栏与底部控制条。
              //
              // 所有 kind 共用同一个 Positioned 子树（靠 key 匹配，跨 kind 不重建），
              // 只有几何参数随 kind 变化：快速扫动底栏按钮时弹层走 AnimatedSwitcher
              // 原位交叉淡入，不再整窗销毁后重播入场动画；各 kind 底边统一同一
              // 内边距，与进度条的距离保持一致。
              final panelTop = isSettings || isEpisodes ? 76.0 : null;
              final double panelLeft;
              if (isEpisodes) {
                panelLeft = size.width - 20 - content.width;
              } else if (isSettings) {
                panelLeft = (value.anchor.center.dx - content.width / 2).clamp(
                  20.0,
                  size.width - content.width - 20,
                );
              } else {
                panelLeft = (value.anchor.center.dx - content.width / 2).clamp(
                  14.0,
                  size.width - content.width - 14,
                );
              }

              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (isEpisodes)
                    // 选集：衔接底栏按钮的悬停走廊，紧贴面板底边下方，
                    // 防止移向面板途中弹层提前关闭。
                    Positioned(
                      key: const ValueKey<String>('episodes-corridor'),
                      left: panelLeft,
                      bottom: panelBottomInset - 14,
                      width: content.width,
                      height: 14,
                      child: IgnorePointer(
                        ignoring: !value.visible,
                        child: MouseRegion(
                          onEnter: (_) => widget.onPanelEnter(),
                          onExit: (_) => widget.onPanelExit(),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  AnimatedPositioned(
                    key: const ValueKey<String>('hover-panel'),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: panelLeft,
                    top: panelTop,
                    bottom: panelBottomInset,
                    width: content.width,
                    child: isSettings || isEpisodes
                        ? panel
                        : ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: (value.anchor.top - 86).clamp(
                                160.0,
                                size.height - 180,
                              ),
                            ),
                            child: panel,
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// 悬停小选项面板（速度/画质/字幕/音轨）。
class DesktopHoverOptionsPanel extends StatelessWidget {
  const DesktopHoverOptionsPanel({
    super.key,
    required this.title,
    required this.options,
    required this.emptyLabel,
    required this.onSelected,
    this.offLabel,
    this.onOff,
    this.actions = const <DesktopPanelHeaderAction>[],
  });

  final String title;
  final List<DesktopPlayerPanelOption> options;
  final String emptyLabel;
  final ValueChanged<DesktopPlayerPanelOption> onSelected;
  final String? offLabel;
  final VoidCallback? onOff;

  /// 标题右侧的文字动作组（对齐安卓 panelHeaderTextButton，如音轨「调节」、字幕「样式/导入」）。
  final List<DesktopPanelHeaderAction> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xBFFFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                for (final action in actions)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _PanelHeaderTextButton(
                      label: action.label,
                      onTap: action.onTap,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          const Divider(height: 1, color: Color(0x24FFFFFF)),
          const SizedBox(height: 6),
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (options.isNotEmpty && onOff != null && offLabel != null)
                    _DesktopHoverOptionRow(
                      title: offLabel!,
                      leading: Icons.block_rounded,
                      onTap: onOff!,
                    ),
                  if (options.isEmpty && emptyLabel.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 18,
                      ),
                      child: Text(
                        emptyLabel,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    for (final option in options)
                      _DesktopHoverOptionRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        selected: option.selected,
                        onTap: () => onSelected(option),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 画质悬停面板：主层按分辨率合并，自定义层再展开同档码率。
class DesktopHoverQualityPanel extends StatefulWidget {
  const DesktopHoverQualityPanel({
    super.key,
    required this.source,
    required this.onSelected,
  });

  final MpvMediaSource source;
  final ValueChanged<int> onSelected;

  @override
  State<DesktopHoverQualityPanel> createState() =>
      _DesktopHoverQualityPanelState();
}

class _DesktopHoverQualityPanelState extends State<DesktopHoverQualityPanel> {
  bool _custom = false;
  String? _expandedTier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final menu = DesktopMpvRuntime.qualityMenu(widget.source);
    final customLabel = l10n.nativePlayerText0054.replaceFirst('⚙', '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    onTap: _custom
                        ? () => setState(() => _custom = false)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    hoverColor: const Color(0x38FFFFFF),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (_custom)
                          const Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        Text(
                          _custom
                              ? '$customLabel${l10n.nativePlayerText0021}'
                              : l10n.nativePlayerText0021,
                          style: const TextStyle(
                            color: Color(0xD9FFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_custom)
                  Text(
                    _currentSummary(menu, l10n),
                    style: const TextStyle(
                      color: Color(0xFF72A7FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  TextButton(
                    onPressed: () => setState(() => _custom = true),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 28),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(customLabel),
                        const Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0x24FFFFFF)),
          const SizedBox(height: 7),
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: _custom
                  ? _buildCustom(menu, l10n)
                  : _buildMain(menu, l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain(DesktopQualityMenu menu, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final choice in menu.mainChoices)
          _DesktopQualityRow(
            title: choice.isOriginal
                ? l10n.playerQualityOriginal
                : choice.displayTier,
            detail: DesktopMpvRuntime.isCurrentQuality(widget.source, choice)
                ? _mainChoiceDetail(choice)
                : '',
            selected: DesktopMpvRuntime.isCurrentQuality(widget.source, choice),
            onTap: () {
              if (!DesktopMpvRuntime.isCurrentQuality(widget.source, choice)) {
                widget.onSelected(choice.sourceIndex);
              }
            },
          ),
      ],
    );
  }

  Widget _buildCustom(DesktopQualityMenu menu, AppLocalizations l10n) {
    _expandedTier ??=
        _currentTier(menu) ??
        (menu.customGroups.isEmpty ? null : menu.customGroups.keys.first);
    final choices =
        menu.customGroups[_expandedTier] ?? const <DesktopQualityChoice>[];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final group in menu.customGroups.entries) ...<Widget>[
                _DesktopQualityTierButton(
                  title: group.key,
                  selected: group.key == _expandedTier,
                  onTap: () => setState(() => _expandedTier = group.key),
                ),
                if (group.key != menu.customGroups.keys.last)
                  const SizedBox(height: 6),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final choice in choices)
                _DesktopQualityBitrateButton(
                  label: _choiceSummary(choice, l10n),
                  selected: DesktopMpvRuntime.isCurrentQuality(
                    widget.source,
                    choice,
                  ),
                  onTap: () {
                    if (!DesktopMpvRuntime.isCurrentQuality(
                      widget.source,
                      choice,
                    )) {
                      widget.onSelected(choice.sourceIndex);
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _currentSummary(DesktopQualityMenu menu, AppLocalizations l10n) {
    for (final choices in menu.customGroups.values) {
      for (final choice in choices) {
        if (DesktopMpvRuntime.isCurrentQuality(widget.source, choice)) {
          return '${choice.displayTier} ${_choiceSummary(choice, l10n)}';
        }
      }
    }
    return '';
  }

  String? _currentTier(DesktopQualityMenu menu) {
    for (final group in menu.customGroups.entries) {
      if (group.value.any(
        (choice) => DesktopMpvRuntime.isCurrentQuality(widget.source, choice),
      )) {
        return group.key;
      }
    }
    return null;
  }

  String _choiceSummary(DesktopQualityChoice choice, AppLocalizations l10n) {
    return <String>[
      DesktopMpvRuntime.qualityBitrateLabel(choice.quality.bitrate),
      if (choice.isOriginal) l10n.playerQualityOriginal,
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  String _mainChoiceDetail(DesktopQualityChoice choice) {
    return <String>[
      if (choice.isOriginal) choice.displayTier,
      DesktopMpvRuntime.qualityBitrateLabel(choice.quality.bitrate),
    ].where((part) => part.isNotEmpty).join(' ');
  }
}

class _DesktopQualityRow extends StatelessWidget {
  const _DesktopQualityRow({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF72A7FF) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: const Color(0x38FFFFFF),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (detail.isNotEmpty)
              Text(
                detail,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DesktopQualityTierButton extends StatelessWidget {
  const _DesktopQualityTierButton({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    hoverColor: const Color(0x38FFFFFF),
    child: Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? const Color(0x22FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: selected ? const Color(0xFF72A7FF) : Colors.white70,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white,
            size: 18,
          ),
        ],
      ),
    ),
  );
}

class _DesktopQualityBitrateButton extends StatelessWidget {
  const _DesktopQualityBitrateButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: const Color(0x38FFFFFF),
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0x22FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFF72A7FF) : Colors.white70,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    ),
  );
}

class _DesktopHoverOptionRow extends StatefulWidget {
  const _DesktopHoverOptionRow({
    required this.title,
    required this.onTap,
    this.subtitle = '',
    this.selected = false,
    this.leading,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final IconData? leading;
  final VoidCallback onTap;

  @override
  State<_DesktopHoverOptionRow> createState() => _DesktopHoverOptionRowState();
}

class _DesktopHoverOptionRowState extends State<_DesktopHoverOptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: widget.selected
              ? const Color(0x2E4F9EFF)
              : _hovered
              ? const Color(0x1FFFFFFF)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: <Widget>[
                  AnimatedScale(
                    scale: _hovered ? 1.08 : 1,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      widget.leading ??
                          (widget.selected
                              ? Icons.check_rounded
                              : Icons.circle_outlined),
                      size: widget.selected ? 18 : 15,
                      color: widget.selected
                          ? const Color(0xFF83B5FF)
                          : const Color(0x8CFFFFFF),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.selected
                                ? const Color(0xFFD9E9FF)
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: widget.selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (widget.subtitle.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0x80FFFFFF),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹层标题右侧的头部动作。
class DesktopPanelHeaderAction {
  const DesktopPanelHeaderAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

/// 面板标题右侧的文字按钮（对齐安卓 panelHeaderTextButton）。
class _PanelHeaderTextButton extends StatelessWidget {
  const _PanelHeaderTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0x1FFFFFFF),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: Color(0x24FFFFFF)),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      hoverColor: const Color(0x38FFFFFF),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// 上/下一集悬停预览卡：海报缩略图 + 方向标签（「上一集」/「下一集」）+ 集标题。
/// 内容只负责展示；外观与定位仍由通用悬浮小窗外壳（DesktopFloatingPanel +
/// PlayerHoverOverlayLayer 通用分支）承担。
class DesktopHoverEpisodePreviewPanel extends StatefulWidget {
  const DesktopHoverEpisodePreviewPanel({
    super.key,
    required this.label,
    required this.title,
    required this.posterPath,
    this.headers = const <String, String>{},
  });

  final String label;
  final String title;
  final String posterPath;
  final Map<String, String> headers;

  @override
  State<DesktopHoverEpisodePreviewPanel> createState() =>
      _DesktopHoverEpisodePreviewPanelState();
}

class _DesktopHoverEpisodePreviewPanelState
    extends State<DesktopHoverEpisodePreviewPanel> {
  @override
  Widget build(BuildContext context) {
    // 上/下一集共用同一个玻璃外壳，动画只发生在内容层：标签/标题/海报任一
    // 变化即内部交叉（淡入+轻微上移），窗口本身不动、不闪。
    final contentKey = ValueKey<String>(
      '${widget.label}|${widget.title}|${widget.posterPath}',
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            for (final child in previousChildren)
              Positioned(left: 0, right: 0, bottom: 0, child: child),
            if (currentChild != null) currentChild,
          ],
        ),
        child: KeyedSubtree(
          key: contentKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DesktopEpisodePoster(
                    widget.posterPath,
                    true,
                    headers: widget.headers,
                    current: false,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              // 固定两行高度：不同集标题行数不同也不改变窗口高度，
              // 内容交叉时几何完全稳定。
              SizedBox(
                height: 38,
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
