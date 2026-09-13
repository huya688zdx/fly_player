import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';

void main() {
  testWidgets('活动绑定重取 NAS 弹幕，未匹配时保留已有来源', (tester) async {
    final pending = Completer<bool>();
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 650,
            child: DesktopDanmakuSourcePanel(
              currentSourceLabel: '本地导入',
              commentCount: 20,
              loading: false,
              initialKeyword: '测试作品',
              flyAccountSignedIn: true,
              serviceSourceIdentity: 'Emby · 测试作品 第 1 集',
              onRefreshServiceSource: () {
                requests++;
                return pending.future;
              },
              onLoadSavedSources: () async => [],
              onSearch: (_) async => [],
              onSelectSavedSource: (_) async => false,
              onSelectSearchResult: (_) async => false,
              onDeleteSavedSource: (_) async {},
              onImportFile: () async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('服务弹幕'), findsOneWidget);
    await tester.tap(find.text('重新获取'));
    await tester.pump();
    expect(requests, 1);
    expect(find.text('正在获取'), findsOneWidget);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('暂无服务弹幕，可在媒体资料中查找'), findsOneWidget);
    expect(find.text('本地导入'), findsOneWidget);
    expect(find.text('20 条'), findsOneWidget);
  });
}
