import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/screens/home/widgets/home_continue_watching_section.dart';
import 'package:fly_player/theme/app_theme.dart';

const continueFixture = HomeContinueCardData(
  id: 'item-1',
  title: '吹响吧！上低音号',
  contextText: '第 1 季 · 第 9 集 · 剩 18 分钟',
  progress: .5,
  imageRequest: MediaImageRequest.empty,
  downloaded: false,
);

Widget testApp(Widget child) => MaterialApp(
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  home: Scaffold(body: SizedBox(width: 390, child: child)),
);

void main() {
  testWidgets('续看卡主体、播放键、长按分别调用独立回调', (tester) async {
    var detail = 0;
    var play = 0;
    var longPress = 0;
    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: const <HomeContinueCardData>[continueFixture],
          onOpenDetail: (_) => detail++,
          onPlay: (_) => play++,
          onLongPress: (_) => longPress++,
        ),
      ),
    );

    expect(find.text('查看全部'), findsNothing);
    expect(find.text('1 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('continue-card-item-1')),
    );
    expect(detail, 1);
    expect(play, 0);

    await tester.tap(
      find.byKey(const ValueKey<String>('continue-play-item-1')),
    );
    expect(play, 1);
    expect(detail, 1);

    await tester.longPress(
      find.byKey(const ValueKey<String>('continue-card-item-1')),
    );
    expect(longPress, 1);
    expect(detail, 1);
  });

  testWidgets('续看使用可访问字重、封面裁切和语义主题色', (tester) async {
    const imageFixture = HomeContinueCardData(
      id: 'image-item',
      title: '标题',
      contextText: '第 2 季 · 第 4 集',
      progress: .25,
      imageRequest: MediaImageRequest(
        urls: <String>['https://example.test/backdrop.jpg'],
        selfAuthenticated: true,
      ),
      downloaded: true,
    );
    await tester.pumpWidget(
      testApp(
        HomeContinueWatchingSection(
          items: const <HomeContinueCardData>[imageFixture],
          onOpenDetail: (_) {},
          onPlay: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('continue-image-image-item')),
    );
    expect(image.fit, BoxFit.cover);
    expect(
      tester.widget<Text>(find.text('标题')).style?.fontWeight,
      FontWeight.w500,
    );
    expect(
      tester.widget<Text>(find.text('第 2 季 · 第 4 集')).style?.fontWeight,
      FontWeight.w400,
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey<String>('continue-progress-image-item')),
    );
    expect(progress.color, AppThemePalette.fallback.accent);

    final playButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('continue-play-image-item')),
    );
    final scheme = AppThemeBuilder.build(AppThemePreset.midnight).colorScheme;
    expect(
      playButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      scheme.primary,
    );
    expect(
      playButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      scheme.onPrimary,
    );
    expect(tester.takeException(), isNull);
  });
}
