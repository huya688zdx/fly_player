import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_danmaku_overlay.dart';
import 'package:fly_player/desktop/playback/desktop_mpv_runtime.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/playback/settings/mpv_settings_store.dart';

void main() {
  test('Windows 弹幕层能读取原生预取的 compact payload', () async {
    final directory = await Directory.systemTemp.createTemp(
      'desktop-danmaku-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/payload.json');
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'sourceKey': 'dandan:42',
        'commentsCompact': <List<Object?>>[
          <Object?>['a', 1250, '滚动', 0, 0xFFFFFFFF],
          <Object?>['b', 2100, '顶部', 1, 0xFFFF0000],
        ],
      }),
    );

    final payload = await DesktopDanmakuPayload.load(file.path);

    expect(payload.sourceLabel, 'dandan:42');
    expect(payload.comments.map((item) => item.text), <String>['滚动', '顶部']);
    expect(payload.comments.last.timeMs, 2100);
  });

  test('Windows 音频滤镜沿用 MPV 设置中的 EQ 与限幅参数', () {
    final settings = <String, String>{
      ...MpvSettingsCatalog.defaults,
      MpvSettingsCatalog.audioEqKey: 'clarity',
      MpvSettingsCatalog.audioLimiterKey: 'light',
    };

    final filters = DesktopMpvRuntime.audioFilters(settings);

    expect(filters, contains('equalizer=f=2800'));
    expect(filters, contains('alimiter=limit=0.95'));
  });

  testWidgets('Windows 弹幕显示设置与弹幕源分开呈现', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopDanmakuSettingsPanel(
          settings: DanmakuSettings.defaults,
          onChanged: (_) async {},
        ),
      ),
    );

    expect(find.text('滚动弹幕'), findsOneWidget);
    expect(find.text('导入本地弹幕'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopDanmakuSourcePanel(
          currentSourceLabel: 'dandan:42',
          commentCount: 120,
          loading: false,
          initialKeyword: '测试作品',
          onLoadSavedSources: () async => const <Map<String, dynamic>>[],
          onSearch: (_) async => const <Map<String, dynamic>>[],
          onSelectSavedSource: (_) async => false,
          onSelectSearchResult: (_) async => false,
          onDeleteSavedSource: (_) async {},
          onImportFile: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('弹幕源'), findsOneWidget);
    expect(find.text('导入本地弹幕'), findsOneWidget);
    expect(find.text('在线搜索'), findsOneWidget);
  });
}
