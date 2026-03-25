import '../../models/remote_subtitle.dart';
import '../../models/stream_track_data.dart';

enum PlayerSubtitleSelectionAction { closeDrawer, blockedByDirectFile, apply }

class PlayerSubtitleSelectionPlan {
  final PlayerSubtitleSelectionAction action;
  final String normalizedGuid;
  final bool subtitleExplicitlyDisabled;
  final DateTime? subtitleStatusTipSuppressedUntil;

  const PlayerSubtitleSelectionPlan({
    required this.action,
    required this.normalizedGuid,
    required this.subtitleExplicitlyDisabled,
    required this.subtitleStatusTipSuppressedUntil,
  });
}

class PlayerSubtitleDeletionResult {
  final List<SubtitleTrackOption> remainingTracks;
  final String nextCurrentGuid;
  final bool nextSubtitleExplicitlyDisabled;
  final bool shouldApplySelection;
  final String? removedCachedPath;
  final DateTime? subtitleStatusTipSuppressedUntil;

  const PlayerSubtitleDeletionResult({
    required this.remainingTracks,
    required this.nextCurrentGuid,
    required this.nextSubtitleExplicitlyDisabled,
    required this.shouldApplySelection,
    required this.removedCachedPath,
    required this.subtitleStatusTipSuppressedUntil,
  });
}

class PlayerSubtitleController {
  static const double defaultSubtitlePositionFactor = 0.08;
  final Map<String, String> subtitleFileByGuid = <String, String>{};
  final Set<String> serverFallbackSubtitleGuids = <String>{};
  final Set<String> subtitleFailureNoticeShownGuids = <String>{};

  bool subtitleLoading = false;
  bool subtitleSelectionRefreshInFlight = false;
  bool subtitleExplicitlyDisabled = false;
  bool pendingSubtitleSelectionRefresh = false;

  double subtitleDelaySeconds = 0;
  double subtitlePositionFactor = defaultSubtitlePositionFactor;
  double subtitleScaleFactor = 0;

  DateTime? subtitleStatusTipSuppressedUntil;
  String? pendingExternalSubtitlePath;
  String? subtitleDeletingGuid;
  String subtitleSearchLanguage = 'zh-CN';
  String? subtitleSearchLoadingLanguage;
  String? subtitleDownloadTrimId;
  List<RemoteSubtitleSearchItem> subtitleSearchResults =
      const <RemoteSubtitleSearchItem>[];

  void resetForSourceChange({required bool pendingSelectionRefresh}) {
    serverFallbackSubtitleGuids.clear();
    subtitleFailureNoticeShownGuids.clear();
    subtitleExplicitlyDisabled = false;
    pendingSubtitleSelectionRefresh = pendingSelectionRefresh;
    pendingExternalSubtitlePath = null;
    subtitleDeletingGuid = null;
    subtitleSearchLoadingLanguage = null;
    subtitleDownloadTrimId = null;
    subtitleSearchResults = const <RemoteSubtitleSearchItem>[];
  }

  String normalizeSelectionGuid(String guid) {
    return guid.trim();
  }

  bool isSelectionUnchanged({
    required String nextGuid,
    required String? currentGuid,
  }) {
    return nextGuid == (currentGuid ?? '').trim();
  }

  bool selectionRequiresDirectFile({
    required bool serverManagedPlayback,
    required String nextGuid,
    required bool hasDirectFile,
  }) {
    return serverManagedPlayback && nextGuid.isNotEmpty && !hasDirectFile;
  }

  void beginSelectionChange(String nextGuid) {
    subtitleExplicitlyDisabled = nextGuid.isEmpty;
    subtitleStatusTipSuppressedUntil = null;
    if (nextGuid.isEmpty) return;
    subtitleFailureNoticeShownGuids.remove(nextGuid);
    serverFallbackSubtitleGuids.remove(nextGuid);
  }

