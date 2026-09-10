import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 列表展示偏好的本地副本；存储键由调用方按服务器、账号和列表隔离。
class UserListPreferenceStore {
  const UserListPreferenceStore(this.key);

  final String key;

  Future<Map<String, dynamic>?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(value));
    } catch (_) {
      // 本地副本不可写时仍允许服务端同步。
    }
  }
}
