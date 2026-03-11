import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../utils/api_url_helper.dart';

class EpisodePickerSheetItem {
  final String id;
  final String title;
  final String durationLabel;
  final String statusLabel;
  final Color statusColor;
  final String posterPath;
  final bool? _isPlaying;
  final bool selected;

  bool get isPlaying => _isPlaying ?? false;

  const EpisodePickerSheetItem({
    required this.id,
    required this.title,
    required this.durationLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.posterPath,
    bool? isPlaying,
    required this.selected,
  }) : _isPlaying = isPlaying;
}

class EpisodePickerSheet {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? sectionLabel,
    String? selectedId,
    required bool autoPlayEnabled,
    required ValueChanged<bool> onAutoPlayChanged,
    required String baseUrl,
    required String token,
    required List<EpisodePickerSheetItem> items,
  }) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width > media.size.height;
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) {
        return _EpisodePickerDialog(
          title: title,
          sectionLabel: sectionLabel,
          selectedId: selectedId,
          autoPlayEnabled: autoPlayEnabled,
          onAutoPlayChanged: onAutoPlayChanged,
          baseUrl: baseUrl,
          token: token,
          items: items,
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: isWide ? const Offset(0.08, 0) : const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _EpisodePickerDialog extends StatefulWidget {
  final String title;
  final String? sectionLabel;
  final String? selectedId;
  final bool autoPlayEnabled;
  final ValueChanged<bool> onAutoPlayChanged;
  final String baseUrl;
  final String token;
  final List<EpisodePickerSheetItem> items;

  const _EpisodePickerDialog({
    required this.title,
    required this.sectionLabel,
    required this.selectedId,
    required this.autoPlayEnabled,
    required this.onAutoPlayChanged,
    required this.baseUrl,
    required this.token,
    required this.items,
  });

  @override
  State<_EpisodePickerDialog> createState() => _EpisodePickerDialogState();
}

class _EpisodePickerDialogState extends State<_EpisodePickerDialog> {
  late bool _autoPlayEnabled;
  late final ScrollController _scrollController;
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _autoPlayEnabled = widget.autoPlayEnabled;
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToSelectedItem();
    });
  }

  @override
  void didUpdateWidget(covariant _EpisodePickerDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToSelectedItem();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpToSelectedItem() {
    if (!_scrollController.hasClients) return;
    final selectedId = widget.selectedId?.trim() ?? '';
    if (selectedId.isEmpty) {
      _scrollController.jumpTo(0);
      return;
    }
    final targetContext = _itemKeys[selectedId]?.currentContext;
    if (targetContext == null) {
      _scrollController.jumpTo(0);
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.06,
      duration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width > media.size.height;
    final compactWide = isWide && media.size.width < 1100;
    final width = _panelWidth(media.size.width, isWide: isWide);
    final topInset = isWide ? 0.0 : null;
    const bottomInset = 0.0;
    const rightInset = 0.0;
    final leftInset = isWide ? null : 0.0;
    final sheetHeight = isWide
        ? null
        : math.max(300.0, media.size.height * 0.45);
    const borderRadius = BorderRadius.zero;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: topInset,
            left: leftInset,
            right: rightInset,
            bottom: bottomInset,
            width: isWide ? width : null,
            height: sheetHeight,
            child: ClipRRect(
              borderRadius: borderRadius,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  color: Colors.black.withValues(alpha: isWide ? 0.56 : 0.78),
                  border: isWide
                      ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? (compactWide ? 16 : 18) : 16,
                    isWide
                        ? math.max(media.padding.top, compactWide ? 12 : 14)
                        : 14,
                    isWide ? (compactWide ? 12 : 14) : 16,
                    isWide
                        ? math.max(media.padding.bottom, compactWide ? 12 : 14)
                        : math.max(media.padding.bottom, 10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: (widget.sectionLabel ?? '').trim().isEmpty
                                ? const SizedBox.shrink()
                                : Text(
                                    widget.sectionLabel!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isWide
                                          ? (compactWide ? 13 : 14)
                                          : 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                          SizedBox(width: isWide ? 8 : 14),
                          _AutoPlayToggle(
                            value: _autoPlayEnabled,
                            compact: isWide,
                            onChanged: (value) {
                              setState(() => _autoPlayEnabled = value);
                              widget.onAutoPlayChanged(value);
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: isWide ? (compactWide ? 8 : 10) : 12),
                      Expanded(
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: EdgeInsets.zero,
                          itemCount: widget.items.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(height: isWide ? 8 : 10),
                          itemBuilder: (context, index) {
                            final item = widget.items[index];
                            final itemKey = _itemKeys.putIfAbsent(
                              item.id,
                              () => GlobalKey(),
                            );
                            return _EpisodeTile(
                              key: itemKey,
                              item: item,
                              baseUrl: widget.baseUrl,
                              token: widget.token,
                              wide: isWide,
                              compactWide: compactWide,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _panelWidth(double screenWidth, {required bool isWide}) {
    if (!isWide) {
      return screenWidth - 28;
    }
    if (screenWidth < 900) {
      return screenWidth * 0.52;
    }
    if (screenWidth < 1200) {
      return screenWidth * 0.45;
    }
    return math.min(560, screenWidth * 0.42);
  }
}

class _EpisodeTile extends StatelessWidget {
  final EpisodePickerSheetItem item;
  final String baseUrl;
  final String token;
  final bool wide;
  final bool compactWide;

  const _EpisodeTile({
    super.key,
    required this.item,
    required this.baseUrl,
    required this.token,
    required this.wide,
    this.compactWide = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = item.selected ? const Color(0xFFF6F9FF) : Colors.white;
    const durationColor = Color(0xFF95A1B5);
    final borderColor = wide
        ? (item.selected ? const Color(0x50358FFF) : const Color(0x0CFFFFFF))
        : Colors.transparent;
    final backgroundColor = wide
        ? (item.selected ? const Color(0x0C4B7DE0) : Colors.transparent)
        : Colors.transparent;
    final titleSize = wide ? (compactWide ? 14.0 : 15.0) : 14.0;
    final metaSize = wide ? (compactWide ? 11.5 : 12.0) : 11.5;
    final tileRadius = wide ? BorderRadius.circular(16) : BorderRadius.zero;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(item.id),
        borderRadius: tileRadius,
        child: Ink(
          padding: EdgeInsets.fromLTRB(
            wide ? (compactWide ? 8 : 10) : 0,
            wide ? (compactWide ? 7 : 8) : 6,
            wide ? (compactWide ? 8 : 10) : 0,
            wide ? (compactWide ? 7 : 8) : 6,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: tileRadius,
            border: wide
                ? Border.all(
                    color: borderColor,
                    width: item.selected ? 0.9 : 0.6,
                  )
                : const Border(
                    bottom: BorderSide(color: Color(0x1FFFFFFF), width: 0.6),
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EpisodePoster(
                baseUrl: baseUrl,
                token: token,
                posterPath: item.posterPath,
                showCurrentMarker: item.selected,
                wide: wide,
                compactWide: compactWide,
              ),
              SizedBox(width: wide ? (compactWide ? 10 : 12) : 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: wide ? 1 : 1,
                    right: wide ? 2 : 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                      ),
                      SizedBox(height: wide ? (compactWide ? 5 : 6) : 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              item.durationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: durationColor,
                                fontSize: metaSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(width: wide ? 8 : 10),
                          Text(
                            item.statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: item.statusColor,
                              fontSize: metaSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodePoster extends StatelessWidget {
  final String baseUrl;
  final String token;
  final String posterPath;
  final bool showCurrentMarker;
  final bool wide;
  final bool compactWide;

  const _EpisodePoster({
    required this.baseUrl,
    required this.token,
    required this.posterPath,
    required this.showCurrentMarker,
    required this.wide,
    this.compactWide = false,
  });

  @override
  Widget build(BuildContext context) {
    final posterWidth = wide ? (compactWide ? 118.0 : 130.0) : 118.0;
    final posterHeight = wide ? (compactWide ? 66.0 : 73.0) : 66.0;
    return SizedBox(
      width: posterWidth,
      height: posterHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0xFF172334),
              child: _EpisodePosterImage(
                urls: ApiUrlHelper.imageCandidates(
                  baseUrl,
                  posterPath,
                  width: 560,
                ),
                token: token,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.06),
                      Colors.black.withValues(alpha: 0.24),
                    ],
                  ),
                ),
              ),
            ),
            if (showCurrentMarker)
              const Positioned(
                left: 12,
                bottom: 12,
                child: _PosterNowPlayingIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class _AutoPlayToggle extends StatelessWidget {
  final bool value;
  final bool compact;
  final ValueChanged<bool> onChanged;

  const _AutoPlayToggle({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '自动连播',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 12 : 15,
            fontWeight: compact ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        SizedBox(width: compact ? 6 : 12),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: compact ? 48 : 64,
            height: compact ? 28 : 36,
            padding: EdgeInsets.all(compact ? 2 : 3),
            decoration: BoxDecoration(
              color: value ? const Color(0xFF2D87FF) : const Color(0x3DFFFFFF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Align(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: compact ? 24 : 30,
                height: compact ? 24 : 30,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PosterNowPlayingIndicator extends StatefulWidget {
  const _PosterNowPlayingIndicator();

  @override
  State<_PosterNowPlayingIndicator> createState() =>
      _PosterNowPlayingIndicatorState();
}

class _PosterNowPlayingIndicatorState extends State<_PosterNowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: 18,
          height: 18,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List<Widget>.generate(4, (index) {
              final phase = (_controller.value + index * 0.18) % 1.0;
              final height = lerpDouble(
                8,
                18,
                0.5 + 0.5 * math.sin(phase * math.pi * 2),
              )!;
              return Container(
                width: 3,
                height: height,
                margin: EdgeInsets.only(right: index == 3 ? 0 : 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _EpisodePosterImage extends StatefulWidget {
  final List<String> urls;
  final String token;

  const _EpisodePosterImage({required this.urls, required this.token});

  @override
  State<_EpisodePosterImage> createState() => _EpisodePosterImageState();
}

class _EpisodePosterImageState extends State<_EpisodePosterImage> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _EpisodePosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls || oldWidget.token != widget.token) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty ||
        _index >= widget.urls.length ||
        widget.token.trim().isEmpty) {
      return const Center(
        child: Icon(Icons.movie_outlined, color: Colors.white30, size: 28),
      );
    }

    final current = widget.urls[_index];
    final headers = <String, String>{
      'Authorization': widget.token,
      'Trim-MC-token': widget.token,
    };

    return Image.network(
      current,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.none,
      headers: headers,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final loaded = wasSynchronouslyLoaded || frame != null;
        if (loaded) return child;
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: Colors.white38,
            ),
          ),
        );
      },
      errorBuilder: (_, error, __) {
        if (_index + 1 < widget.urls.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _index += 1);
            }
          });
          return const SizedBox.expand();
        }
        return const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white30,
            size: 28,
          ),
        );
      },
    );
  }
}
