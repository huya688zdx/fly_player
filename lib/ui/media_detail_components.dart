import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_transitions.dart';

class DetailHeroImage extends StatefulWidget {
  final List<String> urls;
  final String token;
  final BoxFit fit;

  const DetailHeroImage({
    super.key,
    required this.urls,
    required this.token,
    this.fit = BoxFit.cover,
  });

  @override
  State<DetailHeroImage> createState() => _DetailHeroImageState();
}

class _DetailHeroImageState extends State<DetailHeroImage> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant DetailHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlsChanged = !listEquals(oldWidget.urls, widget.urls);
    final tokenChanged = oldWidget.token != widget.token;
    if (urlsChanged || tokenChanged) _index = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty || _index >= widget.urls.length) {
      return _buildPlaceholder();
    }
    final url = widget.urls[_index];
    final isLocal = _isLocalImageSource(url);
    if (!isLocal && widget.token.trim().isEmpty) {
      return _buildPlaceholder();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final cacheW = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(120, 1600)
            : null;
        final cacheH = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * dpr).round().clamp(120, 2400)
            : null;
        return AppTransitions.crossFadeSwitch(
          switchKey: 'detail-hero-$url',
          duration: AppTransitions.contentSwitchDuration,
          alignment: Alignment.center,
          child: isLocal
              ? Image.file(
                  File(_localImagePath(url)),
                  key: ValueKey<String>(url),
                  fit: widget.fit,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  cacheWidth: cacheW,
                  cacheHeight: cacheH,
                  errorBuilder: (_, error, ___) =>
                      _fallbackOrPlaceholder(currentUrl: url, error: error),
                )
              : Image.network(
                  url,
                  key: ValueKey<String>(url),
                  fit: widget.fit,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  cacheWidth: cacheW,
                  cacheHeight: cacheH,
                  headers: {
                    'Authorization': widget.token,
                    'Trim-MC-token': widget.token,
                  },
                  errorBuilder: (_, error, ___) =>
                      _fallbackOrPlaceholder(currentUrl: url, error: error),
                ),
        );
      },
    );
  }

  Widget _fallbackOrPlaceholder({
    required String currentUrl,
    required Object error,
  }) {
    if (_index + 1 < widget.urls.length) {
      final nextUrl = widget.urls[_index + 1];
      debugPrint(
        '[IMG][DETAIL_HERO] failed url=$currentUrl error=$error -> fallback=$nextUrl',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index += 1);
      });
      return const SizedBox.expand();
    }
    debugPrint(
      '[IMG][DETAIL_HERO] failed url=$currentUrl error=$error -> no_more_fallback',
    );
    return _buildPlaceholder();
  }

  bool _isLocalImageSource(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'file') return true;
    if (trimmed.startsWith('/')) return true;
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed);
  }

  String _localImagePath(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'file') return uri!.toFilePath();
    return trimmed;
  }

  Widget _buildPlaceholder() {
    const fallback = AppThemePalette.fallback;
    return Container(
      color: fallback.surfaceSubtle,
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 28,
          color: fallback.textMuted.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class DetailPrimaryPlayButton extends StatelessWidget {
  final String text;
  final String? textSwitchKey;
  final TextStyle? textStyle;
  final bool enabled;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool useCircularPlayIcon;

  const DetailPrimaryPlayButton({
    super.key,
    required this.text,
    this.textSwitchKey,
    this.textStyle,
    this.enabled = true,
    this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.useCircularPlayIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolvedBackgroundColor = backgroundColor ?? colors.accent;
    final resolvedForegroundColor = foregroundColor ?? colors.textPrimary;
    final resolvedTextStyle =
        (textStyle ??
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))
            .copyWith(color: resolvedForegroundColor);
    final label = Text(text, style: resolvedTextStyle);
    final animatedLabel = textSwitchKey == null
        ? label
        : AppTransitions.crossFadeSwitch(
            switchKey: textSwitchKey!,
            duration: AppTransitions.switchDuration,
            alignment: Alignment.centerLeft,
            child: KeyedSubtree(
              key: ValueKey<String>(textSwitchKey!),
              child: label,
            ),
          );

    return FilledButton(
      onPressed: enabled ? onTap ?? () {} : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: resolvedBackgroundColor,
        foregroundColor: resolvedForegroundColor,
        disabledBackgroundColor: resolvedBackgroundColor.withValues(
          alpha: 0.32,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (useCircularPlayIcon)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/play.svg',
                  width: 11,
                  height: 11,
                  colorFilter: ColorFilter.mode(
                    resolvedBackgroundColor,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            )
          else
            SvgPicture.asset(
              'assets/icons/play.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(
                resolvedForegroundColor,
                BlendMode.srcIn,
              ),
            ),
          const SizedBox(width: 8),
          animatedLabel,
        ],
      ),
    );
  }
}

