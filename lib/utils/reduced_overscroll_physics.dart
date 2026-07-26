import 'package:flutter/widgets.dart';

/// Reduces overscroll at the top edge so pull-to-refresh requires a more
/// deliberate drag gesture.
class ReducedOverscrollPhysics extends BouncingScrollPhysics {
  /// Fraction of normal overscroll to allow when pulling down at the top.
  ///
  /// 0.5 means the user must pull ~2× as far to trigger the refresh indicator.
  final double topOverscrollFraction;

  const ReducedOverscrollPhysics({
    this.topOverscrollFraction = 0.5,
    super.parent,
  });

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      return (value - position.pixels) * topOverscrollFraction;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  ReducedOverscrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ReducedOverscrollPhysics(
      topOverscrollFraction: topOverscrollFraction,
      parent: buildParent(ancestor),
    );
  }
}
