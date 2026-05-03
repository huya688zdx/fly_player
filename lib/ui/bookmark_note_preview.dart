import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

class BookmarkNotePreview extends StatefulWidget {
  final String note;
  final int collapsedMaxLines;

  const BookmarkNotePreview({
    super.key,
    required this.note,
    this.collapsedMaxLines = 2,
  });

  @override
  State<BookmarkNotePreview> createState() => _BookmarkNotePreviewState();
}

class _BookmarkNotePreviewState extends State<BookmarkNotePreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final note = widget.note.trim();
    if (note.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final showToggle = note.runes.length > 28;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          note,
          maxLines: _expanded ? null : widget.collapsedMaxLines,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            height: 1.45,
          ),
        ),
        if (showToggle)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _expanded ? l10n.bookmarkNoteCollapse : l10n.bookmarkNoteExpand,
            ),
          ),
      ],
    );
  }
}
