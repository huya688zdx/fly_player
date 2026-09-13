import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_playback_activity.dart';
import 'package:fly_player/services/fly_data/fly_bif_service.dart';
import 'package:fly_player/playback/playback_source.dart';

void main() {
  test(
    'same-file subtitle, track and URL refresh keep the lease; source replacement stops it',
    () {
      fakeAsync((clock) {
        var current = const MpvMediaSource(
          statsScope: 'scope',
          itemGuid: 'item',
          mediaGuid: 'file',
          videoGuid: '',
          url: 'https://media/original',
          headers: {},
          title: 'video',
          loadNonce: 3,
        );
        final identity = FlyBifPlaybackIdentity(current);
        final events = <String>[];
        final lease = FlyPlaybackActivity(
          send: (b) async {
            events.add(b['state'] as String);
          },
          isCurrent: () => identity.matches(current),
        );
        lease.start(paused: false);
        clock.flushMicrotasks();
        current = current.copyWith(audioTrackGuid: 'audio-2');
        clock.elapse(const Duration(seconds: 15));
        current = current.copyWith(subtitleTrackGuid: 'external-subtitle');
        clock.elapse(const Duration(seconds: 15));
        current = current.copyWith(url: 'https://media/renewed');
        clock.elapse(const Duration(seconds: 15));
        expect(events, ['playing', 'playing', 'playing', 'playing']);
        current = current.copyWith(mediaGuid: 'different-version');
        clock.elapse(const Duration(seconds: 15));
        expect(events.last, 'stopped');
        expect(
          identity.matches(current.copyWith(mediaGuid: 'file', loadNonce: 4)),
          isFalse,
        );
      });
    },
  );
  test('paused lease refreshes every 15 seconds; stop is terminal', () {
    fakeAsync((clock) {
      final events = <Map<String, dynamic>>[];
      final lease = FlyPlaybackActivity(
        send: (body) async {
          events.add(body);
        },
        isCurrent: () => true,
      );
      lease.start(paused: true);
      clock.flushMicrotasks();
      final id = events.single['session_id'];
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      clock.elapse(const Duration(seconds: 30));
      expect(events.map((e) => e['state']), ['paused', 'paused', 'paused']);
      lease.update(paused: false);
      clock.flushMicrotasks();
      lease.stop();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 90));
      expect(events.map((e) => e['state']), [
        'paused',
        'paused',
        'paused',
        'playing',
        'stopped',
      ]);
      expect(events.every((e) => e['session_id'] == id), isTrue);
    });
  });
  test(
    'pending activity preserves order and source/account invalidation stops lease',
    () {
      fakeAsync((clock) {
        var current = true;
        final events = <String>[];
        final pending = Completer<void>();
        final lease = FlyPlaybackActivity(
          send: (body) async {
            events.add(body['state'] as String);
            if (events.length == 1) await pending.future;
          },
          isCurrent: () => current,
        );
        lease.start(paused: false);
        clock.flushMicrotasks();
        lease.stop();
        clock.flushMicrotasks();
        expect(events, ['playing']);
        pending.complete();
        clock.flushMicrotasks();
        expect(events, ['playing', 'stopped']);
        final other = FlyPlaybackActivity(
          send: (b) async {
            events.add(b['state'] as String);
          },
          isCurrent: () => current,
        );
        other.start(paused: true);
        clock.flushMicrotasks();
        current = false;
        clock.elapse(const Duration(seconds: 15));
        expect(events.last, 'stopped');
        clock.elapse(const Duration(seconds: 90));
        expect(events, ['playing', 'stopped', 'paused', 'stopped']);
      });
    },
  );
}
