import 'dart:async';

import '../api/person_list_request.dart';
import '../media_backend/feiniu/feiniu_detail_data_gateway.dart';
import '../models/person_credit.dart';
import '../models/play_info.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import '../services/app_log_service.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/play_detail_track_selector.dart';

/// 表示详情页首次加载完成后的聚合数据。
class PlayDetailInitialData {
  final PlayInfoData info;
  final StreamTrackData streamTrackData;
  final List<StreamListOption> streamOptions;
  final List<PersonCredit> personCredits;
  final int? selectedStreamIndex;
  final String? selectedSubtitleGuid;
  final String? selectedAudioGuid;
  final String imdbId;
  final String trimId;

  /// 根据详情页首屏所需数据构造对象。
  const PlayDetailInitialData({
    required this.info,
    required this.streamTrackData,
    required this.streamOptions,
    required this.personCredits,
    required this.selectedStreamIndex,
    required this.selectedSubtitleGuid,
    required this.selectedAudioGuid,
    required this.imdbId,
    required this.trimId,
  });
}

/// 表示详情页在状态变更后重新刷新的数据。
class PlayDetailRefreshData {
  final PlayInfoData info;
  final StreamTrackData streamTrackData;
  final List<StreamListOption> streamOptions;
  final int? selectedStreamIndex;
  final String? selectedSubtitleGuid;
  final String? selectedAudioGuid;
  final String imdbId;
  final String trimId;

  /// 根据详情页刷新结果构造对象。
  const PlayDetailRefreshData({
    required this.info,
    required this.streamTrackData,
    required this.streamOptions,
    required this.selectedStreamIndex,
    required this.selectedSubtitleGuid,
    required this.selectedAudioGuid,
    required this.imdbId,
    required this.trimId,
  });
}

/// 表示播放器返回详情页时携带的数据。
class PlayDetailPlayerReturnData {
  final String itemGuid;
  final int currentTsSeconds;
  final PlayDetailRefreshData? refreshData;
  final String? parentItemGuid;
  final bool canPopToParent;

  /// 根据播放器返回字段构造对象。
  const PlayDetailPlayerReturnData({
    required this.itemGuid,
    required this.currentTsSeconds,
    this.refreshData,
    this.parentItemGuid,
    this.canPopToParent = false,
  });

  /// 转换为可供路由或平台桥接传递的映射结构。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'itemGuid': itemGuid.trim(),
      'currentTsSeconds': currentTsSeconds,
      'parentItemGuid': parentItemGuid?.trim(),
      'canPopToParent': canPopToParent,
    };
  }

  /// 从映射结构恢复播放器返回数据。
  factory PlayDetailPlayerReturnData.fromMap(Map<String, dynamic> raw) {
    return PlayDetailPlayerReturnData(
      itemGuid: (raw['itemGuid'] ?? '').toString().trim(),
      currentTsSeconds:
          int.tryParse(
            '${raw['currentTsSeconds'] ?? raw['current_ts_seconds'] ?? 0}',
          ) ??
          0,
      parentItemGuid:
          (raw['parentItemGuid'] ?? raw['parent_item_guid'] ?? '')
              .toString()
              .trim()
              .isEmpty
          ? null
          : (raw['parentItemGuid'] ?? raw['parent_item_guid'])
                .toString()
                .trim(),
      canPopToParent: raw['canPopToParent'] == true,
    );
  }
}

/// 负责装配详情页播放相关数据的加载器。
class PlayDetailDataLoader {
  static const PersonListRequest _creditsRequest = PersonListRequest(
    page: 1,
    pageSize: 200,
  );

  final FeiniuDetailDataGateway api;

  /// 根据注入的飞牛详情数据网关构造详情页数据加载器。
  const PlayDetailDataLoader(this.api);

