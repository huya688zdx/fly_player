import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media_backend/media_backend_kind.dart';
import 'secure_credential_store.dart';

/// 表示一次登录记录的持久化内容。
class LoginHistoryEntry {
  /// 该登录记录对应的后端类型（飞牛 / Emby）。
  ///
  /// 旧版本历史不带该字段，反序列化时默认按 [MediaBackendKind.feiniu] 迁移。
  final MediaBackendKind kind;
  final String baseUrl;
  final String userName;
  final String password;
  final String accessCode;
  final bool rememberPassword;
  final int updatedAtMillis;

  /// 根据登录信息构造历史记录对象。
  const LoginHistoryEntry({
    this.kind = MediaBackendKind.feiniu,
    required this.baseUrl,
    required this.userName,
    required this.password,
    this.accessCode = '',
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
    final snapshot = await _loadSnapshot();
    return snapshot.entries;
  }

  static Future<_LoginHistoryLoadSnapshot> _loadSnapshot({
    SharedPreferences? prefs,
  }) async {
    final targetPrefs = prefs ?? await SharedPreferences.getInstance();
    final rawEntries =
        targetPrefs.getStringList(_historyKey) ?? const <String>[];
    final entries = <LoginHistoryEntry>[];
    final unavailablePasswordKeys = <String>{};
    final unavailableAccessCodeKeys = <String>{};
    var needsRewrite = false;
    for (final raw in rawEntries) {
      late final _ParsedLoginHistoryEntry parsed;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          needsRewrite = true;
          continue;
        }
        if (decoded.containsKey('accessCode')) {
          needsRewrite = true;
        }
        parsed = _ParsedLoginHistoryEntry(
          entry: LoginHistoryEntry.fromJson(decoded),
          legacyPassword: (decoded['password'] ?? '').toString(),
        );
      } catch (_) {
        needsRewrite = true;
        continue;
      }
      // 凭据 I/O 必须位于坏 JSON 容错范围之外，避免安全存储失败被当成无效历史吞掉。
      final restoredPassword = await _restorePassword(
        parsed.entry,
        legacyPassword: parsed.legacyPassword,
      );
      final restoredAccessCode = await _restoreAccessCode(parsed.entry);
      final entry = LoginHistoryEntry(
        kind: parsed.entry.kind,
        baseUrl: parsed.entry.baseUrl,
        userName: parsed.entry.userName,
        password: restoredPassword.value,
        accessCode: restoredAccessCode.value,
        rememberPassword: parsed.entry.rememberPassword,
        updatedAtMillis: parsed.entry.updatedAtMillis,
      );
      if (entry.baseUrl.trim().isNotEmpty && entry.userName.trim().isNotEmpty) {
        entries.add(entry);
        if (!restoredPassword.available) {
          unavailablePasswordKeys.add(_passwordKey(entry));
        } else if (parsed.legacyPassword.isNotEmpty) {
          needsRewrite = true;
        }
        if (!restoredAccessCode.available &&
            entry.kind == MediaBackendKind.feiniu) {
          unavailableAccessCodeKeys.add(_accessCodeKey(entry));
        }
      }
    }
    entries.sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    if (needsRewrite) {
      await _writeEntries(
        targetPrefs,
        entries,
        preserveCredentialKeys: <String>{
          ...unavailablePasswordKeys,
          ...unavailableAccessCodeKeys,
        },
      );
    }
    return _LoginHistoryLoadSnapshot(
      entries: entries,
      unavailablePasswordKeys: unavailablePasswordKeys,
      unavailableAccessCodeKeys: unavailableAccessCodeKeys,
    );
  }

  /// 保存一条登录历史，并按去重规则返回最新列表。
  static Future<List<LoginHistoryEntry>> save(LoginHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = await _loadSnapshot(prefs: prefs);
    final current = snapshot.entries;
    final next = <LoginHistoryEntry>[
      entry,
      ...current.where((item) => item.dedupeKey != entry.dedupeKey),
    ];
    if (next.length > _maxHistoryCount) {
      final removed = next.sublist(_maxHistoryCount);
      for (final item in removed) {
        await _deleteCredentialKeys(item);
      }
      next.removeRange(_maxHistoryCount, next.length);
    }
    for (final item in current.where(
      (item) => !next.any((nextItem) => nextItem.dedupeKey == item.dedupeKey),
    )) {
      await _deleteCredentialKeys(item);
    }
    final preserveCredentialKeys = <String>{
      ...snapshot.unavailablePasswordKeys,
      ...snapshot.unavailableAccessCodeKeys,
    };
    if (!entry.rememberPassword || entry.password.isNotEmpty) {
      preserveCredentialKeys.remove(_passwordKey(entry));
    }
    if (entry.kind == MediaBackendKind.feiniu &&
        (!entry.rememberPassword || entry.accessCode.isNotEmpty)) {
      preserveCredentialKeys.remove(_accessCodeKey(entry));
    }
    await _writeEntries(
      prefs,
      next,
      preserveCredentialKeys: preserveCredentialKeys,
    );
    return next;
  }

  /// 删除指定登录历史，并返回更新后的列表。
  static Future<List<LoginHistoryEntry>> remove(LoginHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = await _loadSnapshot(prefs: prefs);
    final current = snapshot.entries;
    final next = current
        .where((item) => item.dedupeKey != entry.dedupeKey)
        .toList(growable: false);
    await _deleteCredentialKeys(entry);
    final preserveCredentialKeys =
        <String>{
            ...snapshot.unavailablePasswordKeys,
            ...snapshot.unavailableAccessCodeKeys,
          }
          ..remove(_passwordKey(entry))
          ..remove(_accessCodeKey(entry));
    await _writeEntries(
      prefs,
      next,
      preserveCredentialKeys: preserveCredentialKeys,
    );
    return next;
  }

  /// 清空全部登录历史记录。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = await _loadSnapshot(prefs: prefs);
    for (final entry in snapshot.entries) {
      await _deleteCredentialKeys(entry);
    }
    await prefs.remove(_historyKey);
  }

  static Future<({String value, bool available})> _restorePassword(
    LoginHistoryEntry entry, {
    required String legacyPassword,
  }) async {
    if (!entry.rememberPassword) {
      await SecureCredentialStore.delete(_passwordKey(entry));
      return (value: '', available: true);
    }
    final stored = await SecureCredentialStore.read(_passwordKey(entry));
    if (stored.isUnavailable) {
      return (value: '', available: false);
    }
    if (stored.value.isNotEmpty) {
      return (value: stored.value, available: true);
    }
    if (legacyPassword.isNotEmpty) {
      await SecureCredentialStore.write(_passwordKey(entry), legacyPassword);
      return (value: legacyPassword, available: true);
    }
    return (value: '', available: true);
  }

  static Future<({String value, bool available})> _restoreAccessCode(
    LoginHistoryEntry entry,
  ) async {
    if (entry.kind != MediaBackendKind.feiniu) {
      return (value: '', available: true);
    }
    final key = _accessCodeKey(entry);
    if (!entry.rememberPassword) {
      await SecureCredentialStore.delete(key);
      return (value: '', available: true);
    }
    final stored = await SecureCredentialStore.read(key);
    if (stored.isUnavailable) {
      return (value: '', available: false);
    }
    return (value: stored.value, available: true);
  }

  static Future<void> _writeEntries(
    SharedPreferences prefs,
    List<LoginHistoryEntry> entries, {
    Set<String> preserveCredentialKeys = const <String>{},
  }) async {
    for (final entry in entries) {
      final key = _passwordKey(entry);
      if (!preserveCredentialKeys.contains(key)) {
        if (entry.rememberPassword && entry.password.isNotEmpty) {
          await SecureCredentialStore.write(key, entry.password);
        } else {
          await SecureCredentialStore.delete(key);
        }
      }
      if (entry.kind != MediaBackendKind.feiniu) continue;
      final accessCodeKey = _accessCodeKey(entry);
      if (preserveCredentialKeys.contains(accessCodeKey)) continue;
      if (entry.rememberPassword && entry.accessCode.isNotEmpty) {
        await SecureCredentialStore.write(accessCodeKey, entry.accessCode);
      } else {
        await SecureCredentialStore.delete(accessCodeKey);
      }
    }
    await prefs.setStringList(
      _historyKey,
      entries.map((item) => jsonEncode(item.toJson())).toList(growable: false),
    );
  }

  static String _passwordKey(LoginHistoryEntry entry) {
    final digest = sha256.convert(utf8.encode(entry.dedupeKey)).toString();
    return 'login_history.password.$digest';
  }

  static String _accessCodeKey(LoginHistoryEntry entry) {
    final digest = sha256.convert(utf8.encode(entry.dedupeKey)).toString();
    return 'login_history.access_code.$digest';
  }

  static Future<void> _deleteCredentialKeys(LoginHistoryEntry entry) async {
    await SecureCredentialStore.delete(_passwordKey(entry));
    if (entry.kind == MediaBackendKind.feiniu) {
      await SecureCredentialStore.delete(_accessCodeKey(entry));
    }
  }
}

class _LoginHistoryLoadSnapshot {
  final List<LoginHistoryEntry> entries;
  final Set<String> unavailablePasswordKeys;
  final Set<String> unavailableAccessCodeKeys;

  const _LoginHistoryLoadSnapshot({
    required this.entries,
    required this.unavailablePasswordKeys,
    required this.unavailableAccessCodeKeys,
  });
}

class _ParsedLoginHistoryEntry {
  final LoginHistoryEntry entry;
  final String legacyPassword;

  const _ParsedLoginHistoryEntry({
    required this.entry,
    required this.legacyPassword,
  });
}
