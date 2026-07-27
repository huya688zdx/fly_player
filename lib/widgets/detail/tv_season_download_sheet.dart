import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/download_task_record.dart';
import '../../models/tv_episode_browser_models.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../../theme/download_sheet_theme.dart';
import '../../ui/capability_badge_mapper.dart';
import '../../ui/detail_artwork_resolver.dart';
import '../../ui/media_detail_components.dart';

class TvSeasonDownloadQualityOption {
  final String value;
  final String label;
  final String hint;

  const TvSeasonDownloadQualityOption({
    required this.value,
    required this.label,
    this.hint = '',
  });
}

class TvSeasonDownloadSheetPayload {
  final String sheetTitle;
  final String qualityLabel;
  final String qualitySheetTitle;
  final String itemTitle;
  final List<String> posterUrls;
  final String token;
  final String posterBadgeLabel;
  final List<TvEpisodeCardData> episodeEntries;
  final List<TvSeasonDownloadQualityOption> qualityOptions;
  final String initialQuality;
  final int initialRangeIndex;
  final int rangeSize;
  final String downloadLabel;
  final String downloadingLabel;
  final String downloadedLabel;
  final String pausedLabel;
  final String openListLabel;
  final DownloadActionState primaryActionState;
  final Map<String, DownloadActionState> episodeActionStates;
  final bool loadingError;

  const TvSeasonDownloadSheetPayload({
    required this.sheetTitle,
    required this.qualityLabel,
    required this.qualitySheetTitle,
    required this.itemTitle,
    required this.posterUrls,
    required this.token,
    required this.posterBadgeLabel,
    this.episodeEntries = const <TvEpisodeCardData>[],
    required this.qualityOptions,
    required this.initialQuality,
    this.initialRangeIndex = 0,
    this.rangeSize = 30,
    required this.downloadLabel,
    required this.downloadingLabel,
    required this.downloadedLabel,
    required this.pausedLabel,
    required this.openListLabel,
    this.primaryActionState = DownloadActionState.idle,
    this.episodeActionStates = const <String, DownloadActionState>{},
    this.loadingError = false,
  });

  TvSeasonDownloadSheetPayload copyWith({bool? loadingError}) {
    return TvSeasonDownloadSheetPayload(
      sheetTitle: sheetTitle,
      qualityLabel: qualityLabel,
      qualitySheetTitle: qualitySheetTitle,
      itemTitle: itemTitle,
      posterUrls: posterUrls,
      token: token,
      posterBadgeLabel: posterBadgeLabel,
      episodeEntries: episodeEntries,
      qualityOptions: qualityOptions,
      initialQuality: initialQuality,
      initialRangeIndex: initialRangeIndex,
      rangeSize: rangeSize,
      downloadLabel: downloadLabel,
      downloadingLabel: downloadingLabel,
      downloadedLabel: downloadedLabel,
      pausedLabel: pausedLabel,
      openListLabel: openListLabel,
      primaryActionState: primaryActionState,
      episodeActionStates: episodeActionStates,
      loadingError: loadingError ?? this.loadingError,
    );
  }
}

class TvSeasonDownloadSheet extends StatefulWidget {
  final ValueNotifier<TvSeasonDownloadSheetPayload> payloadNotifier;
  final ValueChanged<String> onDownloadTap;
  final void Function(String episodeGuid, String quality)? onEpisodeDownloadTap;
  final VoidCallback onOpenDownloadListTap;

  const TvSeasonDownloadSheet({
    super.key,
    required this.payloadNotifier,
    required this.onDownloadTap,
    this.onEpisodeDownloadTap,
    required this.onOpenDownloadListTap,
  });

