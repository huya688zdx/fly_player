import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/media_backend/emby/emby_playback_mappers.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/media_backend/playback/media_playback_selectors.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/playback/emby_playback_source_bridge.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/services/server_reentry_support.dart';

Map<String, Object?> _source({
  String id = 'ms1',
  int height = 2160,
  int bitrate = 40000000,
  Object? supportsTranscoding,
}) {
  return <String, Object?>{
    'Id': id,
    if (supportsTranscoding != null) 'SupportsTranscoding': supportsTranscoding,
    'MediaStreams': <Object?>[
      <String, Object?>{
        'Type': 'Video',
        'Index': 0,
        'Height': height,
        'BitRate': bitrate,
      },
    ],
  };
}

void main() {
  group('mapEmbyPlaybackQualities', () {
    test('原画档恒在首位且为默认；高码率 4K 源出全梯度', () {
      final qualities = mapEmbyPlaybackQualities(_source());
      expect(qualities.first.delivery, MediaPlaybackDeliveryKind.original);
      expect(qualities.first.isDefault, isTrue);
      expect(qualities.first.resolution, '2160P');
      expect(qualities.first.sourceId, 'ms1');
      // 40Mbps 远超 2160 档 20Mbps 上限 → 同分辨率转码档保留；1440/1080/720 全出。
      final transcodeRes = qualities
          .where((q) => q.delivery == MediaPlaybackDeliveryKind.transcoding)
          .map((q) => q.resolution)
          .toList();
      expect(transcodeRes, <String>['2160P', '1440P', '1080P', '720P']);
    });

    test('不出高于源分辨率的档；源同档码率不高时跳过', () {
      final qualities = mapEmbyPlaybackQualities(
        _source(height: 1080, bitrate: 5000000),
      );
      final transcodeRes = qualities
          .where((q) => q.delivery == MediaPlaybackDeliveryKind.transcoding)
          .map((q) => q.resolution)
          .toList();
      // 1080 档上限 8Mbps，源 5Mbps 转码无省流意义 → 只出 720P。
      expect(transcodeRes, <String>['720P']);
    });

    test('SupportsTranscoding=false 只出原画档', () {
      final qualities = mapEmbyPlaybackQualities(
        _source(supportsTranscoding: false),
      );
      expect(qualities, hasLength(1));
      expect(qualities.single.delivery, MediaPlaybackDeliveryKind.original);
    });

    test('候选 id 自包含：可还原版本 id 并判别候选/裸版本', () {
      final qualities = mapEmbyPlaybackQualities(_source());
      for (final quality in qualities) {
        expect(isEmbyQualityCandidateId(quality.id), isTrue);
        expect(embyQualityVersionId(quality.id), 'ms1');
      }
      expect(isEmbyQualityCandidateId('ms1'), isFalse);
      expect(embyQualityVersionId('ms1'), 'ms1');
      expect(embyQualityVersionId(null), '');
    });

    test('embyQualityMaxHeight 从 resolution 解析目标高度', () {
      final qualities = mapEmbyPlaybackQualities(_source());
      final tier1080 = qualities.firstWhere((q) => q.resolution == '1080P');
      expect(embyQualityMaxHeight(tier1080), 1080);
    });

    test('selectPlaybackQuality 语义：无指定回原画默认，下标切转码档', () {
      final qualities = mapEmbyPlaybackQualities(_source());
      final byDefault = selectPlaybackQuality(qualities: qualities);
      expect(byDefault?.delivery, MediaPlaybackDeliveryKind.original);
      final byIndex = selectPlaybackQuality(
        qualities: qualities,
        qualityIndex: 3,
      );
      expect(byIndex, same(qualities[3]));
      final byResolution = selectPlaybackQuality(
        qualities: qualities,
        preferredResolution: '720P',
      );
      expect(byResolution?.resolution, '720P');
    });
  });

  group('EmbyPlaybackSourceBridge loadArgs 契约（原生壳消费面）', () {
    test(
      '画质候选写进 loadArgs["qualities"]，键名对齐原生 qualityList/qualityLabel',
      () async {
        final qualities = mapEmbyPlaybackQualities(_source());
        final bundle = MediaPlaybackBundle(
          itemId: 'item1',
          selectedSource: const MediaPlaybackSource(
            id: 'ms1',
            videoTrackId: '0',
            delivery: MediaPlaybackDeliveryKind.directLink,
            url: 'http://x/stream.mkv',
            width: 3840,
            height: 2160,
            reliableSeek: true,
          ),
          session: const MediaPlaybackSession(),
          selectedQuality: qualities.first,
          qualities: qualities,
        );
        final source = await const EmbyPlaybackSourceBridge().assemble(
          request: const MediaPlaybackRequest(itemId: 'item1'),
          bundle: bundle,
        );
        final map = source.toMap();
        final list = (map['qualities'] as List)
            .cast<Map<String, Object?>>()
            .toList();
        expect(list, hasLength(qualities.length));
        // 原生壳读的键：resolution（打勾/档位合并）、source（原画优先）、bitrate。
        expect(list.first['resolution'], '2160P');
        expect(list.first['source'], 'originalProxy');
        expect(
          list.where((q) => q['source'] == 'serverSession'),
          hasLength(qualities.length - 1),
        );
        // 原画态：playbackMode originalQuality；resolution 与候选同源（打勾匹配）。
        expect(map['playbackMode'], 'originalQuality');
        expect(map['resolution'], '2160P');
      },
    );

    test('转码档装配：serverSession 托管、aid/sid 清空、resolution 对齐选中档', () async {
      final qualities = mapEmbyPlaybackQualities(_source());
      final tier = qualities.firstWhere(
        (q) =>
            q.delivery == MediaPlaybackDeliveryKind.transcoding &&
            q.resolution == '1080P',
      );
      const audio = MediaPlaybackTrack(
        id: '1',
        kind: MediaPlaybackTrackKind.audio,
        index: 1,
        label: 'AAC 5.1',
        isDefault: true,
      );
      final bundle = MediaPlaybackBundle(
        itemId: 'item1',
        selectedSource: const MediaPlaybackSource(
          id: 'ms1',
          videoTrackId: '0',
          delivery: MediaPlaybackDeliveryKind.transcoding,
          url: 'http://x/master.m3u8',
          reliableSeek: true,
        ),
        session: const MediaPlaybackSession(
          id: 'ps1',
          serverManaged: true,
          requiresStop: true,
        ),
        selectedQuality: tier,
        qualities: qualities,
        audioTracks: const <MediaPlaybackTrack>[audio],
        selectedAudioTrack: audio,
      );
      final source = await const EmbyPlaybackSourceBridge().assemble(
        request: const MediaPlaybackRequest(itemId: 'item1'),
        bundle: bundle,
      );
      expect(source.playbackMode, PlayerPlaybackMode.serverSession);
      // 转码流音轨已烧录：不设 aid，避免 mpv 选轨报错/没声音。
      expect(source.audioTrackIndex, isNull);
      expect(source.resolution, '1080P');
      expect(source.toMap()['serverPlaybackManaged'], true);
    });
  });

  group('ServerReentrySupport.currentQualityIndex', () {
    List<PlaybackQualityOption> options() => <PlaybackQualityOption>[
      const PlaybackQualityOption(
        mediaGuid: 'emby:q:ms1:original',
        videoGuid: '0',
        resolution: '2160P',
        bitrate: 40000000,
        isDefault: 1,
        source: PlaybackQualitySource.originalProxy,
        directLinkQualityIndex: null,
      ),
      const PlaybackQualityOption(
        mediaGuid: 'emby:q:ms1:1080:8000000',
        videoGuid: '0',
        resolution: '1080P',
        bitrate: 8000000,
        isDefault: 0,
        source: PlaybackQualitySource.serverSession,
        directLinkQualityIndex: null,
      ),
      const PlaybackQualityOption(
        mediaGuid: 'emby:q:ms1:720:4000000',
        videoGuid: '0',
        resolution: '720P',
        bitrate: 4000000,
        isDefault: 0,
        source: PlaybackQualitySource.serverSession,
        directLinkQualityIndex: null,
      ),
    ];

    test('原画态定位原画档下标', () {
      final source = MpvMediaSource(
        itemGuid: 'item',
        mediaGuid: 'ms1',
        videoGuid: '0',
        headers: const <String, String>{},
        url: 'http://x/stream',
        title: 't',
        resolution: '2160P',
        qualities: options(),
      );
      expect(ServerReentrySupport.currentQualityIndex(source), 0);
    });

    test('转码态按分辨率+码率对位当前档', () {
      final source = MpvMediaSource(
        itemGuid: 'item',
        mediaGuid: 'ms1',
        videoGuid: '0',
        headers: const <String, String>{},
        url: 'http://x/master.m3u8',
        title: 't',
        resolution: '720P',
        bitrate: 4000000,
        playbackMode: PlayerPlaybackMode.serverSession,
        qualities: options(),
      );
      expect(ServerReentrySupport.currentQualityIndex(source), 2);
    });

    test('码率缺失退分辨率首档；无候选返回 null', () {
      final source = MpvMediaSource(
        itemGuid: 'item',
        mediaGuid: 'ms1',
        videoGuid: '0',
        headers: const <String, String>{},
        url: 'http://x/master.m3u8',
        title: 't',
        resolution: '1080P',
        playbackMode: PlayerPlaybackMode.serverSession,
        qualities: options(),
      );
      expect(ServerReentrySupport.currentQualityIndex(source), 1);
      const empty = MpvMediaSource(
        itemGuid: 'item',
        mediaGuid: 'ms1',
        videoGuid: '0',
        headers: <String, String>{},
        url: 'http://x/master.m3u8',
        title: 't',
        playbackMode: PlayerPlaybackMode.serverSession,
      );
      expect(ServerReentrySupport.currentQualityIndex(empty), isNull);
    });
  });
}
