import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_backend.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_playback_context.dart';
import 'package:fly_player/media_backend/filter/media_catalog_filter.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/media_backend/playback/media_session_reload.dart';
import 'package:fly_player/models/media_item.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/models/play_info.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_list_option.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/server_reentry_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 覆写播放编排所需的 API 方法，使 [FeiniuMediaBackend.getPlayback] 可在无网络下测试。
class _FakePlaybackApi extends FeiniuApi {
  _FakePlaybackApi(
    super.nas, {
    this.failTrackData = false,
    this.liveChannel = false,
  });

  final bool failTrackData;
  final bool liveChannel;

  bool trackDataCalled = false;
  String? playbackStreamMediaGuid;
  String? resetItemGuid;
  String? resetMediaGuid;
  final List<Map<String, dynamic>> itemListPayloads = <Map<String, dynamic>>[];

  int playInfoTs = 600;
  int itemWatchedTs = 120;
  int itemDuration = 3000;

  @override
  Future<List<MediaItem>> getMediaList() async {
    return <MediaItem>[MediaItem(id: 'iptv-1', name: '电视直播', type: 'IPTV')];
  }

  @override
  Future<ItemListPage> getItemsPage(Map<String, dynamic> payload) async {
    itemListPayloads.add(Map<String, dynamic>.from(payload));
    return ItemListPage(
      total: 1,
      items: <MediaLibraryItem>[
        MediaLibraryItem.fromJson(<String, dynamic>{
          'guid': 'live-1',
          'type': 'LiveChannel',
          'title': 'CCTV1',
        }),
      ],
    );
  }

  @override
  Future<PlayInfoData> getPlayInfo(String itemGuid) async {
    if (liveChannel) {
      return PlayInfoData.fromJson(<String, dynamic>{
        'type': 'LiveChannel',
        'media_guid': 'line-b',
        'item': <String, dynamic>{
          'guid': itemGuid,
          'type': 'LiveChannel',
          'title': 'CCTV1',
          'posters': '/live-poster.jpg',
        },
        'live_channels': <Map<String, dynamic>>[
          <String, dynamic>{
            'guid': 'line-b',
            'path': 'http://source.test/live-b.m3u8?from=source',
            'file_name': '线路2',
            'sort_num': 2,
            'can_play': 1,
          },
          <String, dynamic>{
            'guid': 'line-a',
            'path': 'http://source.test/live-a.m3u8',
            'file_name': '线路1',
            'sort_num': 0,
            'can_play': 1,
          },
          <String, dynamic>{
            'guid': 'line-disabled',
            'path': 'http://source.test/disabled.m3u8',
            'file_name': '线路3',
            'sort_num': 3,
            'can_play': 0,
            'play_error': '源不可用',
          },
        ],
      });
    }
    return PlayInfoData.fromJson(<String, dynamic>{
      'grand_guid': 'series-1',
      'type': 'Episode',
      'ts': playInfoTs,
      'media_guid': 'media-default',
      'video_guid': 'video-default',
      'audio_guid': 'audio-1',
      'subtitle_guid': 'sub-1',
      'parent_guid': 'season-1',
      'item': <String, dynamic>{
        'guid': itemGuid,
        'trim_id': 'tmdb-1',
        'type': 'Episode',
        'title': '第 1 集',
        'tv_title': '剧集名',
        'duration': itemDuration,
        'watched_ts': itemWatchedTs,
        'season_number': 1,
        'episode_number': 1,
        'posters': '/poster.jpg',
      },
    });
  }

  @override
  Future<void> resetPlaybackRecord({
    required String itemGuid,
    required String mediaGuid,
  }) async {
    resetItemGuid = itemGuid;
    resetMediaGuid = mediaGuid;
  }

  @override
  Future<StreamTrackData> getStreamTrackData(String itemGuid) async {
    trackDataCalled = true;
    if (liveChannel) {
      throw StateError('直播没有点播轨道接口');
    }
    if (failTrackData) {
      throw Exception('track data boom');
    }
    return const StreamTrackData(
      options: <StreamListOption>[],
      fileByMediaGuid: <String, StreamFileInfo>{},
      videoByMediaGuid: <String, VideoStreamInfo>{},
      audioByMediaGuid: <String, List<AudioTrackOption>>{},
      subtitleByMediaGuid: <String, List<SubtitleTrackOption>>{},
    );
  }

