import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/common/track_option_sheet.dart';
import 'desktop_environment.dart';
import 'desktop_floating_panel.dart';

/// 下拉唤起方式：悬停（选轨小窗）/ 点击（排序、布局等下拉菜单）。
enum DesktopDropdownActivation { hover, tap }

/// 一组互斥选项：组内 [selectedId] 高亮选中项，点选经 [onSelected] 上抛。
class DesktopDropdownOptionGroup {
  const DesktopDropdownOptionGroup({
    required this.items,
    required this.selectedId,
    required this.onSelected,
  });

  final List<TrackOptionSheetItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelected;
}

/// 下拉面板的内容描述：多个选项组之间用分隔线隔开（如图 2 的「排序字段 +
/// 升降序」双组形态），条目复用 [TrackOptionSheetItem]（`onDelete` 用于本地
/// 导入字幕的删除按钮）。
class DesktopHoverDropdownSpec {
  const DesktopHoverDropdownSpec({
    this.title,
    required this.groups,
    this.width = 280,
    this.maxHeight = 380,
  });

  /// 单组便捷构造（字幕/音轨等单列表场景）。
  factory DesktopHoverDropdownSpec.single({
    String? title,
    required List<TrackOptionSheetItem> items,
    required String? selectedId,
    required ValueChanged<String> onSelected,
    double width = 280,
    double maxHeight = 380,
  }) {
    return DesktopHoverDropdownSpec(
      title: title,
      groups: <DesktopDropdownOptionGroup>[
        DesktopDropdownOptionGroup(
          items: items,
          selectedId: selectedId,
          onSelected: onSelected,
        ),
      ],
      width: width,
      maxHeight: maxHeight,
    );
  }

  /// 面板标题；null 时不渲染标题行（排序/布局下拉直接以选项开头）。
  final String? title;
  final List<DesktopDropdownOptionGroup> groups;

  /// 面板固定宽度（紧凑下拉样式，条目过长省略号截断）。
  final double width;
  final double maxHeight;
}

/// 下拉弹窗：[DesktopDropdownActivation.hover] 鼠标悬停触发件弹出、移出自动
/// 收起；[DesktopDropdownActivation.tap] 点击开合、点击面板外关闭（排序/布局
/// 菜单）。
///
/// 定位：默认贴触发件下方左对齐（水平钳制到窗口边界内），下方空间不足时
/// 翻转到上方；经 [CompositedTransformFollower] 锚定，页面滚动时跟随触发件。
///
/// Overlay 弹层子树承载的是 tight 全屏约束，因此内容经 [UnconstrainedBox]
/// 逃逸约束、按面板内容收缩——否则命中测试区会随弹层铺满全屏，鼠标永远
/// 「在小窗内」，移出收起逻辑全部失效。
///
/// 点选由外部收起；触发件自身的 onTap 在打开模态 sheet 前应先调用
/// [DesktopHoverDropdownState.hide]。
class DesktopHoverDropdown extends StatefulWidget {
  const DesktopHoverDropdown({
    super.key,
    required this.child,
    required this.spec,
    this.activation = DesktopDropdownActivation.hover,
    this.onOpenChanged,
  });

  final Widget child;
  final DesktopHoverDropdownSpec? spec;
  final DesktopDropdownActivation activation;

  /// 展开态回调（详情页用它复用箭头旋转动画）。
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<DesktopHoverDropdown> createState() => DesktopHoverDropdownState();
}

class DesktopHoverDropdownState extends State<DesktopHoverDropdown> {
  static const _graceDuration = Duration(milliseconds: 140);
  static const _fadeDuration = Duration(milliseconds: 160);

  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  Timer? _graceTimer;
  Timer? _unmountTimer;
  bool _visible = false;

  bool get _tapMode => widget.activation == DesktopDropdownActivation.tap;

  bool get _enabled => widget.spec != null && widget.spec!.groups.isNotEmpty;

  void _notifyOpenChanged() => widget.onOpenChanged?.call(_visible);

