import 'dart:ui';

import 'package:flutter/material.dart';

import 'player_backdrop_image.dart';

class PlayerListenVideoPresentation extends StatelessWidget {
  final List<String> artworkUrls;
  final String token;
  final String title;
  final String subtitle;
  final bool compactUi;

  const PlayerListenVideoPresentation({
    super.key,
    required this.artworkUrls,
    required this.token,
    required this.title,
    required this.subtitle,
    required this.compactUi,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRect(
      child: IgnorePointer(
        ignoring: true,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: Transform.scale(
                scale: 1.12,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: PlayerBackdropImage(
                    urls: artworkUrls,
                    token: token,
                    fallback: const ColoredBox(color: Color(0xFF101826)),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      const Color(0x52060A12),
                      const Color(0x82111B2C),
                      const Color(0xAA17263A),
                    ],
                    stops: const <double>[0, 0.46, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.18),
                    radius: 0.92,
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.10),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.20),
                    ],
                    stops: const <double>[0, 0.58, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useSideBySideLayout = _shouldUseSideBySideLayout(
                    constraints.biggest,
                  );
                  final horizontalPadding = _horizontalPadding(
                    constraints.maxWidth,
                  );
                  final titleStyle = theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontSize: _titleFontSize(
                      maxWidth: constraints.maxWidth,
                      sideBySide: useSideBySideLayout,
                    ),
                    fontWeight: FontWeight.w700,
                    height: 1.18,
                    letterSpacing: 0.2,
                  );
                  final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: _subtitleFontSize(
                      maxWidth: constraints.maxWidth,
                      sideBySide: useSideBySideLayout,
                    ),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  );
                  final bottomReserve = useSideBySideLayout
                      ? (compactUi ? 116.0 : 130.0)
                      : (compactUi ? 164.0 : 188.0);
                  final availableHeight =
                      (constraints.maxHeight -
                              bottomReserve -
                              (compactUi ? 22.0 : 28.0))
                          .clamp(160.0, constraints.maxHeight)
                          .toDouble();
                  final portraitPosterSize = _clampDouble(
                    constraints.maxWidth * (compactUi ? 0.66 : 0.60),
                    constraints.maxWidth < 380 ? 148.0 : 176.0,
                    availableHeight * 0.52,
                  );
                  final landscapePosterSize = _clampDouble(
                    availableHeight * 0.70,
                    132.0,
                    compactUi ? 188.0 : 228.0,
                  );

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      compactUi ? 22 : 28,
                      horizontalPadding,
                      bottomReserve,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: useSideBySideLayout ? 760 : 440,
                        ),
                        child: useSideBySideLayout
                            ? _buildLandscapeContent(
                                posterSize: landscapePosterSize,
                                titleStyle: titleStyle,
                                subtitleStyle: subtitleStyle,
                              )
                            : _buildPortraitContent(
                                posterSize: portraitPosterSize,
                                titleStyle: titleStyle,
                                subtitleStyle: subtitleStyle,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitContent({
    required double posterSize,
    required TextStyle? titleStyle,
    required TextStyle? subtitleStyle,
  }) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildArtworkCard(posterSize),
          SizedBox(height: compactUi ? 22 : 28),
          _buildTitleBlock(
            center: true,
            titleStyle: titleStyle,
            subtitleStyle: subtitleStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeContent({
    required double posterSize,
    required TextStyle? titleStyle,
    required TextStyle? subtitleStyle,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildArtworkCard(posterSize),
        SizedBox(width: compactUi ? 24 : 34),
        Flexible(
          child: _buildTitleBlock(
            center: false,
            titleStyle: titleStyle?.copyWith(fontSize: compactUi ? 24 : 28),
            subtitleStyle: subtitleStyle?.copyWith(
              fontSize: compactUi ? 13.5 : 15.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtworkCard(double posterSize) {
    final posterRadius = BorderRadius.circular(compactUi ? 28 : 34);
    return Container(
      key: const Key('playerListenVideoArtworkCard'),
      width: posterSize,
      height: posterSize,
      decoration: BoxDecoration(
        borderRadius: posterRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: posterRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PlayerArtworkImage(
              urls: artworkUrls,
              token: token,
              fit: BoxFit.cover,
              fallback: const ColoredBox(color: Color(0xFF1B2230)),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.06),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBlock({
    required bool center,
    required TextStyle? titleStyle,
    required TextStyle? subtitleStyle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          title.trim().isEmpty ? '当前视频' : title.trim(),
          key: const Key('playerListenVideoTitle'),
          textAlign: center ? TextAlign.center : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        if (subtitle.trim().isNotEmpty) ...[
          SizedBox(height: compactUi ? 10 : 12),
          Text(
            subtitle.trim(),
            key: const Key('playerListenVideoSubtitle'),
            textAlign: center ? TextAlign.center : TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          ),
        ],
      ],
    );
  }

  double _clampDouble(double value, double min, double max) {
    if (max < min) {
      return min;
    }
    return value.clamp(min, max).toDouble();
  }

  bool _shouldUseSideBySideLayout(Size size) {
    if (size.width < (compactUi ? 620 : 700)) {
      return false;
    }
    return size.width > size.height * 1.12;
  }

  double _horizontalPadding(double maxWidth) {
    if (maxWidth < 380) {
      return 18.0;
    }
    return compactUi ? 24.0 : 40.0;
  }

  double _titleFontSize({required double maxWidth, required bool sideBySide}) {
    if (!sideBySide && maxWidth < 380) {
      return 22.0;
    }
    return compactUi ? 27.0 : 32.0;
  }

  double _subtitleFontSize({
    required double maxWidth,
    required bool sideBySide,
  }) {
    if (!sideBySide && maxWidth < 380) {
      return 13.0;
    }
    return compactUi ? 14.5 : 16.0;
  }
}
