import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/playback/settings/mpv_settings_store.dart';
import 'package:fly_player/services/fly_data/fly_oped.dart';

// Synthetic service response using representative millisecond OP/ED boundaries.
// No media service, real file, native player, or player action is invoked.
FlyOpedSet reviewedSet({bool includeEd = true}) {
  const source = FlySourceRef(bindingId: 'fixture', remoteItemId: 'episode');
  return FlyOpedSet.parse(
    {
      'status': 'published',
      'playback_context_id': 'fixture-load',
      'generation': 0,
      'set_revision': 'fixture-set',
      'file_context': {
        'source_ref': source.toJson(),
        'identity_state': 'verified',
        'file_revision_id': 'fixture-file',
        'media_coordinate_id': 'fixture-coordinate',
        'duration_ms': 1421005,
      },
      'segments': [
        {
          'id': 'op',
          'kind': 'op',
          'start_ms': 79876,
          'end_ms': 164876,
          'skip_policy': 'prompt_only',
        },
        if (includeEd)
          {
            'id': 'ed',
            'kind': 'ed',
            'start_ms': 1330000,
            'end_ms': 1420000,
            'skip_policy': 'prompt_only',
          },
      ],
      'protected_ranges': [
        {'start_ms': 1420000, 'end_ms': 1421005},
      ],
    },
    source: source,
    contextId: 'fixture-load',
    generation: 0,
  )!;
}

Widget settingsPanel({
  bool signedIn = false,
  bool enabled = true,
  FlyOpedSet? published,
  bool chaptersEnabled = true,
  bool fixedEnabled = false,
  DesktopPlaybackSettingsPage page = DesktopPlaybackSettingsPage.introOutro,
  Future<void> Function(bool)? onFlyChanged,
  ValueChanged<bool>? onChapterChanged,
}) => DesktopPlaybackSettingsPanel(
  source: const MpvMediaSource(
    itemGuid: 'fixture',
    mediaGuid: 'fixture',
    videoGuid: 'fixture',
    url: 'https://example.invalid/fixture',
    headers: {},
    title: 'Fixture episode',
  ),
  position: Duration.zero,
  duration: const Duration(milliseconds: 1421005),
  autoPlayEnabled: true,
  nextEpisodePreloadEnabled: false,
  aspectRatioMode: 'fit',
  decoderMode: 'hardware',
  mpvSettings: MpvSettingsCatalog.defaults,
  videoAdjustments: MpvSettingsCatalog.videoAdjustmentDefaults,
  audioDelaySeconds: 0,
  bookmarks: const [],
  danmakuEnabled: false,
  danmakuSourceLabel: '',
  danmakuCommentCount: 0,
  chapters: const [
    DesktopPlayerChapter(title: 'OP', position: Duration(seconds: 30)),
    DesktopPlayerChapter(title: '正片', position: Duration(seconds: 90)),
    DesktopPlayerChapter(title: 'ED', position: Duration(minutes: 22)),
  ],
  introOutroEnabled: chaptersEnabled,
  introMaxMinutes: 2,
  outroMaxMinutes: 2,
  fixedDurationSkipEnabled: fixedEnabled,
  flyAccountSignedIn: signedIn,
  flyOpedEnabled: enabled,
  flyOpedSet: published,
  onFlyOpedChanged: onFlyChanged,
  hasNextEpisode: true,
  subtitleDelaySeconds: 0,
  subtitlePosition: 92,
  subtitleScale: 1,
  onIntroOutroChanged:
      ({
        required enabled,
        required introMaxMinutes,
        required outroMaxMinutes,
        required fixedDurationEnabled,
      }) async {
        onChapterChanged?.call(enabled);
      },
  onSubtitleStyleChanged:
      ({required delaySeconds, required position, required scale}) async {},
  onSelectChapter: (_) async {},
  onAutoPlayChanged: (_) async {},
  onNextEpisodePreloadChanged: (_) async {},
  onAspectRatioChanged: (_) async {},
  onDecoderChanged: (_) async {},
  onMpvAdvancedChanged: (_, _) async {},
  onVideoAdjustmentChanged: (_, _) async {},
  onAudioDelayChanged: (_) async {},
  onLoadSavedPresets: (_) async => [],
  onApplySavedPreset: (_) async {},
  onAddBookmark: () async => [],
  onDeleteBookmark: (_) async => [],
  onSelectBookmark: (_) async {},
  danmakuSettingsPageBuilder: (_) => const SizedBox.shrink(),
  danmakuSourcesPageBuilder: (_) => const SizedBox.shrink(),
  initialPage: page,
);

