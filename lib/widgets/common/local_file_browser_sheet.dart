import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/storage_access_service.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';
import '../../utils/app_top_tip.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

class LocalFileBrowserSheet extends StatelessWidget {
  final String title;
  final List<String> allowedExtensions;

  const LocalFileBrowserSheet({
    super.key,
    required this.title,
    required this.allowedExtensions,
  });

  static Future<LocalBrowserFileSelection?> pickFile(
    BuildContext context, {
    required String title,
    required List<String> allowedExtensions,
  }) async {
    if (!context.mounted) return null;

    return AppSheetTransitions.showAdaptiveSheet<LocalBrowserFileSelection>(
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
                  onTap: () =>
                      AppSheetTransitions.close<LocalBrowserFileSelection>(
                        dialogContext,
                      ),
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
                  onTap: () =>
                      AppSheetTransitions.close<LocalBrowserFileSelection>(
                        context,
                      ),
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
              onFileSelected: (selection) async {
                if (!context.mounted) return;
                if (AppSheetTransitions.maybeClose<LocalBrowserFileSelection>(
                  context,
                  selection,
                )) {
                  return;
                }
                Navigator.of(context).pop(selection);
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
  final Future<void> Function(LocalBrowserFileSelection selection)?
  onFileSelected;

  const LocalFileBrowserBody({
    super.key,
    required this.allowedExtensions,
    this.onFileSelected,
  });

  @override
  State<LocalFileBrowserBody> createState() => _LocalFileBrowserBodyState();
}

class _LocalFileBrowserBodyState extends State<LocalFileBrowserBody> {
  final AppTopTip _topTip = AppTopTip();

  List<ScopedBrowserDirectory> _directoryStack =
      const <ScopedBrowserDirectory>[];
  List<ScopedBrowserEntry> _entries = const <ScopedBrowserEntry>[];
  bool _loading = true;
  bool _blocked = false;
  int _loadGeneration = 0;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _blocked = false;
      });
    }
    final root = await StorageAccessService.getScopedTreeRoot();
    if (!mounted) return;
    if (root == null) {
      setState(() {
        _loading = false;
        _blocked = true;
        _directoryStack = const <ScopedBrowserDirectory>[];
        _entries = const <ScopedBrowserEntry>[];
        _statusMessage = AppLocalizations.of(
          context,
        ).localFileNoAuthorizedFolder;
      });
      return;
    }
    _directoryStack = <ScopedBrowserDirectory>[root];
    await _openDirectory(root.id, depth: 0);
  }

  Future<void> _requestFolderAccess() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _blocked = false;
      });
    }
    final root = await StorageAccessService.requestScopedTreeAccess();
    if (!mounted) return;
    if (root == null) {
      setState(() {
        _loading = false;
        _blocked = true;
        _directoryStack = const <ScopedBrowserDirectory>[];
        _entries = const <ScopedBrowserEntry>[];
        _statusMessage = AppLocalizations.of(
          context,
        ).localFileAuthorizationCanceled;
      });
      return;
    }
    _directoryStack = <ScopedBrowserDirectory>[root];
    await _openDirectory(root.id, depth: 0);
  }

  Future<void> _openDirectory(String directoryId, {required int depth}) async {
    final loadGeneration = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _blocked = false;
      });
    }
    try {
      final listing = await StorageAccessService.listScopedTreeEntries(
        directoryId: directoryId,
        allowedExtensions: widget.allowedExtensions,
      );
      if (!mounted || loadGeneration != _loadGeneration) return;
      if (listing == null) {
        setState(() {
          _loading = false;
          _blocked = true;
          _directoryStack = _directoryStack.take(depth).toList(growable: false);
          _entries = const <ScopedBrowserEntry>[];
          _statusMessage = AppLocalizations.of(
            context,
          ).localFileAuthorizedFolderUnavailable;
        });
        return;
      }
      final nextStack = <ScopedBrowserDirectory>[
        ..._directoryStack.take(depth),
        listing.directory,
      ];
      setState(() {
        _loading = false;
        _blocked = false;
        _directoryStack = nextStack;
        _entries = listing.entries;
      });
    } catch (error) {
      if (!mounted || loadGeneration != _loadGeneration) return;
      setState(() {
        _loading = false;
        _blocked = true;
        _entries = const <ScopedBrowserEntry>[];
        _statusMessage = AppLocalizations.of(
          context,
        ).localFileReadDirectoryFailedRetry;
      });
      _topTip.show(
        context,
        message: AppLocalizations.of(
          context,
        ).localFileReadDirectoryFailed(error),
        color: context.appColors.danger,
      );
    }
  }

  Future<void> _goUp() async {
    if (_directoryStack.length <= 1) return;
    final parentIndex = _directoryStack.length - 2;
    await _openDirectory(_directoryStack[parentIndex].id, depth: parentIndex);
  }

  Future<void> _jumpToDirectory(int index) async {
    if (index < 0 || index >= _directoryStack.length) return;
    await _openDirectory(_directoryStack[index].id, depth: index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(
        child: SizedBox(width: 24, height: 24, child: BirdGlyph(size: 24)),
      );
    }

    if (_blocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _statusMessage.isEmpty
                    ? l10n.localFileAuthorizeFirst
                    : _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => unawaited(_requestFolderAccess()),
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(l10n.localFileAuthorizeFolder),
              ),
            ],
          ),
        ),
      );
    }

    final atRoot = _directoryStack.length <= 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _directoryStack.length; i++) ...[
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
                        label: _directoryStack[i].name,
                        onTap: () => unawaited(_jumpToDirectory(i)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => unawaited(_requestFolderAccess()),
              child: Text(l10n.localFileChangeFolder),
            ),
          ],
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
                    subtitle: l10n.localFileParentDirectory,
                    onTap: () => unawaited(_goUp()),
                  );
                }
                final actualIndex = atRoot ? index : index - 1;
                final entry = _entries[actualIndex];
                if (entry.isDirectory) {
                  return _BrowserEntryTile(
                    icon: Icons.folder_rounded,
                    title: entry.name,
                    subtitle: l10n.localFileFolder,
                    onTap: () => unawaited(
                      _openDirectory(entry.id, depth: _directoryStack.length),
                    ),
                  );
                }
                return _BrowserEntryTile(
                  icon: Icons.insert_drive_file_rounded,
                  title: entry.name,
                  subtitle: _humanFileSize(entry.sizeBytes),
                  onTap: () async {
                    await widget.onFileSelected?.call(
                      LocalBrowserFileSelection(
                        identifier: entry.id,
                        displayName: entry.name,
                      ),
                    );
                  },
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
