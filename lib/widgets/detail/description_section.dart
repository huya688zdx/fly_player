import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../ui/adaptive_text.dart';

class DescriptionSection extends StatefulWidget {
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
  State<DescriptionSection> createState() => _DescriptionSectionState();
}

class _DescriptionSectionState extends State<DescriptionSection> {
  // 仅缓存截断结果；颜色变化和回调更新仍使用本次 build 的值。
  (String, double, int, double, String)? _layoutKey;
  bool _overflowed = false;
  String _clipped = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final content = widget.text.trim().isEmpty
        ? l10n.detailOverviewEmpty
        : widget.text;
    final descSize = AdaptiveText.roleSize(
      widget.baseFontSize,
      role: AdaptiveFontRole.body,
    );
    final textStyle = TextStyle(
      color: colors.textSecondary,
      fontSize: descSize,
      height: 1.35,
    );
    final moreStyle = textStyle.copyWith(
      color: colors.link,
      fontWeight: FontWeight.w600,
    );
    final normalized = content.replaceAll('\n', ' ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || width <= 0) {
          return Text(normalized, style: textStyle);
        }

        const suffix = '... ';
        final more = l10n.bookmarkNoteExpand;
        final key = (normalized, width, widget.maxLines, descSize, more);
        if (_layoutKey != key) {
          final painter = TextPainter(
            text: TextSpan(text: normalized, style: textStyle),
            maxLines: widget.maxLines,
            textDirection: TextDirection.ltr,
          );
          try {
            painter.layout(maxWidth: width);
            _overflowed = painter.didExceedMaxLines;
            var low = 0;
            var high = normalized.length;
            var best = 0;
            while (_overflowed && low <= high) {
              final mid = (low + high) >> 1;
              final candidate = normalized.substring(0, mid).trimRight();
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
            _clipped = normalized.substring(0, best).trimRight();
            _layoutKey = key;
          } finally {
            painter.dispose();
          }
        }

        if (!_overflowed) {
          return Text(normalized, style: textStyle);
        }

        return RichText(
          maxLines: widget.maxLines,
          overflow: TextOverflow.clip,
          text: TextSpan(
            style: textStyle,
            children: [
              TextSpan(text: _clipped),
              const TextSpan(text: suffix),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onMoreTap,
                  child: Text(more, style: moreStyle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
