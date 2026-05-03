import '../../models/remote_subtitle.dart';
import '../../models/stream_track_data.dart';

/// 定义字幕切换流程中可执行的动作类型。
enum PlayerSubtitleSelectionAction { closeDrawer, blockedByDirectFile, apply }

/// 描述一次字幕选择请求经校验后的执行计划。
class PlayerSubtitleSelectionPlan {
  final PlayerSubtitleSelectionAction action;
  final String normalizedGuid;
  final bool subtitleExplicitlyDisabled;
  final DateTime? subtitleStatusTipSuppressedUntil;

  /// 根据字幕切换决策结果构造对象。
  const PlayerSubtitleSelectionPlan({
    required this.action,
    required this.normalizedGuid,
    required this.subtitleExplicitlyDisabled,
    required this.subtitleStatusTipSuppressedUntil,
  });
}

/// 描述删除字幕轨后的剩余状态。
class PlayerSubtitleDeletionResult {
  final List<SubtitleTrackOption> remainingTracks;
  final String nextCurrentGuid;
  final bool nextSubtitleExplicitlyDisabled;
  final bool shouldApplySelection;
  final String? removedCachedPath;
  final DateTime? subtitleStatusTipSuppressedUntil;

  /// 根据删除结果与后续状态构造对象。
  const PlayerSubtitleDeletionResult({
    required this.remainingTracks,
    required this.nextCurrentGuid,
    required this.nextSubtitleExplicitlyDisabled,
    required this.shouldApplySelection,
    required this.removedCachedPath,
    required this.subtitleStatusTipSuppressedUntil,
  });
}

/// 统一管理播放器内的字幕选择、搜索与样式状态。
class PlayerSubtitleController {
  static const double defaultSubtitlePositionFactor = 0.08;
  final Map<String, String> subtitleFileByGuid = <String, String>{};
  final Map<String, Future<String?>> subtitleFileRequestByGuid =
      <String, Future<String?>>{};
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

  /// 在媒体源切换后重置与字幕相关的临时状态。
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

  /// 归一化字幕选择标识。
  String normalizeSelectionGuid(String guid) {
    return guid.trim();
  }

  /// 判断新的字幕选择是否与当前状态一致。
  bool isSelectionUnchanged({
    required String nextGuid,
    required String? currentGuid,
  }) {
    return nextGuid == (currentGuid ?? '').trim();
  }

  /// 判断本次字幕切换是否需要先准备独立字幕文件。
  bool selectionRequiresDirectFile({
    required bool serverManagedPlayback,
    required String nextGuid,
    required bool requiresExternalFile,
    required bool hasDirectFile,
  }) {
    return serverManagedPlayback &&
        nextGuid.isNotEmpty &&
        requiresExternalFile &&
        !hasDirectFile;
  }

  /// 在字幕切换真正执行前更新本地状态。
  void beginSelectionChange(String nextGuid) {
    subtitleExplicitlyDisabled = nextGuid.isEmpty;
    subtitleStatusTipSuppressedUntil = null;
    if (nextGuid.isEmpty) return;
    subtitleFailureNoticeShownGuids.remove(nextGuid);
    serverFallbackSubtitleGuids.remove(nextGuid);
  }

