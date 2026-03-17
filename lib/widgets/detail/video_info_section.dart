import 'package:flutter/material.dart';

import '../../models/stream_track_data.dart';
import '../../theme/app_theme.dart';
import '../../utils/media_language_mapper.dart';

class VideoInfoSection extends StatelessWidget {
  final VideoStreamInfo? video;
  final AudioTrackOption? audio;
  final SubtitleTrackOption? subtitle;
  final VoidCallback? onViewAll;

  const VideoInfoSection({
    super.key,
    required this.video,
    required this.audio,
    required this.subtitle,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLightSurface = colors.backgroundBase.computeLuminance() >= 0.58;
    if (video == null && audio == null && subtitle == null) {
      return const SizedBox.shrink();
    }

    final panelColor = Color.alphaBlend(
      colors.surfaceStrong.withValues(alpha: isLightSurface ? 0.10 : 0.16),
      colors.backgroundElevated,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u89c6\u9891\u4fe1\u606f',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.borderSubtle.withValues(
                alpha: isLightSurface ? 0.58 : 0.80,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.videocam_rounded,
                title: '\u89c6\u9891',
                value: _videoLine(video),
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.graphic_eq_rounded,
                title: '\u97f3\u9891',
                value: _audioLine(audio),
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.closed_caption_rounded,
                title: '\u5b57\u5e55',
                value: _subtitleLine(subtitle),
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
                            '\u67e5\u770b\u5168\u90e8',
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

String _videoLine(VideoStreamInfo? video) {
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

String _audioLine(AudioTrackOption? audio) {
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

String _subtitleLine(SubtitleTrackOption? subtitle) {
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
