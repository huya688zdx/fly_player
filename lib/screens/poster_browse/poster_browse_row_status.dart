import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import 'poster_browse_rows.dart';

class PosterBrowseRowStatus extends StatelessWidget {
  final PosterBrowseRow? row;
  final VoidCallback onRetry;

  const PosterBrowseRowStatus({
    super.key,
    required this.row,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: switch (row?.loadState) {
        PosterBrowseRowLoadState.failed => Semantics(
          button: true,
          child: TextButton(
            onPressed: onRetry,
            child: Text(
              l10n.posterBrowseLoadFailed,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
        PosterBrowseRowLoadState.loaded => Text(
          l10n.posterBrowseCatalogEmpty,
          style: const TextStyle(color: Colors.white70),
        ),
        _ => const CircularProgressIndicator(
          key: ValueKey('poster_browse_row_loading'),
        ),
      },
    );
  }
}
