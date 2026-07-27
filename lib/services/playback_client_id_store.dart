import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 管理播放请求随身携带的客户端标识：本地生成一次、持久化后长期复用。
class PlaybackClientIdStore {
  static const String _clientIdKey = 'playback_client_id';

  final Random _random = Random();

  /// 创建一个播放客户端标识存储实例。
  PlaybackClientIdStore();

  /// 获取已持久化的客户端标识；不存在则生成新值并写入本地。
  Future<String> ensureClientId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_clientIdKey) ?? '';
    if (existing.trim().isNotEmpty) return existing;

    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final value = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(_clientIdKey, value);
    return value;
  }
}
