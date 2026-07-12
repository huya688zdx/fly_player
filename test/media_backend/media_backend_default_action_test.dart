import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/detail/media_episode_summary.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/detail/media_source_info.dart';
import 'package:fly_player/media_backend/filter/media_catalog_filter.dart';
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_catalog.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/media_backend/playback/media_playback_resolution.dart';
import 'package:fly_player/media_backend/playback/media_playback_source_bridge.dart';

void main() {
  test('默认收藏和已看操作必须显式报告不支持', () async {
    final backend = _MinimalBackend();

    await expectLater(
      backend.setItemFavorite('item-1', favorite: true),
      throwsUnsupportedError,
    );
    await expectLater(
      backend.setItemWatched('item-1', watched: true),
      throwsUnsupportedError,
    );
  });
}

class _MinimalBackend extends MediaBackend {
  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.feiniu();

  @override
  MediaPlaybackSourceBridge get playbackSourceBridge => _NoopBridge();

  @override
  Future<List<MediaCatalog>> getCatalogs() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> getHomeSummary() => throw UnimplementedError();

  @override
  Future<List<MediaItemCard>> getContinueWatching({
    bool forceRefresh = false,
  }) => throw UnimplementedError();

  @override
  Future<List<MediaItemCard>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) => throw UnimplementedError();

  @override
  Future<List<MediaItemCard>> searchItems(String query) =>
      throw UnimplementedError();

  @override
  Future<MediaCatalogFilterSchema> getCatalogFilterSchema(String catalogId) =>
      throw UnimplementedError();

  @override
  Future<MediaItemCardPage> queryCatalogItems(MediaCatalogQuery query) =>
      throw UnimplementedError();

  @override
  Future<MediaDetail> getItemDetail(String itemId) =>
      throw UnimplementedError();

  @override
  Future<MediaSourceInfo?> getItemSourceInfo(String itemId) =>
      throw UnimplementedError();

  @override
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId) =>
      throw UnimplementedError();

  @override
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId) =>
      throw UnimplementedError();

  @override
  Future<MediaPlaybackResolution> getPlayback(MediaPlaybackRequest request) =>
      throw UnimplementedError();
}

class _NoopBridge implements MediaPlaybackSourceBridge {
  @override
  Future<MediaPlaybackSourceResult> assemblePlaybackSource({
    required MediaPlaybackRequest request,
    required MediaPlaybackBundle bundle,
    required MediaPlaybackBackendContext? context,
    required AppLocalizations l10n,
  }) => throw UnimplementedError();
}
