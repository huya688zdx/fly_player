import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../theme/detail_tokens.dart';
import '../../ui/adaptive_text.dart';

class DescriptionSection extends StatelessWidget {
  final String text;
  final VoidCallback onMoreTap;
  final int maxLines;
  final double baseFontSize;

  const DescriptionSection({
    super.key,
    required this.text,
    required this.onMoreTap,
    this.maxLines = 4,
    this.baseFontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final content = text.trim().isEmpty ? '\u6682\u65E0\u7B80\u4ECB' : text;
    final descSize = AdaptiveText.roleSize(
      baseFontSize,
      role: AdaptiveFontRole.body,
    );
    final textStyle = TextStyle(
      color: DetailTokens.textSecondary,
      fontSize: descSize,
      height: 1.35,
    );
    final moreStyle = textStyle.copyWith(
      color: const Color(0xFF2D87FF),
      fontWeight: FontWeight.w600,
    );
    final normalized = content.replaceAll('\n', ' ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || width <= 0) {
          return Text(normalized, style: textStyle);
        }

        final overflowProbe = TextPainter(
          text: TextSpan(text: normalized, style: textStyle),
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);

        if (!overflowProbe.didExceedMaxLines) {
          return Text(normalized, style: textStyle);
        }

        const suffix = '... ';
        const more = '\u66F4\u591A';
        final maxChars = normalized.length;
        var low = 0;
        var high = maxChars;
        var best = 0;

        while (low <= high) {
          final mid = (low + high) >> 1;
          final candidate = normalized.substring(0, mid).trimRight();
          final painter = TextPainter(
            text: TextSpan(
              style: textStyle,
              children: const [TextSpan(text: '')],
            ),
            maxLines: maxLines,
            textDirection: TextDirection.ltr,
          );
          painter.text = TextSpan(
            style: textStyle,
            children: [
              TextSpan(text: candidate),
              const TextSpan(text: suffix),
              TextSpan(text: more, style: moreStyle),
            ],
          );
          painter.layout(maxWidth: width);
          if (painter.didExceedMaxLines) {
            high = mid - 1;
          } else {
            best = mid;
            low = mid + 1;
          }
        }

        final clipped = normalized.substring(0, best).trimRight();
        return RichText(
          maxLines: maxLines,
          overflow: TextOverflow.clip,
          text: TextSpan(
            style: textStyle,
            children: [
              TextSpan(text: clipped),
              const TextSpan(text: suffix),
              TextSpan(
                text: more,
                style: moreStyle,
                recognizer: TapGestureRecognizer()..onTap = onMoreTap,
              ),
            ],
          ),
        );
      },
    );
  }
}
