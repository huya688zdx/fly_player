import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final useBlur = enableBlur && !isAndroid;
    return ClipRRect(
      borderRadius: DetailTokens.glassPanelRadius,
      child: Stack(
        children: [
          if (useBlur)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: const SizedBox.expand(),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.78),
                    Colors.black.withValues(alpha: 0.90),
                  ],
                  stops: const [0.0, 0.58, 1.0],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                ),
              ),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}
