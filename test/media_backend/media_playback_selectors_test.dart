import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/media_backend/playback/media_playback_selectors.dart';

void main() {
  const original = MediaPlaybackQuality(
    id: 'original',
    sourceId: 'source-a',
    videoTrackId: 'video-a',
    label: '原画',
    resolution: '4K',
    bitrate: 20000000,
    isDefault: true,
    delivery: MediaPlaybackDeliveryKind.original,
  );
  const transcoded = MediaPlaybackQuality(
    id: 'transcoded',
    sourceId: 'source-b',
    videoTrackId: 'video-b',
    label: '1080p',
    resolution: '1080p',
    bitrate: 8000000,
    isDefault: false,
    delivery: MediaPlaybackDeliveryKind.serverSession,
  );
  const directLink = MediaPlaybackQuality(
    id: 'direct-link',
    sourceId: 'source-a',
    videoTrackId: 'video-direct',
    label: '1080p direct',
    resolution: '1080p',
    bitrate: 8000000,
    isDefault: false,
    delivery: MediaPlaybackDeliveryKind.directLink,
    directLinkIndex: 0,
  );

  test('quality id wins over index', () {
    final selected = selectPlaybackQuality(
      qualities: const [original, transcoded],
      qualityId: 'transcoded',
      qualityIndex: 0,
    );

    expect(selected, transcoded);
  });

  test('quality id for a source prefers original/default over direct link', () {
    final selected = selectPlaybackQuality(
      qualities: const [directLink, original],
      qualityId: 'source-a',
    );

    expect(selected, original);
  });

  test('quality index is used when id is absent', () {
    final selected = selectPlaybackQuality(
      qualities: const [original, transcoded],
      qualityIndex: 1,
    );

    expect(selected, transcoded);
  });

  test('default quality is used as fallback', () {
    final selected = selectPlaybackQuality(
      qualities: const [transcoded, original],
    );

    expect(selected, original);
  });

  test(
    'direct link is preferred before non-direct default for initial playback',
    () {
      final selected = selectPlaybackQuality(
        qualities: const [original, directLink],
      );

      expect(selected, directLink);
    },
  );

  group('selectPlaybackQuality 分辨率继承 (画质跨集继承)', () {
    test('preferredResolution 命中转码档：跨集沿用当前分辨率', () {
      final selected = selectPlaybackQuality(
        qualities: const [original, transcoded],
        preferredResolution: '1080p',
      );

      expect(selected, transcoded);
    });

    test('preferredResolution 找不到：回退默认画质梯度', () {
      final selected = selectPlaybackQuality(
        qualities: const [original, transcoded],
        preferredResolution: '480p',
      );

      // 默认梯度：无直链 → 原画档优先。
      expect(selected, original);
    });

    test('qualityId/qualityIndex 优先于 preferredResolution', () {
      final selected = selectPlaybackQuality(
        qualities: const [original, transcoded],
        qualityIndex: 0,
        preferredResolution: '1080p',
      );

      expect(selected, original);
    });
  });

  test('subtitle can be explicitly disabled', () {
    const subtitle = MediaPlaybackTrack(
      id: 'subtitle-1',
      kind: MediaPlaybackTrackKind.subtitle,
      label: '中文',
      language: 'chi',
      codec: 'ass',
      title: '',
      isDefault: true,
      subtitleLocation: MediaSubtitleLocation.embedded,
    );

    final selected = selectPlaybackTrack(
      tracks: const [subtitle],
      preferredTrackId: null,
      explicitlyDisabled: true,
    );

    expect(selected, isNull);
  });

  group('selectPlaybackTrack 序号继承 (Bug B)', () {
    const a0 = MediaPlaybackTrack(
      id: 'audio-jpn',
      kind: MediaPlaybackTrackKind.audio,
      language: 'jpn',
      isDefault: true,
    );
    const a1 = MediaPlaybackTrack(
      id: 'audio-chi',
      kind: MediaPlaybackTrackKind.audio,
      language: 'chi',
    );
    const a2 = MediaPlaybackTrack(
      id: 'audio-eng',
      kind: MediaPlaybackTrackKind.audio,
      language: 'eng',
    );

    test('preferredTrackIndex 命中：取第 N 条（跨集沿用序号）', () {
      final selected = selectPlaybackTrack(
        tracks: const [a0, a1, a2],
        preferredTrackIndex: 2,
        // 服务端默认是第 0 条，但序号继承应压过它。
        fallbackTrackId: 'audio-jpn',
      );

      expect(selected, a2);
    });

    test('preferredTrackIndex 越界：回退服务端默认（找不到对应序号回默认）', () {
      final selected = selectPlaybackTrack(
        tracks: const [a0, a1],
        preferredTrackIndex: 5,
        fallbackTrackId: 'audio-chi',
      );

      expect(selected, a1);
    });

    test('显式 preferredTrackId 优先于序号', () {
      final selected = selectPlaybackTrack(
        tracks: const [a0, a1, a2],
        preferredTrackId: 'audio-eng',
        preferredTrackIndex: 0,
      );

      expect(selected, a2);
    });

    test('无序号无显式：fallback 默认 guid 命中（保持原有 open 行为）', () {
      final selected = selectPlaybackTrack(
        tracks: const [a0, a1, a2],
        fallbackTrackId: 'audio-chi',
      );

      expect(selected, a1);
    });

    test('序号继承压过 fallback：preferredIndex 0 而默认是第 1 条', () {
      final selected = selectPlaybackTrack(
        tracks: const [a0, a1, a2],
        preferredTrackIndex: 0,
        fallbackTrackId: 'audio-chi',
      );

      expect(selected, a0);
    });
  });
}
