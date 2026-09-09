import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/sqlite_runtime.dart';
import 'package:fly_player/services/play_stats/native_play_stats_recorder.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('桌面初始化后，连续观看并退出的统计能落盘并重新读取', () async {
    final temporary = await Directory.systemTemp.createTemp('fly-stats-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => temporary.path,
    );
    final recorder = NativePlayStatsRecorder();
    addTearDown(() async {
      recorder.dispose();
      await PlayStatsService.instance.bindOwnerScope('closed');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await temporary.delete(recursive: true);
    });

    await initializeSqliteRuntime();
    await PlayStatsService.instance.bindOwnerScope('desktop-test');
    await recorder.onLaunch({
      'itemGuid': 'movie-1',
      'title': '测试影片',
      'mediaType': 'movie',
      'durationSeconds': 100,
    });
    for (var second = 0; second <= 5; second++) {
      await recorder.onProgress({
        'itemGuid': 'movie-1',
        'ts': second,
        'duration': 100,
        'isPaused': false,
      });
    }
    await recorder.finishPlayback();
    final database = await PlayStatsService.instance.database.rawDatabase;
    final path = database.path;
    expect(path, startsWith(temporary.path));
    await PlayStatsService.instance.bindOwnerScope('closed');
    final reopened = await openDatabase(path);
    try {
      final rows = await reopened.query('play_history');
      expect(rows, hasLength(1));
      expect(rows.single['title'], '测试影片');
      expect(rows.single['watched_ms'], 5000);
    } finally {
      await reopened.close();
    }
  }, skip: !Platform.isWindows && !Platform.isLinux);
}
