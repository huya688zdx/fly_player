import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/native_player_bridge.dart';
import 'package:fly_player/services/manual_subtitle_store.dart';
import 'package:fly_player/utils/manual_subtitle_tracks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fly_player/native_player');
  const codec = StandardMethodCodec();

  test('原生导入和删除事件转发到详情刷新回调', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    var imported = <String, dynamic>{};
    var removed = <String, dynamic>{};
    final token = NativePlayerBridge.bindReentry(
      onResolvePlayback:
          (
            _, {
            qualityIndex,
            qualityMediaGuid,
            startPositionMs,
            subtitleGuid,
            audioGuid,
            audioTrackIndex,
            subtitleTrackIndex,
            preferredQualityResolution,
          }) async => null,
      onRecordProgress: (_) async {},
      onLocalSubtitleImported: (args) async => imported = args,
      onLocalSubtitleRemoved: (args) async => removed = args,
    );
    addTearDown(() => NativePlayerBridge.unbindReentry(token));

    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('localSubtitleImported', <String, Object?>{
          'guid': 'local:sub:srt',
          'itemGuid': 'episode-1',
        }),
      ),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('localSubtitleRemoved', <String, Object?>{
          'guid': 'local:sub:srt',
        }),
      ),
      (_) {},
    );

    expect(imported, <String, dynamic>{
      'guid': 'local:sub:srt',
      'itemGuid': 'episode-1',
    });
    expect(removed, <String, dynamic>{'guid': 'local:sub:srt'});
  });

  test('原生导入事件触发详情式刷新后可看到 SRT 与 SUP', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ManualSubtitleStore.prefKey: jsonEncode(<String, Object?>{
        'version': 2,
        'entries': <Object?>[
          <String, Object?>{
            'guid': 'local:sub:srt',
            'mediaGuid': 'media-1',
            'itemGuid': 'episode-1',
            'fileName': 'episode.srt',
            'path': '/data/subtitles/episode.srt',
            'format': 'srt',
            'importedAtMs': 1,
          },
          <String, Object?>{
            'guid': 'local:sub:sup',
            'mediaGuid': 'media-1',
            'itemGuid': 'episode-1',
            'fileName': 'episode.sup',
            'path': '/data/subtitles/episode.sup',
            'format': 'sup',
            'importedAtMs': 2,
          },
        ],
        'selectedByScope': <String, String>{'item:episode-1': 'local:sub:sup'},
      }),
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    var visibleGuids = <String>[];
    final token = NativePlayerBridge.bindReentry(
      onResolvePlayback:
          (
            _, {
            qualityIndex,
            qualityMediaGuid,
            startPositionMs,
            subtitleGuid,
            audioGuid,
            audioTrackIndex,
            subtitleTrackIndex,
            preferredQualityResolution,
          }) async => null,
      onRecordProgress: (_) async {},
      onLocalSubtitleImported: (_) async {
        final entries = await const ManualSubtitleStore().loadForItem(
          'episode-1',
          mediaGuid: 'media-1',
        );
        visibleGuids = manualSubtitleTracksForMedia(
          'media-1',
          entries,
        ).map((track) => track.guid).toList(growable: false);
      },
    );
    addTearDown(() => NativePlayerBridge.unbindReentry(token));

    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('localSubtitleImported', <String, Object?>{
          'guid': 'local:sub:sup',
          'itemGuid': 'episode-1',
        }),
      ),
      (_) {},
    );

    expect(visibleGuids, <String>['local:sub:sup', 'local:sub:srt']);
  });
}
