import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../models/media_library_item.dart';
import '../providers/nas_provider.dart';
import '../services/app_log_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../widgets/common/app_action_sheet.dart';
import 'play_detail_item_actions.dart';

enum _MediaItemSheetAction { toggleWatched, toggleFavorite }

class MediaItemActionSheetState {
  final bool watched;
  final bool favorite;

  const MediaItemActionSheetState({
    required this.watched,
    required this.favorite,
  });
}

class MediaItemActionSheetController {
  static final DetailTopTip _topTip = DetailTopTip();

  const MediaItemActionSheetController();

  Future<void> show(
    BuildContext context, {
    required MediaLibraryItem item,
    required String title,
    Map<String, dynamic> localeMap = const <String, dynamic>{},
    bool favoriteOnly = false,
    bool? initialFavorite,
    bool? initialWatched,
    ValueChanged<MediaItemActionSheetState>? onChanged,
  }) async {
    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    var watched = initialWatched ?? item.watched == 1;
    var favorite = initialFavorite ?? false;

    final needFavorite = initialFavorite == null;
    final needWatched = !favoriteOnly && initialWatched == null;
    if (needFavorite || needWatched) {
      try {
        final detail = await api.getItemDetail(item.guid);
        final rawItem = detail['item'];
        final itemMap = rawItem is Map<String, dynamic> ? rawItem : detail;
        if (needFavorite) {
          favorite =
              _intFlag(itemMap['is_favorite']) == 1 ||
              _intFlag(detail['is_favorite']) == 1;
        }
        if (needWatched) {
          watched =
              _intFlag(itemMap['is_watched']) == 1 ||
              _intFlag(itemMap['watched']) == 1;
        }
      } catch (error, stackTrace) {
        unawaited(
          AppErrorReporter.report(
            error,
            action: 'prefetch media item detail',
            source: 'media_item_action_sheet',
            stackTrace: stackTrace,
            fallbackKind: AppExceptionKind.noData,
            level: AppLogLevel.warning,
            details: 'itemGuid=${item.guid}',
          ),
        );
        // Fall back to the current list state if detail prefetch fails.
      }
    }

    if (!context.mounted) return;
    final action = await showAppActionSheet<_MediaItemSheetAction>(
      context,
      title: title,
      options: <AppActionSheetOption<_MediaItemSheetAction>>[
        if (!favoriteOnly)
          AppActionSheetOption(
            value: _MediaItemSheetAction.toggleWatched,
            label: watched ? '标记为未观看' : '标记为已观看',
          ),
        AppActionSheetOption(
          value: _MediaItemSheetAction.toggleFavorite,
          label: favorite ? '取消收藏' : '收藏',
        ),
      ],
    );
    if (!context.mounted || action == null) return;

    try {
      switch (action) {
        case _MediaItemSheetAction.toggleWatched:
          final result = await PlayDetailItemActions(
            api,
            localeMap: localeMap,
          ).toggleWatched(itemGuid: item.guid, currentWatched: watched);
          if (!context.mounted) return;
          watched = result.state;
          onChanged?.call(
            MediaItemActionSheetState(watched: watched, favorite: favorite),
          );
          _showTopTip(
            context,
            result.message,
            watched ? context.appColors.success : context.appColors.textMuted,
          );
          break;
        case _MediaItemSheetAction.toggleFavorite:
          final result = await PlayDetailItemActions(
            api,
            localeMap: localeMap,
          ).toggleFavorite(itemGuid: item.guid, currentLiked: favorite);
          if (!context.mounted) return;
          favorite = result.state;
          onChanged?.call(
            MediaItemActionSheetState(watched: watched, favorite: favorite),
          );
          _showTopTip(
            context,
            result.message,
            favorite ? context.appColors.success : context.appColors.textMuted,
          );
          break;
      }
    } catch (error, stackTrace) {
      if (!context.mounted) return;
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'toggle media item state',
          source: 'media_item_action_sheet',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.transient,
        ),
      );
      _showTopTip(context, '操作失败，请稍后重试', context.appColors.danger);
    }
  }

  static String defaultTitle(MediaLibraryItem item) {
    final type = item.type.trim().toLowerCase();
    final baseTitle = _baseTitle(item);
    if (type == 'episode') {
      return '《$baseTitle》 ${_seasonLabel(item.seasonNumber)} ${_episodeLabel(item.episodeNumber)}';
    }
    if (type == 'season') {
      return '《$baseTitle》 ${_seasonLabel(item.seasonNumber)}';
    }
    return '《$baseTitle》';
  }

  static String seasonTitle(String seriesTitle, MediaLibraryItem season) {
    final baseTitle = seriesTitle.trim().isNotEmpty
        ? seriesTitle.trim()
        : _baseTitle(season);
    return '《$baseTitle》 ${_seasonLabel(season.seasonNumber)}';
  }

  static String episodeTitle(String seriesTitle, MediaLibraryItem episode) {
    final baseTitle = seriesTitle.trim().isNotEmpty
        ? seriesTitle.trim()
        : _baseTitle(episode);
    return '《$baseTitle》 ${_seasonLabel(episode.seasonNumber)} ${_episodeLabel(episode.episodeNumber)}';
  }

  static String _baseTitle(MediaLibraryItem item) {
    if (item.tvTitle.trim().isNotEmpty) {
      return item.tvTitle.trim();
    }
    if (item.displayTitle.trim().isNotEmpty) {
      return item.displayTitle.trim();
    }
    return item.title.trim();
  }

  static String _seasonLabel(int seasonNumber) {
    if (seasonNumber == 0) return '特别篇';
    final season = seasonNumber > 0 ? seasonNumber : 1;
    return '第$season季';
  }

  static String _episodeLabel(int episodeNumber) {
    final episode = episodeNumber > 0 ? episodeNumber : 1;
    return '第$episode集';
  }

  static int _intFlag(dynamic value) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static void _showTopTip(BuildContext context, String message, Color color) {
    _topTip.show(context, message: message, color: color);
  }
}
