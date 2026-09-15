import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_playback_host.dart';
import 'package:fly_player/desktop/playback/desktop_playback_launch_guard.dart';
import 'package:fly_player/playback/platform_playback_host.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('不同页面和入口共享首个起播请求及当前标题', (tester) async {
    final contexts = await _mountContexts(tester);
    final ready = Completer<void>();
    final executed = <String>[];
    final first = runPlaybackLaunch<String>(
      contexts.$1,
      title: '剧集 A',
      actionKey: 'item:A',
      action: (host) async {
        executed.add('A');
        await ready.future;
        return 'A';
      },
    );
    addTearDown(() {
      if (!ready.isCompleted) ready.complete();
    });
    Future<String?> second() => runPlaybackLaunch<String>(
      contexts.$2,
      title: '剧集 B',
      actionKey: 'season:B',
      action: (host) async {
        executed.add('B');
        return 'B';
      },
    );

    expect(contexts.$1, isNot(same(contexts.$2)));
    expect(await second(), isNull);
    await tester.pump();
    expect(executed, ['A']);
    expect(find.text('正在准备：剧集 A'), findsOneWidget);
    expect(find.text('取消加载'), findsOneWidget);
    expect(find.text('正在准备：剧集 B'), findsNothing);

    ready.complete();
    await tester.pump();
    expect(await first, 'A');
    expect(await second(), 'B');
    await tester.pump();
    expect(executed, ['A', 'B']);
    expect(find.text('取消加载'), findsNothing);
  });

  testWidgets('点击取消后迟到片源不能起播且清理期间保持占用', (tester) async {
    final contexts = await _mountContexts(tester);
    final resolved = Completer<MpvMediaSource>();
    final cleanup = Completer<void>();
    var cleanupStarted = false;
    var createdSessions = 0;
    bool? lateLaunchResult;
    late DesktopPlaybackHost host;
    final first = DesktopPlaybackLaunchGuard.run<String>(
      contexts.$1,
      title: '剧集 A',
      sourceInUse: DesktopPlaybackHost.sourceInUse,
      action: (request) async {
        request.onCancel = () async {
          cleanupStarted = true;
          await cleanup.future;
        };
        host = DesktopPlaybackHost(
          contexts.$1,
          launchRequest: request,
          createSession: (_, {danmakuFilePath}) {
            createdSessions++;
            throw StateError('取消后的片源不应创建播放会话');
          },
        );
        final source = await resolved.future;
        rememberPlaybackLaunchSource(host, source);
        lateLaunchResult = await host.launch(source: source, offline: true);
        return 'A';
      },
    );
    const source = MpvMediaSource(
      itemGuid: 'A',
      mediaGuid: 'media-A',
      videoGuid: 'video-A',
      url: 'file:///synthetic-A.mkv',
      headers: {},
      title: '剧集 A',
    );
    addTearDown(() {
      if (!resolved.isCompleted) resolved.complete(source);
      if (!cleanup.isCompleted) cleanup.complete();
    });
    var nextExecutions = 0;
    Future<String?> next() => runPlaybackLaunch<String>(
      contexts.$2,
      title: '剧集 B',
      actionKey: 'download:B',
      action: (_) async {
        nextExecutions++;
        return 'B';
      },
    );

    await tester.pump();
    expect(playbackLaunchIsCurrent(host), isTrue);
    await tester.tap(find.text('取消加载'));
    await tester.pump();
    expect(playbackLaunchIsCurrent(host), isFalse);
    expect(cleanupStarted, isTrue);
    expect(find.text('正在取消，等待清理…'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    expect(await next(), isNull);

    resolved.complete(source);
    await tester.idle();
    expect(lateLaunchResult, isFalse);
    expect(createdSessions, 0);
    expect(await next(), isNull);
    expect(nextExecutions, 0);

    cleanup.complete();
    await tester.pump();
    expect(await first, isNull);
    expect(await next(), 'B');
    await tester.pump();
    expect(nextExecutions, 1);
    expect(find.text('取消加载'), findsNothing);
  });
}

Future<(BuildContext, BuildContext)> _mountContexts(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final nas = NasProvider();
  final backend = MediaBackendProvider(nas);
  late BuildContext first;
  late BuildContext second;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NasProvider>.value(value: nas),
        ChangeNotifierProvider.value(value: backend),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Builder(
                builder: (context) {
                  first = context;
                  return const SizedBox();
                },
              ),
              Builder(
                builder: (context) {
                  second = context;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.idle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
    nas.dispose();
  });
  return (first, second);
}
