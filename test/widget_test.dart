import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/main.dart';
import 'package:fly_player/screens/connection_screen.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});

    await tester.pumpWidget(const FlyPlayerApp());
    await tester.pumpAndSettle();

    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);
    await tester.tap(find.byKey(const Key('feiniuAdvancedOptionsButton')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'lib/img/app_logo.png',
      ),
      findsOneWidget,
    );
    for (final assetName in <String>[
      'lib/img/feiniu_Logo.png',
      'lib/img/Emby_logo.png',
      'lib/img/jellyfin_logo.png',
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == assetName,
        ),
        findsOneWidget,
      );
    }
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });
}
