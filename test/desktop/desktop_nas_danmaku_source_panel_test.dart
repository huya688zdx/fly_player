import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';

void main() {
  testWidgets('飞翔后端可在播放器内搜索作品、展开分集并应用', (tester) async {
    final pending = Completer<bool>();
    var requests = 0;
    var applied = false;
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
              onSearchFly: (_) async => [
                {'source': 'fly', 'kind': 'series', 'title': '后端作品'},
              ],
              onExpandSearchResult: (candidate) async {
                expect(candidate['kind'], 'series');
                return [{'source': 'fly', 'kind': 'episode', 'title': '后端第 1 集'}];
              },
              onSelectSavedSource: (_) async => false,
              onSelectSearchResult: (candidate) async => candidate['kind'] == 'episode',
              onApplied: () => applied = true,
              onDeleteSavedSource: (_) async {},
              onImportFile: () async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('飞翔后端弹幕'), findsOneWidget);
    await tester.tap(find.text('重新获取'));
    await tester.pump();
    expect(requests, 1);
    expect(find.text('正在获取'), findsOneWidget);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('暂无可自动使用的弹幕，可点“查找来源”选择'), findsOneWidget);
    expect(find.text('本地导入'), findsOneWidget);
    expect(find.text('20 条'), findsOneWidget);
    await tester.tap(find.text('查找来源'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('后端作品'), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('后端作品'));
    await tester.pumpAndSettle();
    expect(applied, isFalse);
    expect(find.text('返回作品列表'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('后端第 1 集'), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('后端第 1 集'));
    await tester.pumpAndSettle();
    expect(applied, isTrue);
  });
}
