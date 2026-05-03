import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/media_library_item.dart';
import '../providers/nas_provider.dart';
import '../services/app_log_service.dart';
import '../theme/app_theme.dart';
import '../utils/async_action_guard.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../widgets/common/app_action_sheet.dart';
import 'play_detail_item_actions.dart';

enum _MediaItemSheetAction { toggleWatched, toggleFavorite }

/// 表示条目操作菜单执行后的最新状态。
class MediaItemActionSheetState {
  final bool watched;
  final bool favorite;

  /// 根据收藏与观看状态构造对象。
  const MediaItemActionSheetState({
    required this.watched,
    required this.favorite,
  });
}

/// 负责展示媒体条目的快捷操作菜单。
class MediaItemActionSheetController {
  static final DetailTopTip _topTip = DetailTopTip();

  /// 创建一个媒体条目操作菜单控制器。
  const MediaItemActionSheetController();

  /// 展示媒体条目的操作菜单并处理用户选择。
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
    final l10n = AppLocalizations.of(context);
    await AsyncActionGuard.run<void>(
      'media_item_sheet:${item.guid.trim()}:${favoriteOnly ? 'favorite' : 'full'}',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
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
                label: watched
                    ? l10n.actionMarkAsUnwatched
                    : l10n.actionMarkAsWatched,
              ),
            AppActionSheetOption(
              value: _MediaItemSheetAction.toggleFavorite,
              label: favorite
                  ? l10n.actionFavoriteRemove
                  : l10n.actionFavoriteAdd,
            ),
          ],
        );
        if (!context.mounted || action == null) return;

        try {
          switch (action) {
            case _MediaItemSheetAction.toggleWatched:
              final result = await PlayDetailItemActions(
                api,
                l10n: l10n,
              ).toggleWatched(itemGuid: item.guid, currentWatched: watched);
              if (!context.mounted) return;
              watched = result.state;
              onChanged?.call(
                MediaItemActionSheetState(watched: watched, favorite: favorite),
              );
              _showTopTip(
                context,
                result.message,
                watched
                    ? context.appColors.success
                    : context.appColors.textMuted,
              );
              break;
            case _MediaItemSheetAction.toggleFavorite:
              final result = await PlayDetailItemActions(
                api,
                l10n: l10n,
              ).toggleFavorite(itemGuid: item.guid, currentLiked: favorite);
              if (!context.mounted) return;
              favorite = result.state;
              onChanged?.call(
                MediaItemActionSheetState(watched: watched, favorite: favorite),
              );
              _showTopTip(
                context,
                result.message,
                favorite
                    ? context.appColors.success
                    : context.appColors.textMuted,
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
          _showTopTip(
            context,
            l10n.commonOperationFailedRetryLater,
            context.appColors.danger,
          );
        }
      },
    );
  }

  /// 生成条目操作菜单的默认标题。
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

  /// 生成季度条目在操作菜单中的标题。
  static String seasonTitle(String seriesTitle, MediaLibraryItem season) {
    final baseTitle = seriesTitle.trim().isNotEmpty
        ? seriesTitle.trim()
        : _baseTitle(season);
    return '《$baseTitle》 ${_seasonLabel(season.seasonNumber)}';
  }

  /// 生成剧集条目在操作菜单中的标题。
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
    if (seasonNumber == 0) return 'Special';
    final season = seasonNumber > 0 ? seasonNumber : 1;
    return 'Season $season';
  }

  static String _episodeLabel(int episodeNumber) {
    final episode = episodeNumber > 0 ? episodeNumber : 1;
    return 'Episode $episode';
  }

  static int _intFlag(dynamic value) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static void _showTopTip(BuildContext context, String message, Color color) {
    _topTip.show(context, message: message, color: color);
  }
}
