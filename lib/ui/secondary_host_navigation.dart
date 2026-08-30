import 'dart:async';

import 'package:flutter/material.dart';

import '../desktop/desktop_environment.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';

Future<void> handleSecondaryHostBack(BuildContext context) {
  return EmbeddedDetailLauncher.closeHostOrPop(context);
}

class SecondaryHostBackScope extends StatelessWidget {
  final Widget child;

  const SecondaryHostBackScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        unawaited(handleSecondaryHostBack(context));
      },
      child: child,
    );
  }
}

PreferredSizeWidget buildSecondaryHostAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
  bool centerTitle = false,
  Color? backgroundColor,
}) {
  if (DesktopEnvironment.isDesktopPlatform) {
    // 桌面端二级页统一头部：透明无边框、返回为小方钮，
    // 与设置区等桌面首页的视觉语言保持一致（颜色走全局取色）。
    final colors = context.appColors;
    return AppBar(
      automaticallyImplyLeading: false,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              onPressed: () {
                unawaited(handleSecondaryHostBack(context));
              },
              style: IconButton.styleFrom(
                backgroundColor: colors.surface,
                side: BorderSide(color: colors.borderSubtle),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
            ),
          ),
        ),
      ),
      leadingWidth: 44,
      title: title,
      titleSpacing: 4,
      actions: actions,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }
  return AppBar(
    automaticallyImplyLeading: false,
    leading: IconButton(
      onPressed: () {
        unawaited(handleSecondaryHostBack(context));
      },
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
    ),
    title: title,
    actions: actions,
    centerTitle: centerTitle,
    backgroundColor: backgroundColor,
  );
}
