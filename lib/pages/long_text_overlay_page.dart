import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/nas_provider.dart';
import '../theme/detail_tokens.dart';
import '../ui/app_transitions.dart';
import '../utils/media_locale_store.dart';

class LongTextOverlayPage extends StatelessWidget {
  final String title;
  final String sectionTitle;
  final String content;
  final Map<String, dynamic> localeMap;
  final bool floating;

  const LongTextOverlayPage({
    super.key,
    required this.title,
    required this.sectionTitle,
    required this.content,
    this.localeMap = const <String, dynamic>{},
    this.floating = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String sectionTitle,
    required String content,
  }) async {
    final provider = context.read<NasProvider>();
    final localeMap = await MediaLocaleStore.load(provider);
    if (!context.mounted) return;

    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final page = LongTextOverlayPage(
      title: title,
      sectionTitle: sectionTitle,
      content: content,
      localeMap: localeMap,
      floating: isLandscape,
    );

    if (isLandscape) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: const Color(0xBF020812),
        builder: (_) => page,
      );
    }

    return AppTransitions.showDrawerSheet<void>(context, builder: (_) => page);
  }

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final panelHeight = (media.size.height * 0.72).clamp(420.0, 760.0);
    final panelDialogHeight = (media.size.height * 0.68).clamp(360.0, 700.0);
    final panelDialogWidth = (media.size.width * 0.62).clamp(560.0, 920.0);
    final bodyText = content.trim().isEmpty
        ? _t('layout.details.overview.empty', '暂无简介')
        : content;

    final child = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2834),
        borderRadius: BorderRadius.circular(floating ? 28 : 26),
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
                    style: const TextStyle(
                      color: DetailTokens.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(14),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        color: Color(0xFFB2C0D2),
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
                    style: const TextStyle(
                      color: Color(0xFFC4D0DE),
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
