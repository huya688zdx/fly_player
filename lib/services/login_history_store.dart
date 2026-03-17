import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LoginHistoryEntry {
  final String baseUrl;
  final String userName;
  final String password;
  final bool rememberPassword;
  final int updatedAtMillis;

  const LoginHistoryEntry({
    required this.baseUrl,
    required this.userName,
    required this.password,
    required this.rememberPassword,
    required this.updatedAtMillis,
  });

  factory LoginHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LoginHistoryEntry(
      baseUrl: (json['baseUrl'] ?? '').toString(),
      userName: (json['userName'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      rememberPassword: json['rememberPassword'] != false,
      updatedAtMillis: (json['updatedAtMillis'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'baseUrl': baseUrl,
      'userName': userName,
      'password': password,
      'rememberPassword': rememberPassword,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  String get dedupeKey => '${baseUrl.trim()}::${userName.trim()}';
}

class LoginHistoryStore {
  static const String _historyKey = 'login_history_v1';
  static const int _maxHistoryCount = 10;

  const LoginHistoryStore._();

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

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
