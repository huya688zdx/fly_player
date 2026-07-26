import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/detail/media_source_info.dart';
import '../../models/stream_track_data.dart';
import '../../theme/app_theme.dart';
import '../../utils/media_language_mapper.dart';
import '../common/liquid_glass.dart';

/// 「视频信息」区块的后端中立数据——已格式化好的三行（视频 / 音频 / 字幕）文本。
///
/// 这是飞牛与 Emby 等公共后端的**共同管理点**：两端各自把自家数据（飞牛流轨道 DTO /
/// Emby 中立 [MediaSourceInfo]）格式化成同一组行文本，再喂给同一个 [VideoInfoSection]
/// 渲染，从而视频信息块视觉统一、格式化逻辑各归各家。
class VideoInfoLines {
  const VideoInfoLines({this.video = '', this.audio = '', this.subtitle = ''});

  final String video;
  final String audio;
  final String subtitle;

  bool get hasAny =>
      video.trim().isNotEmpty ||
      audio.trim().isNotEmpty ||
      subtitle.trim().isNotEmpty;

  /// 飞牛：从当前选中流的视频 / 音频 / 字幕轨道 DTO 格式化（保持原飞牛文案逐字不变）。
  factory VideoInfoLines.fromFeiniu(
    VideoStreamInfo? video,
    AudioTrackOption? audio,
    SubtitleTrackOption? subtitle,
  ) {
    return VideoInfoLines(
      video: _feiniuVideoLine(video),
      audio: _feiniuAudioLine(audio),
      subtitle: _feiniuSubtitleLine(subtitle),
    );
  }

  /// Emby 等公共后端：从中立 [MediaSourceInfo] 的各流摘要取每类型首条，拼成单行。
  factory VideoInfoLines.fromSource(MediaSourceInfo info) {
    return VideoInfoLines(
      video: _sourceLineFor(info, MediaStreamType.video),
      audio: _sourceLineFor(info, MediaStreamType.audio),
      subtitle: _sourceLineFor(info, MediaStreamType.subtitle),
    );
  }
}

class VideoInfoSection extends StatelessWidget {
  final VideoInfoLines lines;
  final VoidCallback? onViewAll;

  const VideoInfoSection({super.key, required this.lines, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    if (!lines.hasAny) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.detailVideoInfoTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        LiquidGlass(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoRow(
                icon: Icons.videocam_rounded,
                title: l10n.mediaDetailsVideoSection,
                value: lines.video,
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.graphic_eq_rounded,
                title: l10n.mediaDetailsAudioSection,
                value: lines.audio,
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.closed_caption_rounded,
                title: l10n.mediaDetailsSubtitleSection,
                value: lines.subtitle,
              ),
              if (onViewAll != null) ...[
                const SizedBox(height: 14),
                Divider(color: colors.borderSubtle, height: 1),
                InkWell(
                  onTap: onViewAll,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.detailVideoInfoViewAll,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.textSecondary,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.textMuted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.isEmpty ? '-' : value,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _feiniuVideoLine(VideoStreamInfo? video) {
  if (video == null) return '';
  final res = video.resolutionType.trim().isEmpty ? '' : video.resolutionType;
  final codec = video.codecName.trim().isEmpty
      ? ''
      : video.codecName.toUpperCase();
  final mbps = video.bps > 0
      ? '${(video.bps / 1000000.0).toStringAsFixed(2)} mbps'
      : '';
  final bit = video.bitDepth > 0 ? '${video.bitDepth} bit' : '';
  final parts = <String>[
    if (res.isNotEmpty) res,
    if (codec.isNotEmpty) codec,
    if (mbps.isNotEmpty) mbps,
    if (bit.isNotEmpty) bit,
  ];
  return parts.join(' ');
}

String _feiniuAudioLine(AudioTrackOption? audio) {
  if (audio == null) return '';
  final lan = MediaLanguageMapper.languageName(audio.language);
  final codec = audio.codecName.trim().isEmpty
      ? ''
      : audio.codecName.toUpperCase();
  final ch = audio.channelLayout.trim().isNotEmpty
      ? audio.channelLayout.trim()
      : _channelFromCount(audio.channels);
  final rate = audio.sampleRate > 0 ? '${audio.sampleRate} Hz' : '';
  final parts = <String>[
    if (lan.isNotEmpty && lan != '未知') lan,
    if (codec.isNotEmpty) codec,
    if (ch.isNotEmpty) ch,
    if (rate.isNotEmpty) rate,
  ];
  return parts.join('  ');
}

String _feiniuSubtitleLine(SubtitleTrackOption? subtitle) {
  if (subtitle == null) return '';
  final lan = MediaLanguageMapper.languageName(subtitle.language);
  final fmt =
      (subtitle.format.isNotEmpty ? subtitle.format : subtitle.codecName)
          .trim()
          .toUpperCase();
  final parts = <String>[
    if (lan.isNotEmpty && lan != '未知') lan,
    if (fmt.isNotEmpty) fmt,
  ];
  return parts.join('  ');
}

String _channelFromCount(int channels) {
  if (channels == 1) return '1.0ch';
  if (channels == 2) return '2.0ch';
  if (channels == 6) return '5.1ch';
  if (channels == 8) return '7.1ch';
  return channels > 0 ? '$channels ch' : '';
}

/// 中立 [MediaSourceInfo] 某类型首条流 → 单行（`label  summary`）。
String _sourceLineFor(MediaSourceInfo info, MediaStreamType type) {
  for (final stream in info.streams) {
    if (stream.type != type) continue;
    return <String>[
      if (stream.label.trim().isNotEmpty) stream.label.trim(),
      if (stream.summary.trim().isNotEmpty) stream.summary.trim(),
    ].join('  ');
  }
  return '';
}
