import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import 'desktop_breakpoints.dart';
import 'desktop_split_controller.dart';
import 'desktop_tokens.dart';

/// 桌面侧栏（宽 216，对应原型 styles.css 的 .side-nav）。
///
/// 顶部品牌区 + 两项主导航（tab 级，选中态 selectionSoft 底色 + 左侧 3px
/// selection 竖条）+ 分隔线下的次级入口（rootNavigator 具名路由）+ 底部
/// 「浏览 | 详情」分屏开关（仅窗口 ≥ [DesktopBreakpoints.splitMinWidth] 时显示）。
///
/// 颜色一律经 [AppThemeColors] 读取，7 套预设与亮暗模式自动跟随。
class DesktopSideBar extends StatelessWidget {
  const DesktopSideBar({
    super.key,
    required this.selectedTabIndex,
    required this.onTabSelected,
    this.splitController,
  });

  /// 当前主导航页签序号（0=影视、1=设置，与 MainPrimaryTab.tabIndex 对齐）。
  final int selectedTabIndex;

  /// 点击主导航项回调，参数为目标页签序号。
  final ValueChanged<int> onTabSelected;

  /// 分屏状态；为 null 时不渲染底部开关（Shell 内注入，保持可独立预览）。
  final DesktopSplitController? splitController;

  void _openSecondary(BuildContext context, String routeName) {
    Navigator.of(context, rootNavigator: true).pushNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showSplitToggle =
        splitController != null &&
        MediaQuery.widthOf(context) >= DesktopBreakpoints.splitMinWidth;

    return SizedBox(
      width: DesktopTokens.sidebarWidth,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _DesktopSideBarBrand(title: l10n.appTitle),
            _DesktopSideBarRow(
              icon: Icons.video_library_outlined,
              label: l10n.navMovies,
              selected: selectedTabIndex == 0,
              onTap: () => onTabSelected(0),
            ),
            _DesktopSideBarRow(
              icon: Icons.tune_rounded,
              label: l10n.navSettings,
              selected: selectedTabIndex == 1,
              onTap: () => onTabSelected(1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Divider(
                height: 1,
                thickness: 1,
                color: context.appColors.borderSubtle,
              ),
            ),
            // 次级入口：与首页 AppBar 的搜索/大屏浏览入口同目的地，走 rootNavigator。
            _DesktopSideBarRow(
              icon: Icons.connected_tv,
              label: l10n.posterBrowseEntryTooltip,
              onTap: () => _openSecondary(context, '/screen/poster-browse'),
            ),
            _DesktopSideBarRow(
              icon: Icons.search_rounded,
              label: l10n.searchPlaceholder,
              onTap: () => _openSecondary(context, '/screen/search'),
            ),
            _DesktopSideBarRow(
              icon: Icons.favorite_border_rounded,
              label: l10n.listFilterFavorite,
              onTap: () => _openSecondary(context, '/screen/favorites'),
            ),
            _DesktopSideBarRow(
              icon: Icons.download_outlined,
              label: l10n.downloadListTitle,
              onTap: () => _openSecondary(context, '/screen/downloads'),
            ),
            const Spacer(),
            if (showSplitToggle)
              _DesktopSideBarSplitToggle(controller: splitController!),
          ],
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

class _DesktopSideBarRow extends StatefulWidget {
  const _DesktopSideBarRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_DesktopSideBarRow> createState() => _DesktopSideBarRowState();
}

class _DesktopSideBarRowState extends State<_DesktopSideBarRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = widget.selected;
    final foreground = selected ? colors.textPrimary : colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: DesktopTokens.hoverDuration,
            curve: Curves.easeOutCubic,
            height: DesktopTokens.sidebarItemHeight,
            decoration: BoxDecoration(
              color: selected
                  ? colors.selectionSoft
                  : _hovering
                  ? colors.surface
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
                Icon(widget.icon, size: 20, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSideBarSplitToggle extends StatefulWidget {
  const _DesktopSideBarSplitToggle({required this.controller});

  final DesktopSplitController controller;

  @override
  State<_DesktopSideBarSplitToggle> createState() =>
      _DesktopSideBarSplitToggleState();
}

class _DesktopSideBarSplitToggleState
    extends State<_DesktopSideBarSplitToggle> {
  bool _hovering = false;

  // 「浏览 | 详情」为分屏开关的固定组合标签，无对应 l10n key（两侧语义随语言变化
  // 也难以整句翻译），按约定使用中文常量。
  static const String _splitToggleLabel = '浏览 | 详情';

  void _toggle() {
    widget.controller.enabled = !widget.controller.enabled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: AnimatedContainer(
                duration: DesktopTokens.hoverDuration,
                curve: Curves.easeOutCubic,
                height: DesktopTokens.sidebarItemHeight,
                decoration: BoxDecoration(
                  color: _hovering ? colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    DesktopTokens.sidebarItemRadius,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _splitToggleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 26,
                      // 显式取 AppThemeColors：Material 默认 Switch 读
                      // ColorScheme.primary，动态取色只更新 ThemeExtension，
                      // 不显式着色会永远停在静态主题色。
                      child: Switch(
                        value: widget.controller.enabled,
                        onChanged: (value) => widget.controller.enabled = value,
                        activeThumbColor: colors.selection,
                        activeTrackColor: colors.selection.withValues(
                          alpha: 0.45,
                        ),
                        inactiveThumbColor: colors.textMuted,
                        inactiveTrackColor: colors.surface,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
