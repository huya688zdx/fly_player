import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../screens/app_settings_screen.dart';
import '../screens/media_list_screen.dart';
import '../theme/app_theme.dart';
import 'desktop_detail_pane_host.dart';
import 'desktop_side_bar.dart';
import 'desktop_split_controller.dart';

/// 桌面侧栏 Shell：左侧 [DesktopSideBar] + 右侧主导航两页（与
/// MainNavigation 的底部胶囊路径复用同一组页面），宽窗口下替代底部导航。
///
/// 分屏「浏览 | 详情」状态经 [ChangeNotifierProvider] 注入
/// [DesktopSplitController]；开启分屏后右栏由 [DesktopDetailPaneHost]
/// 承载（经 [DesktopSplitController.paneHostBuilder] 接线）。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, this.initialTab = 0, this.pages});

  /// 初始主导航页签序号（0=影视、1=设置，与 MainPrimaryTab.tabIndex 对齐）。
  final int initialTab;

  /// 主导航两页内容；生产环境固定复用 [MediaListScreen] / [AppSettingsScreen]
  /// （与 MainNavigation 的 IndexedStack 相同）。IndexedStack 会同时构建两页，
  /// 测试可注入轻量替身避免拉起完整 provider 栈。
  final List<Widget>? pages;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  // 接线分屏详情宿主（feat/desktop-detail-pane）：开启分屏后右栏由
  // DesktopDetailPaneHost 承载，共享同一 DesktopSplitController。
  late final DesktopSplitController _splitController = DesktopSplitController()
    ..paneHostBuilder = _buildPaneHost;
  late int _selectedTab = widget.initialTab;

  Widget _buildPaneHost(BuildContext context) =>
      DesktopDetailPaneHost(splitController: _splitController);

  @override
  void didUpdateWidget(covariant DesktopShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（如 MainHostBridge）切换 tab 时同步到 Shell 内部状态。
    final nextTab = widget.initialTab;
    if (nextTab != oldWidget.initialTab &&
        nextTab >= 0 &&
        nextTab <= 1 &&
        nextTab != _selectedTab) {
      _selectedTab = nextTab;
    }
  }

  @override
  void dispose() {
    _splitController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index < 0 || index > 1 || index == _selectedTab) return;
    setState(() => _selectedTab = index);
  }

  void _openSearch() {
    Navigator.of(context, rootNavigator: true).pushNamed('/screen/search');
  }

  Future<void> _escape() async {
    await Navigator.of(context, rootNavigator: true).maybePop();
  }

  /// 主焦点位于文本输入（EditableText / TextField）内时，数字与 Esc 快捷键让路，
  /// 不劫持输入；Ctrl+K 组合键不受影响。
  bool get _isEditingTextActive {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pages =
        widget.pages ?? const <Widget>[MediaListScreen(), AppSettingsScreen()];
    final dividerColor = colors.borderSubtle;

    return ChangeNotifierProvider<DesktopSplitController>.value(
      value: _splitController,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _DesktopOpenSearchIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _DesktopEscapeIntent(),
          SingleActivator(LogicalKeyboardKey.digit1): _DesktopTabIntent(0),
          SingleActivator(LogicalKeyboardKey.numpad1): _DesktopTabIntent(0),
          SingleActivator(LogicalKeyboardKey.digit2): _DesktopTabIntent(1),
          SingleActivator(LogicalKeyboardKey.numpad2): _DesktopTabIntent(1),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _DesktopOpenSearchIntent:
                _DesktopShortcutAction<_DesktopOpenSearchIntent>(
                  onInvoke: (_) => _openSearch(),
                ),
            _DesktopEscapeIntent: _DesktopShortcutAction<_DesktopEscapeIntent>(
              enabledWhen: (_) => !_isEditingTextActive,
              onInvoke: (_) => unawaited(_escape()),
            ),
            _DesktopTabIntent: _DesktopShortcutAction<_DesktopTabIntent>(
              enabledWhen: (_) => !_isEditingTextActive,
              onInvoke: (intent) => _selectTab(intent.tabIndex),
            ),
          },
          // autofocus 兜底：Shell 内无可聚焦控件时也保证按键事件进入本快捷键域。
          child: Focus(
            autofocus: true,
            skipTraversal: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DesktopSideBar(
                  selectedTabIndex: _selectedTab,
                  onTabSelected: _selectTab,
                  splitController: _splitController,
                ),
                VerticalDivider(width: 1, thickness: 1, color: dividerColor),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _splitController,
                    builder: (context, _) {
                      if (!_splitController.enabled) {
                        return IndexedStack(
                          index: _selectedTab,
                          children: pages,
                        );
                      }
                      // paneFraction 为详情栏（右栏）宽度占比，按 flex 换算。
                      final paneFlex = (_splitController.paneFraction * 100)
                          .round();
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            flex: 100 - paneFlex,
                            child: IndexedStack(
                              index: _selectedTab,
                              children: pages,
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: dividerColor,
                          ),
                          Expanded(
                            flex: paneFlex,
                            child: _buildDetailPane(context),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPane(BuildContext context) {
    final hostBuilder = _splitController.paneHostBuilder;
    if (hostBuilder != null) return hostBuilder(context);
    return _DesktopPanePlaceholder(controller: _splitController);
  }
}

class _DesktopOpenSearchIntent extends Intent {
  const _DesktopOpenSearchIntent();
}

class _DesktopEscapeIntent extends Intent {
  const _DesktopEscapeIntent();
}

class _DesktopTabIntent extends Intent {
  const _DesktopTabIntent(this.tabIndex);

  final int tabIndex;
}

/// 带动态启用条件的快捷键 Action：disabled 时 Shortcuts 返回 ignored，
/// 按键继续冒泡（文本框内数字/Esc 不被吞掉）。
class _DesktopShortcutAction<T extends Intent> extends Action<T> {
  _DesktopShortcutAction({required this.onInvoke, this.enabledWhen});

  final void Function(T intent) onInvoke;
  final bool Function(T intent)? enabledWhen;

  @override
  bool isEnabled(T intent) => enabledWhen?.call(intent) ?? true;

  @override
  Object? invoke(T intent) {
    onInvoke(intent);
    return null;
  }
}

/// 分屏详情宿主未接线（desktop-detail-pane 未合入）时的右栏占位：
/// 居中提示 + 比例预设 chip + 关闭分屏按钮。
class _DesktopPanePlaceholder extends StatelessWidget {
  const _DesktopPanePlaceholder({required this.controller});

  final DesktopSplitController controller;

  // 分屏详情宿主尚未接入的占位文案，无对应 l10n key（接入后随宿主一并移除）。
  static const String _placeholderMessage = '分屏详情宿主待接入（desktop-detail-pane）';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return ColoredBox(
          color: colors.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.view_sidebar_outlined,
                  size: 40,
                  color: colors.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  _placeholderMessage,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Material(
                  type: MaterialType.transparency,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final fraction
                          in DesktopSplitController
                              .paneFractionPresets) ...<Widget>[
                        _PaneFractionChip(
                          fraction: fraction,
                          selected:
                              (controller.paneFraction - fraction).abs() <
                              0.001,
                          onTap: () => controller.setPaneFraction(fraction),
                        ),
                        if (fraction !=
                            DesktopSplitController.paneFractionPresets.last)
                          const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                IconButton(
                  key: const ValueKey<String>('desktop_pane_close'),
                  tooltip: l10n.commonClose,
                  onPressed: () => controller.enabled = false,
                  icon: const Icon(Icons.close),
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PaneFractionChip extends StatelessWidget {
  const _PaneFractionChip({
    required this.fraction,
    required this.selected,
    required this.onTap,
  });

  final double fraction;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.selectionSoft : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colors.selection : colors.chipBorder,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          '${(fraction * 100).round()}%',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: selected ? colors.textPrimary : colors.textSecondary,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
