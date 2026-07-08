import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/detail/media_source_info.dart';
import '../models/stream_track_data.dart';
import '../theme/app_theme.dart';
import '../ui/app_sheet_transitions.dart';
import '../utils/media_language_mapper.dart';

/// 「查看全部」媒体明细页的一张卡片：[header] 为卡片标题行（如 `4K HEVC HDR`），
/// [fields] 为逐字段明细（枚举键 + 已格式化值，标签由 UI 用 l10n 渲染）。
class MediaInfoCard {
  const MediaInfoCard({required this.header, required this.fields});

  final String header;
  final List<MediaInfoField> fields;
}

/// 「查看全部」媒体明细页的后端中立数据——一个可切换的版本（飞牛多清晰度 / Emby 多源）。
///
/// 飞牛与 Emby 各自把自家轨道数据格式化成同一组 [MediaInfoCard]，喂给同一个
/// [MediaDetailOverlayPage] 渲染，从而视觉统一、格式化逻辑各归各家（与 `VideoInfoSection`
/// 同款抽象）。文件信息不在此页——飞牛/Emby 都走详情主页独立的 `FileInfoSection`。
class MediaDetailVariant {
  const MediaDetailVariant({
    required this.key,
    required this.title,
    this.video,
    this.audios = const <MediaInfoCard>[],
    this.subtitles = const <MediaInfoCard>[],
  });

  final String key;
  final String title;
  final MediaInfoCard? video;
  final List<MediaInfoCard> audios;
  final List<MediaInfoCard> subtitles;

  /// 飞牛：从当前清晰度的视频 / 音频 / 字幕轨道 DTO 构建（行序与文案逐字保持原飞牛）。
  factory MediaDetailVariant.fromFeiniu({
    required String key,
    required String title,
    required AppLocalizations l10n,
    VideoStreamInfo? video,
    List<AudioTrackOption> audios = const <AudioTrackOption>[],
    List<SubtitleTrackOption> subtitles = const <SubtitleTrackOption>[],
  }) {
    return MediaDetailVariant(
      key: key,
      title: title,
      video: video == null ? null : _feiniuVideoCard(video),
      audios: audios.map(_feiniuAudioCard).toList(growable: false),
      subtitles: subtitles
          .map((s) => _feiniuSubtitleCard(s, l10n))
          .toList(growable: false),
    );
  }

  /// Emby 等公共后端：从中立 [MediaSourceInfo] 构建（明细行由映射层在 [MediaSourceStream.fields]
  /// 备好）。文件信息走详情主页独立的 `FileInfoSection`（与飞牛同），不放进本 overlay。
  factory MediaDetailVariant.fromSource({
    required String key,
    required String title,
    required MediaSourceInfo info,
  }) {
    MediaInfoCard cardOf(MediaSourceStream s) =>
        MediaInfoCard(header: s.label, fields: s.fields);
    final videoStreams = info.videoStreams;
    return MediaDetailVariant(
      key: key,
      title: title,
      video: videoStreams.isEmpty ? null : cardOf(videoStreams.first),
      audios: info.audioStreams.map(cardOf).toList(growable: false),
      subtitles: info.subtitleStreams.map(cardOf).toList(growable: false),
    );
  }
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
      barrierLabel: AppLocalizations.of(context).mediaDetailsTitle,
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
                          'media-detail-page-${variant.key}',
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _variantSections(l10n, variant),
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

