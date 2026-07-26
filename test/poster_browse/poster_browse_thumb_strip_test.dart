import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_thumb_strip.dart';

void main() {
  final cards = <MediaItemCard>[
    const MediaItemCard(
      id: 'a',
      title: 'A',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
      rating: '8.9',
      resumePositionSeconds: 300,
      durationSeconds: 600,
    ),
    const MediaItemCard(
      id: 'b',
      title: 'B',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    ),
  ];

  testWidgets('评分角标只在有评分时出现，点击回调携带 index', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosterBrowseThumbStrip(
            items: cards,
            focusedIndex: 0,
            imageUrlOf: (_) => '',
            showProgress: true,
            onItemTap: (index) => tapped = index,
          ),
        ),
      ),
    );
    expect(find.text('★ 8.9'), findsOneWidget); // a 有评分
    expect(find.textContaining('★'), findsOneWidget); // b 无评分不占位
    await tester.tap(find.byKey(const ValueKey('poster_browse_thumb_b')));
    expect(tapped, 1);
  });

  testWidgets('继续观看行显示进度条', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosterBrowseThumbStrip(
            items: cards,
            focusedIndex: 0,
            imageUrlOf: (_) => '',
            showProgress: true,
            onItemTap: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget); // 只有 a 有进度
  });
}
