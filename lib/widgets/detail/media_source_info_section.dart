import 'package:flutter/material.dart';

import '../../media_backend/detail/media_source_info.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';

/// 中立后端（Emby 等）详情页的「文件信息 + 视频信息」区块。
///
/// 数据来自中立 [MediaSourceInfo]（已格式化好行文本），与飞牛专属的 `FileInfoSection`/
/// `VideoInfoSection`（绑流轨道 / NAS 授权目录）解耦。按取舍只展示文件路径 / 容器 / 大小 /
/// 添加日期 + 各流摘要行，不做 `/vol` 切换、授权目录、逐字段明细。
class MediaSourceInfoSection extends StatelessWidget {
  const MediaSourceInfoSection({
    super.key,
    required this.info,
    required this.fileTitle,
    required this.videoTitle,
    required this.locationLabel,
    required this.videoLabel,
    required this.audioLabel,
    required this.subtitleLabel,
    required this.addedAtPrefix,
  });

  final MediaSourceInfo info;
  final String fileTitle;
  final String videoTitle;
  final String locationLabel;
  final String videoLabel;
  final String audioLabel;
  final String subtitleLabel;
  final String addedAtPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasFile =
        info.path.isNotEmpty || info.container.isNotEmpty || info.sizeBytes > 0;
    final hasStreams = info.streams.isNotEmpty;
    if (!hasFile && !hasStreams) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hasFile) ...<Widget>[
          _sectionTitle(colors, fileTitle),
          const SizedBox(height: 12),
          LiquidGlass(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (info.path.isNotEmpty)
                  _InfoRow(
                    icon: Icons.folder_rounded,
                    title: locationLabel,
                    value: info.path,
                  ),
                if (_fileMetaLine().isNotEmpty) ...<Widget>[
                  if (info.path.isNotEmpty) const SizedBox(height: 14),
                  Text(
                    _fileMetaLine(),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (hasStreams) ...<Widget>[
          if (hasFile) const SizedBox(height: 20),
          _sectionTitle(colors, videoTitle),
          const SizedBox(height: 12),
          LiquidGlass(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _streamRows(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(AppThemeColors colors, String title) {
    return Text(
      title,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  String _fileMetaLine() {
    return <String>[
      if (info.container.isNotEmpty) info.container.toUpperCase(),
      if (info.sizeBytes > 0) _formatSize(info.sizeBytes),
      if (info.addedDate.isNotEmpty)
        '$addedAtPrefix ${_formatDate(info.addedDate)}',
    ].join('  ·  ');
  }

  List<Widget> _streamRows() {
    final rows = <Widget>[];
    for (final stream in info.streams) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(
        _InfoRow(
          icon: _iconFor(stream.type),
          title: _titleFor(stream.type),
          value: <String>[
            if (stream.label.isNotEmpty) stream.label,
            if (stream.summary.isNotEmpty) stream.summary,
          ].join('  ·  '),
        ),
      );
    }
    return rows;
  }

  IconData _iconFor(MediaStreamType type) {
    switch (type) {
      case MediaStreamType.video:
        return Icons.videocam_rounded;
      case MediaStreamType.audio:
        return Icons.graphic_eq_rounded;
      case MediaStreamType.subtitle:
        return Icons.closed_caption_rounded;
      case MediaStreamType.other:
        return Icons.info_outline_rounded;
    }
  }

  String _titleFor(MediaStreamType type) {
    switch (type) {
      case MediaStreamType.video:
        return videoLabel;
      case MediaStreamType.audio:
        return audioLabel;
      case MediaStreamType.subtitle:
        return subtitleLabel;
      case MediaStreamType.other:
        return '';
    }
  }
}

/// 字节 → 友好大小（与飞牛文件信息观感一致：GB / MB 两位小数）。
String _formatSize(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// ISO 日期 → `yyyy/MM/dd HH:mm`（本地时间），解析失败原样返回。
String _formatDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: colors.textMuted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
