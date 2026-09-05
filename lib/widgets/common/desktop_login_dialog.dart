import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_transitions.dart';
import 'app_modal_surface.dart';

/// 桌面连接辅助页使用受约束弹窗，避免首登阶段覆盖整个主窗口。
Future<T?> showDesktopLoginDialog<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 1180,
  double maxHeight = 860,
}) {
  final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  if (!isDesktop) {
    return Navigator.of(context).push<T>(
      AppTransitions.leftToRightPageTurnRoute<T>(child, fullscreenDialog: true),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(36),
        child: AppModalSurface(
          floating: true,
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(dialogContext).pop();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              key: const Key('desktopLoginDialogSurface'),
              width: (size.width - 72).clamp(0.0, maxWidth),
              height: (size.height - 72).clamp(0.0, maxHeight),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
