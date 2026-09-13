import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/services/fly_data/fly_oped.dart';

void main() {
  test('published ED preserves paused tails and permits normal actual EOF', () {
    expect(
      flyOpedAllowsAutoNext(
        protectedEdTail: true,
        playbackEnded: false,
        pausedByUser: false,
      ),
      isFalse,
    );
    expect(
      flyOpedAllowsAutoNext(
        protectedEdTail: true,
        playbackEnded: false,
        pausedByUser: true,
      ),
      isFalse,
    );
    expect(
      flyOpedAllowsAutoNext(
        protectedEdTail: true,
        playbackEnded: true,
        pausedByUser: true,
      ),
      isFalse,
    );
    expect(
      flyOpedAllowsAutoNext(
        protectedEdTail: true,
        playbackEnded: true,
        pausedByUser: false,
      ),
      isTrue,
    );
    expect(
      flyOpedAllowsAutoNext(
        protectedEdTail: false,
        playbackEnded: false,
        pausedByUser: true,
      ),
      isTrue,
    );
  });
  const original = MpvMediaSource(
    itemGuid: 'catalog-item',
    mediaGuid: 'selected-file',
    videoGuid: '',
    url: 'https://media.invalid/original',
    headers: {},
    title: 'Source delivery boundary',
  );

  test('only original NAS delivery shares the verified file coordinate', () {
    expect(original.supportsVerifiedFileOped, isTrue);
    for (final source in [
      original.copyWith(playbackMode: PlayerPlaybackMode.serverSession),
      original.copyWith(playbackMode: PlayerPlaybackMode.directLinkQuality),
      original.copyWith(isDownloadedFile: true),
      original.copyWith(externalLocalSource: true),
    ]) {
      expect(source.supportsVerifiedFileOped, isFalse);
    }
  });

  test('Android load arguments preserve the delivery and local-copy facts', () {
    final direct = original.toMap();
    expect(direct['playbackMode'], 'originalQuality');
    expect(direct['isDownloadedFile'], isFalse);
    expect(direct['externalLocalSource'], isFalse);
    final transformed = original
        .copyWith(playbackMode: PlayerPlaybackMode.serverSession)
        .toMap();
    expect(transformed['playbackMode'], 'serverSession');
    expect(
      original.copyWith(isDownloadedFile: true).toMap()['isDownloadedFile'],
      isTrue,
    );
  });
}
