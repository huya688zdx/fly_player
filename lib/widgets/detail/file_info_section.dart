import 'package:flutter/material.dart';

import '../../models/authorized_dir_entry.dart';
import '../../models/stream_track_data.dart';
import '../../theme/detail_tokens.dart';

class FileInfoSection extends StatefulWidget {
  final StreamFileInfo? file;
  final List<AuthorizedDirEntry> authorizedDirs;
  final String title;
  final String locationLabel;
  final String sizeLabel;
  final String createdAtLabel;
  final String addedAtLabel;
  final String toggleToRawLabel;
  final String toggleToFriendlyLabel;

  const FileInfoSection({
    super.key,
    required this.file,
    this.authorizedDirs = const <AuthorizedDirEntry>[],
    this.title = '文件信息',
    this.locationLabel = '文件位置',
    this.sizeLabel = '文件大小',
    this.createdAtLabel = '文件创建日期',
    this.addedAtLabel = '添加日期',
    this.toggleToRawLabel = '/vol',
    this.toggleToFriendlyLabel = '转换',
  });

  @override
  State<FileInfoSection> createState() => _FileInfoSectionState();
}

class _FileInfoSectionState extends State<FileInfoSection> {
  bool _showRawPath = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    if (f == null) return const SizedBox.shrink();

    final friendlyPath = _friendlyPath(f.path, widget.authorizedDirs);
    final displayedPath = _showRawPath || friendlyPath.isEmpty
        ? f.path
        : friendlyPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            color: DetailTokens.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B2635), Color(0xFF182231)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RowBlock(
                label: widget.locationLabel,
                value: displayedPath,
                trailing: TextButton.icon(
                  onPressed: friendlyPath.isEmpty
                      ? null
                      : () => setState(() => _showRawPath = !_showRawPath),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: friendlyPath.isEmpty
                        ? DetailTokens.textMuted
                        : const Color(0xFF9FB5D3),
                  ),
                  icon: Icon(
                    _showRawPath
                        ? Icons.folder_open_outlined
                        : Icons.swap_horiz,
                    size: 15,
                  ),
                  label: Text(
                    _showRawPath
                        ? widget.toggleToFriendlyLabel
                        : widget.toggleToRawLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _RowBlock(label: widget.sizeLabel, value: _formatBytes(f.size)),
              const SizedBox(height: 16),
              _RowBlock(
                label: widget.createdAtLabel,
                value: _formatTs(f.fileBirthTime),
              ),
              const SizedBox(height: 16),
              _RowBlock(
                label: widget.addedAtLabel,
                value: _formatTs(f.createTime),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RowBlock extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _RowBlock({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: DetailTokens.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value.isEmpty ? '-' : value,
          style: const TextStyle(
            color: DetailTokens.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.34,
          ),
        ),
      ],
    );
  }
}

String _friendlyPath(String rawPath, List<AuthorizedDirEntry> authorizedDirs) {
  final normalized = rawPath.trim();
  if (normalized.isEmpty || !normalized.startsWith('/vol')) {
    return normalized;
  }

  AuthorizedDirEntry? matched;
  for (final entry in authorizedDirs) {
    final path = entry.path.trim();
    if (path.isEmpty) continue;
    final hit = normalized == path || normalized.startsWith('$path/');
    if (!hit) continue;
    if (matched == null || path.length > matched.path.length) {
      matched = entry;
    }
  }

  final rootMatch = RegExp(r'^/vol(\d+)/\d+').firstMatch(normalized);
  if (rootMatch == null) return normalized;

  final volumeNo = rootMatch.group(1) ?? '';
  final rootPrefix = rootMatch.group(0) ?? '';
  if (rootPrefix.isEmpty || volumeNo.isEmpty) return normalized;

  final suffix = normalized.substring(rootPrefix.length);
  final uname = matched?.uname.trim().isNotEmpty == true
      ? matched!.uname.trim()
      : '';
  final head = uname.isNotEmpty ? '存储空间$volumeNo/$uname 的文件' : '存储空间$volumeNo';
  return '$head$suffix';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '-';
  const kb = 1024.0;
  const mb = kb * 1024.0;
  const gb = mb * 1024.0;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
  return '$bytes B';
}

String _formatTs(int ms) {
  if (ms <= 0) return '-';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}/${p2(dt.month)}/${p2(dt.day)} ${p2(dt.hour)}:${p2(dt.minute)}';
}