  @override
  Future<PlaybackStreamData> getPlaybackStream(
    String mediaGuid, {
    int level = 1,
    String userAgent = '',
  }) async {
    playbackStreamMediaGuid = mediaGuid;
    return PlaybackStreamData(
      fileStream: null,
      videoStream: const VideoStreamInfo(
        mediaGuid: 'media-default',
        guid: 'video-default',
        resolutionType: '1080p',
        colorRangeType: 'SDR',
        codecName: 'h264',
        profile: 'High',
        level: '',
        displayAspectRatio: '',
        pixFmt: '',
        rFrameRate: '',
        colorRange: '',
        colorSpace: 'bt709',
        colorTransfer: 'bt709',
        colorPrimaries: 'bt709',
        bps: 8000000,
        bitDepth: 8,
        refs: 0,
        progressive: 0,
        width: 1920,
        height: 1080,
      ),
      audioStreams: <AudioTrackOption>[
        AudioTrackOption(
          mediaGuid: mediaGuid,
          guid: 'audio-1',
          title: '',
          codecName: 'aac',
          profile: '',
          language: 'jpn',
          audioType: '',
          channelLayout: '',
          channels: 2,
          sampleRate: 48000,
          bps: 256000,
          index: 1,
          isDefault: 1,
        ),
      ],
      subtitleStreams: <SubtitleTrackOption>[
        SubtitleTrackOption(
          mediaGuid: mediaGuid,
          guid: 'sub-1',
          title: '',
          codecName: 'ass',
          format: 'ass',
          language: 'chi',
          index: 0,
          isDefault: 1,
          forced: 0,
          isExternal: 0,
          extraFile: 0,
          isBitmap: 0,
        ),
      ],
      qualities: <PlaybackQualityOption>[
        PlaybackQualityOption(
          mediaGuid: mediaGuid,
          videoGuid: 'video-default',
          resolution: '1080p',
          bitrate: 8000000,
          isDefault: 1,
          source: PlaybackQualitySource.originalProxy,
          directLinkQualityIndex: null,
        ),
      ],
      directLinkQualities: const <DirectLinkQualitySource>[],
      cloudStorageInfo: null,
      responseHeaders: const PlaybackResponseHeaders(
        cookies: <String>['sess=abc'],
        userAgents: <String>['FlyPlayer/1.0'],
      ),
      requestUserAgent: 'FlyPlayer/1.0',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  NasProvider buildNas(List<Object> teardown) {
    final nas = NasProvider();
    teardown.add(nas);
    return nas;
  }

  group('FeiniuMediaBackend.getPlayback', () {
    test('直播按指定线路直出原始 URL，并绕过点播流与轨道接口', () async {
      final teardown = <Object>[];
      final nas = buildNas(teardown);
      addTearDown(() {
        for (final n in teardown) {
          (n as NasProvider).dispose();
        }
      });
      final api = _FakePlaybackApi(nas, liveChannel: true);
      final backend = FeiniuMediaBackend(api);

      final preview = await backend.getCatalogPreviewItems(
        'iptv-1',
        page: 2,
        limit: 7,
      );
      final page = await backend.queryCatalogItems(
        const MediaCatalogQuery(
          catalogId: 'iptv-1',
          page: 3,
          pageSize: 9,
          sortField: 'sort_num',
          sortType: 'ASC',
        ),
      );
      expect(preview.single.type, 'LiveChannel');
      expect(page.items.single.type, 'LiveChannel');
      expect(api.itemListPayloads, hasLength(2));
      expect(api.itemListPayloads[0], <String, dynamic>{
        'type': 'LIVE_CHANNEL',
        'ancestor_guid': 'iptv-1',
        'page': 2,
        'num': 7,
      });
      expect(api.itemListPayloads[1], <String, dynamic>{
        'type': 'LIVE_CHANNEL',
        'ancestor_guid': 'iptv-1',
        'page': 3,
        'num': 9,
        'sort_column': 'sort_num',
        'sort_type': 'ASC',
      });

      final versions = await backend.getItemSourceVersions(
        'live-1',
        isLive: true,
      );
      expect(versions.map((version) => version.id), <String>[
        'line-b',
        'line-a',
        'line-disabled',
      ]);
      expect(api.trackDataCalled, isFalse);

      final resolution = await backend.getPlayback(
        const MediaPlaybackRequest(itemId: 'live-1', qualityId: 'line-a'),
      );
      final bundle = resolution.bundle;

      expect(api.trackDataCalled, isFalse);
      expect(api.playbackStreamMediaGuid, isNull);
      expect(bundle.itemType, 'LiveChannel');
      expect(bundle.selectedSource.id, 'line-a');
      expect(bundle.selectedSource.url, 'http://source.test/live-a.m3u8');
      expect(bundle.selectedSource.headers, isEmpty);
      expect(bundle.startPosition, Duration.zero);
      expect(bundle.durationSeconds, 0);
      expect(bundle.selectedSource.reliableSeek, isFalse);
      expect(bundle.qualities.map((quality) => quality.id), <String>[
        'line-b',
        'line-a',
        'line-disabled',
      ]);

      final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));
      final result = await backend.playbackSourceBridge.assemblePlaybackSource(
        request: const MediaPlaybackRequest(
          itemId: 'live-1',
          qualityId: 'line-a',
        ),
        bundle: bundle,
        context: resolution.backendContext,
        l10n: l10n,
      );
      final source = result.source;
      expect(source.mediaType, 'LiveChannel');
      expect(source.url, 'http://source.test/live-a.m3u8');
      expect(source.url, isNot(contains('token=')));
      expect(source.headers, isEmpty);
      expect(source.startPosition, Duration.zero);
      expect(source.durationSeconds, 0);
      expect(source.reliableSeek, isFalse);
      expect(source.qualities, hasLength(3));

      final reloaded = await ServerReentrySupport.reloadServerSession(
        backend,
        currentLoadArgs: jsonEncode(source.toMap()),
        intent: const MediaSessionReloadIntent(),
        l10n: l10n,
      );
      final reloadedArgs =
          jsonDecode(reloaded!['loadArgs']! as String) as Map<String, dynamic>;
      expect(reloadedArgs['mediaGuid'], 'line-a');
      expect(reloadedArgs['url'], 'http://source.test/live-a.m3u8');
      expect(reloadedArgs['startPositionMs'], 0);
    });

    test(
      '编排 getPlayInfo + getStreamTrackData + getPlaybackStream，装配中立 bundle',
      () async {
        final teardown = <Object>[];
        final nas = buildNas(teardown);
        addTearDown(() {
          for (final n in teardown) {
            (n as NasProvider).dispose();
          }
        });
        final api = _FakePlaybackApi(nas);
        final backend = FeiniuMediaBackend(api);

        final resolution = await backend.getPlayback(
          const MediaPlaybackRequest(itemId: 'item-1'),
        );
        final bundle = resolution.bundle;

        expect(api.trackDataCalled, isTrue);
        expect(api.playbackStreamMediaGuid, 'media-default');
        expect(bundle.itemId, 'item-1');
        expect(bundle.seriesId, 'series-1');
        expect(bundle.seasonId, 'season-1');
        expect(bundle.selectedSource.id, 'media-default');
        expect(bundle.selectedSource.videoTrackId, 'video-default');
        expect(bundle.selectedSource.headers['User-Agent'], 'FlyPlayer/1.0');
        expect(bundle.qualities, hasLength(1));
        expect(bundle.audioTracks.single.id, 'audio-1');
        expect(bundle.subtitleTracks.single.id, 'sub-1');
        expect(bundle.selectedAudioTrack?.id, 'audio-1');
        expect(bundle.selectedSubtitleTrack?.id, 'sub-1');

        // 不透明后端上下文：持飞牛 raw facts，且这些 raw 结构不进中立 bundle。
        final context = resolution.backendContext;
        expect(context, isA<FeiniuPlaybackContext>());
        final feiniuContext = context as FeiniuPlaybackContext;
        expect(feiniuContext.effectiveSourceId, 'media-default');
        expect(feiniuContext.videoTrackId, 'video-default');
        expect(
          feiniuContext.playbackStream.responseHeaders.cookieHeader,
          'sess=abc',
        );
        expect(feiniuContext.selectedQuality?.mediaGuid, 'media-default');
        expect(feiniuContext.selectedAudio?.guid, 'audio-1');
        expect(feiniuContext.selectedSubtitle?.guid, 'sub-1');
      },
    );

    test(
      'startFromBeginning 用选中 source id 调 resetPlaybackRecord，起播归零',
      () async {
        final teardown = <Object>[];
        final nas = buildNas(teardown);
        addTearDown(() {
          for (final n in teardown) {
            (n as NasProvider).dispose();
          }
        });
        final api = _FakePlaybackApi(nas);
        final backend = FeiniuMediaBackend(api);

        final bundle = (await backend.getPlayback(
          const MediaPlaybackRequest(
            itemId: 'item-1',
            startFromBeginning: true,
          ),
        )).bundle;

        expect(api.resetItemGuid, 'item-1');
        expect(api.resetMediaGuid, 'media-default');
        expect(bundle.startPosition, Duration.zero);
      },
    );

    test('getStreamTrackData 失败仍返回 bundle（best-effort）', () async {
      final teardown = <Object>[];
      final nas = buildNas(teardown);
      addTearDown(() {
        for (final n in teardown) {
          (n as NasProvider).dispose();
        }
      });
      final api = _FakePlaybackApi(nas, failTrackData: true);
      final backend = FeiniuMediaBackend(api);

      final bundle = (await backend.getPlayback(
        const MediaPlaybackRequest(itemId: 'item-1'),
      )).bundle;

      expect(api.trackDataCalled, isTrue);
      expect(bundle.selectedSource.id, 'media-default');
    });

    test('qualityId 覆盖默认 source id', () async {
      final teardown = <Object>[];
      final nas = buildNas(teardown);
      addTearDown(() {
        for (final n in teardown) {
          (n as NasProvider).dispose();
        }
      });
      final api = _FakePlaybackApi(nas);
      final backend = FeiniuMediaBackend(api);

      final bundle = (await backend.getPlayback(
        const MediaPlaybackRequest(itemId: 'item-1', qualityId: 'media-alt'),
      )).bundle;

      expect(api.playbackStreamMediaGuid, 'media-alt');
      expect(bundle.selectedSource.id, 'media-alt');
    });

    test('显式关闭字幕：selectedSubtitleTrack 为 null', () async {
      final teardown = <Object>[];
      final nas = buildNas(teardown);
      addTearDown(() {
        for (final n in teardown) {
          (n as NasProvider).dispose();
        }
      });
      final api = _FakePlaybackApi(nas);
      final backend = FeiniuMediaBackend(api);

      final bundle = (await backend.getPlayback(
        const MediaPlaybackRequest(
          itemId: 'item-1',
          subtitleTrackExplicitlyDisabled: true,
        ),
      )).bundle;

      expect(bundle.selectedSubtitleTrack, isNull);
      // 字幕候选仍在列表里，只是没有默认选中。
      expect(bundle.subtitleTracks, isNotEmpty);
    });

    test('续播位置：ts>0 用 ts，ts==0 回退 watchedTs', () async {
      final teardown = <Object>[];
      final nas = buildNas(teardown);
      addTearDown(() {
        for (final n in teardown) {
          (n as NasProvider).dispose();
        }
      });

      final api = _FakePlaybackApi(nas)
        ..playInfoTs = 600
        ..itemWatchedTs = 120;
      final bundle = (await FeiniuMediaBackend(
        api,
      ).getPlayback(const MediaPlaybackRequest(itemId: 'item-1'))).bundle;
      expect(bundle.startPosition, const Duration(seconds: 600));

      final api2 = _FakePlaybackApi(nas)
        ..playInfoTs = 0
        ..itemWatchedTs = 120;
      final bundle2 = (await FeiniuMediaBackend(
        api2,
      ).getPlayback(const MediaPlaybackRequest(itemId: 'item-1'))).bundle;
      expect(bundle2.startPosition, const Duration(seconds: 120));
    });

    test('restartWhenCompleted=true 且已看完（ts>=duration）→ 起播归零', () async {
      final teardown = <Object>[];
      final nas = buildNas(teardown);
      addTearDown(() {
        for (final n in teardown) {
          (n as NasProvider).dispose();
        }
      });

      final api = _FakePlaybackApi(nas)
        ..itemDuration = 3000
        ..playInfoTs = 3000;
      final bundle = (await FeiniuMediaBackend(api).getPlayback(
        const MediaPlaybackRequest(
          itemId: 'item-1',
          restartWhenCompleted: true,
        ),
      )).bundle;

      expect(bundle.startPosition, Duration.zero);
    });

    test('restartWhenCompleted=false（默认）且已看完 → 维持网络位（保 B-2 单条目现状）', () async {
      final teardown = <Object>[];
      final nas = buildNas(teardown);
      addTearDown(() {
        for (final n in teardown) {
          (n as NasProvider).dispose();
        }
      });

      final api = _FakePlaybackApi(nas)
        ..itemDuration = 3000
        ..playInfoTs = 3000;
      final bundle = (await FeiniuMediaBackend(
        api,
      ).getPlayback(const MediaPlaybackRequest(itemId: 'item-1'))).bundle;

      expect(bundle.startPosition, const Duration(seconds: 3000));
    });
  });
}
