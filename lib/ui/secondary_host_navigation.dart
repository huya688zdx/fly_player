import 'dart:async';

import 'package:flutter/material.dart';

import '../services/embedded_detail_launcher.dart';

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