  /// 生成一次字幕切换的执行计划。
  PlayerSubtitleSelectionPlan planSelectionChange({
    required String guid,
    required String? currentGuid,
    required bool serverManagedPlayback,
    required bool requiresExternalFile,
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
      requiresExternalFile: requiresExternalFile,
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

  /// 标记指定字幕轨进入删除流程。
  bool beginDeletingTrack(String guid) {
    if (subtitleDeletingGuid == guid) return false;
    subtitleDeletingGuid = guid;
    return true;
  }

  /// 结束当前字幕轨删除流程。
  void finishDeletingTrack() {
    subtitleDeletingGuid = null;
  }

  /// 完成字幕轨删除并返回后续应采用的状态。
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

  /// 标记开始远程字幕搜索。
  bool beginRemoteSearch(String language) {
    if (subtitleSearchLoadingLanguage == language) return false;
    subtitleSearchLoadingLanguage = language;
    return true;
  }

  /// 提交远程字幕搜索结果。
  void completeRemoteSearch(List<RemoteSubtitleSearchItem> results) {
    subtitleSearchResults = results;
    subtitleSearchLoadingLanguage = null;
  }

  /// 将远程字幕搜索状态重置为失败结果。
  void failRemoteSearch() {
    subtitleSearchResults = const <RemoteSubtitleSearchItem>[];
    subtitleSearchLoadingLanguage = null;
  }

  /// 更新远程字幕搜索的目标语言。
  bool updateSearchLanguage(String language) {
    if (subtitleSearchLanguage == language) return false;
    subtitleSearchLanguage = language;
    return true;
  }

  /// 标记开始下载远程字幕。
  void beginRemoteDownload(String trimId) {
    subtitleDownloadTrimId = trimId;
  }

  /// 清除远程字幕下载中的标记。
  void finishRemoteDownload() {
    subtitleDownloadTrimId = null;
  }

  /// 缓存字幕标识与本地文件路径的映射关系。
  void cacheLocalSubtitleFile({required String guid, required String path}) {
    subtitleFileByGuid[guid] = path;
  }

  /// 移除字幕缓存路径并返回旧路径。
  String? removeCachedSubtitleFile(String guid) {
    final path = subtitleFileByGuid.remove(guid);
    if (path == null || path.isEmpty) return null;
    return path;
  }

  /// 判断指定字幕轨是否允许在本地删除。
  bool subtitleCanDelete(SubtitleTrackOption track) {
    return track.isExternal == 1;
  }

  /// 更新字幕时间偏移，并返回归一化后的秒数。
  double updateSubtitleDelaySeconds(double value) {
    final normalized = value.clamp(-10.0, 10.0).toDouble();
    subtitleDelaySeconds = double.parse(normalized.toStringAsFixed(1));
    return subtitleDelaySeconds;
  }

  /// 更新字幕纵向位置，并返回界面展示所需的百分比。
  int updateSubtitlePositionFactor(double value) {
    subtitlePositionFactor = value.clamp(0.0, 1.0).toDouble();
    return ((1 - subtitlePositionFactor) * 100).round().clamp(0, 100).toInt();
  }

  /// 更新字幕缩放因子，并返回实际字号倍率。
  double updateSubtitleScaleFactor(
    double value, {
    required double minScale,
    required double maxScale,
  }) {
    subtitleScaleFactor = value.clamp(0.0, 1.0).toDouble();
    return minScale + ((maxScale - minScale) * subtitleScaleFactor);
  }

  /// 将字幕样式恢复为默认值。
  void resetSubtitleStyle({
    required double minScale,
    required double maxScale,
  }) {
    subtitleDelaySeconds = 0;
    subtitlePositionFactor = defaultSubtitlePositionFactor;
    subtitleScaleFactor = (1.0 - minScale) / (maxScale - minScale);
  }

  /// 返回字幕搜索语言对应的展示文案。
  String subtitleSearchLanguageLabel(String language) {
    switch (language) {
      case 'en':
        return 'English';
      case 'zh-CN':
      default:
        return 'Chinese';
    }
  }

  /// 从文件名或路径推断字幕格式。
  String subtitleFormatFromFileName(String fileName, String fallbackPath) {
    final source = fileName.trim().isNotEmpty ? fileName.trim() : fallbackPath;
    final dot = source.lastIndexOf('.');
    if (dot < 0 || dot == source.length - 1) return 'ass';
    return source.substring(dot + 1).toLowerCase();
  }

  /// 生成字幕轨在界面上的附加标题。
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

  /// 生成字幕抽屉内的切换提示文案。
  String subtitleDrawerSwitchMessageForTrack(
    SubtitleTrackOption? track, {
    required String Function(SubtitleTrackOption track) titleBuilder,
  }) {
    if (track == null) {
      return 'Closing subtitles...';
    }
    final title = titleBuilder(track);
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toLowerCase();
    final suffix = format.isEmpty ? '' : ' ($format)';
    return 'Switching to $title$suffix subtitles...';
  }

  /// 为本地导入字幕构造统一的字幕轨对象。
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

  /// 将字幕轨插入列表，若已存在则执行替换。
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

  /// 从字幕轨列表中移除指定标识的字幕项。
  List<SubtitleTrackOption> removeSubtitleTrack(
    List<SubtitleTrackOption> currentTracks,
    String guid,
  ) {
    return List<SubtitleTrackOption>.from(currentTracks)
      ..removeWhere((item) => item.guid == guid);
  }
}