class DetailRoundIconButton extends StatelessWidget {
  final String asset;
  final String? selectedAsset;
  final bool selected;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final Color? selectedBackgroundColor;
  final Color? selectedBorderColor;
  final Color? selectedIconColor;

  const DetailRoundIconButton({
    super.key,
    required this.asset,
    this.selectedAsset,
    this.selected = false,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.iconColor,
    this.selectedBackgroundColor,
    this.selectedBorderColor,
    this.selectedIconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final iconAsset = selected && selectedAsset != null
        ? selectedAsset!
        : asset;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: selected
              ? (selectedBackgroundColor ?? colors.selection)
              : (backgroundColor ??
                    colors.backgroundElevated.withValues(alpha: 0.82)),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: selected
                ? (selectedBorderColor ?? colors.selection)
                : (borderColor ?? colors.borderStrong),
          ),
        ),
        child: Center(
          child: SvgPicture.asset(
            iconAsset,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              selected
                  ? (selectedIconColor ?? colors.textPrimary)
                  : (iconColor ?? colors.textPrimary),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}

class DetailActionBar extends StatelessWidget {
  final String primaryText;
  final bool primaryEnabled;
  final bool liked;
  final bool watched;

  const DetailActionBar({
    super.key,
    required this.primaryText,
    required this.primaryEnabled,
    required this.liked,
    required this.watched,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DetailPrimaryPlayButton(
            text: primaryText,
            enabled: primaryEnabled,
          ),
        ),
        const SizedBox(width: 12),
        DetailRoundIconButton(asset: 'assets/icons/heart.svg', selected: liked),
        const SizedBox(width: 10),
        const DetailRoundIconButton(asset: 'assets/icons/download.svg'),
        const SizedBox(width: 10),
        DetailRoundIconButton(
          asset: 'assets/icons/watched.svg',
          selectedAsset: 'assets/icons/watched_selected.svg',
          selected: watched,
        ),
      ],
    );
  }
}

class DetailTagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool hasDropdown;
  final bool compact;

  const DetailTagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.hasDropdown = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: compact ? 28 : 36,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: selected ? colors.selectionSoft : colors.chipBackground,
        borderRadius: BorderRadius.circular(compact ? 9 : 12),
        border: Border.all(
          color: selected ? colors.selection : colors.chipBorder,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? colors.selectionStrong : colors.chipText,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasDropdown) ...[
            SizedBox(width: compact ? 4 : 6),
            Icon(
              Icons.keyboard_arrow_down,
              size: compact ? 14 : 16,
              color: colors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

class DetailOverview extends StatelessWidget {
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  const DetailOverview({
    super.key,
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final value = text.trim().isEmpty ? l10n.detailOverviewEmpty : text;
    return GestureDetector(
      onTap: onToggle,
      child: Text(
        expanded ? value : value.replaceAll('\n', ' '),
        maxLines: expanded ? null : 3,
        overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: TextStyle(color: colors.textSecondary, fontSize: 16),
      ),
    );
  }
}
