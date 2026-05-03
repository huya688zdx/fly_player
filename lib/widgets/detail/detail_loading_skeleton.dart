import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
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
        .min(size.height * 0.36, size.width / 1.36)
        .clamp(_isPane ? 220.0 : 260.0, _isPane ? 380.0 : 460.0)
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
              ),
              Expanded(child: ColoredBox(color: colors.backgroundBase)),
            ],
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, _isPane ? 8 : 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isPane)
                    _SkeletonBox(width: 44, height: 44, color: fill),
                  const Spacer(),
                  _SkeletonBox(
                    width: size.width * (_isPane ? 0.56 : 0.48),
                    height: _isPane ? 28 : 34,
                    color: fill,
                  ),
                  const SizedBox(height: 12),
                  _SkeletonBox(
                    width: size.width * 0.74,
                    height: 14,
                    color: line,
                  ),
                  const SizedBox(height: 8),
                  _SkeletonBox(
                    width: size.width * 0.46,
                    height: 14,
                    color: line,
                  ),
                  SizedBox(height: _isPane ? 22 : 30),
                  DecoratedBox(
                    decoration: BoxDecoration(color: colors.backgroundBase),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBox(
                          width: double.infinity,
                          height: _isPane ? 42 : 48,
                          color: subtle,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _SkeletonBox(height: 36, color: fill),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SkeletonBox(height: 36, color: fill),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _SkeletonBox(
                          width: size.width * 0.88,
                          height: 12,
                          color: line,
                        ),
                        const SizedBox(height: 8),
                        _SkeletonBox(
                          width: size.width * 0.78,
                          height: 12,
                          color: line,
                        ),
                        const SizedBox(height: 8),
                        _SkeletonBox(
                          width: size.width * 0.64,
                          height: 12,
                          color: line,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: media.padding.bottom + 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final Color color;

  const _SkeletonBox({this.width, required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