  List<Widget> _variantSections(
    AppLocalizations l10n,
    MediaDetailVariant variant,
  ) {
    final children = <Widget>[];
    if (variant.video != null) {
      children
        ..add(_SectionTitle(l10n.mediaDetailsVideoSection))
        ..add(const SizedBox(height: 8))
        ..add(_InfoCard(card: variant.video!))
        ..add(const SizedBox(height: 14));
    }
    if (variant.audios.isNotEmpty) {
      children
        ..add(_SectionTitle(l10n.mediaDetailsAudioSection))
        ..add(const SizedBox(height: 8));
      for (final card in variant.audios) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _InfoCard(card: card),
          ),
        );
      }
    }
    if (variant.subtitles.isNotEmpty) {
      children
        ..add(const SizedBox(height: 4))
        ..add(_SectionTitle(l10n.mediaDetailsSubtitleSection))
        ..add(const SizedBox(height: 8));
      for (final card in variant.subtitles) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _InfoCard(card: card),
          ),
        );
      }
    }
    return children;
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
  final MediaInfoCard card;

  const _InfoCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final rows = card.fields;
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
          if (card.header.trim().isNotEmpty) ...[
            Text(
              card.header,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0 && rows[i].isDivider)
              Divider(color: colors.borderSubtle, height: 14),
            if (!rows[i].isDivider)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _label(l10n, rows[i].key),
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      _displayValue(l10n, rows[i]),
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

/// 布尔字段（值为 `1`/`0` 中立标记）的键集合，UI 据此渲染本地化「是/否」。
const Set<MediaInfoFieldKey> _boolFieldKeys = <MediaInfoFieldKey>{
  MediaInfoFieldKey.interlaced,
  MediaInfoFieldKey.isDefault,
  MediaInfoFieldKey.forced,
  MediaInfoFieldKey.external,
};

String _displayValue(AppLocalizations l10n, MediaInfoField field) {
  if (_boolFieldKeys.contains(field.key)) {
    if (field.value == '1') return l10n.commonYes;
    if (field.value == '0') return l10n.commonNo;
    return '-';
  }
  return _safe(field.value);
}

String _label(AppLocalizations l10n, MediaInfoFieldKey key) {
  switch (key) {
    case MediaInfoFieldKey.encoder:
      return l10n.mediaDetailsFieldEncoder;
    case MediaInfoFieldKey.profile:
      return l10n.mediaDetailsFieldProfile;
    case MediaInfoFieldKey.level:
      return l10n.mediaDetailsFieldLevel;
    case MediaInfoFieldKey.resolution:
      return l10n.mediaDetailsFieldResolution;
    case MediaInfoFieldKey.aspectRatio:
      return l10n.mediaDetailsFieldAspectRatio;
    case MediaInfoFieldKey.interlaced:
      return l10n.mediaDetailsFieldInterlaced;
    case MediaInfoFieldKey.frameRate:
      return l10n.mediaDetailsFieldFrameRate;
    case MediaInfoFieldKey.bitrate:
      return l10n.mediaDetailsFieldBitrate;
    case MediaInfoFieldKey.range:
      return l10n.mediaDetailsFieldRange;
    case MediaInfoFieldKey.colorPrimaries:
      return l10n.mediaDetailsFieldColorPrimaries;
    case MediaInfoFieldKey.colorSpace:
      return l10n.mediaDetailsFieldColorSpace;
    case MediaInfoFieldKey.colorTransfer:
      return l10n.mediaDetailsFieldColorTransfer;
    case MediaInfoFieldKey.bitDepth:
      return l10n.mediaDetailsFieldBitDepth;
    case MediaInfoFieldKey.pixelFormat:
      return l10n.mediaDetailsFieldPixelFormat;
    case MediaInfoFieldKey.refs:
      return l10n.mediaDetailsFieldRefs;
    case MediaInfoFieldKey.language:
      return l10n.mediaDetailsFieldLanguage;
    case MediaInfoFieldKey.channels:
      return l10n.mediaDetailsFieldChannels;
    case MediaInfoFieldKey.sampleRate:
      return l10n.mediaDetailsFieldSampleRate;
    case MediaInfoFieldKey.layout:
      return l10n.mediaDetailsFieldLayout;
    case MediaInfoFieldKey.isDefault:
      return l10n.mediaDetailsFieldDefault;
    case MediaInfoFieldKey.forced:
      return l10n.mediaDetailsFieldForced;
    case MediaInfoFieldKey.external:
      return l10n.mediaDetailsFieldExternal;
    case MediaInfoFieldKey.divider:
      return '';
  }
}

// ── 飞牛轨道 DTO → 中立卡片（行序 / 文案逐字保持原 `_VideoCard`/`_AudioCard`/`_SubtitleCard`）──

MediaInfoCard _feiniuVideoCard(VideoStreamInfo video) {
  final headerParts = <String>[
    if (video.resolutionType.trim().isNotEmpty) video.resolutionType,
    if (video.codecName.trim().isNotEmpty) video.codecName.toUpperCase(),
    if (video.colorRangeType.trim().isNotEmpty) video.colorRangeType,
  ];
  return MediaInfoCard(
    header: headerParts.join(' '),
    fields: <MediaInfoField>[
      MediaInfoField(MediaInfoFieldKey.encoder, video.codecName),
      MediaInfoField(MediaInfoFieldKey.profile, video.profile),
      MediaInfoField(MediaInfoFieldKey.level, video.level),
      MediaInfoField(
        MediaInfoFieldKey.resolution,
        _resolution(video.width, video.height),
      ),
      MediaInfoField(MediaInfoFieldKey.aspectRatio, video.displayAspectRatio),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.interlaced,
        _boolRaw(video.progressive == 1),
      ),
      MediaInfoField(MediaInfoFieldKey.frameRate, video.rFrameRate),
      MediaInfoField(MediaInfoFieldKey.bitrate, _kbps(video.bps)),
      MediaInfoField(MediaInfoFieldKey.range, video.colorRangeType),
      MediaInfoField(MediaInfoFieldKey.colorPrimaries, video.colorPrimaries),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.colorSpace, video.colorSpace),
      MediaInfoField(MediaInfoFieldKey.colorTransfer, video.colorTransfer),
      MediaInfoField(
        MediaInfoFieldKey.bitDepth,
        video.bitDepth > 0 ? '${video.bitDepth} bit' : '',
      ),
      MediaInfoField(MediaInfoFieldKey.pixelFormat, video.pixFmt),
      MediaInfoField(
        MediaInfoFieldKey.refs,
        video.refs > 0 ? '${video.refs}' : '',
      ),
    ],
  );
}

