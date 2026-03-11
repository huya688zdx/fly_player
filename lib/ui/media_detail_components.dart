import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_transitions.dart';

class DetailHeroImage extends StatefulWidget {
  final List<String> urls;
  final String token;

  const DetailHeroImage({super.key, required this.urls, required this.token});

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
    if (widget.urls.isEmpty ||
        _index >= widget.urls.length ||
        widget.token.trim().isEmpty) {
      return _buildPlaceholder();
    }
    final url = widget.urls[_index];
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
          child: Image.network(
            url,
            key: ValueKey<String>(url),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            cacheWidth: cacheW,
            cacheHeight: cacheH,
            headers: {
              'Authorization': widget.token,
              'Trim-MC-token': widget.token,
            },
            errorBuilder: (_, error, ___) {
              if (_index + 1 < widget.urls.length) {
                final nextUrl = widget.urls[_index + 1];
                debugPrint(
                  '[IMG][DETAIL_HERO] failed url=$url error=$error -> fallback=$nextUrl',
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _index += 1);
                });
                return const SizedBox.expand();
              }
              debugPrint(
                '[IMG][DETAIL_HERO] failed url=$url error=$error -> no_more_fallback',
              );
              return _buildPlaceholder();
            },
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF1A2534),
      child: const Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 28,
          color: Color(0x7FA8B7CB),
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
    final label = Text(
      text,
      style:
          textStyle ??
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    );
    final animatedLabel = textSwitchKey == null
        ? label
        : AppTransitions.crossFadeSwitch(
            switchKey: textSwitchKey!,
            duration: AppTransitions.switchDuration,
            alignment: Alignment.centerLeft,
            child: KeyedSubtree(key: ValueKey<String>(textSwitchKey!), child: label),
          );

    return FilledButton(
      onPressed: enabled ? onTap ?? () {} : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: backgroundColor ?? const Color(0xFF2D87FF),
        foregroundColor: foregroundColor ?? Colors.white,
        disabledBackgroundColor: const Color(0x66385878),
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
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/play.svg',
                  width: 11,
                  height: 11,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF2D87FF),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            )
          else
            SvgPicture.asset('assets/icons/play.svg', width: 18, height: 18),
          const SizedBox(width: 8),
          animatedLabel,
        ],
      ),
    );
  }
}

class DetailRoundIconButton extends StatelessWidget {
  final String asset;
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: selected
              ? (selectedBackgroundColor ?? const Color(0xFF1F5EA7))
              : (backgroundColor ?? const Color(0xFF162233)),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: selected
                ? (selectedBorderColor ?? const Color(0x446E8DB1))
                : (borderColor ?? const Color(0x446E8DB1)),
          ),
        ),
        child: Center(
          child: SvgPicture.asset(
            asset,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              selected
                  ? (selectedIconColor ?? Colors.white)
                  : (iconColor ?? Colors.white),
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
          asset: 'assets/icons/check.svg',
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
    return Container(
      height: compact ? 28 : 36,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF15243A),
        borderRadius: BorderRadius.circular(compact ? 9 : 12),
        border: Border.all(
          color: selected ? const Color(0xFF2D87FF) : const Color(0x335D7392),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF5AA8FF) : Colors.white70,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasDropdown) ...[
            SizedBox(width: compact ? 4 : 6),
            Icon(
              Icons.keyboard_arrow_down,
              size: compact ? 14 : 16,
              color: Colors.white70,
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
    final value = text.trim().isEmpty ? '暂无简介' : text;
    return GestureDetector(
      onTap: onToggle,
      child: Text(
        expanded ? value : value.replaceAll('\n', ' '),
        maxLines: expanded ? null : 3,
        overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 16),
      ),
    );
  }
}