  static Future<void> show(
    BuildContext context, {
    required ValueNotifier<TvSeasonDownloadSheetPayload> payloadNotifier,
    required ValueChanged<String> onDownloadTap,
    void Function(String episodeGuid, String quality)? onEpisodeDownloadTap,
    required VoidCallback onOpenDownloadListTap,
  }) async {
    await HapticFeedback.mediumImpact();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.downloadSheetTheme.barrierColor,
      builder: (context) {
        return TvSeasonDownloadSheet(
          payloadNotifier: payloadNotifier,
          onDownloadTap: onDownloadTap,
          onEpisodeDownloadTap: onEpisodeDownloadTap,
          onOpenDownloadListTap: onOpenDownloadListTap,
        );
      },
    );
  }

  @override
  State<TvSeasonDownloadSheet> createState() => _TvSeasonDownloadSheetState();
}

class _TvSeasonDownloadSheetState extends State<TvSeasonDownloadSheet> {
  late TvSeasonDownloadSheetPayload _payload;
  late String _selectedQuality;
  late int _selectedRangeIndex;
  final Map<String, DownloadActionState> _localActionStates =
      <String, DownloadActionState>{};

  @override
  void initState() {
    super.initState();
    _payload = widget.payloadNotifier.value;
    _initFromPayload(_payload);
    widget.payloadNotifier.addListener(_onPayloadUpdated);
  }

  @override
  void dispose() {
    widget.payloadNotifier.removeListener(_onPayloadUpdated);
    super.dispose();
  }

  void _onPayloadUpdated() {
    final updated = widget.payloadNotifier.value;
    if (identical(updated, _payload)) return;
    setState(() {
      _payload = updated;
      _selectedQuality = _resolveInitialQuality(updated);
      _localActionStates
        ..clear()
        ..addAll(updated.episodeActionStates);
    });
  }

  void _initFromPayload(TvSeasonDownloadSheetPayload payload) {
    _selectedQuality = _resolveInitialQuality(payload);
    _selectedRangeIndex = payload.initialRangeIndex;
    _localActionStates
      ..clear()
      ..addAll(payload.episodeActionStates);
  }

  String _resolveInitialQuality(TvSeasonDownloadSheetPayload payload) {
    final initial = payload.initialQuality.trim();
    if (initial.isNotEmpty &&
        payload.qualityOptions.any((option) => option.value == initial)) {
      return initial;
    }
    if (payload.qualityOptions.isNotEmpty) {
      return payload.qualityOptions.first.value;
    }
    return '';
  }

  Future<void> _openQualitySheet() async {
    final selected = await _TvSeasonDownloadQualitySheet.show(
      context,
      title: _payload.qualitySheetTitle,
      options: _payload.qualityOptions,
      selectedValue: _selectedQuality,
    );
    if (!mounted || selected == null || selected == _selectedQuality) return;
    setState(() => _selectedQuality = selected);
  }

  void _handleDownloadTap() {
    final selectedQuality = _selectedQuality;
    widget.onDownloadTap(selectedQuality);
  }

  void _handleEpisodeDownloadTap(String episodeGuid) {
    final selectedQuality = _selectedQuality;
    widget.onEpisodeDownloadTap?.call(episodeGuid, selectedQuality);
    if (!mounted) return;
    setState(() {
      _localActionStates[episodeGuid] = const DownloadActionState(
        downloading: true,
      );
    });
  }

