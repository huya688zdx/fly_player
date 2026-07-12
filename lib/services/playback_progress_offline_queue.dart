import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/feiniu_api.dart';
import '../providers/nas_provider.dart';
import '../utils/app_exception.dart';

/// 进度离线排队。
///
/// 原生壳/在线播放器把播放进度回写 NAS（`recordPlayback`）时，断网/超时会直接丢失。
/// 本队列在回写失败（可恢复错误）时把进度落盘，**网络恢复或下次启动**重放回 NAS。
///
/// - 去重键 = `itemGuid|mediaGuid|videoGuid`，同一条目只保留**最新**一条（旧的被覆盖），
///   避免断网期间高频心跳把队列撑爆；
/// - 重放成功删除；仍断网（transient）保留并提前结束等下次；鉴权/数据/致命类错误（重放
///   也不会成功）直接丢弃，防止死条目堆积；
/// - 仅存 `recordPlayback` 所需字段，不落整个 loadArgs。
class PlaybackProgressOfflineQueue {
  PlaybackProgressOfflineQueue._();

  static const String _prefsKey = 'playback_progress_offline_queue_v1';
  static const String _serverPrefsKey =
      'playback_server_progress_offline_queue_v1';
  static const int _maxEntries = 200;

  static bool _flushing = false;
  static bool _serverFlushing = false;

  static Future<void> enqueueServer({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
    bool isPaused = false,
  }) async {
    final normalizedItemId = itemId.trim();
    final normalizedMediaSourceId = mediaSourceId.trim();
    if (normalizedItemId.isEmpty || normalizedMediaSourceId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = _readServer(prefs);
      entries['$normalizedItemId|$normalizedMediaSourceId'] = <String, Object?>{
        'itemId': normalizedItemId,
        'mediaSourceId': normalizedMediaSourceId,
        'positionSeconds': positionSeconds < 0 ? 0 : positionSeconds,
        'isPaused': isPaused,
        'enqueuedAt': DateTime.now().millisecondsSinceEpoch,
      };
      _trimServer(entries);
      await prefs.setString(_serverPrefsKey, jsonEncode(entries));
    } catch (_) {
      // 离线队列是旁路能力，落盘失败不应阻断播放。
    }
  }

