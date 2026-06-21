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

  test('quality id wins over index', () {
    final selected = selectPlaybackQuality(
      qualities: const [original, transcoded],
      qualityId: 'transcoded',
      qualityIndex: 0,
    );

    expect(selected, transcoded);
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
}
