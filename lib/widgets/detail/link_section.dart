import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

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
          '\u94fe\u63a5',
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.link,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
