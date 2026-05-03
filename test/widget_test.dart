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
  });
}
