import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

import 'package:fly_player/player/controllers/player_source_controller.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/player/controllers/player_subtitle_controller.dart';

void main() {
  group('PlayerSourceController.shouldForceNativeProxyForPlaybackUrl', () {
    test('forces proxy for protected NAS server-session HLS', () {
      final shouldForce =
          PlayerSourceController.shouldForceNativeProxyForPlaybackUrl(
            'http://192.168.6.120:5666/v/media/session-1/preset.m3u8',
            const {
              'Authorization': 'Bearer token',
              'Trim-MC-token': 'trim-token',
            },
          );

      expect(shouldForce, isTrue);
    });

    test('does not force proxy without NAS auth headers', () {
      final shouldForce =
          PlayerSourceController.shouldForceNativeProxyForPlaybackUrl(
            'http://192.168.6.120:5666/v/media/session-1/preset.m3u8',
            const {'User-Agent': 'fly-player'},
          );

      expect(shouldForce, isFalse);
    });

    test('does not force proxy for signed cloud playback urls', () {
      final shouldForce =
          PlayerSourceController.shouldForceNativeProxyForPlaybackUrl(
            'https://media.ctyun.cn/video/preset.m3u8?X-Amz-Signature=abc',
            const {'Authorization': 'Bearer token'},
          );

      expect(shouldForce, isFalse);
    });

    test('does not force proxy for non-HLS media files', () {
      final shouldForce =
          PlayerSourceController.shouldForceNativeProxyForPlaybackUrl(
            'http://192.168.6.120:5666/v/media/session-1/video.mp4',
            const {'Authorization': 'Bearer token'},
          );

      expect(shouldForce, isFalse);
    });
  });

  group('PlayerSourceController.resolveReloadVideoState', () {
    const snapshot = PlayerSourceSnapshot(
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      subtitleSourceMediaGuid: 'media-1',
      videoGuid: 'video-720',
      directLinkQualityIndex: null,
      audioGuid: 'audio-1',
      subtitleGuid: 'sub-1',
      resolution: '720p',
      bitrate: 2500000,
      fileSizeBytes: 0,
      videoWidth: 1280,
      videoHeight: 720,
      currentHeaders: <String, String>{},
      activeProxySessionId: 'proxy-1',
      activeSubtitleProxySessionId: null,
      audioTracks: <AudioTrackOption>[],
      subtitleTracks: <SubtitleTrackOption>[],
      qualities: <PlaybackQualityOption>[],
      playbackMode: PlayerPlaybackMode.serverSession,
      serverFallbackSubtitleGuids: <String>{},
    );
    const targetVideoInfo = VideoStreamInfo(
      mediaGuid: 'media-1',
      guid: 'video-1080',
      resolutionType: '1080p',
      colorRangeType: '',
      codecName: 'hevc',
      profile: 'main10',
      level: '',
      displayAspectRatio: '',
      pixFmt: '',
      rFrameRate: '',
      colorRange: '',
      colorSpace: 'bt709',
      colorTransfer: 'bt709',
      colorPrimaries: 'bt709',
      bps: 4000000,
      bitDepth: 10,
      refs: 0,
      progressive: 1,
      width: 1920,
      height: 1080,
    );

    test(
      'keeps current server-managed quality when reload request has no quality',
      () {
        final resolved = PlayerSourceController.resolveReloadVideoState(
          selectedQuality: null,
          snapshot: snapshot,
          targetVideoInfo: targetVideoInfo,
        );

        expect(resolved.videoGuid, 'video-720');
        expect(resolved.resolution, '720p');
        expect(resolved.bitrate, 2500000);
        expect(resolved.videoWidth, 1280);
        expect(resolved.videoHeight, 720);
      },
    );

    test('uses explicit selected quality when provided', () {
      const selectedQuality = PlaybackQualityOption(
        mediaGuid: 'media-1',
        videoGuid: 'video-480',
        resolution: '480p',
        bitrate: 1200000,
        isDefault: 0,
        source: PlaybackQualitySource.serverSession,
        directLinkQualityIndex: null,
      );

      final resolved = PlayerSourceController.resolveReloadVideoState(
        selectedQuality: selectedQuality,
        snapshot: snapshot,
        targetVideoInfo: targetVideoInfo,
      );

      expect(resolved.videoGuid, 'video-480');
      expect(resolved.resolution, '480p');
      expect(resolved.bitrate, 1200000);
      expect(resolved.videoWidth, 1920);
      expect(resolved.videoHeight, 1080);
    });
  });

  group('PlayerSubtitleController.activeExternalSubtitlePath', () {
    test(
      'falls back to cached subtitle path after pending path is cleared',
      () async {
        final controller = PlayerSubtitleController();
        final tempDir = await Directory.systemTemp.createTemp(
          'fly_player_subtitle_test_',
        );
        final subtitleFile = File(
          '${tempDir.path}${Platform.pathSeparator}subtitle.ass',
        );
        await subtitleFile.writeAsString('[Script Info]\n');
        controller.cacheLocalSubtitleFile(
          guid: 'sub-external',
          path: subtitleFile.path,
        );

        final resolved = controller.activeExternalSubtitlePath(
          currentGuid: 'sub-external',
          pendingExternalSubtitlePath: null,
        );

        expect(resolved, subtitleFile.path);
        await tempDir.delete(recursive: true);
      },
    );
  });
}