  /// 立即展开（悬停移入触发件 / 点击触发件）。
  void _openNow() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _unmountTimer?.cancel();
    _unmountTimer = null;
    if (!_portal.isShowing) _portal.show();
    if (_visible) return;
    setState(() => _visible = true);
    _notifyOpenChanged();
  }

  /// 收起（悬停移出 / 点选完成 / 点击面板外 / 触发件被点击打开 sheet 前）。
  void _close() {
    _graceTimer?.cancel();
    _graceTimer = null;
    if (!_visible) return;
    setState(() => _visible = false);
    _notifyOpenChanged();
    _unmountTimer?.cancel();
    _unmountTimer = Timer(_fadeDuration, () {
      _unmountTimer = null;
      if (mounted && !_visible && _portal.isShowing) _portal.hide();
    });
  }

  /// 点击式触发件开合入口。
  void toggle() {
    if (_visible) {
      _close();
    } else {
      _openNow();
    }
  }

  /// 供外部收起弹窗。
  void hide() => _close();

  /// 悬停走廊：指针在触发件与小窗之间的间隙时延迟收起。
  void _scheduleGraceClose() {
    _graceTimer?.cancel();
    _graceTimer = Timer(_graceDuration, _close);
  }

  void _handlePanelEnter() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  void _handlePanelExit() => _scheduleGraceClose();

  @override
  void didUpdateWidget(covariant DesktopHoverDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && _visible) _close();
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    _unmountTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hoverMode = !_tapMode;
    final enabled = _enabled;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlayPanel,
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          cursor: !hoverMode && enabled
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          onEnter: hoverMode && enabled ? (_) => _openNow() : null,
          onExit: hoverMode && enabled
              // 移出触发件进入小窗前的间隙时延迟收起；移入小窗会取消该计时。
              ? (_) => _scheduleGraceClose()
              : null,
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildOverlayPanel(BuildContext overlayContext) {
    // 淡出卸载期间 spec 可能已被置空（如媒体切换），此时直接返回占位。
    final spec = widget.spec;
    if (spec == null) return const SizedBox.shrink();
    final placement = _resolvePlacement(spec);
    if (placement == null) return const SizedBox.shrink();

    final panel = IgnorePointer(
      ignoring: !_visible,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: placement.above
            ? Alignment.topLeft
            : Alignment.bottomLeft,
        followerAnchor: placement.above
            ? Alignment.bottomLeft
            : Alignment.topLeft,
        offset: Offset(placement.dx, placement.above ? -6 : 6),
        child: UnconstrainedBox(
          alignment: Alignment.topLeft,
          clipBehavior: Clip.none,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _visible ? 1 : 0),
            duration: _fadeDuration,
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 6),
                child: child,
              ),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: MouseRegion(
                onEnter: _tapMode ? null : (_) => _handlePanelEnter(),
                onExit: _tapMode ? null : (_) => _handlePanelExit(),
                child: DesktopFloatingPanel(
                  child: SizedBox(
                    width: spec.width,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (spec.title != null) ...<Widget>[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              child: Text(
                                spec.title!,
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
                            const SizedBox(height: 9),
                            const Divider(height: 1, color: Color(0x24FFFFFF)),
                            const SizedBox(height: 6),
                          ],
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: placement.maxHeight,
                            ),
                            child: SingleChildScrollView(
                              padding: EdgeInsets.zero,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (
                                    var i = 0;
                                    i < spec.groups.length;
                                    i++
                                  ) ...<Widget>[
                                    if (i > 0) ...<Widget>[
                                      const SizedBox(height: 4),
                                      const Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Color(0x24FFFFFF),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    for (final item in spec.groups[i].items)
                                      _HoverDropdownOptionRow(
                                        item: item,
                                        selected:
                                            item.id ==
                                            spec.groups[i].selectedId,
                                        onTap: () {
                                          _close();
                                          spec.groups[i].onSelected(item.id);
                                        },
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!_tapMode) return panel;

    // 点击式：面板打开时铺一层透明点击屏障——点击面板外任意处（含再次点击
    // 触发件）关闭；面板绘制在屏障之上，不受影响。面板同样铺满弹层（锚点
    // 变换把内容放回触发件旁），保证命中测试几何与悬停模式一致。
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_visible,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Positioned.fill(child: panel),
      ],
    );
  }

  /// 计算面板相对触发件的偏移与上下方向；触发件几何不可用时返回 null。
  ///
  /// 触发件与边界必须统一使用所属 Overlay 的局部坐标；嵌套导航器的内容区
  /// 可能带有全局偏移，混用全局坐标与局部尺寸会把右侧菜单推向窗口左边。
  _DropdownPlacement? _resolvePlacement(DesktopHoverDropdownSpec spec) {
    final triggerBox = context.findRenderObject();
    final overlayBox = Overlay.of(context).context.findRenderObject();
    if (triggerBox is! RenderBox ||
        !triggerBox.attached ||
        !triggerBox.hasSize ||
        overlayBox is! RenderBox ||
        !overlayBox.attached ||
        !overlayBox.hasSize) {
      return null;
    }
    final triggerRect =
        triggerBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
        triggerBox.size;
    final overlaySize = overlayBox.size;

    final spaceBelow = overlaySize.height - triggerRect.bottom;
    final spaceAbove = triggerRect.top;
    // 下方放得下（或上下都放不下）时优先下方，贴近图 2 的下拉形态。
    final minNeeded = (spec.maxHeight < 240 ? spec.maxHeight : 240.0) + 18;
    final above = spaceBelow < minNeeded && spaceAbove > spaceBelow;
    final maxExtent = (above ? spaceAbove : spaceBelow) - 12;
    final maxHeight = spec.maxHeight.clamp(
      0.0,
      maxExtent.isNegative ? 0.0 : maxExtent,
    );

    final maxLeft = (overlaySize.width - spec.width - 12).clamp(
      12.0,
      double.infinity,
    );
    final left = triggerRect.left.clamp(12.0, maxLeft);
    return _DropdownPlacement(
      dx: left - triggerRect.left,
      above: above,
      maxHeight: maxHeight,
    );
  }
}

/// 桌面平台把 [child] 包成点击唤起的下拉触发件（锚定 [child] 定位）；其他
/// 平台或 [spec] 为空时原样返回 [child]，由调用方走原有弹层入口。
Widget desktopTapDropdownWrapper({
  required GlobalKey<DesktopHoverDropdownState> dropdownKey,
  required DesktopHoverDropdownSpec? spec,
  required Widget child,
}) {
  if (!DesktopEnvironment.isDesktopPlatform || spec == null) return child;
  return DesktopHoverDropdown(
    key: dropdownKey,
    activation: DesktopDropdownActivation.tap,
    spec: spec,
    child: child,
  );
}

class _DropdownPlacement {
  const _DropdownPlacement({
    required this.dx,
    required this.above,
    required this.maxHeight,
  });

  final double dx;
  final bool above;
  final double maxHeight;
}

class _HoverDropdownOptionRow extends StatefulWidget {
  const _HoverDropdownOptionRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final TrackOptionSheetItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_HoverDropdownOptionRow> createState() =>
      _HoverDropdownOptionRowState();
}

class _HoverDropdownOptionRowState extends State<_HoverDropdownOptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final titleColor = selected ? const Color(0xFF83B5FF) : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0x2E4F9EFF)
                : _hovered
                ? const Color(0x1FFFFFFF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (item.subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? const Color(0x99A9C9FF)
                                  : const Color(0x80FFFFFF),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Color(0xFF83B5FF),
                      ),
                    ),
                  if (item.onDelete != null)
                    IconButton(
                      onPressed: item.onDelete,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      iconSize: 17,
                      color: _hovered
                          ? const Color(0xCCFFFFFF)
                          : const Color(0x73FFFFFF),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).deleteButtonTooltip,
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
