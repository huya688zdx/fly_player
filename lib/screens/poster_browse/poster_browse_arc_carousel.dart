import 'package:flutter/material.dart';

import '../../media_backend/media_image_request.dart';
import 'poster_browse_display_item.dart';
import 'poster_browse_poster_card.dart';

class PosterBrowseArcTransform {
  final double horizontalOffset;
  final double verticalOffset;
  final double scale;
  final double rotation;
  final double opacity;
  final int zIndex;

  const PosterBrowseArcTransform({
    required this.horizontalOffset,
    required this.verticalOffset,
    required this.scale,
    required this.rotation,
    required this.opacity,
    required this.zIndex,
  });
}

abstract final class PosterBrowseArcMath {
  static const int visibleRadius = 3;

  static int realIndex(int virtualIndex, int length) {
    if (length <= 0) {
      return 0;
    }
    final modulo = virtualIndex % length;
    return modulo < 0 ? modulo + length : modulo;
  }

  static double spacingFor({
    required double viewportWidth,
    required double cardWidth,
  }) {
    final widthProgress = ((viewportWidth - 390) / (844 - 390)).clamp(0.0, 1.0);
    final ratio = 1.30 + widthProgress * 0.25;
    return (cardWidth * ratio).clamp(cardWidth + 24, 190).toDouble();
  }

  static PosterBrowseArcTransform transformFor(double delta) {
    final clampedDelta = delta.clamp(-visibleRadius, visibleRadius).toDouble();
    final distance = clampedDelta.abs();
    final direction = clampedDelta == 0 ? 0.0 : clampedDelta.sign;

    return PosterBrowseArcTransform(
      horizontalOffset: clampedDelta,
      verticalOffset: (distance * distance * 12 + distance * 8)
          .clamp(0.0, 132.0)
          .toDouble(),
      scale: (1 - distance * 0.11).clamp(0.68, 1.0).toDouble(),
      rotation: (direction * distance * 0.09).clamp(-0.34, 0.34).toDouble(),
      opacity: (1 - distance * 0.18).clamp(0.30, 1.0).toDouble(),
      zIndex: 1000 - (distance * 100).round(),
    );
  }
}

class PosterBrowseArcCarousel extends StatefulWidget {
  final List<PosterBrowseDisplayItem> items;
  final int initialIndex;
  final bool showProgress;
  final MediaImageRequest Function(PosterBrowseDisplayItem item) imageOf;
  final String Function(PosterBrowseDisplayItem item) secondaryLabelOf;
  final ValueChanged<int> onSettled;
  final ValueChanged<int> onCenteredTap;
  final double cardWidth;
  final double? spacing;

  const PosterBrowseArcCarousel({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.showProgress,
    required this.imageOf,
    required this.secondaryLabelOf,
    required this.onSettled,
    required this.onCenteredTap,
    this.cardWidth = 116,
    this.spacing,
  });

  @override
  State<PosterBrowseArcCarousel> createState() =>
      _PosterBrowseArcCarouselState();
}

