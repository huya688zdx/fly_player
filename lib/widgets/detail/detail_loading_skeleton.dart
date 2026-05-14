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
    final size = media.size;
    final heroHeight = math
        .min(size.height * 0.38, size.width / 1.36)
        .clamp(_isPane ? 220.0 : 300.0, _isPane ? 380.0 : 560.0)
        .toDouble();
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
    final pad = DetailTokens.screenHorizontalPadding;
    final buttonHeight = _isPane ? 48.0 : 56.0;
    final topReserve = media.padding.top + 12 + DetailTokens.topButtonSize + 8;
    final bodyWidth = size.width - pad * 2;
    // Poster card: matches tv_season_detail_page / TvSeasonDetailPanel
    final posterWidth = (size.width * (_isPane ? 0.24 : 0.30))
        .clamp(120.0, _isPane ? 150.0 : 180.0);
    final posterHeight = posterWidth * 1.45;
    // Fill remaining space beside poster
    final textZoneWidth = bodyWidth - posterWidth - 16;
    final titleWidth = textZoneWidth * 0.88;
    final metaWidth1 = textZoneWidth;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Container(
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
                  pad, topReserve, pad, _isPane ? 12 : 20,
                ),
                child: Column(
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
                              _Bar(width: titleWidth, height: _isPane ? 20 : 24, radius: 6, color: fill),
                              const SizedBox(height: 10),
                              _Bar(width: metaWidth1, height: 14, radius: 7, color: line),
                              const SizedBox(height: 6),
                              _Bar(width: metaWidth1 * 0.52, height: 14, radius: 7, color: line),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                child: Column(
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
                    _Bar(width: bodyWidth * 0.92, height: 12, radius: 6, color: line),
                    const SizedBox(height: 8),
                    _Bar(width: bodyWidth * 0.64, height: 12, radius: 6, color: line),
                  ],
                ),
              ),
              Expanded(child: ColoredBox(color: colors.backgroundBase)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final Color color;
  const _Bar({this.width, required this.height, this.radius = 0, required this.color});

  @override
  Widget build(BuildContext context) {
    final decoration = radius > 0
        ? BoxDecoration(
            color: color,
            borderRadius: BorderRadius.all(Radius.circular(radius)),
          )
        : BoxDecoration(color: color);
    return SizedBox(
      width: width, height: height,
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
      width: size, height: size,
      child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}
