import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../media_backend/media_backend_kind.dart';

/// 表示一次登录记录的持久化内容。
class LoginHistoryEntry {
  /// 该登录记录对应的后端类型（飞牛 / Emby）。
  ///
  /// 旧版本历史不带该字段，反序列化时默认按 [MediaBackendKind.feiniu] 迁移。
  final MediaBackendKind kind;
  final String baseUrl;
  final String userName;
  final String password;
  final bool rememberPassword;
  final int updatedAtMillis;

  /// 根据登录信息构造历史记录对象。
  const LoginHistoryEntry({
    this.kind = MediaBackendKind.feiniu,
    required this.baseUrl,
    required this.userName,
    required this.password,
    required this.rememberPassword,
    required this.updatedAtMillis,
  });

  /// 从持久化映射恢复登录记录。
  factory LoginHistoryEntry.fromJson(Map<String, dynamic> json) {
    final kindName = (json['kind'] ?? '').toString();
    final kind = MediaBackendKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => MediaBackendKind.feiniu,
    );
    return LoginHistoryEntry(
      kind: kind,
      baseUrl: (json['baseUrl'] ?? '').toString(),
      userName: (json['userName'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      rememberPassword: json['rememberPassword'] != false,
      updatedAtMillis: (json['updatedAtMillis'] as num?)?.toInt() ?? 0,
    );
  }

  /// 将登录记录序列化为可持久化映射。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': kind.name,
      'baseUrl': baseUrl,
      'userName': userName,
      'password': password,
      'rememberPassword': rememberPassword,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  String get dedupeKey => '${kind.name}::${baseUrl.trim()}::${userName.trim()}';
}

/// 管理登录历史记录的读取与写入。
class LoginHistoryStore {
  static const String _historyKey = 'login_history_v1';
  static const int _maxHistoryCount = 10;

  const LoginHistoryStore._();

  /// 读取并按最近更新时间排序返回登录历史。
  static Future<List<LoginHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawEntries = prefs.getStringList(_historyKey) ?? const <String>[];
    final entries = <LoginHistoryEntry>[];
    for (final raw in rawEntries) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final entry = LoginHistoryEntry.fromJson(decoded);
          if (entry.baseUrl.trim().isNotEmpty &&
              entry.userName.trim().isNotEmpty) {
            entries.add(entry);
          }
        }
      } catch (_) {
        continue;
      }
    }
    entries.sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    return entries;
  }

  /// 保存一条登录历史，并按去重规则返回最新列表。
  static Future<List<LoginHistoryEntry>> save(LoginHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final next = <LoginHistoryEntry>[
      entry,
      ...current.where((item) => item.dedupeKey != entry.dedupeKey),
    ];
    if (next.length > _maxHistoryCount) {
      next.removeRange(_maxHistoryCount, next.length);
    }
    await prefs.setStringList(
      _historyKey,
      next.map((item) => jsonEncode(item.toJson())).toList(growable: false),
    );
    return next;
  }

  /// 删除指定登录历史，并返回更新后的列表。
  static Future<List<LoginHistoryEntry>> remove(LoginHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final next = current
        .where((item) => item.dedupeKey != entry.dedupeKey)
        .toList(growable: false);
    await prefs.setStringList(
      _historyKey,
      next.map((item) => jsonEncode(item.toJson())).toList(growable: false),
    );
    return next;
  }

  /// 清空全部登录历史记录。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
