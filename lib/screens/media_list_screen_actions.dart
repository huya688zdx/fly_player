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
    final type = item.type.trim().toLowerCase();
    if (type == 'movie') return item.displayTitle;
    if (type != 'episode') return item.displayTitle;
    final seriesTitle = item.tvTitle.trim().isNotEmpty
        ? item.tvTitle.trim()
        : item.displayTitle;
    final seasonText = item.seasonNumber == 0
        ? '特别篇'
        : '第${item.seasonNumber > 0 ? item.seasonNumber : 1}季';
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
    final flags = await _loadContinueItemFlags(item);
    if (!mounted) return;

    final action = await showAppActionSheet<_ContinueWatchingAction>(
      context,
      title: _continueActionTitleV2(item),
      options: <AppActionSheetOption<_ContinueWatchingAction>>[
        const AppActionSheetOption(
          value: _ContinueWatchingAction.viewDetail,
          label: '查看影片详情',
        ),
        AppActionSheetOption(
          value: _ContinueWatchingAction.markWatched,
          label: flags.watched ? '标记为未观看' : '标记为已观看',
        ),
        AppActionSheetOption(
          value: _ContinueWatchingAction.favorite,
          label: flags.favorite ? '取消收藏' : '收藏',
        ),
        const AppActionSheetOption(
          value: _ContinueWatchingAction.restart,
          label: '从头开始播放',
        ),
        const AppActionSheetOption(
          value: _ContinueWatchingAction.remove,
          label: '从“继续观看”中移除',
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
          _showHomeSnackBar(nextWatched ? '已标记为已观看' : '已标记为未观看');
          break;
        case _ContinueWatchingAction.favorite:
          final nextFavorite = !flags.favorite;
          await api.setFavorite(item.guid, favorite: nextFavorite);
          _showHomeSnackBar(nextFavorite ? '已加入收藏' : '已取消收藏');
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
          _showHomeSnackBar('已从继续观看中移除');
          break;
      }
    } catch (error) {
      debugPrint('[UI][HOME] continue action failed ${item.guid}: $error');
      _showHomeSnackBar('操作失败，请稍后重试', backgroundColor: const Color(0xFF7A1F28));
    }
  }
}