Future<void> pumpSettings(WidgetTester tester, Widget panel) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SizedBox(width: 480, child: panel)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('非飞翔登录隐藏服务项和范围，保留章节与固定时长', (tester) async {
    await pumpSettings(
      tester,
      settingsPanel(published: reviewedSet(), fixedEnabled: true),
    );
    expect(find.text('飞翔已核验区间'), findsNothing);
    expect(find.textContaining('01:19.876'), findsNothing);
    expect(find.text('按章节识别'), findsOneWidget);
    expect(find.text('固定时长跳过'), findsOneWidget);
    expect(find.text('固定片头时长'), findsOneWidget);
    expect(find.textContaining('章节识别 · 00:30–01:30'), findsOneWidget);
  });

  testWidgets('服务范围优先显示毫秒与仅提示，片尾跳到真实结束点并保留尾段', (tester) async {
    await pumpSettings(
      tester,
      settingsPanel(
        signedIn: true,
        published: reviewedSet(),
        onFlyChanged: (_) async {},
      ),
    );
    expect(find.text('飞翔已核验区间'), findsOneWidget);
    expect(find.text('飞翔已核验 · 01:19.876–02:44.876 · 仅提示'), findsOneWidget);
    expect(find.text('飞翔已核验 · 22:10–23:40 · 仅提示'), findsOneWidget);
    expect(find.text('点击跳过后跳到 23:40，保留结束点之后的内容。'), findsOneWidget);
    expect(find.textContaining('播放下一集'), findsNothing);
    expect(find.textContaining('章节识别 ·'), findsNothing);
  });

  testWidgets('服务仅发布OP时不会误报仍可执行章节ED', (tester) async {
    await pumpSettings(
      tester,
      settingsPanel(
        signedIn: true,
        published: reviewedSet(includeEd: false),
        onFlyChanged: (_) async {},
      ),
    );
    expect(find.text('飞翔已核验 · 01:19.876–02:44.876 · 仅提示'), findsOneWidget);
    expect(find.text('当前不提示跳过'), findsOneWidget);
    expect(find.text('飞翔未发布此类型区间。关闭“飞翔已核验区间”后可使用章节或固定时长设置。'), findsOneWidget);
    expect(find.textContaining('章节识别 ·'), findsNothing);
    expect(find.textContaining('播放下一集'), findsNothing);
  });

  testWidgets('服务开关与章节独立，关闭服务恢复章节范围', (tester) async {
    var serviceEnabled = true, chapterEnabled = true;
    final serviceChanges = <bool>[], chapterChanges = <bool>[];
    await pumpSettings(
      tester,
      StatefulBuilder(
        builder: (context, setState) => settingsPanel(
          signedIn: true,
          enabled: serviceEnabled,
          published: reviewedSet(),
          chaptersEnabled: chapterEnabled,
          onFlyChanged: (value) async {
            serviceChanges.add(value);
            setState(() => serviceEnabled = value);
          },
          onChapterChanged: (value) {
            chapterChanges.add(value);
            setState(() => chapterEnabled = value);
          },
        ),
      ),
    );
    await tester.tap(find.text('飞翔已核验区间'));
    await tester.pumpAndSettle();
    expect(serviceChanges, [false]);
    expect(chapterChanges, isEmpty);
    expect(find.textContaining('01:19.876'), findsNothing);
    expect(find.textContaining('章节识别 · 00:30–01:30'), findsOneWidget);
    await tester.tap(find.text('按章节识别'));
    await tester.pumpAndSettle();
    expect(chapterChanges, [false]);
    expect(serviceChanges, [false]);
    await tester.tap(find.text('飞翔已核验区间'));
    await tester.pumpAndSettle();
    expect(serviceChanges, [false, true]);
    expect(find.text('飞翔已核验 · 22:10–23:40 · 仅提示'), findsOneWidget);
  });

  testWidgets('无服务范围仍显示原章节，退出飞翔登录立即隐藏服务项', (tester) async {
    var signedIn = true;
    late StateSetter update;
    await pumpSettings(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return settingsPanel(signedIn: signedIn);
        },
      ),
    );
    expect(find.text('飞翔已核验区间'), findsOneWidget);
    expect(find.textContaining('章节识别 · 00:30–01:30'), findsOneWidget);
    final serviceSwitch = tester.widgetList<Switch>(find.byType(Switch)).first;
    expect(serviceSwitch.onChanged, isNull);
    update(() => signedIn = false);
    await tester.pumpAndSettle();
    expect(find.text('飞翔已核验区间'), findsNothing);
    expect(find.text('按章节识别'), findsOneWidget);
  });

  for (final signedIn in [false, true]) {
    testWidgets('设置首页按登录状态介绍可用来源：$signedIn', (tester) async {
      await pumpSettings(
        tester,
        settingsPanel(
          signedIn: signedIn,
          page: DesktopPlaybackSettingsPage.main,
        ),
      );
      expect(
        find.text('飞翔已核验区间、章节与固定时长'),
        signedIn ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('按时长窗口提示跳过片头片尾'),
        signedIn ? findsNothing : findsOneWidget,
      );
    });
  }
}
