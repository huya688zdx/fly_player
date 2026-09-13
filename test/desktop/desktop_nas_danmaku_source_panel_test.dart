import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';
import 'package:fly_player/services/fly_data/fly_nas_danmaku_cache.dart';

void main() {
  testWidgets('NAS 重取显示当前连接和单集，未匹配时保留已有来源', (tester) async {
    final pending = Completer<FlyNasDanmakuStatus>();
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
              nasScopeLabel: 'Emby · 测试作品 第 1 集',
              nasStatus: FlyNasDanmakuStatus.notRequested,
              onReloadNas: () {
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
    expect(find.text('NAS 已保存弹幕'), findsOneWidget);
    expect(find.textContaining('Emby · 测试作品 第 1 集'), findsOneWidget);
    await tester.tap(find.text('重新获取 NAS 弹幕'));
    await tester.pump();
    expect(requests, 1);
    expect(find.text('正在获取 NAS 弹幕…'), findsOneWidget);
    pending.complete(FlyNasDanmakuStatus.miss);
    await tester.pumpAndSettle();
    expect(find.textContaining('当前连接的这一集'), findsOneWidget);
    expect(find.text('本地导入'), findsOneWidget);
    expect(find.text('20 条'), findsOneWidget);
  });
}
