import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/models/download_task_record.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/download_list_screen.dart';
import 'package:fly_player/services/download_task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File videoFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('fly-player-download-test-');
    videoFile = File('${tempDir.path}/episode-1.mp4')
      ..writeAsStringSync('video');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DownloadTaskService.instance.debugReplaceRecordsForTesting(
      <DownloadTaskRecord>[_downloadedRecord(videoFile.path)],
    );
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('下载列表选择模式下系统返回先退出选择状态', (tester) async {
    final observer = _PopCountingObserver();

    await tester.pumpWidget(
      _testApp(observer: observer, routePage: const DownloadListScreen()),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DownloadListScreen), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('取消'), findsOneWidget);

    final popped = await tester
        .state<NavigatorState>(find.byType(Navigator))
        .maybePop();
    await tester.pump(const Duration(milliseconds: 300));

    expect(popped, isTrue);
    expect(observer.popCount, 0);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.byType(DownloadListScreen), findsOneWidget);
  });

  testWidgets('下载详情选择模式下系统返回先退出选择状态', (tester) async {
    final observer = _PopCountingObserver();
    expect(
      DownloadTaskService.instance.groupById(
        '白箱 第 1 季',
        status: DownloadTaskStatus.downloaded,
      ),
      isNotNull,
    );

    await tester.pumpWidget(
      _testApp(
        observer: observer,
        routePage: const DownloadGroupDetailScreen(groupId: '白箱 第 1 季'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DownloadGroupDetailScreen), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('取消'), findsOneWidget);

    final popped = await tester
        .state<NavigatorState>(find.byType(Navigator))
        .maybePop();
    await tester.pump(const Duration(milliseconds: 300));

    expect(popped, isTrue);
    expect(observer.popCount, 0);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.byType(DownloadGroupDetailScreen), findsOneWidget);
  });

  testWidgets('下载列表使用最新任务记录刷新进度', (tester) async {
    final record = _downloadingRecord();
    DownloadTaskService.instance.debugReplaceRecordsForTesting(
      <DownloadTaskRecord>[record],
    );

    await tester.pumpWidget(
      _testApp(
        observer: _PopCountingObserver(),
        routePage: const DownloadListScreen(
          initialTab: DownloadListTab.downloading,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('128 B / 1.00 KB'), findsOneWidget);

    DownloadTaskService.instance.debugReplaceRecordsForTesting(
      <DownloadTaskRecord>[
        record.copyWith(downloadedBytes: 512, updatedAtMs: 3),
      ],
    );
    await tester.pump();

    expect(find.text('512 B / 1.00 KB'), findsOneWidget);
  });

  testWidgets('下载详情使用最新任务记录刷新进度', (tester) async {
    final record = _downloadingRecord();
    DownloadTaskService.instance.debugReplaceRecordsForTesting(
      <DownloadTaskRecord>[record],
    );

    await tester.pumpWidget(
      _testApp(
        observer: _PopCountingObserver(),
        routePage: const DownloadGroupDetailScreen(
          groupId: '白箱 第 1 季',
          initialTab: DownloadListTab.downloading,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('128 B / 1.00 KB'), findsOneWidget);

    DownloadTaskService.instance.debugReplaceRecordsForTesting(
      <DownloadTaskRecord>[
        record.copyWith(downloadedBytes: 512, updatedAtMs: 3),
      ],
    );
    await tester.pump();

    expect(find.text('512 B / 1.00 KB'), findsOneWidget);
  });
}

Widget _testApp({
  required NavigatorObserver observer,
  required Widget routePage,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => NasProvider()),
      ChangeNotifierProxyProvider<NasProvider, MediaBackendProvider>(
        create: (context) => MediaBackendProvider(context.read<NasProvider>()),
        update: (_, __, provider) => provider!,
      ),
    ],
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [observer],
      initialRoute: '/download',
      routes: <String, WidgetBuilder>{
        '/': (_) => const Scaffold(body: SizedBox.shrink()),
        '/download': (_) => routePage,
      },
    ),
  );
}

DownloadTaskRecord _downloadedRecord(String filePath) {
  return DownloadTaskRecord(
    id: 'record-1',
    remoteTaskId: 'remote-1',
    itemGuid: 'item-1',
    mediaGuid: 'media-1',
    groupId: 'group-1',
    groupTitle: '白箱 第 1 季',
    title: '第 1 集',
    durationText: '24m',
    posterUrls: const <String>[],
    groupPosterUrls: const <String>[],
    resolution: '1080P',
    fileName: 'episode-1.mp4',
    filePath: filePath,
    totalBytes: 1024,
    downloadedBytes: 1024,
    status: DownloadTaskStatus.downloaded,
    errorMessage: '',
    createdAtMs: 1,
    updatedAtMs: 2,
    seasonNumber: 1,
    episodeNumber: 1,
  );
}

DownloadTaskRecord _downloadingRecord() {
  return const DownloadTaskRecord(
    id: 'record-1',
    remoteTaskId: 'remote-1',
    itemGuid: 'item-1',
    mediaGuid: 'media-1',
    groupId: 'group-1',
    groupTitle: '白箱 第 1 季',
    title: '第 1 集',
    durationText: '24m',
    posterUrls: <String>[],
    groupPosterUrls: <String>[],
    resolution: '1080P',
    fileName: 'episode-1.mp4',
    filePath: '',
    totalBytes: 1024,
    downloadedBytes: 128,
    status: DownloadTaskStatus.downloading,
    errorMessage: '',
    createdAtMs: 1,
    updatedAtMs: 2,
    seasonNumber: 1,
    episodeNumber: 1,
  );
}

class _PopCountingObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount += 1;
    super.didPop(route, previousRoute);
  }
}