MediaInfoCard _feiniuAudioCard(AudioTrackOption audio) {
  final lan = MediaLanguageMapper.languageName(audio.language);
  final headerParts = <String>[
    if (lan != _unknownLanguageName) lan,
    if (audio.codecName.trim().isNotEmpty) audio.codecName,
    if (audio.channelLayout.trim().isNotEmpty) audio.channelLayout,
  ];
  return MediaInfoCard(
    header: headerParts.join(' '),
    fields: <MediaInfoField>[
      MediaInfoField(
        MediaInfoFieldKey.language,
        lan == _unknownLanguageName ? '' : lan,
      ),
      MediaInfoField(MediaInfoFieldKey.encoder, audio.codecName),
      MediaInfoField(MediaInfoFieldKey.profile, audio.profile),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.channels, _channelText(audio.channels)),
      MediaInfoField(
        MediaInfoFieldKey.sampleRate,
        audio.sampleRate > 0 ? '${audio.sampleRate} Hz' : '',
      ),
      MediaInfoField(MediaInfoFieldKey.bitrate, _kbps(audio.bps)),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.layout, audio.channelLayout),
      MediaInfoField(
        MediaInfoFieldKey.isDefault,
        _boolRaw(audio.isDefault == 1),
      ),
    ],
  );
}

MediaInfoCard _feiniuSubtitleCard(
  SubtitleTrackOption subtitle,
  AppLocalizations l10n,
) {
  final lan = MediaLanguageMapper.languageName(subtitle.language);
  final fmt =
      (subtitle.format.isNotEmpty ? subtitle.format : subtitle.codecName)
          .trim()
          .toUpperCase();
  final header =
      '${lan == _unknownLanguageName ? l10n.mediaDetailsSubtitleSection : lan} ($fmt)';
  return MediaInfoCard(
    header: header,
    fields: <MediaInfoField>[
      MediaInfoField(
        MediaInfoFieldKey.language,
        lan == _unknownLanguageName ? '' : lan,
      ),
      MediaInfoField(MediaInfoFieldKey.encoder, fmt.toLowerCase()),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.isDefault,
        _boolRaw(subtitle.isDefault == 1),
      ),
      MediaInfoField(MediaInfoFieldKey.forced, _boolRaw(subtitle.forced == 1)),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.external,
        _boolRaw(subtitle.isExternal == 1),
      ),
    ],
  );
}

String _boolRaw(bool value) => value ? '1' : '0';

String _safe(String value) => value.trim().isEmpty ? '-' : value.trim();

const String _unknownLanguageName = '未知';

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
