part of 'media_list_screen.dart';

extension _MediaListScreenActions on _MediaListScreenState {
  Future<void> _showPosterItemActions(MediaLibraryItem item) async {
    await const MediaItemActionSheetController().show(
      context,
      item: item,
      title: MediaItemActionSheetController.defaultTitle(item),
      localeMap: _localeMap,
      favoriteOnly: _isPersonItem(item),
      initialWatched: item.watched == 1,
      onChanged: (state) {
        _replaceItemLocally(
          item.guid,
          (current) => current.copyWith(watched: state.watched ? 1 : 0),
        );
      },
    );
  }

  String _continueActionTitleV2(MediaLibraryItem item) {
    final l10n = AppLocalizations.of(context);
    final type = item.type.trim().toLowerCase();
    if (type == 'movie') return item.displayTitle;
    if (type != 'episode') return item.displayTitle;
    final seriesTitle = item.tvTitle.trim().isNotEmpty
        ? item.tvTitle.trim()
        : item.displayTitle;
    final seasonText = item.seasonNumber == 0
        ? l10n.detailSeasonSpecial
        : l10n.detailSeasonNumber(
            item.seasonNumber > 0 ? item.seasonNumber : 1,
          );
    return '《$seriesTitle》 $seasonText';
  }

  int _intFlag(dynamic value) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Future<({bool watched, bool favorite})> _loadContinueItemFlags(
    MediaLibraryItem item,
  ) async {
    var watched = item.watched == 1;
    var favorite = false;
    try {
      final detail = await FeiniuApi(
        context.read<NasProvider>(),
      ).getItemDetail(item.guid);
      final rawItem = detail['item'];
      final itemMap = rawItem is Map<String, dynamic> ? rawItem : detail;
      watched =
          _intFlag(itemMap['is_watched']) == 1 ||
          _intFlag(itemMap['watched']) == 1;
      favorite =
          _intFlag(itemMap['is_favorite']) == 1 ||
          _intFlag(detail['is_favorite']) == 1;
    } catch (error) {
      debugPrint('[UI][HOME] continue flags load failed ${item.guid}: $error');
    }
    return (watched: watched, favorite: favorite);
  }

  Future<void> _showContinueWatchingActionsV2(
    MediaLibraryItem item, {
    required String heroTag,
  }) async {
    await AsyncActionGuard.run<void>(
      'continue_watch_sheet:${item.guid.trim()}',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
        final flags = await _loadContinueItemFlags(item);
        if (!mounted) return;
        final l10n = AppLocalizations.of(context);

        final action = await showAppActionSheet<_ContinueWatchingAction>(
          context,
          title: _continueActionTitleV2(item),
          options: <AppActionSheetOption<_ContinueWatchingAction>>[
            AppActionSheetOption(
              value: _ContinueWatchingAction.viewDetail,
              label: l10n.homeActionViewDetail,
            ),
            AppActionSheetOption(
              value: _ContinueWatchingAction.markWatched,
              label: flags.watched
                  ? l10n.actionMarkAsUnwatched
                  : l10n.actionMarkAsWatched,
            ),
            AppActionSheetOption(
              value: _ContinueWatchingAction.favorite,
              label: flags.favorite
                  ? l10n.actionFavoriteRemove
                  : l10n.actionFavoriteAdd,
            ),
            AppActionSheetOption(
              value: _ContinueWatchingAction.restart,
              label: l10n.homeActionRestartPlayback,
            ),
            AppActionSheetOption(
              value: _ContinueWatchingAction.remove,
              label: l10n.homeActionRemoveFromContinue,
              destructive: true,
            ),
          ],
        );
        if (!mounted || action == null) return;

        final api = FeiniuApi(context.read<NasProvider>());
        try {
          switch (action) {
            case _ContinueWatchingAction.viewDetail:
              await _openItemDetail(item, heroTag: heroTag);
              break;
            case _ContinueWatchingAction.markWatched:
              final nextWatched = !flags.watched;
              await api.setWatched(item.guid, watched: nextWatched);
              _replaceItemLocally(
                item.guid,
                (current) => current.copyWith(
                  watched: nextWatched ? 1 : 0,
                  watchedTs: nextWatched ? current.duration : 0,
                ),
              );
              unawaited(_refreshContinueWatching());
              _showHomeSnackBar(
                nextWatched
                    ? l10n.actionMarkedAsWatched
                    : l10n.actionMarkedAsUnwatched,
              );
              break;
            case _ContinueWatchingAction.favorite:
              final nextFavorite = !flags.favorite;
              await api.setFavorite(item.guid, favorite: nextFavorite);
              _showHomeSnackBar(
                nextFavorite
                    ? l10n.actionFavoriteAdded
                    : l10n.actionFavoriteRemoved,
              );
              break;
            case _ContinueWatchingAction.restart:
              await const ItemPlaybackLauncher().open(
                context,
                itemGuid: item.guid,
                fallbackTitle: item.displayTitle,
                startFromBeginning: true,
              );
              if (!mounted) return;
              unawaited(_refreshContinueWatching());
              break;
            case _ContinueWatchingAction.remove:
              await api.deletePlaybackRecord(itemGuid: item.guid);
              if (!mounted) return;
              _applyState(() {
                _continueWatching = _continueWatching
                    .where((entry) => entry.guid != item.guid)
                    .toList(growable: false);
              });
              unawaited(_refreshContinueWatching());
              _showHomeSnackBar(l10n.homeRemovedFromContinue);
              break;
          }
        } catch (error) {
          debugPrint('[UI][HOME] continue action failed ${item.guid}: $error');
          _showHomeSnackBar(
            l10n.commonOperationFailedRetryLater,
            backgroundColor: const Color(0xFF7A1F28),
          );
        }
      },
    );
  }
}
