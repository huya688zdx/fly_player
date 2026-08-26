import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';

void main() {
  test('MediaPlaybackBundle exposes neutral playback facts', () {
    const source = MediaPlaybackSource(
      id: 'source-1',
      videoTrackId: 'video-1',
      delivery: MediaPlaybackDeliveryKind.directLink,
      url: 'https://example.test/video.m3u8',
      headers: {'User-Agent': 'FlyPlayer'},
      width: 1920,
      height: 1080,
      videoCodec: 'h264',
      videoProfile: 'High',
      colorSpace: 'bt709',
      colorTransfer: 'bt709',
      colorPrimaries: 'bt709',
      bitDepth: 8,
      reliableSeek: true,
      forceNativeProxy: false,
    );
    const quality = MediaPlaybackQuality(
      id: 'quality-1',
      sourceId: 'source-1',
      videoTrackId: 'video-1',
      label: '1080p',
      resolution: '1080p',
      bitrate: 8000000,
      isDefault: true,
      delivery: MediaPlaybackDeliveryKind.directLink,
      directLinkIndex: 0,
    );
    const audio = MediaPlaybackTrack(
      id: 'audio-1',
      kind: MediaPlaybackTrackKind.audio,
      index: 1,
      label: '日语 AAC',
      language: 'jpn',
      codec: 'aac',
      title: 'Main',
      isDefault: true,
    );
    const session = MediaPlaybackSession(
      id: 'session-1',
      serverManaged: true,
      requiresStop: true,
      hlsTimeSeconds: 30,
    );
    const bundle = MediaPlaybackBundle(
      itemId: 'item-1',
      title: 'Episode 1',
      itemType: 'Episode',
      seriesId: 'series-1',
      seasonId: 'season-1',
      seriesTitle: 'Series',
      seasonNumber: 1,
      episodeNumber: 1,
      posterUrl: '/poster.jpg',
      tmdbId: '123',
      durationSeconds: 1500,
      startPosition: Duration(seconds: 42),
      selectedSource: source,
      selectedQuality: quality,
      selectedAudioTrack: audio,
      selectedSubtitleTrack: null,
      qualities: [quality],
      audioTracks: [audio],
      subtitleTracks: [],
      session: session,
    );

    expect(bundle.selectedSource.headers['User-Agent'], 'FlyPlayer');
    expect(bundle.startPosition, const Duration(seconds: 42));
    expect(bundle.selectedQuality?.sourceId, 'source-1');
    expect(bundle.session.requiresStop, isTrue);
  });

  test('MediaPlaybackRequest distinguishes default subtitle from off', () {
    const request = MediaPlaybackRequest(
      itemId: 'item-1',
      subtitleTrackId: null,
      subtitleTrackExplicitlyDisabled: true,
    );

    expect(request.itemId, 'item-1');
    expect(request.subtitleTrackId, isNull);
    expect(request.subtitleTrackExplicitlyDisabled, isTrue);
  });
}
