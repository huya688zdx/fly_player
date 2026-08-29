import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/action/media_item_action_target.dart';
import '../providers/media_backend_provider.dart';
import '../theme/app_theme.dart';
import '../utils/async_action_guard.dart';
import '../utils/app_error_reporter.dart';
import '../services/app_log_service.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../widgets/common/app_action_sheet.dart';

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
///
/// 收藏 / 已看统一走 [MediaBackend] 中立通道（飞牛→FeiniuApi、Emby→FavoriteItems/
/// PlayedItems），入参为后端中立的 [MediaItemActionTarget]，不再认识任何后端私有模型。
class MediaItemActionSheetController {
  static final DetailTopTip _topTip = DetailTopTip();

  /// 创建一个媒体条目操作菜单控制器。
  const MediaItemActionSheetController();

  /// 展示媒体条目的操作菜单并处理用户选择。
  ///
  /// [favoriteOnly] 仅展示收藏项（人物条目无「已看」语义）。[initialFavorite] /
  /// [initialWatched] 为调用方已知的初值，为 null 时按需向后端预取；不支持对应能力的后端
  /// 自动隐藏相应选项。
  Future<void> show(
    BuildContext context, {
    required MediaItemActionTarget target,
    required String title,
    bool favoriteOnly = false,
    bool? initialFavorite,
    bool? initialWatched,
    ValueChanged<MediaItemActionSheetState>? onChanged,
  }) async {
    final l10n = AppLocalizations.of(context);
    final backend = context.read<MediaBackendProvider>().backend;
    final capabilities = backend.capabilities;
    final showWatched = !favoriteOnly && capabilities.supportsWatched;
    final showFavorite = capabilities.supportsFavorite;
    if (!showWatched && !showFavorite) return;

    await AsyncActionGuard.run<void>(
      'media_item_sheet:${target.id.trim()}:${favoriteOnly ? 'favorite' : 'full'}',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
        var watched = initialWatched ?? target.isWatched;
        var favorite = initialFavorite ?? target.favorite ?? false;

        final needFavorite =
            showFavorite && initialFavorite == null && target.favorite == null;
        final needWatched = showWatched && initialWatched == null;
        if (needFavorite || needWatched) {
          try {
            final detail = await backend.getItemDetail(target.id);
            if (needFavorite) favorite = detail.favorite;
            if (needWatched) watched = detail.watched;
          } catch (error, stackTrace) {
            unawaited(
              AppErrorReporter.report(
                error,
                action: 'prefetch media item detail',
                source: 'media_item_action_sheet',
                stackTrace: stackTrace,
                fallbackKind: AppExceptionKind.noData,
                level: AppLogLevel.warning,
                details: 'itemId=${target.id}',
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
            if (showWatched)
              AppActionSheetOption(
                value: _MediaItemSheetAction.toggleWatched,
                label: watched
                    ? l10n.actionMarkAsUnwatched
                    : l10n.actionMarkAsWatched,
              ),
            if (showFavorite)
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
              final state = await backend.setItemWatched(
                target.id,
                watched: !watched,
              );
              if (!context.mounted) return;
              watched = state;
              onChanged?.call(
                MediaItemActionSheetState(watched: watched, favorite: favorite),
              );
              _showTopTip(
                context,
                state
                    ? l10n.actionMarkedAsWatched
                    : l10n.actionMarkedAsUnwatched,
                state ? context.appColors.success : context.appColors.textMuted,
              );
              break;
            case _MediaItemSheetAction.toggleFavorite:
              final state = await backend.setItemFavorite(
                target.id,
                favorite: !favorite,
              );
              if (!context.mounted) return;
              favorite = state;
              onChanged?.call(
                MediaItemActionSheetState(watched: watched, favorite: favorite),
              );
              _showTopTip(
                context,
                state ? l10n.actionFavoriteAdded : l10n.actionFavoriteRemoved,
                state ? context.appColors.success : context.appColors.textMuted,
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

  /// 以后端中立通道直接切换条目已看状态（桌面右键菜单等场景复用，与 [show] 的
  /// 「标记已看」动作同源）。成功返回后端确认的最新状态；失败时已上报并提示，
  /// 返回 null。
  Future<bool?> setItemWatched(
    BuildContext context, {
    required String itemId,
    required bool watched,
  }) async {
    final l10n = AppLocalizations.of(context);
    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final state = await backend.setItemWatched(itemId, watched: watched);
      if (!context.mounted) return state;
      _showTopTip(
        context,
        state ? l10n.actionMarkedAsWatched : l10n.actionMarkAsUnwatched,
        state ? context.appColors.success : context.appColors.textMuted,
      );
      return state;
    } catch (error, stackTrace) {
      if (!context.mounted) return null;
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'toggle media item watched',
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
      return null;
    }
  }

  /// 以后端中立通道直接切换条目收藏状态（桌面右键菜单等场景复用，与 [show] 的
  /// 「收藏」动作同源）。语义与 [setItemWatched] 一致。
  Future<bool?> setItemFavorite(
    BuildContext context, {
    required String itemId,
    required bool favorite,
  }) async {
    final l10n = AppLocalizations.of(context);
    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final state = await backend.setItemFavorite(itemId, favorite: favorite);
      if (!context.mounted) return state;
      _showTopTip(
        context,
        state ? l10n.actionFavoriteAdded : l10n.actionFavoriteRemoved,
        state ? context.appColors.success : context.appColors.textMuted,
      );
      return state;
    } catch (error, stackTrace) {
      if (!context.mounted) return null;
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'toggle media item favorite',
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
      return null;
    }
  }

  /// 生成条目操作菜单的默认标题。
  static String defaultTitle(
    AppLocalizations l10n,
    MediaItemActionTarget target,
  ) {
    final type = target.type.trim().toLowerCase();
    final base = target.baseTitle.trim();
    if (type == 'episode') {
      return l10n.mediaActionTitleWithSuffix(
        base,
        _seasonEpisodeLabel(l10n, target.seasonNumber, target.episodeNumber),
      );
    }
    if (type == 'season') {
      return l10n.mediaActionTitleWithSuffix(
        base,
        _seasonLabel(l10n, target.seasonNumber),
      );
    }
    return l10n.mediaActionTitle(base);
  }

  /// 生成季度条目在操作菜单中的标题。
  static String seasonTitle(
    AppLocalizations l10n,
    String seriesTitle,
    MediaItemActionTarget season,
  ) {
    final base = seriesTitle.trim().isNotEmpty
        ? seriesTitle.trim()
        : season.baseTitle.trim();
    return l10n.mediaActionTitleWithSuffix(
      base,
      _seasonLabel(l10n, season.seasonNumber),
    );
  }

  /// 生成剧集条目在操作菜单中的标题。
  static String episodeTitle(
    AppLocalizations l10n,
    String seriesTitle,
    MediaItemActionTarget episode,
  ) {
    final base = seriesTitle.trim().isNotEmpty
        ? seriesTitle.trim()
        : episode.baseTitle.trim();
    return l10n.mediaActionTitleWithSuffix(
      base,
      _seasonEpisodeLabel(l10n, episode.seasonNumber, episode.episodeNumber),
    );
  }

  static String _seasonLabel(AppLocalizations l10n, int seasonNumber) {
    if (seasonNumber == 0) return l10n.detailSeasonSpecial;
    return l10n.detailSeasonNumber(seasonNumber > 0 ? seasonNumber : 1);
  }

  static String _seasonEpisodeLabel(
    AppLocalizations l10n,
    int seasonNumber,
    int episodeNumber,
  ) {
    final episode = episodeNumber > 0 ? episodeNumber : 1;
    if (seasonNumber == 0) {
      return '${l10n.detailSeasonSpecial} ${l10n.detailEpisodeNumber(episode)}';
    }
    return l10n.detailSeasonEpisodeNumber(seasonNumber, episode);
  }

  static void _showTopTip(BuildContext context, String message, Color color) {
    _topTip.show(context, message: message, color: color);
  }
}
