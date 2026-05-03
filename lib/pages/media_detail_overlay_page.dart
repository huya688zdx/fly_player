import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/stream_track_data.dart';
import '../theme/app_theme.dart';
import '../ui/app_sheet_transitions.dart';
import '../utils/media_language_mapper.dart';

class MediaDetailVariant {
  final String mediaGuid;
  final String title;
  final VideoStreamInfo? video;
  final List<AudioTrackOption> audios;
  final List<SubtitleTrackOption> subtitles;

  const MediaDetailVariant({
    required this.mediaGuid,
    required this.title,
    required this.video,
    required this.audios,
    required this.subtitles,
  });
}

class MediaDetailOverlayPage extends StatefulWidget {
  final List<MediaDetailVariant> variants;
  final int initialIndex;
  final ValueChanged<int>? onVariantChanged;

  const MediaDetailOverlayPage({
    super.key,
    required this.variants,
    required this.initialIndex,
    this.onVariantChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required List<MediaDetailVariant> variants,
    int initialIndex = 0,
    ValueChanged<int>? onVariantChanged,
  }) async {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final page = MediaDetailOverlayPage(
      variants: variants,
      initialIndex: initialIndex,
      onVariantChanged: onVariantChanged,
    );
    if (isLandscape) {
      return showDialog<void>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: true,
        barrierColor: const Color(0xBF020812),
        builder: (_) => page,
      );
    }
    return AppSheetTransitions.showBottomSurface<void>(
      context,
      barrierDismissible: true,
      barrierLabel: 'media_detail_overlay',
      barrierColor: const Color(0xBF020812),
      builder: (_) => page,
    );
  }

  @override
  State<MediaDetailOverlayPage> createState() => _MediaDetailOverlayPageState();
}

class _MediaDetailOverlayPageState extends State<MediaDetailOverlayPage> {
  static const int _loopBase = 1000;
  late final PageController _pageController;
  late final ValueNotifier<int> _indexNotifier;
  late final int _initialPage;

