import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../ui/app_sheet_transitions.dart';

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
        barrierColor: const Color(0xBF020812),
        builder: (_) => Theme(data: inheritedTheme, child: page),
      );
    }

    return AppSheetTransitions.showBottomSurface<void>(
      context,
      barrierDismissible: true,
      barrierLabel: sectionTitle,
      barrierColor: const Color(0xBF020812),
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

    final child = Container(
      decoration: BoxDecoration(
        color: colors.backgroundElevated,
        borderRadius: floating
            ? BorderRadius.circular(28)
            : const BorderRadius.vertical(top: Radius.circular(26)),
      ),
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
                children: [
                  const Spacer(),
                  Text(
                    sectionTitle,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      if (AppSheetTransitions.maybeClose<void>(context)) {
                        return;
                      }
                      Navigator.of(context).maybePop();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        color: colors.textSecondary,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: floating ? 22 : 18),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    bodyText,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 19,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
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
