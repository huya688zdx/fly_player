import '../api/feiniu_api.dart';
import '../models/person_credit.dart';
import '../models/play_info.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import '../utils/play_detail_track_selector.dart';

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

class PlayDetailRefreshData {
  final PlayInfoData info;
  final StreamTrackData streamTrackData;
  final List<StreamListOption> streamOptions;
  final int? selectedStreamIndex;
  final String? selectedSubtitleGuid;
  final String? selectedAudioGuid;
  final String imdbId;
  final String trimId;

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

class PlayDetailPlayerReturnData {
  final String itemGuid;
  final int currentTsSeconds;
  final PlayDetailRefreshData? refreshData;

  const PlayDetailPlayerReturnData({
    required this.itemGuid,
    required this.currentTsSeconds,
    this.refreshData,
  });
}

class PlayDetailDataLoader {
  final FeiniuApi api;

  const PlayDetailDataLoader(this.api);

  Future<PlayDetailInitialData> load(String itemGuid) async {
    final results = await Future.wait<dynamic>([
      api.getPlayInfo(itemGuid),
      api.getStreamTrackData(itemGuid),
      api.getItemDetail(itemGuid),
    ]);

    List<PersonCredit> people = const [];
    try {
      people = await api.getPersonList(itemGuid);
    } catch (_) {}

    final info = results[0] as PlayInfoData;
    final streamTrackData = results[1] as StreamTrackData;
    final itemDetail = results[2] as Map<String, dynamic>;
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

  Future<PlayDetailRefreshData> refreshAfterItemStateChange({
    required String itemGuid,
    required String currentMediaGuid,
    required String? currentSubtitleGuid,
    required String? currentAudioGuid,
  }) async {
    final results = await Future.wait<dynamic>([
      api.getStreamTrackData(itemGuid),
      api.getPlayInfo(itemGuid),
      api.getItemDetail(itemGuid),
    ]);
    final refreshedTrack = results[0] as StreamTrackData;
    final refreshedInfo = results[1] as PlayInfoData;
    final refreshedItem = results[2] as Map<String, dynamic>;
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
