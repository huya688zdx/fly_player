import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_playback_service_client.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';

Widget _panel({
  bool signedIn = false,
  Object identity = 'episode-a',
  String serviceStatus = '',
  Future<bool> Function({void Function(String)? onStatus})? refresh,
}) => DesktopDanmakuSourcePanel(
  currentSourceLabel: '已导入的本地文件',
  commentCount: 23,
  loading: false,
  initialKeyword: '当前作品',
  flyAccountSignedIn: signedIn,
  serviceSourceIdentity: identity,
  serviceStatus: serviceStatus,
  onRefreshServiceSource: refresh,
  onLoadSavedSources: () async => [],
  onSearch: (_) async => [],
  onSelectSavedSource: (_) async => false,
  onSelectSearchResult: (_) async => false,
  onDeleteSavedSource: (_) async {},
  onImportFile: () async => false,
  embedded: true,
);

Future<void> _pump(WidgetTester tester, Widget panel) async {
  await tester.binding.setSurfaceSize(const Size(600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: panel)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('自动弹幕进度与待核对状态无需点击即可更新', (tester) async {
    var status = '正在后台查找这集弹幕，完成后自动加载';
    var requests = 0;
    late StateSetter update;
    await _pump(tester, StatefulBuilder(builder: (context, setState) {
      update = setState;
      return _panel(signedIn: true, serviceStatus: status,
          refresh: ({onStatus}) async { requests++; return true; });
    }));
    expect(find.text(status), findsOneWidget);
    update(() => status = '已提交获取任务，飞翔后台正在更新这集弹幕。');
    await tester.pumpAndSettle();
    expect(find.text(status), findsOneWidget);
    update(() => status = '飞翔后台未能自动确认这集的弹幕来源，需要核对匹配结果。');
    await tester.pumpAndSettle();
    expect(find.text(status), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('保留飞翔会话的普通登录隐藏服务入口，活动绑定才显示', (tester) async {
    final service = FlyDataService.instance;
    final stats = PlayStatsService.instance;
    final database = stats.database as SqflitePlayStatsDatabase;
    service.session = FlyDataSession(
      serverUrl: 'https://fixture.invalid',
      userId: 'alice',
      username: 'alice',
      deviceId: 'fixture-device',
      deviceName: 'fixture',
      token: 'fixture-token',
      installationId: 'fixture-installation',
    );
    addTearDown(() async {
      service.session = null;
      await database.bindOwnerScope('');
    });
    await database.bindOwnerScope('legacy-emby');
    var playbackScope = 'legacy-emby';
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return _panel(
            signedIn: FlyPlaybackServiceClient.instance.hasActiveAccountBinding(
              statsScope: playbackScope,
            ),
            identity: (playbackScope, service.session),
            refresh: ({onStatus}) async => false,
          );
        },
      ),
    );
    expect(service.session, isNotNull);
    expect(find.text('飞翔后端弹幕'), findsNothing);
    expect(find.text('重新获取'), findsNothing);
    expect(find.text('导入本地弹幕'), findsOneWidget);
    expect(find.text('在线搜索'), findsOneWidget);

    playbackScope = PlayStatsService.scopeForBinding(
      service.session!.accountKey,
      'fixture-binding',
    );
    await database.bindOwnerScope(playbackScope);
    database.bindingReference = {'binding_id': 'fixture-binding'};
    update(() {});
    await tester.pumpAndSettle();
    expect(find.text('飞翔后端弹幕'), findsOneWidget);
    expect(find.text('重新获取'), findsOneWidget);

    await database.bindOwnerScope('legacy-feiniu');
    playbackScope = 'legacy-feiniu';
    update(() {});
    await tester.pumpAndSettle();
    expect(service.session, isNotNull);
    expect(find.text('飞翔后端弹幕'), findsNothing);
    expect(find.text('已导入的本地文件'), findsOneWidget);
  });

  testWidgets('服务未命中保留当前来源并允许重新获取', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      _panel(
        signedIn: true,
        refresh: ({onStatus}) async {
          calls++;
          return false;
        },
      ),
    );
    await tester.tap(find.text('重新获取'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('暂无可自动使用的弹幕，可点“查找来源”选择'), findsOneWidget);
    expect(find.text('已导入的本地文件'), findsOneWidget);
    expect(find.text('23 条'), findsOneWidget);
    await tester.tap(find.text('重新获取'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  for (final change in ['account', 'episode']) {
    testWidgets('$change 切换后旧刷新回调不能覆盖新状态', (tester) async {
      final first = Completer<bool>();
      final second = Completer<bool>();
      var identity = 'initial';
      var signedIn = true;
      var calls = 0;
      late StateSetter update;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _panel(
              signedIn: signedIn,
              identity: identity,
              refresh: ({onStatus}) => ++calls == 1 ? first.future : second.future,
            );
          },
        ),
      );
      await tester.tap(find.text('重新获取'));
      await tester.pump();
      update(() {
        identity = 'replacement';
        if (change == 'account') signedIn = false;
      });
      await tester.pump();
        if (change == 'account') {
          expect(find.text('飞翔后端弹幕'), findsNothing);
          update(() => signedIn = true);
          await tester.pump();
        }
        first.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('已加载飞翔后端弹幕'), findsNothing);
        await tester.tap(find.text('重新获取'));
      await tester.pump();
      expect(calls, 2);
        second.complete(false);
        await tester.pumpAndSettle();
      expect(find.text('暂无可自动使用的弹幕，可点“查找来源”选择'), findsOneWidget);
      expect(find.text('已加载飞翔后端弹幕'), findsNothing);
      expect(find.text('已导入的本地文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
