import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/potplayer_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const media = 'https://example.invalid/synthetic.mp4';
  late PotPlayerSession session;
  late Map<String, Object> state;
  late List<String> calls;
  late List<String> errors;
  late int samples;
  late int finishedCount;
  late bool current;

  setUp(() {
    state = {
      'alive': true,
      'file': media,
      'state': 2,
      'positionMs': 5000,
      'durationMs': 100000,
    };
    calls = [];
    errors = [];
    samples = 0;
    finishedCount = 0;
    current = true;
    session = PotPlayerSession(
      pid: 41,
      mediaUrl: media,
      isCurrentSession: () => current,
      onProgress: (_, _, _) => samples++,
      onFinished: () async {
        finishedCount++;
      },
      onError: errors.add,
    );
  });
  tearDown(() async {
    await session.finish(reportFinal: false);
    messenger.setMockMethodCallHandler(PotPlayerSession.channel, null);
  });

  for (final method in ['activate', 'configure']) {
    test('$method false cannot claim resume success', () async {
      messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'snapshot'
            ? Map.of(state)
            : call.method != method;
      });
      expect(
        await session.activate(position: const Duration(seconds: 5)),
        isFalse,
      );
    });
    test('$method PlatformException remains observable', () async {
      messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
        call,
      ) async {
        if (call.method == 'snapshot') return Map.of(state);
        if (call.method == method) {
          throw PlatformException(code: 'potplayer_file_changed');
        }
        return true;
      });
      await expectLater(
        session.activate(position: const Duration(seconds: 5)),
        throwsA(isA<PlatformException>()),
      );
    });
  }
  test(
    'true controls still require a live matching post-command snapshot',
    () async {
      messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
        call,
      ) async {
        if (call.method == 'snapshot') return Map.of(state);
        state['alive'] = false;
        return true;
      });
      expect(await session.activate(), isFalse);
    },
  );
  test('foreground failure is distinct from confirmed playback', () async {
    messenger.setMockMethodCallHandler(PotPlayerSession.channel, (call) async {
      if (call.method == 'snapshot') return Map.of(state);
      if (call.method == 'activate') {
        final args = call.arguments as Map;
        if (args['focus'] != false) return false;
        state['positionMs'] = args['positionMs'] as int;
      }
      return true;
    });
    expect(
      await session.activate(position: const Duration(seconds: 20)),
      isTrue,
    );
    expect(errors, hasLength(1));
    expect(await session.activate(resumePlayback: false), isFalse);
  });
  test(
    'successful controls confirm requested position and playing sample',
    () async {
      state['state'] = 1;
      messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
        call,
      ) async {
        if (call.method == 'snapshot') return Map.of(state);
        final args = call.arguments as Map;
        if (call.method == 'activate' && args.containsKey('positionMs')) {
          state['positionMs'] = args['positionMs'] as int;
        }
        if (call.method == 'configure') {
          state['state'] = args['paused'] == true ? 1 : 2;
        }
        return true;
      });
      expect(
        await session.activate(position: const Duration(seconds: 20)),
        isTrue,
      );
      expect(state['positionMs'], 20000);
      expect(state['state'], 2);
    },
  );

  test(
    'explicit replay supersedes playlist resume while seek is pending',
    () async {
      const nextMedia = 'https://example.invalid/next.mp4';
      final entered = Completer<void>();
      final release = Completer<void>();
      final seeks = <int>[];
      session = PotPlayerSession(
        pid: 41,
        mediaUrl: media,
        isCurrentSession: () => true,
        onProgress: (_, _, _) {},
        onFinished: () async {},
        onError: errors.add,
        onMediaChanged: (_) async => const Duration(seconds: 40),
      );
      messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
        call,
      ) async {
        if (call.method == 'snapshot') return Map.of(state);
        final args = call.arguments as Map;
        if (call.method == 'activate' && args.containsKey('positionMs')) {
          final target = args['positionMs'] as int;
          seeks.add(target);
          state['positionMs'] = target;
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        }
        return true;
      });
      await session.start(
        paused: false,
        speed: 1,
        initialPosition: Duration.zero,
      );
      state['file'] = nextMedia;
      state['positionMs'] = 0;
      await session.poll();
      final replay = session.activate(position: Duration.zero);
      await entered.future;
      await session.poll();
      release.complete();
      expect(await replay, isTrue);
      expect(seeks, [0]);
    },
  );
  for (final seek in [false, true]) {
    test(
      '${seek ? 'seek' : 'resume'} waits for delayed actual samples',
      () async {
        state['state'] = 1;
        var delivered = false;
        var confirmations = 0;
        messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
          call,
        ) async {
          if (call.method == 'snapshot') {
            if (delivered && ++confirmations == 3) {
              if (seek) {
                state['positionMs'] = 20000;
              } else {
                state['state'] = 2;
              }
            }
            return Map.of(state);
          }
          delivered = true;
          return true;
        });
        expect(
          await session.activate(
            position: seek ? const Duration(seconds: 20) : null,
            resumePlayback: !seek,
          ),
          isTrue,
        );
        expect(confirmations, 3);
      },
    );
  }
  test(
    'cancel while waiting for confirmed resume prevents further sampling',
    () async {
      state['state'] = 1;
      var delivered = false;
      final confirming = Completer<void>();
      messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'snapshot') {
          if (delivered && !confirming.isCompleted) confirming.complete();
          return Map.of(state);
        }
        delivered = true;
        return true;
      });
      final activating = session.activate();
      await confirming.future;
      await session.finish(reportFinal: false);
      final count = calls.length;
      expect(await activating, isFalse);
      expect(calls.length, count);
    },
  );
  test(
    'delivered command without any actual change fails within the confirmation bound',
    () async {
      state['state'] = 1;
      messenger.setMockMethodCallHandler(
        PotPlayerSession.channel,
        (call) async => call.method == 'snapshot' ? Map.of(state) : true,
      );
      expect(
        await session.activate().timeout(const Duration(seconds: 5)),
        isFalse,
      );
    },
  );
  test(
    'unchanged old seek position never becomes confirmed as time passes',
    () async {
      state['positionMs'] = 30000;
      messenger.setMockMethodCallHandler(
        PotPlayerSession.channel,
        (call) async => call.method == 'snapshot' ? Map.of(state) : true,
      );
      expect(
        await session
            .activate(position: Duration.zero)
            .timeout(const Duration(seconds: 5)),
        isFalse,
      );
    },
  );
  for (final result in ['true', 'false', 'exception']) {
    test('playlist step $result preserves native delivery result', () async {
      messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
        call,
      ) async {
        expect(call.method, 'stepPlaylist');
        expect((call.arguments as Map)['mediaUrl'], media);
        if (result == 'exception') {
          throw PlatformException(code: 'potplayer_file_changed');
        }
        return result == 'true';
      });
      final command = PotPlayerSession.sendCommand('stepPlaylist', {
        'pid': 41,
        'mediaUrl': media,
        'direction': 1,
      });
      if (result == 'exception') {
        await expectLater(command, throwsA(isA<PlatformException>()));
      } else {
        expect(await command, result == 'true');
      }
    });
    test(
      'close $result always cleans tracking and reports rejected delivery',
      () async {
        messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
          call,
        ) async {
          if (call.method == 'snapshot') return Map.of(state);
          if (call.method == 'close') {
            if (result == 'exception') {
              throw PlatformException(code: 'potplayer_timeout');
            }
            return result == 'true';
          }
          return true;
        });
        await session.start(
          paused: false,
          speed: 1,
          initialPosition: Duration.zero,
        );
        await session.finish(closePlayer: true);
        expect(session.finished, isTrue);
        expect(finishedCount, 1);
        if (result == 'false') expect(errors.single, contains('关闭'));
      },
    );
  }
  for (final boundary in ['snapshot', 'configure', 'activate']) {
    for (final stop in [true, false]) {
      test(
        'startup ${stop ? 'finish' : 'scope change'} during $boundary cannot continue',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          final timers = <Timer>[];
          messenger.setMockMethodCallHandler(PotPlayerSession.channel, (
            call,
          ) async {
            calls.add(call.method);
            if (call.method == boundary && !entered.isCompleted) {
              entered.complete();
              await release.future;
            }
            return call.method == 'snapshot' ? Map.of(state) : true;
          });
          try {
            await runZoned(
              () async {
                final starting = session.start(
                  paused: false,
                  speed: 1,
                  initialPosition: boundary == 'activate'
                      ? const Duration(seconds: 5)
                      : Duration.zero,
                );
                final result = expectLater(starting, throwsStateError);
                await entered.future.timeout(const Duration(seconds: 5));
                if (stop) {
                  await session.finish(reportFinal: false);
                } else {
                  current = false;
                }
                final count = calls.length;
                release.complete();
                await result;
                expect(
                  calls.length,
                  count,
                  reason: 'No later command after cancellation',
                );
                expect(samples, 0);
                expect(timers.where((timer) => timer.isActive), isEmpty);
                expect(
                  TestWidgetsFlutterBinding.instance.removeObserver(session),
                  isFalse,
                  reason: 'Cancelled startup never leaves a binding observer',
                );
                await session.finish(reportFinal: false);
                expect(finishedCount, 1);
              },
              zoneSpecification: ZoneSpecification(
                createPeriodicTimer: (self, parent, zone, duration, callback) {
                  final timer = parent.createPeriodicTimer(
                    zone,
                    duration,
                    callback,
                  );
                  timers.add(timer);
                  return timer;
                },
              ),
            );
          } finally {
            if (!release.isCompleted) release.complete();
            for (final timer in timers) {
              timer.cancel();
            }
            TestWidgetsFlutterBinding.instance.removeObserver(session);
          }
        },
      );
    }
  }
}
