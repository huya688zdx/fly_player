import '../l10n/generated/app_localizations.dart';

class AppLocalizationLookup {
  const AppLocalizationLookup._();

  static String text(
    AppLocalizations l10n,
    String path, {
    required String fallback,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return switch (path) {
      'layout.subheading.season.special' => l10n.detailSeasonSpecial,
      'layout.subheading.season.number' => l10n.detailSeasonNumber(
        _intParam(params, 'number'),
      ),
      'layout.subheading.episode.number' => l10n.detailEpisodeNumber(
        _intParam(params, 'number'),
      ),
      'layout.subheading.episode.unknown' => l10n.detailEpisodeUnknown,
      'layout.subheading.tv.episodes' => l10n.detailEpisodeTotal(
        _intParam(params, 'count'),
      ),
      'layout.subheading.tv.seasons' => l10n.detailTvSeasonCount(
        _intParam(params, 'count'),
      ),
      'layout.subheading.person.items' => l10n.personItemCount(
        _intParam(params, 'count'),
      ),
      'stream.video.videoResolution.others' => l10n.commonOther,
      'stream.audio.audioSpecs.dolbySurround' => l10n.audioSpecDolbySurround,
      'stream.audio.audioSpecs.dolbyAtmos' => l10n.audioSpecDolbyAtmos,
      'stream.audio.audioSpecs.dts' => l10n.audioSpecDts,
      'stream.audio.audioSpecs.stereo' => l10n.audioSpecStereo,
      'stream.audio.audioSpecs.others' => l10n.commonOther,
      'layout.globalError.clickToRetry' => l10n.commonClickTooFastRetryLater,
      'layout.globalError.refresh' => l10n.commonRefreshRetry,
      'layout.dataLayout.noData' => l10n.commonNoData,
      'layout.dataLayout.noAccessLibrary' => l10n.commonNoAccessLibrary,
      'layout.dataLayout.loadFailed' => l10n.globalLoadFailed,
      'common.actions.default.cancel' => l10n.commonCancel,
      'common.actions.cancel' => l10n.commonCancel,
      'common.actions.default.default' => l10n.commonConfirm,
      'common.other.none' => l10n.commonNone,
      'common.other.empty' => l10n.commonEmpty,
      'common.resourceType.directory' => l10n.resourceTypeDirectory,
      'common.resourceType.video' => l10n.resourceTypeVideo,
      'common.person.job.actor' => l10n.personJobActor,
      'common.person.job.director' => l10n.personJobDirector,
      'common.person.job.screenplay' => l10n.personJobScreenplay,
      'common.person.job.writer' => l10n.personJobWriter,
      'common.person.job.producer' => l10n.personJobProducer,
      'common.person.asJob' => l10n.personAsJob('${params['job'] ?? ''}'),
      'layout.details.castAndCrew.showMore' => l10n.commonDetails,
      'layout.details.castAndCrew.biography' => l10n.personBiographyTitle,
      'layout.details.overview.overview' => l10n.detailOverviewTitle,
      'layout.details.episode.empty' => l10n.detailEpisodeEmpty,
      'auth.exit.title' => l10n.authExitTitle,
      'auth.exit.content' => l10n.authExitContent,
      'layout.sidebar.home' => l10n.homeTitle,
      'layout.sidebar.allList' => l10n.mediaAllItemsTitle,
      'layout.sidebar.favorite' => l10n.actionFavoriteAdd,
      'common.actions.favorite.favorite' => l10n.actionFavoriteAdd,
      'layout.sidebar.movieList' => l10n.listTypeMovie,
      'layout.sidebar.tvList' => l10n.listTypeTv,
      'layout.sidebar.otherList' => l10n.commonOther,
      'layout.list.continueWatching' => l10n.homeContinueWatching,
      'layout.list.filter.filterButton' => l10n.listFilterButton,
      'layout.list.filter.all' => l10n.listFilterAll,
      'layout.list.filter.resetButton' => l10n.listFilterResetButton,
      'layout.list.filter.decade.Recent' => l10n.listFilterDecadeRecent,
      'layout.list.filter.type.movie' => l10n.listTypeMovie,
      'layout.list.filter.type.tv' => l10n.listTypeTv,
      'layout.list.filter.recognitionStatus.1' => l10n.listRecognitionUnmatched,
      'layout.list.filter.recognitionStatus.2' => l10n.listRecognitionMatched,
      'layout.list.filter.recognitionStatus.3' => l10n.listRecognitionNfo,
      'layout.list.filter.watched.1' => l10n.listWatched,
      'layout.list.filter.watched.0' => l10n.listUnwatched,
      'layout.list.filter.tagMap.type' => l10n.listFilterType,
      'layout.list.filter.tagMap.genres' => l10n.listFilterGenres,
      'layout.list.filter.tagMap.locate' => l10n.listFilterLocate,
      'layout.list.filter.tagMap.decade' => l10n.listFilterDecade,
      'layout.list.filter.tagMap.resolution' => l10n.listFilterResolution,
      'layout.list.filter.tagMap.color_range' => l10n.listFilterColorRange,
      'layout.list.filter.tagMap.audio_type' => l10n.listFilterAudioType,
      'layout.list.filter.tagMap.recognition_status' =>
        l10n.listFilterRecognitionStatus,
      'layout.list.filter.tagMap.watched' => l10n.listFilterWatched,
      'layout.list.favoriteTabs.all' => l10n.commonAll,
      'layout.list.favoriteTabs.movie' => l10n.listTypeMovie,
      'layout.list.favoriteTabs.tv' => l10n.listTypeTv,
      'layout.list.favoriteTabs.episode' => l10n.favoriteTabEpisodes,
      'layout.list.favoriteTabs.person' => l10n.favoriteTabPeople,
      'layout.list.sort.title' => l10n.listSortTitle,
      'layout.list.sort.sortField.createTime' => l10n.listSortCreateTime,
      'layout.list.sort.sortField.releaseDate' => l10n.listSortReleaseDate,
      'layout.list.sort.sortField.title' => l10n.listSortTitleField,
      'layout.list.sort.sortField.voteAverage' => l10n.listSortVoteAverage,
      'layout.list.sort.sortType.asc' => l10n.listSortAsc,
      'layout.list.sort.sortType.desc' => l10n.listSortDesc,
      'layout.search.history' => l10n.searchHistory,
      'layout.search.resultCount' => l10n.searchResultCount(
        _intParam(params, 'count'),
      ),
      'layout.search.placeholder' => l10n.searchPlaceholder,
      _ => _replaceParams(fallback, params),
    };
  }

  static int _intParam(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static String _replaceParams(String fallback, Map<String, Object?> params) {
    var resolved = fallback;
    for (final entry in params.entries) {
      resolved = resolved.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return resolved;
  }
}