class _PosterBrowseArcCarouselState extends State<PosterBrowseArcCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double>? _pageAnimation;
  double _page = 0;
  double _dragStartPage = 0;
  double? _animationTarget;
  bool _notifyWhenSettled = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex.toDouble();
    _dragStartPage = _page;
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 240),
          )
          ..addListener(_handleAnimationTick)
          ..addStatusListener(_handleAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant PosterBrowseArcCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.items.length != widget.items.length ||
        oldWidget.initialIndex != widget.initialIndex) {
      _controller.stop();
      _pageAnimation = null;
      _animationTarget = null;
      _notifyWhenSettled = false;
      _page = widget.initialIndex.toDouble();
      _dragStartPage = _page;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleAnimationTick)
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final spacing =
            widget.spacing ??
            PosterBrowseArcMath.spacingFor(
              viewportWidth: viewportWidth,
              cardWidth: widget.cardWidth,
            );
        final cards = _visibleCards();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.items.length > 1
              ? _handleDragStart
              : null,
          onHorizontalDragUpdate: widget.items.length > 1
              ? (details) => _handleDragUpdate(details, spacing)
              : null,
          onHorizontalDragEnd: widget.items.length > 1 ? _handleDragEnd : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: cards
                .map((card) => _buildPositionedCard(card, spacing))
                .toList(growable: false),
          ),
        );
      },
    );
  }

  List<_VisibleArcCard> _visibleCards() {
    if (widget.items.length == 1) {
      return <_VisibleArcCard>[
        _VisibleArcCard(virtualIndex: _page.round(), realIndex: 0, delta: 0),
      ];
    }

    final start = _page.floor() - PosterBrowseArcMath.visibleRadius;
    final end = _page.ceil() + PosterBrowseArcMath.visibleRadius;
    final byRealIndex = <int, _VisibleArcCard>{};
    final cards = <_VisibleArcCard>[];

    for (var virtualIndex = start; virtualIndex <= end; virtualIndex++) {
      final delta = virtualIndex - _page;
      final realIndex = PosterBrowseArcMath.realIndex(
        virtualIndex,
        widget.items.length,
      );
      final card = _VisibleArcCard(
        virtualIndex: virtualIndex,
        realIndex: realIndex,
        delta: delta,
      );

      if (widget.items.length <= 7) {
        final previous = byRealIndex[realIndex];
        if (previous == null || delta.abs() < previous.delta.abs()) {
          byRealIndex[realIndex] = card;
        }
      } else {
        cards.add(card);
      }
    }

    final uniqueCards = widget.items.length <= 7
        ? byRealIndex.values.toList(growable: false)
        : cards;
    uniqueCards.sort((a, b) {
      final z = a.transform.zIndex.compareTo(b.transform.zIndex);
      if (z != 0) {
        return z;
      }
      return a.delta.abs().compareTo(b.delta.abs());
    });
    return uniqueCards;
  }

  Widget _buildPositionedCard(_VisibleArcCard card, double spacing) {
    final item = widget.items[card.realIndex];
    final imageRequest = widget.imageOf(item);
    final transform = card.transform;
    final focused = card.delta.abs() < 0.35;

    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(
          transform.horizontalOffset * spacing,
          -transform.verticalOffset,
        ),
        child: Center(
          child: Opacity(
            opacity: transform.opacity,
            child: Transform.rotate(
              angle: transform.rotation,
              child: Transform.scale(
                scale: transform.scale,
                child: PosterBrowsePosterCard(
                  key: ValueKey('poster_browse_arc_card_${card.virtualIndex}'),
                  item: item,
                  focused: focused,
                  showProgress: widget.showProgress,
                  imageUrl: imageRequest.canLoad ? imageRequest.urls.first : '',
                  imageHeaders: imageRequest.headers,
                  secondaryLabel: widget.secondaryLabelOf(item),
                  width: widget.cardWidth,
                  onTap: () => _handleCardTap(card),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleDragStart(DragStartDetails details) {
    _controller.stop();
    _pageAnimation = null;
    _animationTarget = null;
    _notifyWhenSettled = false;
    _dragStartPage = _page;
  }

  void _handleDragUpdate(DragUpdateDetails details, double spacing) {
    final delta = details.primaryDelta ?? details.delta.dx;
    setState(() {
      _page -= delta / spacing;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dx;
    final target = velocity.abs() > 420
        ? _dragStartPage.round() + (velocity < 0 ? 1 : -1)
        : _page.round();
    _animateTo(target.toDouble(), notifyWhenSettled: true);
  }

  void _handleCardTap(_VisibleArcCard card) {
    if (card.delta.abs() < 0.35) {
      widget.onCenteredTap(card.realIndex);
      return;
    }
    _animateTo(card.virtualIndex.toDouble(), notifyWhenSettled: true);
  }

  void _animateTo(double target, {required bool notifyWhenSettled}) {
    _controller.stop();
    _animationTarget = target;
    _notifyWhenSettled = notifyWhenSettled;

    if ((_page - target).abs() < 0.001) {
      setState(() {
        _page = target;
      });
      if (notifyWhenSettled && widget.items.length > 1) {
        widget.onSettled(
          PosterBrowseArcMath.realIndex(target.round(), widget.items.length),
        );
      }
      return;
    }

    _pageAnimation = Tween<double>(
      begin: _page,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0);
  }

  void _handleAnimationTick() {
    final animation = _pageAnimation;
    if (animation == null || !mounted) {
      return;
    }
    setState(() {
      _page = animation.value;
    });
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    final target = _animationTarget;
    if (target == null) {
      return;
    }
    setState(() {
      _page = target;
    });
    if (_notifyWhenSettled && widget.items.length > 1) {
      widget.onSettled(
        PosterBrowseArcMath.realIndex(target.round(), widget.items.length),
      );
    }
    _pageAnimation = null;
    _animationTarget = null;
    _notifyWhenSettled = false;
  }
}

class _VisibleArcCard {
  final int virtualIndex;
  final int realIndex;
  final double delta;

  _VisibleArcCard({
    required this.virtualIndex,
    required this.realIndex,
    required this.delta,
  });

  PosterBrowseArcTransform get transform =>
      PosterBrowseArcMath.transformFor(delta);
}
