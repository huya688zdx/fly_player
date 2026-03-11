import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FlyPlayerApp());

    // Verify that we are on the initial screen.
    // Since NasProvider is empty by default, it should show the configuration prompt.
    expect(find.text('Please configure your NAS connection first.'), findsOneWidget);
  });
}
