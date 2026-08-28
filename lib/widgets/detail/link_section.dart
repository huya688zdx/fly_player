import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'detail_surface.dart';

class LinkSection extends StatelessWidget {
  final String imdbId;
  final String tmdbId;
  final VoidCallback? onImdbTap;
  final VoidCallback? onTmdbTap;

  const LinkSection({
    super.key,
    this.imdbId = '',
    this.tmdbId = '',
    this.onImdbTap,
    this.onTmdbTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImdb = imdbId.trim().isNotEmpty;
    final hasTmdb = tmdbId.trim().isNotEmpty;
    final colors = context.appColors;
    if (!hasImdb && !hasTmdb) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).detailLinksTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (hasImdb) _LinkButton(label: 'IMDB', onTap: onImdbTap),
            if (hasTmdb) _LinkButton(label: 'TMDB', onTap: onTmdbTap),
          ],
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _LinkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DetailSurface(
      key: ValueKey<String>('detail-link-surface-$label'),
      radius: 14,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: Text(
        label,
        style: TextStyle(
          color: colors.link,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
