import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/stream_track_data.dart';
import '../providers/nas_provider.dart';
import '../theme/app_theme.dart';
import '../ui/app_sheet_transitions.dart';
import '../utils/media_language_mapper.dart';
import '../utils/media_locale_store.dart';

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
  final Map<String, dynamic> localeMap;

  const MediaDetailOverlayPage({
    super.key,
    required this.variants,
    required this.initialIndex,
    this.onVariantChanged,
    this.localeMap = const <String, dynamic>{},
  });

  static Future<void> show(
    BuildContext context, {
    required List<MediaDetailVariant> variants,
    int initialIndex = 0,
    ValueChanged<int>? onVariantChanged,
  }) async {
    final provider = context.read<NasProvider>();
    final localeMap = await MediaLocaleStore.load(provider);
    if (!context.mounted) return;
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final page = MediaDetailOverlayPage(
      variants: variants,
      initialIndex: initialIndex,
      onVariantChanged: onVariantChanged,
      localeMap: localeMap,
    );
    if (isLandscape) {
      return showDialog<void>(
        context: context,
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

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      widget.localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
                    _t('player.videoDetails.title', '文件媒体信息'),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: EdgeInsets.all(4),
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
                              _SectionTitle(_t('stream.video.name', '视频')),
                              const SizedBox(height: 8),
                              _VideoCard(
                                video: variant.video!,
                                localeMap: widget.localeMap,
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (variant.audios.isNotEmpty) ...[
                              _SectionTitle(_t('stream.audio.name', '音频')),
                              const SizedBox(height: 8),
                              ...variant.audios.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _AudioCard(
                                    audio: item,
                                    localeMap: widget.localeMap,
                                  ),
                                ),
                              ),
                            ],
                            if (variant.subtitles.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _SectionTitle(_t('stream.subtitle.name', '字幕')),
                              const SizedBox(height: 8),
                              ...variant.subtitles.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SubtitleCard(
                                    subtitle: item,
                                    localeMap: widget.localeMap,
                                  ),
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
  final Map<String, dynamic> localeMap;

  const _VideoCard({required this.video, required this.localeMap});

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerParts = <String>[
      if (video.resolutionType.trim().isNotEmpty) video.resolutionType,
      if (video.codecName.trim().isNotEmpty) video.codecName.toUpperCase(),
      if (video.colorRangeType.trim().isNotEmpty) video.colorRangeType,
    ];
    return _InfoCard(
      header: headerParts.join(' '),
      rows: [
        MapEntry(
          _t('stream.details.fields.encoder', '编码器'),
          _safe(video.codecName),
        ),
        MapEntry(
          _t('stream.details.fields.profile', '配置'),
          _safe(video.profile),
        ),
        MapEntry(_t('stream.details.fields.level', '等级'), _safe(video.level)),
        MapEntry(
          _t('stream.details.fields.resolution', '分辨率'),
          _safe(_resolution(video.width, video.height)),
        ),
        MapEntry(
          _t('stream.details.fields.aspectRatio', '宽高比'),
          _safe(video.displayAspectRatio),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(
          _t('stream.details.fields.interlaced', '隔行扫描'),
          _boolText(video.progressive == 1, localeMap),
        ),
        MapEntry(
          _t('stream.details.fields.frameRate', '帧率'),
          _safe(video.rFrameRate),
        ),
        MapEntry(
          _t('stream.details.fields.bitrate', '码率'),
          _safe(_kbps(video.bps)),
        ),
        MapEntry(
          _t('stream.details.fields.range', '视频动态范围'),
          _safe(video.colorRangeType),
        ),
        MapEntry(
          _t('stream.details.fields.colorPrimaries', '色彩原色'),
          _safe(video.colorPrimaries),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(
          _t('stream.details.fields.colorSpace', '色彩空间'),
          _safe(video.colorSpace),
        ),
        MapEntry(
          _t('stream.details.fields.colorTransfer', '色彩转换'),
          _safe(video.colorTransfer),
        ),
        MapEntry(
          _t('stream.details.fields.bitDepth', '位深度'),
          _safe(video.bitDepth > 0 ? '${video.bitDepth} bit' : ''),
        ),
        MapEntry(
          _t('stream.details.fields.pixelFormat', '像素格式'),
          _safe(video.pixFmt),
        ),
        MapEntry(
          _t('stream.details.fields.refs', '参考帧'),
          _safe(video.refs > 0 ? '${video.refs}' : ''),
        ),
      ],
    );
  }
}

class _AudioCard extends StatelessWidget {
  final AudioTrackOption audio;
  final Map<String, dynamic> localeMap;

  const _AudioCard({required this.audio, required this.localeMap});

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lan = MediaLanguageMapper.languageName(audio.language);
    final headerParts = <String>[
      if (lan != '未知') lan,
      if (audio.codecName.trim().isNotEmpty) audio.codecName,
      if (audio.channelLayout.trim().isNotEmpty) audio.channelLayout,
    ];
    return _InfoCard(
      header: headerParts.join(' '),
      rows: [
        MapEntry(
          _t('stream.details.fields.language', '语言'),
          _safe(lan == '未知' ? '' : lan),
        ),
        MapEntry(
          _t('stream.details.fields.encoder', '编码器'),
          _safe(audio.codecName),
        ),
        MapEntry(
          _t('stream.details.fields.profile', '配置'),
          _safe(audio.profile),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(
          _t('stream.details.fields.channels', '声道'),
          _safe(_channelText(audio.channels)),
        ),
        MapEntry(
          _t('stream.details.fields.sampleRate', '采样率'),
          _safe(audio.sampleRate > 0 ? '${audio.sampleRate} Hz' : ''),
        ),
        MapEntry(
          _t('stream.details.fields.bitrate', '码率'),
          _safe(_kbps(audio.bps)),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(
          _t('stream.details.fields.layout', '布局'),
          _safe(audio.channelLayout),
        ),
        MapEntry(
          _t('stream.details.fields.default', '默认'),
          _boolText(audio.isDefault == 1, localeMap),
        ),
      ],
    );
  }
}

class _SubtitleCard extends StatelessWidget {
  final SubtitleTrackOption subtitle;
  final Map<String, dynamic> localeMap;

  const _SubtitleCard({required this.subtitle, required this.localeMap});

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lan = MediaLanguageMapper.languageName(subtitle.language);
    final fmt =
        (subtitle.format.isNotEmpty ? subtitle.format : subtitle.codecName)
            .trim()
            .toUpperCase();
    final header =
        '${lan == '未知' ? _t('stream.subtitle.subtitle', '字幕') : lan} ($fmt)';
    return _InfoCard(
      header: header,
      rows: [
        MapEntry(
          _t('stream.details.fields.language', '语言'),
          _safe(lan == '未知' ? '' : lan),
        ),
        MapEntry(
          _t('stream.details.fields.encoder', '编码器'),
          _safe(fmt.toLowerCase()),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(
          _t('stream.details.fields.default', '默认'),
          _boolText(subtitle.isDefault == 1, localeMap),
        ),
        MapEntry(
          _t('stream.details.fields.forced', '强制'),
          _boolText(subtitle.forced == 1, localeMap),
        ),
        const MapEntry('__divider__', ''),
        MapEntry(
          _t('stream.details.fields.external', '外部'),
          _boolText(subtitle.isExternal == 1, localeMap),
        ),
      ],
    );
  }
}

bool _isDividerRow(MapEntry<String, String> entry) =>
    entry.key == '__divider__';

String _safe(String value) => value.trim().isEmpty ? '-' : value.trim();

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

String _boolText(bool v, Map<String, dynamic> localeMap) =>
    MediaLocaleStore.text(
      localeMap,
      v ? 'common.yes' : 'common.no',
      fallback: v ? '是' : '否',
    );
