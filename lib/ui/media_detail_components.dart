import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_image_request.dart';
import '../theme/app_theme.dart';
import '../widgets/common/liquid_glass.dart';
import 'app_transitions.dart';

class DetailHeroImage extends StatefulWidget {
  final MediaImageRequest images;
  final BoxFit fit;

  const DetailHeroImage({
    super.key,
    required this.images,
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
    final urlsChanged = !listEquals(oldWidget.images.urls, widget.images.urls);
    final headersChanged = !mapEquals(
      oldWidget.images.headers,
      widget.images.headers,
    );
    if (urlsChanged || headersChanged) _index = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.urls.isEmpty || _index >= widget.images.urls.length) {
      return _buildPlaceholder();
    }
    final url = widget.images.urls[_index];
    final isLocal = _isLocalImageSource(url);
    // 本地文件不需鉴权;网络图无鉴权(既无 header 也非自鉴权直链)时回退占位,
    // 判定语义由 MediaImageRequest.canLoad 统一承载(与 DetailHeroLogoTitle 同口径)。
    if (!isLocal && !widget.images.canLoad) {
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
        // cacheWidth/cacheHeight 双维同传会走 ResizeImagePolicy.exact 精确缩放
        // (不保比例),容器宽高比与源图不同时会把海报压扁;这里改用
        // ResizeImage + ResizeImagePolicy.fit,在限制框内等比缩放,交由外层
        // fit 负责裁剪/留白。
        ImageProvider provider = isLocal
            ? FileImage(File(_localImagePath(url)))
            : NetworkImage(url, headers: widget.images.headers);
        if (cacheW != null || cacheH != null) {
          provider = ResizeImage(
            provider,
            width: cacheW,
            height: cacheH,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          );
        }
        return AppTransitions.crossFadeSwitch(
          switchKey: 'detail-hero-$url',
          duration: AppTransitions.contentSwitchDuration,
          alignment: Alignment.center,
          child: isLocal
              ? Image(
                  image: provider,
                  key: ValueKey<String>(url),
                  fit: widget.fit,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (_, error, ___) =>
                      _fallbackOrPlaceholder(currentUrl: url, error: error),
                )
              : Image(
                  image: provider,
                  key: ValueKey<String>(url),
                  fit: widget.fit,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          child: child,
                        );
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
    if (_index + 1 < widget.images.urls.length) {
      final nextUrl = widget.images.urls[_index + 1];
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

    return SizedBox(
      height: 52,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            FilledButton(
              onPressed: enabled ? onTap ?? () {} : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: resolvedBackgroundColor,
                foregroundColor: resolvedForegroundColor,
                disabledBackgroundColor: resolvedBackgroundColor.withValues(
                  alpha: 0.32,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
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
            ),
            const IgnorePointer(child: LiquidGlassSheen(radius: 28)),
          ],
        ),
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
    return LiquidGlass(
      radius: 26,
      tone: selected ? LiquidGlassTone.accent : LiquidGlassTone.neutral,
      selected: selected,
      sheen: false,
      blurSigma: 16,
      onTap: onTap,
      child: SizedBox(
        width: 52,
        height: 52,
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
    return LiquidGlass(
      radius: compact ? 9 : 12,
      tone: selected ? LiquidGlassTone.accent : LiquidGlassTone.neutral,
      selected: selected,
      sheen: false,
      blurSigma: compact ? 12 : 14,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      child: SizedBox(
        height: compact ? 28 : 36,
        // 用 Row(min) 纵向居中，避免 Center 在松约束下横向撑满导致 chip 全宽换行。
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
