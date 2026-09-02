import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/common/track_option_sheet.dart';
import 'desktop_floating_panel.dart';

/// 悬停下拉弹窗的内容描述。
///
/// 条目复用 [TrackOptionSheetItem]（与选轨 sheet 同一模型，`onDelete` 用于
/// 本地导入字幕的删除按钮）；[selectedId] 标记当前选中项，点选经
/// [onSelected] 上抛后由调用方决定如何落地（弹窗自身只负责收起）。
class DesktopHoverDropdownSpec {
  const DesktopHoverDropdownSpec({
    required this.title,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.width = 280,
    this.maxHeight = 380,
  });

  final String title;
  final List<TrackOptionSheetItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// 面板固定宽度（紧凑下拉样式，条目过长省略号截断）。
  final double width;
  final double maxHeight;
}

/// 鼠标悬停触发的下拉弹窗：悬停触发件弹出 [DesktopFloatingPanel] 小窗，
/// 移入小窗保持、移出（含 140ms 悬停走廊）自动收起。
///
/// 定位：默认贴触发件下方左对齐（水平钳制到窗口边界内），下方空间不足时
/// 翻转到上方；经 [CompositedTransformFollower] 锚定，页面滚动时跟随触发件。
///
/// Overlay 弹层子树承载的是 tight 全屏约束，因此内容经 [UnconstrainedBox]
/// 逃逸约束、按面板内容收缩——否则命中测试区会随弹层铺满全屏，鼠标永远
/// 「在小窗内」，移出收起逻辑全部失效。
///
/// 点选由外部收起：触发件自身的 onTap 在打开模态 sheet 前应先调用
/// [DesktopHoverDropdownState.hide]，避免弹窗与模态 sheet 叠加。
class DesktopHoverDropdown extends StatefulWidget {
  const DesktopHoverDropdown({
    super.key,
    required this.child,
    required this.spec,
    this.onOpenChanged,
  });

  final Widget child;
  final DesktopHoverDropdownSpec? spec;

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

  bool get _enabled => widget.spec != null && widget.spec!.items.isNotEmpty;

  void _notifyOpenChanged() => widget.onOpenChanged?.call(_visible);

  /// 立即展开（鼠标移入触发件）。
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

  /// 收起（鼠标移出触发件与小窗，或点选完成 / 触发件被点击）。
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

  /// 供外部（触发件点击打开模态 sheet 前）收起弹窗。
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
    final enabled = _enabled;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlayPanel,
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: enabled ? (_) => _openNow() : null,
          onExit: enabled
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
    final placement = _resolvePlacement(overlayContext, spec);
    if (placement == null) return const SizedBox.shrink();

    return IgnorePointer(
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
                onEnter: (_) => _handlePanelEnter(),
                onExit: (_) => _handlePanelExit(),
                child: DesktopFloatingPanel(
                  child: SizedBox(
                    width: spec.width,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            child: Text(
                              spec.title,
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
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: placement.maxHeight,
                            ),
                            child: SingleChildScrollView(
                              padding: EdgeInsets.zero,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final item in spec.items)
                                    _HoverDropdownOptionRow(
                                      item: item,
                                      selected: item.id == spec.selectedId,
                                      onTap: () {
                                        _close();
                                        spec.onSelected(item.id);
                                      },
                                    ),
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
  }

  /// 计算面板相对触发件的偏移与上下方向；触发件几何不可用时返回 null。
  ///
  /// 弹层边界取 MediaQuery 窗口尺寸（承载弹层的 overlay 铺满窗口）；
  /// 不在 overlay 子树构建期取其 RenderObject（可能尚未完成布局）。
  _DropdownPlacement? _resolvePlacement(
    BuildContext overlayContext,
    DesktopHoverDropdownSpec spec,
  ) {
    final triggerBox = context.findRenderObject();
    if (triggerBox is! RenderBox ||
        !triggerBox.attached ||
        !triggerBox.hasSize) {
      return null;
    }
    final triggerRect = triggerBox.localToGlobal(Offset.zero) & triggerBox.size;
    final overlaySize = MediaQuery.sizeOf(overlayContext);

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
