import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_catalog.dart';
import '../theme/app_theme.dart';
import 'desktop_hover_region.dart';
import 'desktop_tokens.dart';

/// 桌面侧栏（宽 216，对应原型 styles.css 的 .side-nav）。
///
/// 参考飞牛桌面端布局：主导航（影视 / 搜索 / 收藏 / 下载 / 大屏浏览 / 设置）
/// + 「媒体库」分组（后端媒体库入口）+ 「分类」分组（全部 / 电影 / 电视剧 /
/// 其他，行尾计数）。媒体库、分类与搜索/收藏/下载在影视内容区内打开，
/// 侧栏永远可见；分屏开关在「设置 → 分屏窗口」（与安卓一致）。
///
/// 颜色一律经 [AppThemeColors] 读取，7 套预设、动态取色与亮暗模式自动跟随。
class DesktopSideBar extends StatelessWidget {
  const DesktopSideBar({
    super.key,
    required this.selectedTabIndex,
    required this.onTabSelected,
    this.catalogs = const <MediaCatalog>[],
    this.favoriteCount = 0,
    this.totalItems = 0,
    this.movieCount = 0,
    this.tvCount = 0,
    this.otherCount = 0,
    this.onOpenSearch,
    this.onOpenFavorites,
    this.onOpenDownloads,
    this.onOpenCatalog,
    this.onOpenAllItems,
    this.onOpenByType,
  });

  /// 当前主导航页签序号（0=影视、1=设置，与 MainPrimaryTab.tabIndex 对齐）。
  final int selectedTabIndex;

  /// 点击主导航项回调，参数为目标页签序号。
  final ValueChanged<int> onTabSelected;

  /// 「媒体库」分组：后端媒体库入口列表。
  final List<MediaCatalog> catalogs;

  /// 「分类」分组计数（来自首页概要；后端不可用时为 0）。
  final int favoriteCount;
  final int totalItems;
  final int movieCount;
  final int tvCount;
  final int otherCount;

  /// 内容区入口（搜索 / 收藏 / 下载）。
  final void Function(BuildContext context)? onOpenSearch;
  final void Function(BuildContext context)? onOpenFavorites;
  final void Function(BuildContext context)? onOpenDownloads;

  /// 打开某个媒体库入口（内容区）。
  final void Function(BuildContext context, MediaCatalog catalog)?
  onOpenCatalog;

  /// 打开「全部影视」（内容区）。
  final void Function(BuildContext context)? onOpenAllItems;

  /// 按类型打开分类（内容区）：name 为显示名，typeTags 为中立类型标签。
  final void Function(BuildContext context, String name, List<String> typeTags)?
  onOpenByType;

  void _openSecondary(BuildContext context, String routeName) {
    Navigator.of(context, rootNavigator: true).pushNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      width: DesktopTokens.sidebarWidth,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _DesktopSideBarBrand(title: l10n.appTitle),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _DesktopSideBarRow(
                      icon: Icons.video_library_outlined,
                      label: l10n.navMovies,
                      selected: selectedTabIndex == 0,
                      onTap: () => onTabSelected(0),
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.search_rounded,
                      label: l10n.searchPlaceholder,
                      onTap: () => onOpenSearch?.call(context),
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.favorite_border_rounded,
                      label: l10n.listFilterFavorite,
                      count: favoriteCount > 0 ? favoriteCount : null,
                      onTap: () => onOpenFavorites?.call(context),
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.download_outlined,
                      label: l10n.downloadListTitle,
                      onTap: () => onOpenDownloads?.call(context),
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.connected_tv,
                      label: l10n.posterBrowseEntryTooltip,
                      onTap: () =>
                          _openSecondary(context, '/screen/poster-browse'),
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.tune_rounded,
                      label: l10n.navSettings,
                      selected: selectedTabIndex == 1,
                      onTap: () => onTabSelected(1),
                    ),
                    if (catalogs.isNotEmpty) ...<Widget>[
                      _DesktopSideBarGroupHeader(
                        label: l10n.posterBrowseRowCatalogs,
                      ),
                      for (final catalog in catalogs)
                        _DesktopSideBarRow(
                          icon: Icons.library_books_outlined,
                          label: catalog.title,
                          onTap: () => onOpenCatalog?.call(context, catalog),
                        ),
                    ],
                    _DesktopSideBarGroupHeader(
                      label: l10n.sidebarCategorySectionLabel,
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.apps_rounded,
                      label: l10n.mediaAllItemsTitle,
                      count: totalItems > 0 ? totalItems : null,
                      onTap: () => onOpenAllItems?.call(context),
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.movie_outlined,
                      label: l10n.listTypeMovie,
                      count: movieCount > 0 ? movieCount : null,
                      onTap: () => onOpenByType?.call(
                        context,
                        l10n.listTypeMovie,
                        const <String>['Movie'],
                      ),
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.tv_outlined,
                      label: l10n.listTypeTv,
                      count: tvCount > 0 ? tvCount : null,
                      onTap: () => onOpenByType?.call(
                        context,
                        l10n.listTypeTv,
                        const <String>['TV'],
                      ),
                    ),
                    _DesktopSideBarRow(
                      icon: Icons.folder_outlined,
                      label: l10n.commonOther,
                      count: otherCount > 0 ? otherCount : null,
                      onTap: () => onOpenByType?.call(
                        context,
                        l10n.commonOther,
                        const <String>['Directory', 'Video'],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组标题行：媒体库 / 分类。
class _DesktopSideBarGroupHeader extends StatelessWidget {
  const _DesktopSideBarGroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _DesktopSideBarBrand extends StatelessWidget {
  const _DesktopSideBarBrand({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            // 品牌副标（固定字标，不参与多语言）。
            Text(
              'FLY PLAYER',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 3.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSideBarRow extends StatelessWidget {
  const _DesktopSideBarRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.count,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// 行尾计数（null 不显示）。
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DesktopHoverRegion(
        onTap: onTap,
        builder: (context, hovering) {
          final colors = context.appColors;
          final isLight = Theme.of(context).brightness == Brightness.light;
          final selected = this.selected;
          final foreground = selected
              ? colors.textPrimary
              : hovering && isLight
              ? colors.selection
              : colors.textSecondary;
          return AnimatedContainer(
            // 背景即时切换，避免快速跨项时多行退场动画同时残留。
            duration: Duration.zero,
            curve: Curves.easeOutCubic,
            height: DesktopTokens.sidebarItemHeight,
            decoration: BoxDecoration(
              color: selected
                  ? colors.selectionSoft
                  : hovering
                  ? (isLight
                        ? colors.selection.withValues(alpha: 0.08)
                        : colors.surface)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(
                DesktopTokens.sidebarItemRadius,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: <Widget>[
                // 选中态左侧 3px selection 竖条；未选中时占位保持图标对齐。
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: selected ? colors.selection : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 9),
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count != null) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
