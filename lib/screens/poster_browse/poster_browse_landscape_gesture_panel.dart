import 'dart:async';

import 'package:flutter/material.dart';

import '../../media_backend/media_image_request.dart';
import 'poster_browse_display_item.dart';
import 'poster_browse_poster_track.dart';

class PosterBrowseLandscapeGesturePanel extends StatefulWidget {
  final List<PosterBrowseDisplayItem> items;
  final int focusedIndex;
  final bool showProgress;
  final MediaImageRequest Function(PosterBrowseDisplayItem item) imageOf;
  final String Function(PosterBrowseDisplayItem item) secondaryLabelOf;
  final void Function(int index) onItemTap;
  final Widget collapsedContent;
  final ValueChanged<double>? onCollapseProgressChanged;
  final double cardWidth;
  final double itemSpacing;

  const PosterBrowseLandscapeGesturePanel({
    super.key,
    required this.items,
    required this.focusedIndex,
    required this.showProgress,
    required this.imageOf,
    required this.secondaryLabelOf,
    required this.onItemTap,
    required this.collapsedContent,
    this.onCollapseProgressChanged,
    this.cardWidth = 116,
    this.itemSpacing = 18,
  });

  @override
  State<PosterBrowseLandscapeGesturePanel> createState() =>
      _PosterBrowseLandscapeGesturePanelState();
}

