import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/detail_presentation.dart';

class DetailLoadingSkeleton extends StatelessWidget {
  final DetailPresentation presentation;

  const DetailLoadingSkeleton({
    super.key,
    this.presentation = DetailPresentation.page,
  });

  bool get _isPane => presentation == DetailPresentation.pane;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final fill = Color.alphaBlend(
      colors.surfaceStrong.withValues(alpha: 0.48),
      colors.backgroundBase,
    );
    final subtle = Color.alphaBlend(
      colors.surfaceSubtle.withValues(alpha: 0.42),
      colors.backgroundBase,
    );
    final line = Color.alphaBlend(
      colors.textMuted.withValues(alpha: 0.18),
      colors.backgroundBase,
    );
    const pad = DetailTokens.screenHorizontalPadding;
    final buttonHeight = _isPane ? 48.0 : 56.0;
    final topReserve = media.padding.top + 12 + DetailTokens.topButtonSize + 8;
    final heroBottomPadding = _isPane ? 12.0 : 20.0;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final minHero = _isPane
              ? _SkeletonMetrics.paneMinHero
              : _SkeletonMetrics.pageMinHero;
          final maxHero = _isPane
              ? _SkeletonMetrics.paneMaxHero
              : _SkeletonMetrics.pageMaxHero;
          final preferredHero = math.min(height * 0.38, width / 1.36);
          final heroHeight = math
              .min(
                math.max(0, height - _bodyReserve),
                math.max(minHero, math.min(preferredHero, maxHero)),
              )
              .toDouble();
          final bodyHeight = math
              .min(_bodyReserve, math.max(0, height - heroHeight))
              .toDouble();
          final bodyWidth = width - pad * 2;
          final desiredPosterWidth = (width * (_isPane ? 0.24 : 0.30)).clamp(
            120.0,
            _isPane ? 150.0 : 180.0,
          );
          final availablePosterHeight = math.max(
            0,
            heroHeight - topReserve - heroBottomPadding - 1,
          );
          final posterHeight = math
              .min(desiredPosterWidth * 1.45, availablePosterHeight)
              .toDouble();
          final posterWidth = math
              .min(desiredPosterWidth, posterHeight / 1.45)
              .toDouble();
          final textZoneWidth = bodyWidth - posterWidth - 16;
          final titleWidth = textZoneWidth * 0.88;
          final metaWidth = textZoneWidth;

          return Column(
            children: [
              Container(
                key: const ValueKey('detail-skeleton-hero'),
                height: heroHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      fill,
                      Color.alphaBlend(
                        colors.overlayScrim.withValues(alpha: 0.16),
                        colors.backgroundBase,
                      ),
                      colors.backgroundBase,
                    ],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  pad,
                  topReserve,
                  pad,
                  heroBottomPadding,
                ),
                child: LayoutBuilder(
                  builder: (context, heroConstraints) {
                    if (heroConstraints.maxHeight < _heroContentMinHeight) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      key: const ValueKey('detail-skeleton-hero-content'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Poster card placeholder — matches the vertical poster
                            // beside the title in TvSeasonDetailPanel
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: _Bar(
                                width: posterWidth,
                                height: posterHeight,
                                color: fill,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Bar(
                                    width: titleWidth,
                                    height: _isPane ? 20 : 24,
                                    radius: 6,
                                    color: fill,
                                  ),
                                  const SizedBox(height: 10),
                                  _Bar(
                                    width: metaWidth,
                                    height: 14,
                                    radius: 7,
                                    color: line,
                                  ),
                                  const SizedBox(height: 6),
                                  _Bar(
                                    width: metaWidth * 0.52,
                                    height: 14,
                                    radius: 7,
                                    color: line,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(
                height: bodyHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(pad, 0, pad, 0),
                  child: LayoutBuilder(
                    builder: (context, bodyConstraints) {
                      if (bodyConstraints.maxHeight < _bodyReserve) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        key: const ValueKey('detail-skeleton-body-content'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: _isPane ? 18 : 24),
                          Row(
                            children: [
                              Expanded(
                                child: _Bar(
                                  height: buttonHeight,
                                  radius: buttonHeight / 2,
                                  color: subtle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              _Circle(size: _isPane ? 48.0 : 56.0, color: fill),
                              const SizedBox(width: 10),
                              _Circle(size: _isPane ? 48.0 : 56.0, color: fill),
                              const SizedBox(width: 10),
                              _Circle(size: _isPane ? 48.0 : 56.0, color: fill),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _Bar(
                            width: bodyWidth * 0.92,
                            height: 12,
                            radius: 6,
                            color: line,
                          ),
                          const SizedBox(height: 8),
                          _Bar(
                            width: bodyWidth * 0.64,
                            height: 12,
                            radius: 6,
                            color: line,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Expanded(child: ColoredBox(color: colors.backgroundBase)),
            ],
          );
        },
      ),
    );
  }

  double get _bodyReserve => _isPane
      ? _SkeletonMetrics.paneBodyReserve
      : _SkeletonMetrics.pageBodyReserve;

  double get _heroContentMinHeight => _isPane
      ? _SkeletonMetrics.paneHeroContentHeight
      : _SkeletonMetrics.pageHeroContentHeight;
}

class _SkeletonMetrics {
  static const pageMinHero = 300.0;
  static const pageMaxHero = 560.0;
  static const paneMinHero = 220.0;
  static const paneMaxHero = 380.0;
  static const pageBodyReserve = 130.0;
  static const paneBodyReserve = 116.0;
  static const pageHeroContentHeight = 68.0;
  static const paneHeroContentHeight = 64.0;
}

class _Bar extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final Color color;
  const _Bar({
    this.width,
    required this.height,
    this.radius = 0,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = radius > 0
        ? BoxDecoration(
            color: color,
            borderRadius: BorderRadius.all(Radius.circular(radius)),
          )
        : BoxDecoration(color: color);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(decoration: decoration),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final Color color;
  const _Circle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
