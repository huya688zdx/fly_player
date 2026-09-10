import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/desktop/playback/external_playback_host.dart';
import 'package:fly_player/desktop/playback/potplayer_session.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('外部播放就绪后关闭影片字幕，控制采样与动态弹幕保持同一会话', (tester) async {
    final directory = Directory.systemTemp.createTempSync('fly_external_host_');
    final executable = File('${directory.path}/PotPlayerMini64.exe')
      ..writeAsBytesSync([0]);
    final video = File('${directory.path}/video.mkv')..writeAsBytesSync([0]);
    final comments = File('${directory.path}/comments.json')
      ..writeAsStringSync(
        jsonEncode({
          'commentsCompact': [
            ['1', 1000, '当前影片弹幕', 0, 0xffffffff],
          ],
        }),
      );
    SharedPreferences.setMockInitialValues({
      'desktop_external_player_v1': jsonEncode({
        'enabled': true,
        'executablePath': executable.path,
      }),
      'player_danmaku_settings_v1': DanmakuSettings.defaults
          .copyWith(enabled: false)
          .encode(),
    });
    final nas = NasProvider();
    final backend = MediaBackendProvider(nas);
    final calls = <MethodCall>[];
    final subtitles = <String>[];
    final state = <String, Object>{
      'alive': true,
      'file': video.path,
      'state': 2,
      'positionMs': 5000,
      'durationMs': 100000,
    };
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PotPlayerSession.channel,
      (call) async {
        calls.add(call);
        final arguments = call.arguments as Map;
        if (call.method == 'launch') return 71;
        expect(arguments['pid'], 71);
        if (call.method == 'snapshot') return Map.of(state);
        if (call.method == 'configure') {
          if (arguments.containsKey('mediaUrl')) {
            expect(arguments['mediaUrl'], video.path);
          }
          state['state'] = arguments['paused'] == true ? 1 : 2;
        } else if (call.method == 'activate') {
          expect(arguments['focus'], false);
          state['positionMs'] = arguments['positionMs'] as int;
        } else if (call.method == 'subtitle') {
          expect(arguments['mediaUrl'], video.path);
          expect(calls.any((call) => call.method == 'snapshot'), isTrue);
          subtitles.add(await File(arguments['path'] as String).readAsString());
        }
        return null;
      },
    );
    addTearDown(() async {
      await ExternalPlaybackHost.stop();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PotPlayerSession.channel,
        null,
      );
      backend.dispose();
      nas.dispose();
      directory.deleteSync(recursive: true);
    });
    late BuildContext hostContext;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: nas),
          ChangeNotifierProvider.value(value: backend),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await nas.reloadSettingsForTesting();
      expect(
        await ExternalPlaybackHost(hostContext).launch(
          source: MpvMediaSource(
            itemGuid: 'local-probe',
            mediaGuid: 'local-media',
            videoGuid: 'local-video',
            url: video.path,
            headers: const {},
            title: '本地测试影片',
            externalLocalSource: true,
            subtitleTrackGuid: '',
            danmakuAutoSearchAllowed: false,
          ),
        ),
        isTrue,
      );
      expect(subtitles.single, contains('[Events]'));
      expect(subtitles.single, isNot(contains('Dialogue:')));
      expect(ExternalPlaybackHost.status.value!.position.inSeconds, 5);
      expect(
        await ExternalPlaybackHost.setPaused(true, itemGuid: 'local-probe'),
        isTrue,
      );
      expect(ExternalPlaybackHost.status.value!.paused, isTrue);
      expect(
        await ExternalPlaybackHost.seek(
          const Duration(seconds: 32),
          itemGuid: 'local-probe',
        ),
        isTrue,
      );
      expect(ExternalPlaybackHost.status.value!.position.inSeconds, 32);
      expect(
        await ExternalPlaybackHost.applyDanmaku(
          itemGuid: 'local-probe',
          path: comments.path,
          label: '手动匹配',
          enabled: true,
        ),
        isTrue,
      );
      expect(subtitles, hasLength(2));
      expect(subtitles.last, contains('Dialogue:'));
      expect(subtitles.last, contains('当前影片弹幕'));
      expect(ExternalPlaybackHost.status.value!.danmakuEnabled, isTrue);
      expect(ExternalPlaybackHost.status.value!.danmakuCount, 1);
      expect(ExternalPlaybackHost.status.value!.danmakuLabel, '手动匹配');
      expect(
        await ExternalPlaybackHost.applyDanmaku(
          itemGuid: 'local-probe',
          path: '${directory.path}/missing.json',
          label: '加载失败的源',
          enabled: true,
        ),
        isFalse,
      );
      expect(subtitles, hasLength(2));
      expect(ExternalPlaybackHost.status.value!.danmakuLabel, '手动匹配');
      await ExternalPlaybackHost.stop();
      expect(ExternalPlaybackHost.status.value, isNull);
      expect(calls.last.method, 'close');
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isWindows);
}
