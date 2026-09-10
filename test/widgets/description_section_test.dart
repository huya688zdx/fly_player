import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/widgets/detail/description_section.dart';

void main() {
  testWidgets('简介缓存随宽度和文字更新，更多按钮使用最新回调', (tester) async {
    final longText = '这是一段用于验证简介截断和更多入口的文字。' * 20;
    var taps = 0;
    Future<void> show(String text, double width, VoidCallback onTap) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: DescriptionSection(
                  text: text,
                  maxLines: 2,
                  onMoreTap: onTap,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String clipped() {
      final rich = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(DescriptionSection),
              matching: find.byType(RichText),
            )
            .first,
      );
      return ((rich.text as TextSpan).children!.first as TextSpan).text!;
    }

    await show(longText, 180, () => taps++);
    final narrow = clipped();
    await show(longText, 180, () => taps += 10);
    expect(clipped(), narrow);
    final context = tester.element(find.byType(DescriptionSection));
    final more = AppLocalizations.of(context).bookmarkNoteExpand;
    await tester.tap(find.text(more));
    expect(taps, 10);

    await show(longText, 320, () {});
    expect(clipped().length, greaterThan(narrow.length));
    await show('简短介绍', 320, () {});
    expect(find.text('简短介绍'), findsOneWidget);
    expect(find.text(more), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
