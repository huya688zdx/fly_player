import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_log_service.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_top_tip.dart';

class AppLogScreen extends StatefulWidget {
  const AppLogScreen({super.key});

  @override
  State<AppLogScreen> createState() => _AppLogScreenState();
}

class _AppLogScreenState extends State<AppLogScreen> {
  final AppTopTip _topTip = AppTopTip();
  late final Future<void> _initializeFuture = AppLogService.instance
      .initialize();

  bool _exporting = false;
  bool _clearing = false;

  @override
  void dispose() {
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    if (_exporting) return;
    final l10n = AppLocalizations.of(context);
    final service = AppLogService.instance;
    if (!await service.hasExportableLogs()) {
      if (!mounted) return;
      _topTip.show(
        context,
        message: l10n.logNoExportableLogs,
        color: context.appColors.warning,
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final result = await service.exportToTxt();
      if (!mounted) return;
      final message = result.usedExternalStorage
          ? l10n.logTxtExported(result.path)
          : l10n.logExternalUnavailableExported(result.path);
      _topTip.show(context, message: message, color: context.appColors.success);
    } catch (error) {
      if (!mounted) return;
      _topTip.show(
        context,
        message: l10n.logExportFailed('$error'),
        color: context.appColors.danger,
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _handleClear() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.logClearTitle,
      content: l10n.logClearContent,
      cancelText: l10n.commonCancel,
      confirmText: l10n.logClearConfirm,
      confirmColor: context.appColors.danger,
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearing = true);
    try {
      await AppLogService.instance.clear();
      if (!mounted) return;
      _topTip.show(
        context,
        message: l10n.logCleared,
        color: context.appColors.success,
      );
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(context, title: Text(l10n.logInfoTitle)),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: FutureBuilder<void>(
            future: _initializeFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return AnimatedBuilder(
                animation: AppLogService.instance,
                builder: (context, _) {
                  final service = AppLogService.instance;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 720;
                      final maxContentWidth = constraints.maxWidth >= 1080
                          ? 960.0
                          : 780.0;
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 24,
                            12,
                            compact ? 16 : 24,
                            compact ? 24 : 32,
                          ),
                          children: <Widget>[
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxContentWidth,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  _LogSummaryCard(
                                    compact: compact,
                                    totalCount: service.entries.length,
                                    errorCount: service.errorCount,
                                    latestEntry: service.latestEntry,
                                    exporting: _exporting,
                                    clearing: _clearing,
                                    onExport: _handleExport,
                                    onClear: _handleClear,
                                  ),
                                  const SizedBox(height: 18),
                                  if (service.entries.isEmpty)
                                    const _LogEmptyCard()
                                  else
                                    ...service.entries.map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        child: _LogEntryCard(entry: entry),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LogSummaryCard extends StatelessWidget {
  final bool compact;
  final int totalCount;
  final int errorCount;
  final AppLogEntry? latestEntry;
  final bool exporting;
  final bool clearing;
  final VoidCallback onExport;
  final VoidCallback onClear;

  const _LogSummaryCard({
    required this.compact,
    required this.totalCount,
    required this.errorCount,
    required this.latestEntry,
    required this.exporting,
    required this.clearing,
    required this.onExport,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.borderSubtle),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.surface,
            Color.alphaBlend(
              colors.selection.withValues(alpha: 0.08),
              colors.surfaceSubtle,
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.logErrorLogTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(
                compact ? 20 : 22,
                role: AdaptiveFontRole.title,
              ),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.logErrorLogDescription,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13.6),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _SummaryBadge(
                label: l10n.logTotal,
                value: '$totalCount',
                tint: colors.selection,
              ),
              _SummaryBadge(
                label: l10n.logErrors,
                value: '$errorCount',
                tint: colors.danger,
              ),
              _SummaryBadge(
                label: l10n.logLatest,
                value: latestEntry == null
                    ? l10n.logNone
                    : AppLogService.formatTimestamp(latestEntry!.timestamp),
                tint: colors.accent,
                wide: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _ActionButton(
                icon: Icons.download_rounded,
                label: exporting ? l10n.logExporting : l10n.logExportTxt,
                backgroundColor: colors.accent,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                onPressed: exporting || clearing ? null : onExport,
              ),
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                label: clearing ? l10n.logClearing : l10n.logClearAction,
                backgroundColor: colors.surfaceStrong,
                foregroundColor: colors.textPrimary,
                onPressed: exporting || clearing ? null : onClear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color tint;
  final bool wide;

  const _SummaryBadge({
    required this.label,
    required this.value,
    required this.tint,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      constraints: BoxConstraints(minWidth: wide ? 220 : 108),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tint.withValues(alpha: 0.10),
          colors.surfaceSubtle,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Color.alphaBlend(
            tint.withValues(alpha: 0.18),
            colors.borderSubtle,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: AdaptiveText.roleSize(
                12.5,
                role: AdaptiveFontRole.caption,
              ),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(14),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.52),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.72),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: TextStyle(
            fontSize: AdaptiveText.roleSize(14, role: AdaptiveFontRole.button),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LogEmptyCard extends StatelessWidget {
  const _LogEmptyCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.inbox_outlined, color: colors.textMuted, size: 34),
          const SizedBox(height: 12),
          Text(
            l10n.logEmptyTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(15.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.logEmptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13.4),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogEntryCard extends StatefulWidget {
  final AppLogEntry entry;

  const _LogEntryCard({required this.entry});

  @override
  State<_LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<_LogEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final entry = widget.entry;
    final accent = switch (entry.level) {
      AppLogLevel.error => colors.danger,
      AppLogLevel.warning => colors.warning,
      AppLogLevel.info => colors.accent,
    };

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.18),
            colors.borderSubtle,
          ),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      entry.level.label,
                      style: TextStyle(
                        color: accent,
                        fontSize: AdaptiveText.roleSize(
                          12.2,
                          role: AdaptiveFontRole.caption,
                        ),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    entry.source,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(12.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    AppLogService.formatTimestamp(entry.timestamp),
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: AdaptiveText.roleSize(
                        12.2,
                        role: AdaptiveFontRole.caption,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                entry.message,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: AdaptiveText.roleSize(14.2),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              if ((entry.details ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  entry.details!.trim(),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(13.2),
                    height: 1.45,
                  ),
                ),
              ],
              if ((entry.stackTraceText ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.unfold_less_rounded
                        : Icons.unfold_more_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _expanded ? l10n.logCollapseStack : l10n.logExpandStack,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.link,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, 0),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.backgroundBase.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: SelectableText(
                      entry.stackTraceText!.trim(),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(
                          12.5,
                          role: AdaptiveFontRole.caption,
                        ),
                        height: 1.45,
                      ),
                    ),
                  ),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