  @override
  void initState() {
    super.initState();
    final max = widget.variants.isEmpty ? 0 : widget.variants.length - 1;
    final initialIndex = widget.initialIndex.clamp(0, max);
    _indexNotifier = ValueNotifier<int>(initialIndex);
    _initialPage = widget.variants.length > 1
        ? (widget.variants.length * _loopBase) + initialIndex
        : initialIndex;
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _indexNotifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  int _logicalIndex(int rawPage) {
    final count = widget.variants.length;
    if (count <= 1) return 0;
    var logical = rawPage % count;
    if (logical < 0) logical += count;
    return logical;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    if (widget.variants.isEmpty) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final panelHeight = (media.size.height * 0.88).clamp(520.0, 920.0);
    final panelDialogHeight = (media.size.height * 0.86).clamp(500.0, 840.0);
    final panelDialogWidth = (media.size.width * 0.72).clamp(700.0, 980.0);

    final child = Container(
      decoration: BoxDecoration(
        color: colors.backgroundElevated,
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(24),
          bottom: Radius.circular(isLandscape ? 24 : 0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isLandscape ? 26 : 16,
            isLandscape ? 20 : 12,
            isLandscape ? 26 : 16,
            isLandscape ? 22 : 16,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    l10n.mediaDetailsTitle,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      if (AppSheetTransitions.maybeClose<void>(context)) {
                        return;
                      }
                      Navigator.of(context).maybePop();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        color: colors.textSecondary,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ValueListenableBuilder<int>(
                valueListenable: _indexNotifier,
                builder: (context, index, _) {
                  final current = widget.variants[index];
                  return Text(
                    '${current.title}  ${index + 1}/${widget.variants.length}',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.variants.length > 1 ? null : 1,
                  padEnds: false,
                  onPageChanged: (rawPage) {
                    final index = _logicalIndex(rawPage);
                    if (_indexNotifier.value != index) {
                      _indexNotifier.value = index;
                      widget.onVariantChanged?.call(index);
                    }
                  },
                  itemBuilder: (context, rawPage) {
                    final pageIndex = _logicalIndex(rawPage);
                    final variant = widget.variants[pageIndex];
                    return RepaintBoundary(
                      child: SingleChildScrollView(
                        key: PageStorageKey<String>(
                          'media-detail-page-${variant.mediaGuid}',
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (variant.video != null) ...[
                              _SectionTitle(l10n.mediaDetailsVideoSection),
                              const SizedBox(height: 8),
                              _VideoCard(video: variant.video!),
                              const SizedBox(height: 14),
                            ],
                            if (variant.audios.isNotEmpty) ...[
                              _SectionTitle(l10n.mediaDetailsAudioSection),
                              const SizedBox(height: 8),
                              ...variant.audios.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _AudioCard(audio: item),
                                ),
                              ),
                            ],
                            if (variant.subtitles.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _SectionTitle(l10n.mediaDetailsSubtitleSection),
                              const SizedBox(height: 8),
                              ...variant.subtitles.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SubtitleCard(subtitle: item),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isLandscape) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: panelDialogWidth,
          height: panelDialogHeight,
          child: child,
        ),
      );
    }

    return SizedBox(height: panelHeight, width: double.infinity, child: child);
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text(
      title,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String header;
  final List<MapEntry<String, String>> rows;

  const _InfoCard({required this.header, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0 && _isDividerRow(rows[i])) ...[
              Divider(color: colors.borderSubtle, height: 14),
            ],
            if (!_isDividerRow(rows[i]))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].key,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      rows[i].value,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final VideoStreamInfo video;

  const _VideoCard({required this.video});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final headerParts = <String>[
      if (video.resolutionType.trim().isNotEmpty) video.resolutionType,
      if (video.codecName.trim().isNotEmpty) video.codecName.toUpperCase(),
      if (video.colorRangeType.trim().isNotEmpty) video.colorRangeType,
    ];
    return _InfoCard(
      header: headerParts.join(' '),
      rows: [
        MapEntry(l10n.mediaDetailsFieldEncoder, _safe(video.codecName)),
        MapEntry(l10n.mediaDetailsFieldProfile, _safe(video.profile)),
        MapEntry(l10n.mediaDetailsFieldLevel, _safe(video.level)),
        MapEntry(
          l10n.mediaDetailsFieldResolution,
          _safe(_resolution(video.width, video.height)),
        ),
        MapEntry(
          l10n.mediaDetailsFieldAspectRatio,
          _safe(video.displayAspectRatio),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(
          l10n.mediaDetailsFieldInterlaced,
          _boolText(l10n, video.progressive == 1),
        ),
        MapEntry(l10n.mediaDetailsFieldFrameRate, _safe(video.rFrameRate)),
        MapEntry(l10n.mediaDetailsFieldBitrate, _safe(_kbps(video.bps))),
        MapEntry(l10n.mediaDetailsFieldRange, _safe(video.colorRangeType)),
        MapEntry(
          l10n.mediaDetailsFieldColorPrimaries,
          _safe(video.colorPrimaries),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(l10n.mediaDetailsFieldColorSpace, _safe(video.colorSpace)),
        MapEntry(
          l10n.mediaDetailsFieldColorTransfer,
          _safe(video.colorTransfer),
        ),
        MapEntry(
          l10n.mediaDetailsFieldBitDepth,
          _safe(video.bitDepth > 0 ? '${video.bitDepth} bit' : ''),
        ),
        MapEntry(l10n.mediaDetailsFieldPixelFormat, _safe(video.pixFmt)),
        MapEntry(
          l10n.mediaDetailsFieldRefs,
          _safe(video.refs > 0 ? '${video.refs}' : ''),
        ),
      ],
    );
  }
}

class _AudioCard extends StatelessWidget {
  final AudioTrackOption audio;

  const _AudioCard({required this.audio});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lan = MediaLanguageMapper.languageName(audio.language);
    final headerParts = <String>[
      if (lan != _unknownLanguageName) lan,
      if (audio.codecName.trim().isNotEmpty) audio.codecName,
      if (audio.channelLayout.trim().isNotEmpty) audio.channelLayout,
    ];
    return _InfoCard(
      header: headerParts.join(' '),
      rows: [
        MapEntry(
          l10n.mediaDetailsFieldLanguage,
          _safe(lan == _unknownLanguageName ? '' : lan),
        ),
        MapEntry(l10n.mediaDetailsFieldEncoder, _safe(audio.codecName)),
        MapEntry(l10n.mediaDetailsFieldProfile, _safe(audio.profile)),
        const MapEntry('__divider__', ''),
        MapEntry(
          l10n.mediaDetailsFieldChannels,
          _safe(_channelText(audio.channels)),
        ),
        MapEntry(
          l10n.mediaDetailsFieldSampleRate,
          _safe(audio.sampleRate > 0 ? '${audio.sampleRate} Hz' : ''),
        ),
        MapEntry(l10n.mediaDetailsFieldBitrate, _safe(_kbps(audio.bps))),
        const MapEntry('__divider__', ''),
        MapEntry(l10n.mediaDetailsFieldLayout, _safe(audio.channelLayout)),
        MapEntry(
          l10n.mediaDetailsFieldDefault,
          _boolText(l10n, audio.isDefault == 1),
        ),
      ],
    );
  }
}

class _SubtitleCard extends StatelessWidget {
  final SubtitleTrackOption subtitle;

  const _SubtitleCard({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lan = MediaLanguageMapper.languageName(subtitle.language);
    final fmt =
        (subtitle.format.isNotEmpty ? subtitle.format : subtitle.codecName)
            .trim()
            .toUpperCase();
    final header =
        '${lan == _unknownLanguageName ? l10n.mediaDetailsSubtitleSection : lan} ($fmt)';
    return _InfoCard(
      header: header,
      rows: [
        MapEntry(
          l10n.mediaDetailsFieldLanguage,
          _safe(lan == _unknownLanguageName ? '' : lan),
        ),
        MapEntry(l10n.mediaDetailsFieldEncoder, _safe(fmt.toLowerCase())),
        const MapEntry('__divider__', ''),
        MapEntry(
          l10n.mediaDetailsFieldDefault,
          _boolText(l10n, subtitle.isDefault == 1),
        ),
        MapEntry(
          l10n.mediaDetailsFieldForced,
          _boolText(l10n, subtitle.forced == 1),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(
          l10n.mediaDetailsFieldExternal,
          _boolText(l10n, subtitle.isExternal == 1),
        ),
      ],
    );
  }
}

bool _isDividerRow(MapEntry<String, String> entry) =>
    entry.key == '__divider__';

String _safe(String value) => value.trim().isEmpty ? '-' : value.trim();

const String _unknownLanguageName = '\u672a\u77e5';

String _resolution(int w, int h) {
  if (w <= 0 || h <= 0) return '';
  return '$w * $h';
}

String _kbps(int bps) {
  if (bps <= 0) return '';
  if (bps >= 1000000) return '${(bps / 1000000.0).toStringAsFixed(2)} mbps';
  return '${(bps / 1000.0).toStringAsFixed(0)} kbps';
}

String _channelText(int channels) {
  if (channels <= 0) return '';
  if (channels == 1) return '1 ch';
  if (channels == 2) return '2 ch';
  return '$channels ch';
}

String _boolText(AppLocalizations l10n, bool v) =>
    v ? l10n.commonYes : l10n.commonNo;