  PlayerSubtitleSelectionPlan planSelectionChange({
    required String guid,
    required String? currentGuid,
    required bool serverManagedPlayback,
    required bool hasDirectFile,
  }) {
    final normalizedGuid = normalizeSelectionGuid(guid);
    if (isSelectionUnchanged(
      nextGuid: normalizedGuid,
      currentGuid: currentGuid,
    )) {
      return PlayerSubtitleSelectionPlan(
        action: PlayerSubtitleSelectionAction.closeDrawer,
        normalizedGuid: normalizedGuid,
        subtitleExplicitlyDisabled: subtitleExplicitlyDisabled,
        subtitleStatusTipSuppressedUntil: subtitleStatusTipSuppressedUntil,
      );
    }
    if (selectionRequiresDirectFile(
      serverManagedPlayback: serverManagedPlayback,
      nextGuid: normalizedGuid,
      hasDirectFile: hasDirectFile,
    )) {
      return PlayerSubtitleSelectionPlan(
        action: PlayerSubtitleSelectionAction.blockedByDirectFile,
        normalizedGuid: normalizedGuid,
        subtitleExplicitlyDisabled: subtitleExplicitlyDisabled,
        subtitleStatusTipSuppressedUntil: subtitleStatusTipSuppressedUntil,
      );
    }
    beginSelectionChange(normalizedGuid);
    return PlayerSubtitleSelectionPlan(
      action: PlayerSubtitleSelectionAction.apply,
      normalizedGuid: normalizedGuid,
      subtitleExplicitlyDisabled: subtitleExplicitlyDisabled,
      subtitleStatusTipSuppressedUntil: subtitleStatusTipSuppressedUntil,
    );
  }

  bool beginDeletingTrack(String guid) {
    if (subtitleDeletingGuid == guid) return false;
    subtitleDeletingGuid = guid;
    return true;
  }

  void finishDeletingTrack() {
    subtitleDeletingGuid = null;
  }

  PlayerSubtitleDeletionResult completeTrackDeletion({
    required SubtitleTrackOption track,
    required List<SubtitleTrackOption> currentTracks,
    required String? currentGuid,
  }) {
    final normalizedCurrentGuid = (currentGuid ?? '').trim();
    final shouldApplySelection = track.guid == normalizedCurrentGuid;
    final removedCachedPath = removeCachedSubtitleFile(track.guid);
    serverFallbackSubtitleGuids.remove(track.guid);
    subtitleFailureNoticeShownGuids.remove(track.guid);
    if (shouldApplySelection) {
      subtitleExplicitlyDisabled = false;
      subtitleStatusTipSuppressedUntil = null;
    }
    return PlayerSubtitleDeletionResult(
      remainingTracks: removeSubtitleTrack(currentTracks, track.guid),
      nextCurrentGuid: shouldApplySelection ? '' : normalizedCurrentGuid,
      nextSubtitleExplicitlyDisabled: subtitleExplicitlyDisabled,
      shouldApplySelection: shouldApplySelection,
      removedCachedPath: removedCachedPath,
      subtitleStatusTipSuppressedUntil: subtitleStatusTipSuppressedUntil,
    );
  }

  bool beginRemoteSearch(String language) {
    if (subtitleSearchLoadingLanguage == language) return false;
    subtitleSearchLoadingLanguage = language;
    return true;
  }

  void completeRemoteSearch(List<RemoteSubtitleSearchItem> results) {
    subtitleSearchResults = results;
    subtitleSearchLoadingLanguage = null;
  }

  void failRemoteSearch() {
    subtitleSearchResults = const <RemoteSubtitleSearchItem>[];
    subtitleSearchLoadingLanguage = null;
  }

  bool updateSearchLanguage(String language) {
    if (subtitleSearchLanguage == language) return false;
    subtitleSearchLanguage = language;
    return true;
  }

  void beginRemoteDownload(String trimId) {
    subtitleDownloadTrimId = trimId;
  }

  void finishRemoteDownload() {
    subtitleDownloadTrimId = null;
  }

