import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_playback_mappers.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';

AudioTrackOption buildAudio({
  String guid = 'audio-guid',
  int index = 1,
  String language = 'jpn',
  String codecName = 'aac',
  String title = 'Main',
  int isDefault = 1,
}) {
  return AudioTrackOption(
    mediaGuid: 'media-1',
    guid: guid,
    title: title,
    codecName: codecName,
    profile: '',
    language: language,
    audioType: '',
    channelLayout: '',
    channels: 2,
    sampleRate: 48000,
    bps: 256000,
    index: index,
    isDefault: isDefault,
  );
}

SubtitleTrackOption buildSubtitle({
  String guid = 'sub-guid',
  int index = 0,
  String language = 'chi',
  String codecName = 'ass',
  String format = 'ass',
  String title = '',
  int isDefault = 1,
  int isExternal = 0,
  int extraFile = 0,
}) {
  return SubtitleTrackOption(
    mediaGuid: 'media-1',
    guid: guid,
    title: title,
    codecName: codecName,
    format: format,
    language: language,
    index: index,
    isDefault: isDefault,
    forced: 0,
    isExternal: isExternal,
    extraFile: extraFile,
    isBitmap: 0,
  );
}

void main() {
  group('mapFeiniuPlaybackQualities', () {
    test(
      'media guid 进中立 id / sourceId，video guid 进 videoTrackId，source 进 delivery',
      () {
        const qualities = <PlaybackQualityOption>[
          PlaybackQualityOption(
            mediaGuid: 'media-orig',
            videoGuid: 'video-orig',
            resolution: 'Original',
            bitrate: 20000000,
            isDefault: 1,
            source: PlaybackQualitySource.originalProxy,
            directLinkQualityIndex: null,
          ),
          PlaybackQualityOption(
            mediaGuid: 'media-dl',
            videoGuid: 'video-dl',
            resolution: '1080p',
            bitrate: 8000000,
            isDefault: 0,
            source: PlaybackQualitySource.directLink,
            directLinkQualityIndex: 2,
          ),
        ];

        final mapped = mapFeiniuPlaybackQualities(qualities);

        expect(mapped, hasLength(2));
        expect(mapped[0].id, 'media-orig');
        expect(mapped[0].sourceId, 'media-orig');
        expect(mapped[0].videoTrackId, 'video-orig');
        expect(mapped[0].resolution, 'Original');
        expect(mapped[0].bitrate, 20000000);
        expect(mapped[0].isDefault, isTrue);
        expect(mapped[0].delivery, MediaPlaybackDeliveryKind.original);
        expect(mapped[0].directLinkIndex, isNull);

        expect(mapped[1].id, 'media-dl');
        expect(mapped[1].delivery, MediaPlaybackDeliveryKind.directLink);
        expect(mapped[1].directLinkIndex, 2);
        expect(mapped[1].isDefault, isFalse);
      },
    );

    test('serverSession 源映射为 serverSession 投递', () {
      const qualities = <PlaybackQualityOption>[
        PlaybackQualityOption(
          mediaGuid: 'media-srv',
          videoGuid: 'video-srv',
          resolution: '720p',
          bitrate: 4000000,
          isDefault: 0,
          source: PlaybackQualitySource.serverSession,
          directLinkQualityIndex: null,
        ),
      ];

      final mapped = mapFeiniuPlaybackQualities(qualities);
      expect(mapped.single.delivery, MediaPlaybackDeliveryKind.serverSession);
    });
  });

  group('mapFeiniuAudioTracks', () {
    test('audio guid 进中立 id（不泄漏 audioGuid 命名），保留索引/语言/默认', () {
      final mapped = mapFeiniuAudioTracks(<AudioTrackOption>[
        buildAudio(guid: 'a-1', index: 2, language: 'eng', isDefault: 1),
      ]);

      final track = mapped.single;
      expect(track.id, 'a-1');
      expect(track.kind, MediaPlaybackTrackKind.audio);
      expect(track.index, 2);
      expect(track.language, 'eng');
      expect(track.codec, 'aac');
      expect(track.isDefault, isTrue);
      expect(track.subtitleLocation, isNull);
    });
  });

  group('mapFeiniuSubtitleTracks', () {
    test('内嵌字幕（两标志皆 0）映射为 embedded', () {
      final mapped = mapFeiniuSubtitleTracks(<SubtitleTrackOption>[
        buildSubtitle(isExternal: 0, extraFile: 0),
      ]);
      expect(mapped.single.kind, MediaPlaybackTrackKind.subtitle);
      expect(mapped.single.subtitleLocation, MediaSubtitleLocation.embedded);
    });

    test('服务端外挂字幕（仅 isExternal==1）映射为 external', () {
      final mapped = mapFeiniuSubtitleTracks(<SubtitleTrackOption>[
        buildSubtitle(guid: 's-ext', isExternal: 1, extraFile: 0),
      ]);
      expect(mapped.single.id, 's-ext');
      expect(mapped.single.subtitleLocation, MediaSubtitleLocation.external);
    });

    test('服务端抽取外挂（仅 extraFile==1）映射为 external', () {
      final mapped = mapFeiniuSubtitleTracks(<SubtitleTrackOption>[
        buildSubtitle(isExternal: 0, extraFile: 1),
      ]);
      expect(mapped.single.subtitleLocation, MediaSubtitleLocation.external);
    });

    test('设备本地字幕（isExternal==1 且 extraFile==1）映射为 local', () {
      // 复刻 local_subtitle_bundle / player_subtitle_controller 对设备本地字幕
      // 同时置位 isExternal=1, extraFile=1 的签名。
      final mapped = mapFeiniuSubtitleTracks(<SubtitleTrackOption>[
        buildSubtitle(isExternal: 1, extraFile: 1),
      ]);
      expect(mapped.single.subtitleLocation, MediaSubtitleLocation.local);
    });
  });

  group('mapFeiniuPlaybackSource', () {
    PlaybackStreamData buildStream({
      PlaybackResponseHeaders responseHeaders = const PlaybackResponseHeaders(),
      String requestUserAgent = '',
      VideoStreamInfo? videoStream,
    }) {
      return PlaybackStreamData(
        fileStream: null,
        videoStream: videoStream,
        audioStreams: const <AudioTrackOption>[],
        subtitleStreams: const <SubtitleTrackOption>[],
        qualities: const <PlaybackQualityOption>[],
        directLinkQualities: const <DirectLinkQualitySource>[],
        cloudStorageInfo: null,
        responseHeaders: responseHeaders,
        requestUserAgent: requestUserAgent,
      );
    }

    test(
      'responseHeaders 的 Cookie / User-Agent 进 source.headers，视频元数据进 source',
      () {
        const video = VideoStreamInfo(
          mediaGuid: 'media-1',
          guid: 'video-1',
          resolutionType: '4K',
          colorRangeType: 'HDR',
          codecName: 'hevc',
          profile: 'Main 10',
          level: '',
          displayAspectRatio: '',
          pixFmt: '',
          rFrameRate: '',
          colorRange: 'tv',
          colorSpace: 'bt2020nc',
          colorTransfer: 'smpte2084',
          colorPrimaries: 'bt2020',
          bps: 20000000,
          bitDepth: 10,
          refs: 0,
          progressive: 0,
          width: 3840,
          height: 2160,
        );
        final stream = buildStream(
          responseHeaders: const PlaybackResponseHeaders(
            cookies: <String>['sess=abc'],
            userAgents: <String>['FlyPlayer/1.0'],
          ),
          videoStream: video,
        );

        final source = mapFeiniuPlaybackSource(
          sourceId: 'media-1',
          videoTrackId: 'video-1',
          playbackStream: stream,
          selectedQuality: const PlaybackQualityOption(
            mediaGuid: 'media-1',
            videoGuid: 'video-1',
            resolution: 'Original',
            bitrate: 0,
            isDefault: 1,
            source: PlaybackQualitySource.originalProxy,
            directLinkQualityIndex: null,
          ),
          candidateUrl: 'https://nas.test/play.m3u8',
          headers: const <String, String>{},
        );

        expect(source.id, 'media-1');
        expect(source.videoTrackId, 'video-1');
        expect(source.delivery, MediaPlaybackDeliveryKind.original);
        expect(source.url, 'https://nas.test/play.m3u8');
        expect(source.headers['Cookie'], 'sess=abc');
        expect(source.headers['User-Agent'], 'FlyPlayer/1.0');
        expect(source.width, 3840);
        expect(source.height, 2160);
        expect(source.videoCodec, 'hevc');
        expect(source.videoProfile, 'Main 10');
        expect(source.colorSpace, 'bt2020nc');
        expect(source.colorTransfer, 'smpte2084');
        expect(source.colorPrimaries, 'bt2020');
        expect(source.bitDepth, 10);
      },
    );

    test('显式 headers 覆盖 responseHeaders，requestUserAgent 兜底 UA', () {
      final stream = buildStream(
        responseHeaders: const PlaybackResponseHeaders(
          cookies: <String>['sess=abc'],
        ),
        requestUserAgent: 'Fallback/2.0',
      );

      final source = mapFeiniuPlaybackSource(
        sourceId: 'media-1',
        videoTrackId: 'video-1',
        playbackStream: stream,
        selectedQuality: null,
        candidateUrl: '',
        headers: const <String, String>{'Cookie': 'override=1'},
      );

      // 显式 headers 优先。
      expect(source.headers['Cookie'], 'override=1');
      // responseHeaders 无 UA 时回退 requestUserAgent。
      expect(source.headers['User-Agent'], 'Fallback/2.0');
      // selectedQuality 为空时投递回退 original。
      expect(source.delivery, MediaPlaybackDeliveryKind.original);
    });
  });
}
