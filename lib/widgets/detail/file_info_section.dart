import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/authorized_dir_entry.dart';
import '../../models/stream_track_data.dart';
import '../../theme/app_theme.dart';

class FileInfoSection extends StatefulWidget {
  final StreamFileInfo? file;
  final List<AuthorizedDirEntry> authorizedDirs;
  final String? title;
  final String? locationLabel;
  final String? sizeLabel;
  final String? createdAtLabel;
  final String? addedAtLabel;
  final String toggleToRawLabel;
  final String? toggleToFriendlyLabel;

  const FileInfoSection({
    super.key,
    required this.file,
    this.authorizedDirs = const <AuthorizedDirEntry>[],
    this.title,
    this.locationLabel,
    this.sizeLabel,
    this.createdAtLabel,
    this.addedAtLabel,
    this.toggleToRawLabel = '/vol',
    this.toggleToFriendlyLabel,
  });

  @override
  State<FileInfoSection> createState() => _FileInfoSectionState();
}

class _FileInfoSectionState extends State<FileInfoSection> {
  bool _showRawPath = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final f = widget.file;
    if (f == null) return const SizedBox.shrink();

    final friendlyPath = _friendlyPath(f.path, widget.authorizedDirs, l10n);
    final displayedPath = _showRawPath || friendlyPath.isEmpty
        ? f.path
        : friendlyPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title ?? l10n.detailFileInfoTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.surfaceStrong, colors.surface],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RowBlock(
                label: widget.locationLabel ?? l10n.fileInfoLocationLabel,
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
                        ? colors.textMuted
                        : colors.link,
                  ),
                  icon: Icon(
                    _showRawPath
                        ? Icons.folder_open_outlined
                        : Icons.swap_horiz,
                    size: 15,
                  ),
                  label: Text(
                    _showRawPath
                        ? widget.toggleToFriendlyLabel ??
                              l10n.fileInfoToggleToFriendly
                        : widget.toggleToRawLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _RowBlock(
                label: widget.sizeLabel ?? l10n.fileInfoSizeLabel,
                value: _formatBytes(f.size),
              ),
              const SizedBox(height: 16),
              _RowBlock(
                label: widget.createdAtLabel ?? l10n.fileInfoCreatedAtLabel,
                value: _formatTs(f.fileBirthTime),
              ),
              const SizedBox(height: 16),
              _RowBlock(
                label: widget.addedAtLabel ?? l10n.fileInfoAddedAtLabel,
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
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.textMuted,
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
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.34,
          ),
        ),
      ],
    );
  }
}

String _friendlyPath(
  String rawPath,
  List<AuthorizedDirEntry> authorizedDirs,
  AppLocalizations l10n,
) {
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
  final head = uname.isNotEmpty
      ? l10n.fileInfoStorageSpaceFile(volumeNo, uname)
      : l10n.fileInfoStorageSpace(volumeNo);
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
