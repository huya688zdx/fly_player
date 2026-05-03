import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/player/widgets/player_listen_video_presentation.dart';

void main() {
  Widget buildSubject({
    required Size size,
    required String title,
    required String subtitle,
  }) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: Scaffold(
          body: PlayerListenVideoPresentation(
            artworkUrls: const <String>[],
            token: '',
            title: title,
            subtitle: subtitle,
            compactUi: size.width < 900,
          ),
        ),
      ),
    );
  }

  testWidgets('renders poster card title and subtitle in portrait', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        size: const Size(390, 844),
        title: '春日之邻',
        subtitle: '摇曳露营 · 第2季 · 第1集',
      ),
    );

    expect(
      find.byKey(const Key('playerListenVideoArtworkCard')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('playerListenVideoTitle')), findsOneWidget);
    expect(find.text('春日之邻'), findsOneWidget);
    expect(find.text('摇曳露营 · 第2季 · 第1集'), findsOneWidget);
  });

  testWidgets('keeps layout stable without subtitle in landscape', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(size: const Size(844, 390), title: '当前视频', subtitle: ''),
    );
    await tester.pump();

    expect(find.byType(PlayerListenVideoPresentation), findsOneWidget);
    expect(
      find.byKey(const Key('playerListenVideoArtworkCard')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('playerListenVideoSubtitle')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to stacked layout for narrow split windows', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        size: const Size(560, 420),
        title: '葬送的芙莉莲 第2集',
        subtitle: '葬送的芙莉莲 · 第2集 · Episode',
      ),
    );
    await tester.pump();

    expect(find.byType(PlayerListenVideoPresentation), findsOneWidget);
    expect(
      find.byKey(const Key('playerListenVideoArtworkCard')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('playerListenVideoTitle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
