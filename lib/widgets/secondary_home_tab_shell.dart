import 'package:flutter/material.dart';

import '../desktop/desktop_environment.dart';
import '../l10n/generated/app_localizations.dart';
import '../screens/app_settings_screen.dart';
import '../screens/media_list_screen.dart';
import 'liquid_glass_bottom_navigation.dart';

/// 分屏副栏（/screen/home）的首页宿主。
///
/// 移动端与主 Shell 一样挂底部胶囊导航（影视/设置），保证分屏里也能切换
/// 影视与设置；桌面分屏保持既有裸首页行为（侧栏体系由主窗承担）。
class SecondaryHomeTabShell extends StatefulWidget {
  const SecondaryHomeTabShell({super.key});

  @override
  State<SecondaryHomeTabShell> createState() => _SecondaryHomeTabShellState();
}

class _SecondaryHomeTabShellState extends State<SecondaryHomeTabShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const MediaListScreen(
        key: ValueKey<String>('/screen/home'),
        secondaryHost: true,
      ),
      const AppSettingsScreen(secondaryHost: true),
    ];
    // 桌面分屏宿主自带侧栏体系，副栏首页维持裸内容（不加移动端胶囊）。
    if (DesktopEnvironment.isDesktopPlatform) {
      return pages[0];
    }
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      // 与主 Shell 一致：内容延伸到胶囊后方，由各页面自行预留底部留白。
      extendBody: true,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          for (var index = 0; index < pages.length; index++)
            TickerMode(
              enabled: index == _tabIndex,
              child: pages[index],
            ),
        ],
      ),
      bottomNavigationBar: LiquidGlassBottomNavigation(
        currentIndex: _tabIndex,
        onTap: (index) {
          if (index == _tabIndex) return;
          setState(() {
            _tabIndex = index;
          });
        },
        destinations: <LiquidGlassNavDestination>[
          LiquidGlassNavDestination(
            icon: Icons.video_library_outlined,
            label: l10n.navMovies,
          ),
          LiquidGlassNavDestination(
            icon: Icons.tune_rounded,
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