  static Future<void> flushServer(
    Future<void> Function(Map<String, Object?> progress) report,
  ) async {
    if (_serverFlushing) return;
    _serverFlushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = _readServer(prefs);
      if (entries.isEmpty) return;
      var dirty = false;
      final keys = _sortedServerKeys(entries);
      for (final key in keys) {
        final raw = entries[key];
        if (raw is! Map) {
          entries.remove(key);
          dirty = true;
          continue;
        }
        final progress = raw.map<String, Object?>(
          (entryKey, value) => MapEntry(entryKey.toString(), value),
        );
        progress.remove('enqueuedAt');
        try {
          await report(progress);
          entries.remove(key);
          dirty = true;
        } catch (error) {
          final exception = AppException.from(
            error,
            action: 'replay server playback progress',
            fallbackKind: AppExceptionKind.fatal,
          );
          if (exception.isTransient) {
            break;
          }
          entries.remove(key);
          dirty = true;
        }
      }
      if (dirty) {
        if (entries.isEmpty) {
          await prefs.remove(_serverPrefsKey);
        } else {
          await prefs.setString(_serverPrefsKey, jsonEncode(entries));
        }
      }
    } catch (_) {
      // 重放失败时保留盘上队列，等待下一次网络恢复。
    } finally {
      _serverFlushing = false;
    }
  }

  static String _keyOf(Map<String, dynamic> p) {
    final item = (p['itemGuid'] ?? '').toString().trim();
    final media = (p['mediaGuid'] ?? '').toString().trim();
    final video = (p['videoGuid'] ?? '').toString().trim();
    return '$item|$media|$video';
  }

  /// 入队（按 key upsert，保留最新）。仅在回写失败且可恢复时调用。
  static Future<void> enqueue(Map<String, dynamic> progress) async {
    final itemGuid = (progress['itemGuid'] ?? '').toString().trim();
    final mediaGuid = (progress['mediaGuid'] ?? '').toString().trim();
    final videoGuid = (progress['videoGuid'] ?? '').toString().trim();
    if (itemGuid.isEmpty || mediaGuid.isEmpty || videoGuid.isEmpty) return;
    final duration = (progress['duration'] as num?)?.toInt() ?? 0;
    if (duration <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _read(prefs);
      map[_keyOf(progress)] = <String, dynamic>{
        'itemGuid': itemGuid,
        'mediaGuid': mediaGuid,
        'videoGuid': videoGuid,
        'audioGuid': (progress['audioGuid'] ?? '').toString(),
        'subtitleGuid': (progress['subtitleGuid'] ?? '').toString(),
        'resolution': (progress['resolution'] ?? '').toString(),
        'bitrate': (progress['bitrate'] as num?)?.toInt() ?? 0,
        'ts': (progress['ts'] as num?)?.toInt() ?? 0,
        'duration': duration,
        'playLink': (progress['playLink'] ?? '').toString(),
        'enqueuedAt': DateTime.now().millisecondsSinceEpoch,
      };
      _trim(map);
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {
      // 排队是旁路能力，落盘失败静默。
    }
  }

  /// 重放队列：旧的先发。成功删除；仍断网保留并提前结束；不可恢复错误丢弃该条。
  static Future<void> flush(NasProvider nas) async {
    if (_flushing || !nas.isConfigured) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _read(prefs);
      if (map.isEmpty) return;
      final api = FeiniuApi(nas);
      final keys = _sortedByEnqueuedAt(map);
      var dirty = false;
      for (final key in keys) {
        final entry = map[key];
        if (entry is! Map) {
          map.remove(key);
          dirty = true;
          continue;
        }
        final duration = (entry['duration'] as num?)?.toInt() ?? 0;
        final ts = (entry['ts'] as num?)?.toInt() ?? 0;
        if (duration <= 0) {
          map.remove(key);
          dirty = true;
          continue;
        }
        try {
          await api.recordPlayback(
            itemGuid: (entry['itemGuid'] ?? '').toString(),
            mediaGuid: (entry['mediaGuid'] ?? '').toString(),
            videoGuid: (entry['videoGuid'] ?? '').toString(),
            audioGuid: (entry['audioGuid'] ?? '').toString(),
            subtitleGuid: (entry['subtitleGuid'] ?? '').toString(),
            resolution: (entry['resolution'] ?? '').toString(),
            bitrate: (entry['bitrate'] as num?)?.toInt() ?? 0,
            ts: ts.clamp(0, duration),
            duration: duration,
            playLink: (entry['playLink'] ?? '').toString(),
          );
          map.remove(key);
          dirty = true;
        } catch (e) {
          final ex = AppException.from(e, action: 'playback record');
          if (ex.isTransient) {
            // 网络仍未恢复：保留剩余条目，下次再试。
            break;
          }
          // 鉴权/数据/致命：重放也不会成功，丢弃避免堆积。
          map.remove(key);
          dirty = true;
        }
      }
      if (dirty) {
        if (map.isEmpty) {
          await prefs.remove(_prefsKey);
        } else {
          await prefs.setString(_prefsKey, jsonEncode(map));
        }
      }
    } catch (_) {
      // 重放失败静默，条目仍在盘上，下次再试。
    } finally {
      _flushing = false;
    }
  }

  static Map<String, dynamic> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static List<String> _sortedByEnqueuedAt(Map<String, dynamic> map) {
    return map.keys.toList()..sort((a, b) {
      final ea = ((map[a] as Map?)?['enqueuedAt'] as num?)?.toInt() ?? 0;
      final eb = ((map[b] as Map?)?['enqueuedAt'] as num?)?.toInt() ?? 0;
      return ea.compareTo(eb);
    });
  }

  static void _trim(Map<String, dynamic> map) {
    if (map.length <= _maxEntries) return;
    final keys = _sortedByEnqueuedAt(map);
    final removeCount = map.length - _maxEntries;
    for (var i = 0; i < removeCount; i++) {
      map.remove(keys[i]);
    }
  }

  static Map<String, dynamic> _readServer(SharedPreferences prefs) {
    final raw = prefs.getString(_serverPrefsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static List<String> _sortedServerKeys(Map<String, dynamic> entries) {
    return entries.keys.toList()..sort((a, b) {
      final aTime = ((entries[a] as Map?)?['enqueuedAt'] as num?)?.toInt() ?? 0;
      final bTime = ((entries[b] as Map?)?['enqueuedAt'] as num?)?.toInt() ?? 0;
      return aTime.compareTo(bTime);
    });
  }

  static void _trimServer(Map<String, dynamic> entries) {
    if (entries.length <= _maxEntries) return;
    final keys = _sortedServerKeys(entries);
    final removeCount = entries.length - _maxEntries;
    for (var index = 0; index < removeCount; index++) {
      entries.remove(keys[index]);
    }
  }
}
