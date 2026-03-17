import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../../services/storage_access_service.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';
import '../../utils/app_top_tip.dart';

const String _defaultLocalBrowserPath = '/storage/emulated/0';

class _BrowserEntryRecord {
  final String path;
  final bool isDirectory;
  final int sizeBytes;

  const _BrowserEntryRecord({
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
  });

  String get name => path.split(Platform.pathSeparator).last;

  factory _BrowserEntryRecord.fromMap(Map<String, Object?> raw) {
    return _BrowserEntryRecord(
      path: (raw['path'] ?? '').toString(),
      isDirectory: raw['isDirectory'] == true,
      sizeBytes: switch (raw['sizeBytes']) {
        final int value => value,
        final num value => value.toInt(),
        _ => 0,
      },
    );
  }
}

Map<String, Object?> _readDirectoryEntriesPayload({
  required String normalizedPath,
  required List<String> allowedExtensions,
}) {
  final directory = Directory(normalizedPath);
  if (!directory.existsSync()) {
    throw const FileSystemException('Directory not found');
  }

  final allowed = allowedExtensions
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();

  final entries =
      directory
          .listSync(followLinks: false)
          .map<Map<String, Object?>?>((entity) {
            final name = entity.path.split(Platform.pathSeparator).last.trim();
            if (name.isEmpty || name.startsWith('.')) return null;
            if (entity is Directory) {
              return <String, Object?>{
                'path': entity.path,
                'isDirectory': true,
                'sizeBytes': 0,
              };
            }
            if (entity is! File) return null;
            final dot = name.lastIndexOf('.');
            if (dot <= 0 || dot >= name.length - 1) return null;
            final extension = name.substring(dot + 1).toLowerCase();
            if (!allowed.contains(extension)) return null;
            final sizeBytes = (() {
              try {
                return entity.lengthSync();
              } catch (_) {
                return 0;
              }
            })();
            return <String, Object?>{
              'path': entity.path,
              'isDirectory': false,
              'sizeBytes': sizeBytes,
            };
          })
          .whereType<Map<String, Object?>>()
          .toList()
        ..sort((left, right) {
          final leftIsDir = left['isDirectory'] == true;
          final rightIsDir = right['isDirectory'] == true;
          if (leftIsDir != rightIsDir) {
            return leftIsDir ? -1 : 1;
          }
          final leftName = (left['path'] ?? '')
              .toString()
              .split(Platform.pathSeparator)
              .last
              .toLowerCase();
          final rightName = (right['path'] ?? '')
              .toString()
              .split(Platform.pathSeparator)
              .last
              .toLowerCase();
          return leftName.compareTo(rightName);
        });

  return <String, Object?>{'path': normalizedPath, 'entries': entries};
}

class LocalFileBrowserSheet extends StatelessWidget {
  final String title;
  final List<String> allowedExtensions;

  const LocalFileBrowserSheet({
    super.key,
    required this.title,
    required this.allowedExtensions,
  });

