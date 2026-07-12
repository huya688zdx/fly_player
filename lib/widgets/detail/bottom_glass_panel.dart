import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';

class BottomGlassPanel extends StatelessWidget {
  final Widget child;
  final bool enableBlur;

  const BottomGlassPanel({
    super.key,
    required this.child,
    this.enableBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ClipRRect(
      borderRadius: DetailTokens.glassPanelRadius,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.surfaceStrong.withValues(alpha: 0.38),
                    colors.backgroundElevated.withValues(alpha: 0.82),
                    colors.backgroundBase.withValues(alpha: 0.94),
                  ],
                  stops: const [0.0, 0.58, 1.0],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.borderStrong, width: 1),
              ),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}
