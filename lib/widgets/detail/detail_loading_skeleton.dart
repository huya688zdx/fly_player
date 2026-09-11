import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/detail_presentation.dart';
import 'detail_status_page.dart';

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
    final fill = colors.textMuted.withValues(alpha: 0.16);
    final subtle = colors.selectionSoft.withValues(alpha: 0.22);
    final line = colors.textMuted.withValues(alpha: 0.20);
    const pad = DetailTokens.screenHorizontalPadding;
    final buttonHeight = _isPane ? 40.0 : 44.0;
    final topReserve = media.padding.top + 12 + DetailTokens.topButtonSize + 8;
    final heroBottomPadding = _isPane ? 12.0 : 20.0;

    return DetailStatusPage(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: colors.selectionStrong,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            AppLocalizations.of(context).commonLoading,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final contentWidth = math.min(width, 640.0);
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
          final bodyWidth = math.max(0, contentWidth - pad * 2);
          final desiredPosterWidth = (contentWidth * (_isPane ? 0.22 : 0.26))
              .clamp(120.0, _isPane ? 144.0 : 168.0);
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
          final textZoneWidth = math.max(0, bodyWidth - posterWidth - 20);
          final titleWidth = textZoneWidth * 0.72;
          final metaWidth = textZoneWidth * 0.82;

          return Column(
            children: [
              SizedBox(
                key: const ValueKey('detail-skeleton-hero'),
                height: heroHeight,
                child: Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        pad,
                        topReserve,
                        pad,
                        heroBottomPadding,
                      ),
                      child: LayoutBuilder(
                        builder: (context, heroConstraints) {
                          if (heroConstraints.maxHeight <
                              _heroContentMinHeight) {
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
                                  // 贴近真实详情页的海报轮廓，避免整页大色块。
                                  _Bar(
                                    width: posterWidth,
                                    height: posterHeight,
                                    radius: 16,
                                    color: fill,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _Bar(
                                          width: titleWidth,
                                          height: _isPane ? 18 : 22,
                                          radius: 6,
                                          color: fill,
                                        ),
                                        const SizedBox(height: 12),
                                        _Bar(
                                          width: metaWidth,
                                          height: 10,
                                          radius: 5,
                                          color: line,
                                        ),
                                        const SizedBox(height: 8),
                                        _Bar(
                                          width: metaWidth * 0.56,
                                          height: 10,
                                          radius: 5,
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
                  ),
                ),
              ),
              SizedBox(
                height: bodyHeight,
                child: Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: pad),
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
                                  Flexible(
                                    child: _Bar(
                                      width: _isPane ? 136 : 152,
                                      height: buttonHeight,
                                      radius: buttonHeight / 2,
                                      color: subtle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  _Bar(
                                    width: _isPane ? 58 : 64,
                                    height: _isPane ? 30 : 32,
                                    radius: 16,
                                    color: fill,
                                  ),
                                  const SizedBox(width: 8),
                                  _Bar(
                                    width: _isPane ? 52 : 58,
                                    height: _isPane ? 30 : 32,
                                    radius: 16,
                                    color: fill,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _Bar(
                                width: bodyWidth * 0.82,
                                height: 10,
                                radius: 5,
                                color: line,
                              ),
                              const SizedBox(height: 8),
                              _Bar(
                                width: bodyWidth * 0.54,
                                height: 10,
                                radius: 5,
                                color: line,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
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