  static Future<String?> pickFile(
    BuildContext context, {
    required String title,
    required List<String> allowedExtensions,
  }) async {
    if (!context.mounted) return null;

    return AppSheetTransitions.showAdaptiveSheet<String>(
      context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final colors = dialogContext.appColors;
        final media = MediaQuery.of(dialogContext);
        final isLandscape = media.size.width > media.size.height;
        final drawerWidth = isLandscape
            ? media.size.width * 0.54
            : media.size.width;
        final drawerHeight = isLandscape ? null : media.size.height * 0.56;
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogContext).maybePop(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                top: isLandscape ? 0 : null,
                right: 0,
                left: isLandscape ? null : 0,
                bottom: 0,
                width: isLandscape ? drawerWidth : null,
                height: drawerHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      colors.surfaceStrong.withValues(
                        alpha: isLandscape ? 0.70 : 0.82,
                      ),
                      colors.overlayScrim.withValues(
                        alpha: isLandscape ? 0.30 : 0.48,
                      ),
                    ),
                    border: isLandscape
                        ? Border.all(color: colors.borderSubtle)
                        : null,
                  ),
                  child: SafeArea(
                    child: LocalFileBrowserSheet(
                      title: title,
                      allowedExtensions: allowedExtensions,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        landscape ? 16 : 14,
        landscape ? 10 : 12,
        landscape ? 12 : 14,
        landscape ? 10 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: colors.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LocalFileBrowserBody(
              allowedExtensions: allowedExtensions,
              onFileSelected: (path) async {
                if (!context.mounted) return;
                Navigator.of(context).pop(path);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LocalFileBrowserBody extends StatefulWidget {
  final List<String> allowedExtensions;
  final String initialPath;
  final Future<void> Function(String path)? onFileSelected;

  const LocalFileBrowserBody({
    super.key,
    required this.allowedExtensions,
    this.initialPath = _defaultLocalBrowserPath,
    this.onFileSelected,
  });

  @override
  State<LocalFileBrowserBody> createState() => _LocalFileBrowserBodyState();
}

class _LocalFileBrowserBodyState extends State<LocalFileBrowserBody> {
  final AppTopTip _topTip = AppTopTip();
  late final Set<String> _allowedExtensions = widget.allowedExtensions
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  late final String _rootPath = _normalizePath(widget.initialPath);

  String _currentPath = '';
  List<_BrowserEntryRecord> _entries = const <_BrowserEntryRecord>[];
  bool _loading = true;
  bool _blocked = false;
  int _directoryLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureAccessAndOpen());
  }

  @override
  void dispose() {
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _ensureAccessAndOpen() async {
    final hasAccess = await StorageAccessService.hasFileAccess();
    if (!hasAccess) {
      final granted = await StorageAccessService.requestFileAccess();
      if (!granted) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _blocked = true;
        });
        _topTip.show(
          context,
          message: '文件访问权限未授予，请先在系统设置中允许访问后重试',
          color: context.appColors.danger,
        );
        return;
      }
    }
    await StorageAccessService.primaryStorageRoot();
    await _openDirectory(_rootPath);
  }

  Future<void> _openDirectory(String path) async {
    final normalizedPath = _sanitizePath(path);
    final loadGeneration = ++_directoryLoadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _blocked = false;
      });
    }
    try {
      final payload = await Isolate.run<Map<String, Object?>>(
        () => _readDirectoryEntriesPayload(
          normalizedPath: normalizedPath,
          allowedExtensions: _allowedExtensions.toList(growable: false),
        ),
      );
      if (!mounted || loadGeneration != _directoryLoadGeneration) return;
      final entries =
          (payload['entries'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (raw) =>
                    _BrowserEntryRecord.fromMap(raw.cast<String, Object?>()),
              )
              .toList(growable: false);
      setState(() {
        _currentPath = normalizedPath;
        _entries = entries;
        _loading = false;
        _blocked = false;
      });
    } catch (_) {
      if (!mounted || loadGeneration != _directoryLoadGeneration) return;
      setState(() {
        _loading = false;
        _blocked = true;
      });
      _topTip.show(
        context,
        message: '无法读取当前目录，请确认已授予文件访问权限',
        color: context.appColors.danger,
      );
    }
  }

  List<String> get _segments {
    final normalized = _normalizePath(_currentPath);
    if (normalized == _rootPath) {
      return const <String>['0'];
    }
    final relative = normalized.startsWith('$_rootPath/')
        ? normalized.substring(_rootPath.length + 1)
        : '';
    final children = relative
        .split('/')
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    return <String>['0', ...children];
  }

  String _pathForSegment(int index) {
    if (index <= 0) return _rootPath;
    final relativeParts = _segments.skip(1).take(index).toList(growable: false);
    return '$_rootPath/${relativeParts.join('/')}';
  }

  Future<void> _goUp() async {
    if (_currentPath.trim().isEmpty) return;
    final normalizedCurrent = _normalizePath(_currentPath);
    if (normalizedCurrent == _rootPath) return;
    final parent = _normalizePath(Directory(normalizedCurrent).parent.path);
    if (parent == normalizedCurrent) return;
    await _openDirectory(parent);
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').replaceAll(RegExp('/+'), '/');
  }

  String _sanitizePath(String path) {
    final normalized = _normalizePath(path);
    if (normalized == _rootPath) return normalized;
    if (normalized.startsWith('$_rootPath/')) return normalized;
    return _rootPath;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: colors.accent,
          ),
        ),
      );
    }

    if (_blocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '无法访问本地目录，请检查系统文件访问权限后重试',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    final atRoot = _normalizePath(_currentPath) == _rootPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _segments.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.textMuted,
                      size: 18,
                    ),
                  ),
                _BreadcrumbText(
                  label: _segments[i],
                  onTap: () => _openDirectory(_pathForSegment(i)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.borderSubtle),
              color: colors.surfaceSubtle,
            ),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
              itemCount: _entries.length + (atRoot ? 0 : 1),
              itemBuilder: (context, index) {
                if (!atRoot && index == 0) {
                  return _BrowserEntryTile(
                    icon: Icons.arrow_upward_rounded,
                    title: '..',
                    subtitle: '返回上一级',
                    onTap: _goUp,
                  );
                }
                final actualIndex = atRoot ? index : index - 1;
                final entry = _entries[actualIndex];
                if (entry.isDirectory) {
                  return _BrowserEntryTile(
                    icon: Icons.folder_rounded,
                    title: entry.name,
                    subtitle: '文件夹',
                    onTap: () => _openDirectory(entry.path),
                  );
                }
                return _BrowserEntryTile(
                  icon: Icons.insert_drive_file_rounded,
                  title: entry.name,
                  subtitle: _humanFileSize(entry.sizeBytes),
                  onTap: () async => widget.onFileSelected?.call(entry.path),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String _humanFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }
}

class _BreadcrumbText extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BreadcrumbText({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _BrowserEntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BrowserEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: colors.surface,
                ),
                child: Icon(icon, color: colors.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
