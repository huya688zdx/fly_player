import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/detail/media_source_info.dart';
import '../../theme/app_theme.dart';
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

  /// Emby 等公共后端：从中立 [MediaSourceInfo] 的各流摘要取每类型首条，拼成单行。
  /// 飞牛的行格式化在调用方侧 `lib/ui/feiniu_video_info_lines.dart`（H-015:
  /// 本组件不再持有任何后端专属格式化）。
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
