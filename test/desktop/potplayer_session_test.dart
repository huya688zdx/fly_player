import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/potplayer_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PotPlayerSession session;
  late Map<String, dynamic> state;
  late String reportingFile;
  late Future<Duration?> Function(String) resolveMedia;
  late List<({String file, int seconds, bool paused})> samples;
  late List<int> seeks;
  late List<String> errors;
  late int finishedCount;
  int? initialSeekTarget;

  setUp(() {
    reportingFile = 'https://example.test/a.mp4';
    state = <String, dynamic>{
      'alive': true,
      'file': reportingFile,
      'state': 2,
      'positionMs': 5000,
      'durationMs': 100000,
    };
    samples = [];
    seeks = [];
    errors = [];
    finishedCount = 0;
    initialSeekTarget = null;
    resolveMedia = (_) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PotPlayerSession.channel, (call) async {
          if (call.method == 'snapshot') {
            final snapshot = Map<String, dynamic>.of(state);
            if (initialSeekTarget != null) {
              state['positionMs'] = initialSeekTarget;
              initialSeekTarget = null;
            }
            return snapshot;
          }
          if (call.method == 'activate') {
            final arguments = call.arguments as Map;
            seeks.add(arguments['positionMs'] as int);
            if (arguments.containsKey('focus')) {
              expect(arguments['focus'], false);
            }
            if (seeks.length == 1) {
              initialSeekTarget = arguments['positionMs'] as int;
            }
          }
          if (call.method == 'configure') {
            state['state'] = (call.arguments as Map)['paused'] == true ? 1 : 2;
          }
          return true;
        });
    session = PotPlayerSession(
      pid: 1,
      mediaUrl: reportingFile,
      isCurrentSession: () => true,
      onProgress: (position, _, paused) => samples.add((
        file: reportingFile,
        seconds: position.inSeconds,
        paused: paused,
      )),
      onMediaChanged: (file) => resolveMedia(file),
      onFinished: () async => finishedCount++,
      onError: errors.add,
    );
  });

  tearDown(() async {
    await session.finish(reportFinal: false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PotPlayerSession.channel, null);
  });

  test('列表停止后可继续切集，快速换片不串用续播位或上报加载零位', () async {
    state['positionMs'] = 0;
    await session.start(
      paused: false,
      speed: 1,
      initialPosition: const Duration(seconds: 3),
    );
    expect(samples.first.seconds, 3);
    state['state'] = 0;
    state['positionMs'] = 0;
    await session.poll();
    expect(session.finished, false);
    expect(samples.last.seconds, 3);
    expect(samples.last.paused, true);

    const second = 'https://example.test/b.mp4';
    const third = 'https://example.test/c.mp4';
    final secondReady = Completer<void>();
    final changingSecond = Completer<void>();
    resolveMedia = (file) async {
      if (file == second) {
        changingSecond.complete();
        await secondReady.future;
      }
      reportingFile = file;
      return Duration(seconds: file == second ? 40 : 70);
    };
    state['file'] = second;
    state['state'] = 2;
    final switching = session.poll();
    await changingSecond.future;
    state['file'] = third;
    state['state'] = 1;
    secondReady.complete();
    await switching;
    await session.poll();
    await session.poll();
    expect(seeks, [3000, 70000]);
    expect(state['state'], 2);
    await session.poll();
    expect(
      samples.every(
        (sample) => sample.file.endsWith('/a.mp4') && sample.seconds == 3,
      ),
      isTrue,
    );
    expect(samples.where((sample) => sample.file == third), isEmpty);
    state['positionMs'] = 71000;
    await session.poll();
    expect(samples.last, (file: third, seconds: 71, paused: false));
    expect(samples.where((sample) => sample.file == second), isEmpty);
    expect(errors, isEmpty);
    state['alive'] = false;
    await session.poll();
    expect(session.finished, true);
    expect(finishedCount, 1);
  });

  test('换到列表外媒体时保留旧片最后采样并结束跟踪', () async {
    await session.start(
      paused: false,
      speed: 1,
      initialPosition: Duration.zero,
    );
    state['file'] = 'https://example.test/unknown.mp4';
    state['positionMs'] = 80000;
    await session.poll();
    expect(session.finished, true);
    expect(finishedCount, 1);
    expect(samples, [
      (file: reportingFile, seconds: 5, paused: false),
      (file: reportingFile, seconds: 5, paused: true),
    ]);
    expect(seeks, isEmpty);
    expect(errors.single, contains('列表外'));
  });
}
