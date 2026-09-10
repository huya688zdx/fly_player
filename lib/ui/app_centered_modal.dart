import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_motion.dart';

/// 桌面「独立浮窗」式公共弹层：主题面板 + 遮罩 + 淡入缩放动效。
///
/// 与 [AppSheetTransitions]（底部/侧滑 sheet 的动效语言）互补：本层专做
/// 居中/贴顶的独立弹窗面板。动效时长与曲线复用 [AppMotion]，与既有弹层
/// 保持同一动效语言（220ms，进 easeOutCubic / 退 easeInCubic，缩放
/// 0.96→1 淡入）；颜色一律走 [AppThemeColors] token，亮暗主题自适应。
///
/// ```dart
/// final result = await AppCenteredModal.show<String>(
///   context,
///   builder: (dialogContext) => const MyPanel(),
/// );
/// ```
/// 关闭方式：Esc、点击遮罩（均返回 null）、面板内 `Navigator.pop(result)`。
class AppCenteredModal {
  const AppCenteredModal._();

  static Future<T?> show<T extends Object?>(
    BuildContext context, {
    required WidgetBuilder builder,
    AlignmentGeometry alignment = Alignment.center,
    EdgeInsetsGeometry insetPadding = const EdgeInsets.all(32),
    Color barrierColor = const Color(0x70000000),
    bool barrierDismissible = true,
    String barrierLabel = 'app-centered-modal',
    bool useRootNavigator = false,
  }) {
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor: barrierColor,
      transitionDuration: AppMotion.sheetTransition,
      pageBuilder: (dialogContext, _, __) => _AppCenteredModalPanel(
        alignment: alignment,
        insetPadding: insetPadding,
        child: Builder(builder: builder),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.sheetEnterCurve,
          reverseCurve: AppMotion.sheetExitCurve,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _AppCenteredModalPanel extends StatelessWidget {
  const _AppCenteredModalPanel({
    required this.alignment,
    required this.insetPadding,
    required this.child,
  });

  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry insetPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: insetPadding,
        child: Material(
          color: colors.backgroundElevated,
          clipBehavior: Clip.antiAlias,
          elevation: 28,
          shadowColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.borderSubtle),
          ),
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                DismissIntent: _PopModalAction(context),
              },
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Esc 关闭弹层自身路由（带结果关闭由面板内 pop(result) 负责）。
class _PopModalAction extends Action<DismissIntent> {
  _PopModalAction(this.context);

  final BuildContext context;

  @override
  Object? invoke(DismissIntent intent) {
    Navigator.of(context).pop();
    return null;
  }
}
