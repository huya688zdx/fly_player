import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/embedded_detail_launcher.dart';
import '../../theme/app_theme.dart';
import '../common/app_ambient_page.dart';

/// 详情加载与失败状态共用的页面壳，保证状态切换时返回入口始终可用。
class DetailStatusPage extends StatelessWidget {
  const DetailStatusPage({super.key, required this.child, this.title});

  final Widget child;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leadingWidth: 64,
          title: title,
          titleSpacing: 4,
          centerTitle: false,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(
              child: IconButton(
                key: const ValueKey('detail-status-back'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () {
                  unawaited(EmbeddedDetailLauncher.closeHostOrPop(context));
                },
                style: IconButton.styleFrom(
                  backgroundColor: colors.surface.withValues(alpha: 0.72),
                  side: BorderSide(color: colors.borderSubtle),
                ),
                icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
              ),
            ),
          ),
        ),
        body: child,
      ),
    );
  }
}
