import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/detail_presentation.dart';
import '../../utils/detail_layout_solver.dart';
import 'detail_status_page.dart';

class DetailLoadingSkeleton extends StatelessWidget {
  final DetailPresentation presentation;

  /// 桌面季详情保留竖海报，单集详情使用横幅标题；移动端布局不受影响。
  final bool showPoster;

  const DetailLoadingSkeleton({
    super.key,
    this.presentation = DetailPresentation.page,
    this.showPoster = true,
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
          if (DetailLayoutSolver.usesDesktopLayout(width)) {
            return _buildDesktop(
              context,
              Size(width, height),
              fill,
              subtle,
              line,
            );
          }
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

  Widget _buildDesktop(
    BuildContext context,
    Size size,
    Color fill,
    Color subtle,
    Color line,
  ) {
    final horizontal = DetailLayoutSolver.horizontalPadding(size.width);
    final bodyWidth = size.width - horizontal * 2;
    const posterWidth = DetailLayoutSolver.desktopPosterWidth;
    const posterHeight = posterWidth * 1.45;
    final headerTop = DetailLayoutSolver.desktopSeasonHeaderTop(
      size,
      MediaQuery.paddingOf(context).top,
    );
    final textWidth = showPoster ? bodyWidth - posterWidth - 28 : bodyWidth;
    final actions = SizedBox(
      key: const ValueKey('detail-skeleton-actions'),
      width: DetailLayoutSolver.desktopActionWidth,
      child: Row(
        children: [
          Expanded(child: _Bar(height: 56, radius: 28, color: subtle)),
          const SizedBox(width: 12),
          _Bar(width: 56, height: 56, radius: 28, color: fill),
          const SizedBox(width: 10),
          _Bar(width: 56, height: 56, radius: 28, color: fill),
          if (!showPoster) ...[
            const SizedBox(width: 10),
            _Bar(width: 56, height: 56, radius: 28, color: fill),
          ],
        ],
      ),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!showPoster) ...[
          _Bar(width: textWidth * 0.36, height: 14, radius: 5, color: line),
          const SizedBox(height: 12),
        ],
        _Bar(width: textWidth * 0.64, height: 32, radius: 6, color: fill),
        if (showPoster) ...[
          const SizedBox(height: 18),
          _Bar(width: textWidth * 0.36, height: 16, radius: 5, color: line),
          const SizedBox(height: 12),
          _Bar(width: textWidth * 0.24, height: 12, radius: 5, color: line),
          const SizedBox(height: 20),
          actions,
        ],
      ],
    );
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            key: const ValueKey('detail-skeleton-hero'),
            height: showPoster
                ? headerTop + posterHeight + 24
                : DetailLayoutSolver.desktopHeroHeight(size),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: showPoster
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            key: const ValueKey('detail-skeleton-poster'),
                            width: posterWidth,
                            height: posterHeight,
                            child: _Bar(
                              height: posterHeight,
                              radius: 18,
                              color: fill,
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(child: title),
                        ],
                      )
                    : title,
              ),
            ),
          ),
          if (!showPoster) ...[
            _Bar(width: bodyWidth * 0.30, height: 14, radius: 5, color: line),
            const SizedBox(height: 8),
            _Bar(width: bodyWidth * 0.24, height: 14, radius: 5, color: line),
            const SizedBox(height: 16),
            if (bodyWidth >= DetailLayoutSolver.desktopInlineControlsWidth)
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Bar(
                        width: 240,
                        height: 16,
                        radius: 5,
                        color: line,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  actions,
                ],
              )
            else
              actions,
            const SizedBox(height: 24),
          ],
          _Bar(width: bodyWidth * 0.90, height: 12, radius: 5, color: line),
          const SizedBox(height: 12),
          _Bar(width: bodyWidth * 0.68, height: 12, radius: 5, color: line),
          const SizedBox(height: 32),
          _Bar(width: 96, height: 24, radius: 5, color: fill),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < (showPoster ? 4 : 2); i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: showPoster ? 16 / 9 : 3.5,
                        child: _Bar(height: 112, radius: 12, color: fill),
                      ),
                      const SizedBox(height: 12),
                      _Bar(height: 12, radius: 5, color: line),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),
        ],
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