  /// 首次加载详情页所需的播放信息、轨道与演职员数据。
  Future<PlayDetailInitialData> load(String itemGuid) async {
    List<PersonCredit> people = const [];
    final info = await api.getPlayInfo(itemGuid);
    final streamTrackData = await api.getStreamTrackData(itemGuid);
    final itemDetail = await api.getItemDetail(itemGuid);
    try {
      people = await api.getPersonList(itemGuid, request: _creditsRequest);
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'load person list',
          source: 'play_detail_data_loader',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$itemGuid',
        ),
      );
    }
    final streams = streamTrackData.options;

    final initialIndex = streams.indexWhere(
      (e) => e.mediaGuid == info.mediaGuid,
    );
    final selectedIndex = initialIndex >= 0 ? initialIndex : null;
    final selectedMediaGuid =
        (selectedIndex != null &&
            selectedIndex >= 0 &&
            selectedIndex < streams.length)
        ? streams[selectedIndex].mediaGuid
        : '';
    final subtitleTracks = streamTrackData.subtitlesForMedia(selectedMediaGuid);
    final audioTracks = streamTrackData.audiosForMedia(selectedMediaGuid);

    return PlayDetailInitialData(
      info: info,
      streamTrackData: streamTrackData,
      streamOptions: streams,
      personCredits: people,
      selectedStreamIndex: selectedIndex,
      selectedSubtitleGuid: PlayDetailTrackSelector.pickInitialSubtitleGuid(
        preferred: info.subtitleGuid,
        tracks: subtitleTracks,
      ),
      selectedAudioGuid: PlayDetailTrackSelector.pickInitialAudioGuid(
        preferred: info.audioGuid,
        tracks: audioTracks,
      ),
      imdbId: extractImdbId(itemDetail),
      trimId: extractTrimId(itemDetail),
    );
  }

  /// 在条目状态变化后刷新详情页相关播放数据。
  Future<PlayDetailRefreshData> refreshAfterItemStateChange({
    required String itemGuid,
    required String currentMediaGuid,
    required String? currentSubtitleGuid,
    required String? currentAudioGuid,
  }) async {
    final refreshedTrack = await api.getStreamTrackData(itemGuid);
    final refreshedInfo = await api.getPlayInfo(itemGuid);
    final refreshedItem = await api.getItemDetail(itemGuid);
    final refreshedStreams = refreshedTrack.options;

    int? selectedIndex;
    if (currentMediaGuid.isNotEmpty) {
      final idx = refreshedStreams.indexWhere(
        (e) => e.mediaGuid == currentMediaGuid,
      );
      if (idx >= 0) selectedIndex = idx;
    }
    selectedIndex ??= refreshedStreams.indexWhere(
      (e) => e.mediaGuid == refreshedInfo.mediaGuid,
    );
    if (selectedIndex < 0) selectedIndex = null;

    final selectedMediaGuid =
        (selectedIndex != null &&
            selectedIndex >= 0 &&
            selectedIndex < refreshedStreams.length)
        ? refreshedStreams[selectedIndex].mediaGuid
        : '';
    final subtitleTracks = refreshedTrack.subtitlesForMedia(selectedMediaGuid);
    final audioTracks = refreshedTrack.audiosForMedia(selectedMediaGuid);

    return PlayDetailRefreshData(
      info: refreshedInfo,
      streamTrackData: refreshedTrack,
      streamOptions: refreshedStreams,
      selectedStreamIndex: selectedIndex,
      selectedSubtitleGuid: PlayDetailTrackSelector.pickInitialSubtitleGuid(
        preferred: currentSubtitleGuid?.isNotEmpty == true
            ? currentSubtitleGuid
            : refreshedInfo.subtitleGuid,
        tracks: subtitleTracks,
      ),
      selectedAudioGuid: PlayDetailTrackSelector.pickInitialAudioGuid(
        preferred: currentAudioGuid?.isNotEmpty == true
            ? currentAudioGuid
            : refreshedInfo.audioGuid,
        tracks: audioTracks,
      ),
      imdbId: extractImdbId(refreshedItem),
      trimId: extractTrimId(refreshedItem),
    );
  }

  /// 从详情接口返回中提取 IMDb 标识。
  static String extractImdbId(Map<String, dynamic> data) {
    final direct = (data['imdb_id'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final item = data['item'];
    if (item is Map<String, dynamic>) {
      final nested = (item['imdb_id'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  /// 从详情接口返回中提取第三方条目标识。
  static String extractTrimId(Map<String, dynamic> data) {
    final direct = (data['trim_id'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final item = data['item'];
    if (item is Map<String, dynamic>) {
      final nested = (item['trim_id'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }
}
