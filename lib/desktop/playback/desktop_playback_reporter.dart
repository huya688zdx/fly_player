import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../playback/playback_source.dart';
import '../../services/play_stats/native_play_stats_recorder.dart';

/// 保存采样时的媒体身份，并维护上报、统计和释放服务端会话的顺序。
/// 页面退出后，已排队的数据仍可完成，不再读取播放器或页面状态。
class DesktopPlaybackReporter {
  DesktopPlaybackReporter({this.reportProgress, this.releaseServerSession});

  final Future<void> Function(Map<String, dynamic>)? reportProgress;
  final Future<void> Function(String)? releaseServerSession;
  final NativePlayStatsRecorder _localStats = NativePlayStatsRecorder();
  Future<void> _serverPending = Future<void>.value();
  Future<void> _localPending = Future<void>.value();

  void onLaunch(MpvMediaSource source) {
    final metadata = source.toMap();
    _localPending = _localPending
        .then((_) => _localStats.onLaunch(metadata))
        .catchError(_reportError);
  }

  void recordLocal(
    MpvMediaSource source, {
    required Duration position,
    required Duration duration,
    required bool paused,
  }) {
    if (duration.inSeconds <= 0 || source.externalLocalSource) return;
    final metadata = source.toMap();
    final progress = <String, dynamic>{
      'itemGuid': source.itemGuid,
      'ts': position.inSeconds.clamp(0, duration.inSeconds),
      'duration': duration.inSeconds,
      'isPaused': paused,
    };
    _localPending = _localPending
        .then<void>((_) async {
          _localStats.cacheSource(metadata);
          await _localStats.onProgress(progress);
        })
        .catchError(_reportError);
  }

  void recordServer(
    MpvMediaSource source, {
    required Duration position,
    required Duration duration,
    required bool paused,
    required bool completed,
  }) {
    final report = reportProgress;
    if (report == null ||
        source.externalLocalSource ||
        duration.inSeconds <= 0) {
      return;
    }
    final progress = <String, dynamic>{
      'itemGuid': source.itemGuid,
      'mediaGuid': source.mediaGuid,
      'videoGuid': source.videoGuid,
      'audioGuid': source.audioTrackGuid ?? '',
      'subtitleGuid': source.subtitleTrackGuid ?? '',
      'resolution': source.resolution,
      'bitrate': source.bitrate,
      'playLink': source.playLink ?? '',
      'ts': completed
          ? duration.inSeconds
          : position.inSeconds.clamp(0, duration.inSeconds),
      'duration': duration.inSeconds,
      'isPaused': paused,
    };
    _serverPending = _serverPending
        .then((_) => report(progress))
        .catchError(_reportError);
  }

  void release(MpvMediaSource source, {MpvMediaSource? replacement}) {
    final link = source.playLink?.trim() ?? '';
    final release = releaseServerSession;
    if (link.isEmpty || link == replacement?.playLink || release == null) {
      return;
    }
    // 最后一笔进度先完成，避免在服务端会话销毁后才发送。
    unawaited(
      _serverPending.then((_) => release(link)).catchError(_reportError),
    );
  }

  Future<void> flushServer() => _serverPending;

  Future<void> dispose() async {
    await _localPending;
    try {
      await _localStats.finishPlayback();
    } finally {
      _localStats.dispose();
    }
  }

  static void _reportError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  }
}