  void _handleOpenListTap() {
    final navigator = Navigator.of(context);
    navigator.pop();
    widget.onOpenDownloadListTap();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sheetTheme = context.downloadSheetTheme;
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom > 0 ? media.padding.bottom : 16.0;
    final payload = _payload;
    final hasEpisodeEntries = payload.episodeEntries.isNotEmpty;
    final maxSheetHeight =
        media.size.height * (hasEpisodeEntries ? 0.82 : 0.58);
    final episodeRanges = _buildEpisodeRanges(
      payload.episodeEntries,
      rangeSize: payload.rangeSize,
    );
    final safeRangeIndex = episodeRanges.isEmpty
        ? 0
        : _selectedRangeIndex.clamp(0, episodeRanges.length - 1);
    final visibleEntries = episodeRanges.isEmpty
        ? const <TvEpisodeCardData>[]
        : episodeRanges[safeRangeIndex];
    final selectedOption = payload.qualityOptions
        .cast<TvSeasonDownloadQualityOption?>()
        .firstWhere(
          (option) => option?.value == _selectedQuality,
          orElse: () => null,
        );
    final qualityLoading = payload.qualityOptions.isEmpty;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, bottomInset),
          decoration: BoxDecoration(
            color: sheetTheme.panelBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: sheetTheme.panelBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetTheme.handleColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      payload.sheetTitle,
                      style: TextStyle(
                        color: sheetTheme.titleColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (qualityLoading)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (payload.loadingError)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 14,
                                color: sheetTheme.subtitleColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.globalLoadFailed,
                                style: TextStyle(
                                  color: sheetTheme.subtitleColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        else ...<Widget>[
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: sheetTheme.subtitleColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.downloadLoadingEllipsis,
                            style: TextStyle(
                              color: sheetTheme.subtitleColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    InkWell(
                      onTap: _openQualitySheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              payload.qualityLabel,
                              style: TextStyle(
                                color: sheetTheme.subtitleColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              selectedOption?.label ?? '',
                              style: TextStyle(
                                color: sheetTheme.qualityValueColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: sheetTheme.qualityIconColor,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (!hasEpisodeEntries)
                _DownloadSingleCard(
                  payload: payload,
                  onDownloadTap: _handleDownloadTap,
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: _DownloadEpisodeListSection(
                      ranges: episodeRanges,
                      selectedRangeIndex: safeRangeIndex,
                      onRangeSelected: (index) {
                        setState(() => _selectedRangeIndex = index);
                      },
                      visibleEntries: visibleEntries,
                      token: payload.token,
                      downloadLabel: payload.downloadLabel,
                      downloadingLabel: payload.downloadingLabel,
                      downloadedLabel: payload.downloadedLabel,
                      pausedLabel: payload.pausedLabel,
                      actionStates: _localActionStates,
                      onEpisodeDownloadTap: _handleEpisodeDownloadTap,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _handleOpenListTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: sheetTheme.secondaryButtonBackground,
                    foregroundColor: sheetTheme.secondaryButtonForeground,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    payload.openListLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<List<TvEpisodeCardData>> _buildEpisodeRanges(
  List<TvEpisodeCardData> entries, {
  required int rangeSize,
}) {
  if (entries.isEmpty || rangeSize <= 0) {
    return const <List<TvEpisodeCardData>>[];
  }
  final ranges = <List<TvEpisodeCardData>>[];
  for (int i = 0; i < entries.length; i += rangeSize) {
    final end = (i + rangeSize).clamp(0, entries.length);
    ranges.add(entries.sublist(i, end));
  }
  return ranges;
}

class _DownloadSingleCard extends StatelessWidget {
  final TvSeasonDownloadSheetPayload payload;
  final VoidCallback onDownloadTap;

  const _DownloadSingleCard({
    required this.payload,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sheetTheme = context.downloadSheetTheme;
    final actionState = payload.primaryActionState;
    final actionLabel = actionState.label(
      downloadLabel: payload.downloadLabel,
      downloadingLabel: payload.downloadingLabel,
      downloadedLabel: payload.downloadedLabel,
      pausedLabel: payload.pausedLabel,
    );
    final actionColor = actionState.downloaded
        ? sheetTheme.mutedTextColor
        : actionState.downloading
        ? colors.warning
        : sheetTheme.linkColor;
    final actionIcon = actionState.downloaded
        ? Icons.check_rounded
        : actionState.downloading
        ? Icons.downloading_rounded
        : Icons.download_rounded;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: liquidGlassDecoration(context, radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DownloadPoster(
            urls: payload.posterUrls,
            token: payload.token,
            badgeLabel: payload.posterBadgeLabel,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      payload.itemTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: InkWell(
                      onTap: actionState.canStart ? onDownloadTap : null,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(actionIcon, color: actionColor, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              actionLabel,
                              style: TextStyle(
                                color: actionColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadEpisodeListSection extends StatelessWidget {
  final List<List<TvEpisodeCardData>> ranges;
  final int selectedRangeIndex;
  final ValueChanged<int> onRangeSelected;
  final List<TvEpisodeCardData> visibleEntries;
  final String token;
  final String downloadLabel;
  final String downloadingLabel;
  final String downloadedLabel;
  final String pausedLabel;
  final Map<String, DownloadActionState> actionStates;
  final ValueChanged<String> onEpisodeDownloadTap;

  const _DownloadEpisodeListSection({
    required this.ranges,
    required this.selectedRangeIndex,
    required this.onRangeSelected,
    required this.visibleEntries,
    required this.token,
    required this.downloadLabel,
    required this.downloadingLabel,
    required this.downloadedLabel,
    required this.pausedLabel,
    required this.actionStates,
    required this.onEpisodeDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (ranges.length > 1)
          _DownloadRangeTabs(
            ranges: ranges,
            selectedIndex: selectedRangeIndex,
            onTap: onRangeSelected,
          ),
        if (ranges.length > 1) const SizedBox(height: 14),
        for (int i = 0; i < visibleEntries.length; i++) ...[
          _DownloadEpisodeRow(
            key: ValueKey<String>(visibleEntries[i].guid),
            entry: visibleEntries[i],
            token: token,
            downloadLabel: downloadLabel,
            downloadingLabel: downloadingLabel,
            downloadedLabel: downloadedLabel,
            pausedLabel: pausedLabel,
            actionState:
                actionStates[visibleEntries[i].guid] ??
                DownloadActionState.idle,
            onDownloadTap: () => onEpisodeDownloadTap(visibleEntries[i].guid),
          ),
          if (i != visibleEntries.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _DownloadRangeTabs extends StatelessWidget {
  final List<List<TvEpisodeCardData>> ranges;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _DownloadRangeTabs({
    required this.ranges,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: liquidGlassDecoration(context, radius: 14),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          for (int index = 0; index < ranges.length; index++)
            InkWell(
              onTap: () => onTap(index),
              borderRadius: BorderRadius.circular(8),
              child: Text(
                '${index * _rangeSizeHint() + 1} - ${index * _rangeSizeHint() + ranges[index].length}',
                style: TextStyle(
                  color: index == selectedIndex
                      ? colors.selection
                      : colors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _rangeSizeHint() {
    if (ranges.isEmpty) return 1;
    return ranges.first.length;
  }
}

class _DownloadEpisodeRow extends StatelessWidget {
  final TvEpisodeCardData entry;
  final String token;
  final String downloadLabel;
  final String downloadingLabel;
  final String downloadedLabel;
  final String pausedLabel;
  final DownloadActionState actionState;
  final VoidCallback onDownloadTap;

  const _DownloadEpisodeRow({
    super.key,
    required this.entry,
    required this.token,
    required this.downloadLabel,
    required this.downloadingLabel,
    required this.downloadedLabel,
    required this.pausedLabel,
    required this.actionState,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sheetTheme = context.downloadSheetTheme;
    final resolutionLabel = entry.resolutions.isNotEmpty
        ? entry.resolutions.first
        : '';
    final actionLabel = actionState.label(
      downloadLabel: downloadLabel,
      downloadingLabel: downloadingLabel,
      downloadedLabel: downloadedLabel,
      pausedLabel: pausedLabel,
    );
    final actionColor = actionState.downloaded
        ? sheetTheme.mutedTextColor
        : actionState.downloading
        ? colors.warning
        : sheetTheme.linkColor;
    final actionIcon = actionState.downloaded
        ? Icons.check_rounded
        : actionState.downloading
        ? Icons.downloading_rounded
        : Icons.download_rounded;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: liquidGlassDecoration(context, radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DownloadPoster(
            urls: entry.imageUrls,
            token: token,
            badgeLabel: resolutionLabel,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: InkWell(
                      onTap: actionState.canStart ? onDownloadTap : null,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(actionIcon, color: actionColor, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              actionLabel,
                              style: TextStyle(
                                color: actionColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadPoster extends StatelessWidget {
  final List<String> urls;
  final String token;
  final String badgeLabel;

  const _DownloadPoster({
    required this.urls,
    required this.token,
    required this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final sheetTheme = context.downloadSheetTheme;
    final normalizedBadge = CapabilityBadgeMapper.normalize(badgeLabel);
    final badgeAsset = CapabilityBadgeMapper.badgeAsset(normalizedBadge);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 128,
        height: 72,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DetailHeroImage(images: mediaImageRequestForUrls(urls, token: token)),
            if (badgeLabel.trim().isNotEmpty)
              Positioned(
                right: 0,
                bottom: 4,
                child: badgeAsset != null
                    ? SizedBox(
                        height: 14,
                        child: SvgPicture.asset(
                          badgeAsset,
                          fit: BoxFit.contain,
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: sheetTheme.badgeBackground,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            normalizedBadge,
                            style: TextStyle(
                              color: sheetTheme.badgeTextColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TvSeasonDownloadQualitySheet extends StatelessWidget {
  final String title;
  final List<TvSeasonDownloadQualityOption> options;
  final String selectedValue;

  const _TvSeasonDownloadQualitySheet({
    required this.title,
    required this.options,
    required this.selectedValue,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required List<TvSeasonDownloadQualityOption> options,
    required String selectedValue,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.downloadSheetTheme.barrierColor,
      builder: (context) {
        return _TvSeasonDownloadQualitySheet(
          title: title,
          options: options,
          selectedValue: selectedValue,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheetTheme = context.downloadSheetTheme;
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom > 0 ? media.padding.bottom : 16.0;

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 18, 16, bottomInset),
        decoration: BoxDecoration(
          color: sheetTheme.panelBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: sheetTheme.panelBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: sheetTheme.titleColor,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            for (int index = 0; index < options.length; index++) ...[
              _DownloadQualityOptionTile(
                option: options[index],
                selected: options[index].value == selectedValue,
                onTap: () => Navigator.of(context).pop(options[index].value),
              ),
              if (index != options.length - 1) const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadQualityOptionTile extends StatelessWidget {
  final TvSeasonDownloadQualityOption option;
  final bool selected;
  final VoidCallback onTap;

  const _DownloadQualityOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sheetTheme = context.downloadSheetTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: liquidGlassDecoration(
          context,
          radius: 12,
          tone: selected ? LiquidGlassTone.accent : LiquidGlassTone.neutral,
          selected: selected,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      color: sheetTheme.titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (option.hint.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      option.hint,
                      style: TextStyle(
                        color: sheetTheme.mutedTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _DownloadQualityIndicator(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _DownloadQualityIndicator extends StatelessWidget {
  final bool selected;

  const _DownloadQualityIndicator({required this.selected});

  @override
  Widget build(BuildContext context) {
    final sheetTheme = context.downloadSheetTheme;
    if (selected) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: sheetTheme.optionIndicatorFillColor,
          border: Border.all(color: sheetTheme.optionIndicatorFillColor),
        ),
        child: Center(
          child: SvgPicture.asset(
            'assets/icons/check.svg',
            width: 12,
            height: 12,
            colorFilter: ColorFilter.mode(
              sheetTheme.optionIndicatorIconColor,
              BlendMode.srcIn,
            ),
          ),
        ),
      );
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: sheetTheme.optionIndicatorBorderColor),
      ),
    );
  }
}
