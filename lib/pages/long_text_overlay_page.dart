import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../ui/app_sheet_transitions.dart';
import '../widgets/common/app_modal_surface.dart';

class LongTextOverlayPage extends StatelessWidget {
  final String title;
  final String sectionTitle;
  final String content;
  final bool floating;

  const LongTextOverlayPage({
    super.key,
    required this.title,
    required this.sectionTitle,
    required this.content,
    this.floating = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String sectionTitle,
    required String content,
  }) async {
    final inheritedTheme = Theme.of(context);
    final colors = context.appColors;

    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final page = LongTextOverlayPage(
      title: title,
      sectionTitle: sectionTitle,
      content: content,
      floating: isLandscape,
    );

    if (isLandscape) {
      return showDialog<void>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: true,
        barrierColor: colors.overlayScrim,
        builder: (_) => Theme(data: inheritedTheme, child: page),
      );
    }

    return AppSheetTransitions.showBottomSurface<void>(
      context,
      barrierDismissible: true,
      barrierLabel: sectionTitle,
      barrierColor: colors.overlayScrim,
      builder: (_) => Theme(data: inheritedTheme, child: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final panelHeight = (media.size.height * 0.72).clamp(420.0, 760.0);
    final panelDialogHeight = (media.size.height * 0.68).clamp(360.0, 700.0);
    final panelDialogWidth = (media.size.width * 0.62).clamp(560.0, 920.0);
    final bodyText = content.trim().isEmpty
        ? AppLocalizations.of(context).detailOverviewEmpty
        : content;

    final child = AppModalSurface(
      key: const ValueKey<String>('app-modal-surface-long-text'),
      floating: floating,
      borderRadius: floating ? BorderRadius.circular(28) : null,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            floating ? 28 : 22,
            floating ? 20 : 14,
            floating ? 28 : 22,
            floating ? 24 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sectionTitle,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () {
                      if (AppSheetTransitions.maybeClose<void>(context)) {
                        return;
                      }
                      Navigator.of(context).maybePop();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.close_rounded,
                        color: colors.textSecondary,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: floating ? 18 : 14),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    key: const ValueKey<String>('long-text-content'),
                    bodyText,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 16,
                      height: 1.65,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.08,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (floating) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: panelDialogWidth,
          height: panelDialogHeight,
          child: child,
        ),
      );
    }

    return SizedBox(height: panelHeight, width: double.infinity, child: child);
  }
}