  void cacheLocalSubtitleFile({required String guid, required String path}) {
    subtitleFileByGuid[guid] = path;
  }

  String? removeCachedSubtitleFile(String guid) {
    final path = subtitleFileByGuid.remove(guid);
    if (path == null || path.isEmpty) return null;
    return path;
  }

  bool subtitleCanDelete(SubtitleTrackOption track) {
    return track.isExternal == 1;
  }

  double updateSubtitleDelaySeconds(double value) {
    final normalized = value.clamp(-10.0, 10.0).toDouble();
    subtitleDelaySeconds = double.parse(normalized.toStringAsFixed(1));
    return subtitleDelaySeconds;
  }

  int updateSubtitlePositionFactor(double value) {
    subtitlePositionFactor = value.clamp(0.0, 1.0).toDouble();
    return ((1 - subtitlePositionFactor) * 100).round().clamp(0, 100).toInt();
  }

  double updateSubtitleScaleFactor(
    double value, {
    required double minScale,
    required double maxScale,
  }) {
    subtitleScaleFactor = value.clamp(0.0, 1.0).toDouble();
    return minScale + ((maxScale - minScale) * subtitleScaleFactor);
  }

  void resetSubtitleStyle({
    required double minScale,
    required double maxScale,
  }) {
    subtitleDelaySeconds = 0;
    subtitlePositionFactor = defaultSubtitlePositionFactor;
    subtitleScaleFactor = (1.0 - minScale) / (maxScale - minScale);
  }

  String subtitleSearchLanguageLabel(String language) {
    switch (language) {
      case 'en':
        return '英文';
      case 'zh-CN':
      default:
        return '中文';
    }
  }

  String subtitleFormatFromFileName(String fileName, String fallbackPath) {
    final source = fileName.trim().isNotEmpty ? fileName.trim() : fallbackPath;
    final dot = source.lastIndexOf('.');
    if (dot < 0 || dot == source.length - 1) return 'ass';
    return source.substring(dot + 1).toLowerCase();
  }

  String subtitleStreamTitle(
    SubtitleTrackOption track, {
    required String subtitleLabel,
  }) {
    final raw = track.title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (raw.isEmpty) return '';
    final format = subtitleLabel.trim().toUpperCase();
    if (raw.toUpperCase() == format) return '';
    return raw;
  }

  String subtitleDrawerSwitchMessageForTrack(
    SubtitleTrackOption? track, {
    required String Function(SubtitleTrackOption track) titleBuilder,
  }) {
    if (track == null) {
      return '正在关闭字幕...';
    }
    final title = titleBuilder(track);
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toLowerCase();
    final suffix = format.isEmpty ? '' : ' ($format)';
    return '正在切换到$title$suffix 字幕...';
  }

  SubtitleTrackOption buildLocalSubtitleTrack({
    required String mediaGuid,
    required String guid,
    required String title,
    required String format,
  }) {
    return SubtitleTrackOption(
      mediaGuid: mediaGuid,
      guid: guid,
      title: title,
      codecName: format,
      format: format,
      language: 'und',
      index: -1,
      isDefault: 0,
      forced: 0,
      isExternal: 1,
      extraFile: 1,
      isBitmap: 0,
    );
  }

  List<SubtitleTrackOption> upsertSubtitleTrack(
    List<SubtitleTrackOption> currentTracks,
    SubtitleTrackOption track, {
    bool insertAtFront = false,
  }) {
    final next = List<SubtitleTrackOption>.from(currentTracks)
      ..removeWhere((item) => item.guid == track.guid);
    if (insertAtFront) {
      next.insert(0, track);
    } else {
      next.add(track);
    }
    return next;
  }

  List<SubtitleTrackOption> removeSubtitleTrack(
    List<SubtitleTrackOption> currentTracks,
    String guid,
  ) {
    return List<SubtitleTrackOption>.from(currentTracks)
      ..removeWhere((item) => item.guid == guid);
  }
}
