import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_playback_session.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Actual session cleanup, with an inert player and texture controller.
void main() {
  test(
    'repeated disposal waits for the same pending pause and releases once',
    () async {
      final platform = _Player();
      final session = _session(platform);
      final paused = Completer<void>();
      session.paused = paused.future;
      var sourceReleases = 0;
      var resourceReleases = 0;
      session.releaseSource = (_) => sourceReleases++;
      session.disposeResources = () async => resourceReleases++;
      final first = session.dispose();
      final second = session.dispose();
      var secondFinished = false;
      unawaited(second.then((_) => secondFinished = true));
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);
      expect(platform.disposeCount, 0);
      paused.complete();
      await Future.wait([first, second, session.dispose()]);
      expect(platform.disposeCount, 1);
      expect(sourceReleases, 1);
      expect(resourceReleases, 1);
      expect(session.disposed, isTrue);
      expect(session.retainedByHost, isFalse);
    },
  );

  for (final failure in ['pause', 'player', 'source']) {
    test(
      '$failure cleanup failure still releases the remaining resources once',
      () async {
        final platform = _Player()..fail = failure == 'player';
        final session = _session(platform);
        final paused = Completer<void>();
        session.paused = paused.future;
        var sourceReleases = 0;
        var resourceReleases = 0;
        session.releaseSource = (_) {
          sourceReleases++;
          if (failure == 'source') throw StateError('source failure');
        };
        session.disposeResources = () async => resourceReleases++;
        final disposing = session.dispose();
        final check = expectLater(disposing, throwsStateError);
        if (failure == 'pause') {
          paused.completeError(StateError('pause failure'));
        } else {
          paused.complete();
        }
        await check;
        expect(platform.disposeCount, 1);
        expect(sourceReleases, 1);
        expect(resourceReleases, 1);
        await expectLater(session.dispose(), throwsStateError);
        expect(platform.disposeCount, 1);
        expect(resourceReleases, 1);
      },
    );
  }
}

DesktopPlaybackSession _session(_Player platform) => DesktopPlaybackSession(
  const MpvMediaSource(
    itemGuid: 'fake',
    mediaGuid: 'fake-media',
    videoGuid: 'fake-video',
    url: 'https://media.invalid/fake',
    headers: {},
    title: 'fake',
  ),
  player: Player(platformPlayer: platform),
  videoController: _VideoController(),
);

class _Player extends PlatformPlayer {
  _Player() : super(configuration: const PlayerConfiguration());
  int disposeCount = 0;
  bool fail = false;
  @override
  Future<void> dispose() async {
    disposeCount++;
    await super.dispose();
    if (fail) throw StateError('player failure');
  }
}

class _VideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