class _PosterBrowseLandscapeGesturePanelState
    extends State<PosterBrowseLandscapeGesturePanel>
    with SingleTickerProviderStateMixin {
  static const _settleDuration = Duration(milliseconds: 280);
  static const _dragExtent = 160.0;
  static const _velocityThreshold = 500.0;
  static const _horizontalSettleDuration = Duration(milliseconds: 240);
  static const _horizontalVelocityThreshold = 420.0;
  static const _horizontalDistanceThreshold = 64.0;
  // 快甩阈值：高于它且面板展开时，横滑交给轨道惯性滚动（一次快甩跨多张海报），
  // 低于它保持"切焦点 ±1"的翻页手感。收起态一律走 ±1，不受此阈值影响。
  static const _browseFlingVelocity = 1000.0;
  // 快甩落点的速度投影时长：velocity × 0.35s 估算会滑到哪里。
  static const _flingProjectionTime = 0.35;

  late final AnimationController _collapseController;
  late final ScrollController _scrollController;
  double _horizontalDragDistance = 0;
  double _horizontalDragStartOffset = 0;
  int _horizontalSettleGeneration = 0;
  int _contentSwitchDirection = 1;

  @override
  void initState() {
    super.initState();
    _collapseController = AnimationController(
      vsync: this,
      duration: _settleDuration,
    )..addListener(_notifyCollapseProgress);
    _scrollController = ScrollController();
    _scheduleFocusedItemSync(jump: true);
  }

  @override
  void didUpdateWidget(covariant PosterBrowseLandscapeGesturePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusedIndex != oldWidget.focusedIndex) {
      _contentSwitchDirection = widget.focusedIndex > oldWidget.focusedIndex
          ? 1
          : -1;
    }
    if (widget.focusedIndex != oldWidget.focusedIndex ||
        widget.items.length != oldWidget.items.length ||
        widget.cardWidth != oldWidget.cardWidth ||
        widget.itemSpacing != oldWidget.itemSpacing ||
        _focusedItemId(widget) != _focusedItemId(oldWidget)) {
      _scheduleFocusedItemSync(jump: false);
    }
  }

  @override
  void dispose() {
    _collapseController.removeListener(_notifyCollapseProgress);
    _collapseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _collapseController,
      builder: (context, child) {
        final progress = _collapseController.value;
        return GestureDetector(
          key: const ValueKey('poster_browse_landscape_gesture_panel'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _collapseController.stop(),
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          onHorizontalDragStart: widget.items.length > 1
              ? _handleHorizontalDragStart
              : null,
          onHorizontalDragUpdate: widget.items.length > 1
              ? _handleHorizontalDragUpdate
              : null,
          onHorizontalDragEnd: widget.items.length > 1
              ? _handleHorizontalDragEnd
              : null,
          onHorizontalDragCancel: widget.items.length > 1
              ? _handleHorizontalDragCancel
              : null,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: progress > 0.5,
                    child: Opacity(
                      key: const ValueKey(
                        'poster_browse_landscape_track_opacity',
                      ),
                      opacity: 1 - progress,
                      child: Transform.translate(
                        offset: Offset(0, 96 * progress),
                        child: PosterBrowsePosterTrack(
                          items: widget.items,
                          focusedIndex: widget.focusedIndex,
                          showProgress: widget.showProgress,
                          imageOf: widget.imageOf,
                          secondaryLabelOf: widget.secondaryLabelOf,
                          onItemTap: widget.onItemTap,
                          controller: _scrollController,
                          physics: const NeverScrollableScrollPhysics(),
                          cardWidth: widget.cardWidth,
                          itemSpacing: widget.itemSpacing,
                        ),
                      ),
                    ),
                  ),
                ),
                if (progress > 0.001)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: progress < 0.5,
                      child: Opacity(
                        key: const ValueKey(
                          'poster_browse_landscape_info_opacity',
                        ),
                        opacity: progress,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - progress)),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 30),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: AnimatedBuilder(
                                    animation: animation,
                                    builder: (context, animatedChild) {
                                      final isIncoming =
                                          animatedChild?.key ==
                                          widget.collapsedContent.key;
                                      final direction = isIncoming
                                          ? _contentSwitchDirection
                                          : -_contentSwitchDirection;
                                      return FractionalTranslation(
                                        translation: Offset(
                                          0.08 *
                                              direction *
                                              (1 - animation.value),
                                          0,
                                        ),
                                        child: animatedChild,
                                      );
                                    },
                                    child: child,
                                  ),
                                );
                              },
                              child: widget.collapsedContent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: IgnorePointer(
                    ignoring: progress < 0.5,
                    child: Opacity(
                      key: const ValueKey(
                        'poster_browse_landscape_expand_handle',
                      ),
                      opacity: progress,
                      child: Container(
                        width: 72,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? details.delta.dy;
    _collapseController.value =
        (_collapseController.value + delta / _dragExtent).clamp(0.0, 1.0);
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dy;
    final collapse = velocity.abs() > _velocityThreshold
        ? velocity > 0
        : _collapseController.value >= 0.45;
    _collapseController.animateTo(
      collapse ? 1 : 0,
      duration: _settleDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _notifyCollapseProgress() {
    widget.onCollapseProgressChanged?.call(_collapseController.value);
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    _horizontalSettleGeneration += 1;
    _horizontalDragDistance = 0;
    // 打断进行中的惯性/吸附动画，避免和新拖动叠加；起点取当前实际偏移。
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.offset);
    }
    _horizontalDragStartOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? details.delta.dx;
    _horizontalDragDistance += delta;
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final target = (_horizontalDragStartOffset - _horizontalDragDistance)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _scrollController.jumpTo(target);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dx;
    // 展开态快甩：交给轨道惯性滚动，一次快甩可以横跨多张海报，落点吸附
    // 最近条目并把焦点跟过去。收起态保持"每次滑动切一部"的手感。
    if (_collapseController.value < 0.5 &&
        velocity.abs() > _browseFlingVelocity) {
      unawaited(_settleAfterFling(velocity));
      return;
    }
    final shouldMove =
        velocity.abs() > _horizontalVelocityThreshold ||
        _horizontalDragDistance.abs() >= _horizontalDistanceThreshold;
    var targetIndex = _safeFocusedIndex;
    if (shouldMove) {
      final moveForward = velocity.abs() > _horizontalVelocityThreshold
          ? velocity < 0
          : _horizontalDragDistance < 0;
      targetIndex += moveForward ? 1 : -1;
      targetIndex = targetIndex.clamp(0, widget.items.length - 1);
    }
    _settleHorizontalDrag(targetIndex);
  }

  void _handleHorizontalDragCancel() {
    _settleHorizontalDrag(_safeFocusedIndex);
  }

  /// 快甩惯性：按松手速度投影落点，吸附最近条目，焦点随落点切换。
  Future<void> _settleAfterFling(double velocity) async {
    if (!_scrollController.hasClients) return;
    final generation = ++_horizontalSettleGeneration;
    final currentOffset = _scrollController.offset;
    final projected = currentOffset - velocity * _flingProjectionTime;
    final targetIndex = (projected / _itemExtent).round().clamp(
      0,
      widget.items.length - 1,
    );
    await _animateToIndex(
      targetIndex,
      duration: _flingSettleDuration(targetIndex, currentOffset),
    );
    if (!mounted || generation != _horizontalSettleGeneration) return;
    if (targetIndex != _safeFocusedIndex) {
      widget.onItemTap(targetIndex);
    }
  }

  /// 跨越的条目越多，吸附动画越长，快甩远滑时不会显得戛然而止。
  Duration _flingSettleDuration(int targetIndex, double currentOffset) {
    final distanceItems =
        ((targetIndex * _itemExtent - currentOffset).abs() / _itemExtent);
    final milliseconds = (240 + 90 * distanceItems).clamp(240.0, 720.0);
    return Duration(milliseconds: milliseconds.round());
  }

  Future<void> _settleHorizontalDrag(int targetIndex) async {
    final generation = ++_horizontalSettleGeneration;
    await _animateToIndex(targetIndex);
    if (!mounted || generation != _horizontalSettleGeneration) return;
    if (targetIndex != _safeFocusedIndex) {
      widget.onItemTap(targetIndex);
    }
  }

  Future<void> _animateToIndex(int index, {Duration? duration}) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (index * _itemExtent)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    await _scrollController.animateTo(
      target,
      duration: duration ?? _horizontalSettleDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _scheduleFocusedItemSync({required bool jump}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = (_safeFocusedIndex * _itemExtent)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: _horizontalSettleDuration,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  int get _safeFocusedIndex {
    if (widget.items.isEmpty) return 0;
    return widget.focusedIndex.clamp(0, widget.items.length - 1);
  }

  double get _itemExtent => widget.cardWidth + widget.itemSpacing;

  String? _focusedItemId(PosterBrowseLandscapeGesturePanel panel) {
    if (panel.items.isEmpty) return null;
    final index = panel.focusedIndex.clamp(0, panel.items.length - 1);
    return panel.items[index].card.id;
  }
}
