import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 手动导入的本地字幕（原生壳 SAF 添加）的持久化存储。
///
/// 与原生侧 [NativeSubtitleImportStore] 共享同一个 SharedPreferences 键
/// `flutter.manual_local_subtitles_v1`（Flutter shared_preferences 插件在键名前
/// 自动加 `flutter.` 前缀），原生壳直读同一份元数据，两端严格一致。
///
/// 字幕文件本体存应用私有外部目录（原生 `subtitlesDir`），本 store 持久化元数据
/// 与每集最后选择，并在删除时协调清理文件、元数据和选择记录。
class ManualSubtitleStore {
  /// 存储键（不含 `flutter.` 前缀；SharedPreferences 实际键为 `flutter.` + 此值）。
  static const String prefKey = 'manual_local_subtitles_v1';

  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// 所有写方法（读整体 payload → 改 → 整体写回）串行化到同一条队列上，
  /// 避免并发写入时后完成的整体覆盖写丢失先完成的改动。
  static Future<void> _mutationQueue = Future<void>.value();

  const ManualSubtitleStore();

  static const int stateVersion = 2;

  /// 数据变更版本号；详情页可订阅它刷新本地字幕轨列表。
  ValueListenable<int> get revision => _revision;

  /// 持久化选择作用域：优先用跨画质稳定的 itemGuid，缺失时回退 mediaGuid。
  static String scopeKey(String itemGuid, String mediaGuid) {
    final normalizedItem = itemGuid.trim();
    if (normalizedItem.isNotEmpty) return 'item:$normalizedItem';
    final normalizedMedia = mediaGuid.trim();
    return normalizedMedia.isEmpty ? '' : 'media:$normalizedMedia';
  }

  /// 加载某媒体的全部本地字幕（按导入时间倒序）。
  Future<List<ManualSubtitleEntry>> loadForMedia(String mediaGuid) async {
    final normalized = mediaGuid.trim();
    if (normalized.isEmpty) return const <ManualSubtitleEntry>[];
    final all = await loadAll();
    return all.where((e) => e.mediaGuid == normalized).toList(growable: false);
  }

  /// 加载某条目的全部本地字幕（按 itemGuid 匹配）。
  ///
  /// 原生导入时 mediaGuid 经过画质归一化可能与详情页 stream option 的 mediaGuid 不一致，
  /// 而 itemGuid 稳定不变；详情页按条目查询更可靠。无匹配时回退按 mediaGuid 查询。
  Future<List<ManualSubtitleEntry>> loadForItem(
    String itemGuid, {
    String mediaGuid = '',
  }) async {
    final normalizedItem = itemGuid.trim();
    final normalizedMedia = mediaGuid.trim();
    final all = await loadAll();
    if (normalizedItem.isNotEmpty) {
      final byItem = all
          .where((e) => e.itemGuid == normalizedItem)
          .toList(growable: false);
      if (byItem.isNotEmpty) return byItem;
    }
    if (normalizedMedia.isNotEmpty) {
      return all
          .where((e) => e.mediaGuid == normalizedMedia)
          .toList(growable: false);
    }
    return const <ManualSubtitleEntry>[];
  }

  /// 加载全量本地字幕（跨媒体）。
  Future<List<ManualSubtitleEntry>> loadAll() async {
    final payload = await _loadPayload();
    final rawList =
        (payload['entries'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (item) =>
                  ManualSubtitleEntry.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((e) => e.guid.trim().isNotEmpty)
            .toList(growable: false)
          ..sort(
            (left, right) => right.importedAtMs.compareTo(left.importedAtMs),
          );
    return rawList;
  }

  /// 读取某条目最后选择的手动字幕；条目作用域不存在时回退媒体作用域。
  Future<String?> selectedGuidForItem(
    String itemGuid, {
    String mediaGuid = '',
  }) async {
    final payload = await _loadPayload();
    final selected = _selectedByScope(payload);
    final normalizedItem = itemGuid.trim();
    if (normalizedItem.isNotEmpty) {
      final byItem = selected['item:$normalizedItem']?.trim() ?? '';
      if (byItem.isNotEmpty) return byItem;
    }
    final normalizedMedia = mediaGuid.trim();
    if (normalizedMedia.isEmpty) return null;
    final byMedia = selected['media:$normalizedMedia']?.trim() ?? '';
    return byMedia.isEmpty ? null : byMedia;
  }

  /// 更新某条目最后选择的手动字幕；[guid] 为空表示切回内嵌字幕或关闭字幕。
  Future<void> setSelectedGuid({
    required String itemGuid,
    required String mediaGuid,
    String? guid,
  }) {
    return _enqueueMutation(() async {
      final scope = scopeKey(itemGuid, mediaGuid);
      if (scope.isEmpty) return;
      final payload = await _loadPayload();
      final selected = _selectedByScope(payload);
      final normalizedGuid = guid?.trim() ?? '';
      if (normalizedGuid.isEmpty) {
        selected.remove(scope);
      } else {
        selected[scope] = normalizedGuid;
      }
      payload['selectedByScope'] = selected;
      await _savePayload(payload);
      _revision.value++;
    });
  }

  /// 新增一条本地字幕；同 path 已存在则覆盖（保持同文件只留一条）。
  Future<void> add(ManualSubtitleEntry entry) {
    return _enqueueMutation(() => _add(entry));
  }

  Future<void> _add(ManualSubtitleEntry entry) async {
    if (entry.guid.trim().isEmpty) return;
    final payload = await _loadPayload();
    final originalEntries =
        (payload['entries'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (item) =>
                  ManualSubtitleEntry.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false);
    final displacedGuids = originalEntries
        .where((item) => item.path == entry.path && item.guid != entry.guid)
        .map((item) => item.guid)
        .toSet();
    final entries = originalEntries
        // 按 guid 或 path 去重：同一文件（path 相同）只保留一条；同 guid 覆盖。
        .where((item) => item.guid != entry.guid && item.path != entry.path)
        .toList(growable: true);
    entries.add(entry);
    payload['entries'] = entries.map((e) => e.toJson()).toList(growable: false);
    if (displacedGuids.isNotEmpty) {
      final selected = _selectedByScope(payload)
        ..removeWhere(
          (_, selectedGuid) => displacedGuids.contains(selectedGuid),
        );
      payload['selectedByScope'] = selected;
    }
    await _savePayload(payload);
    _revision.value++;
  }

  /// 删除指定 guid 的字幕；返回被删项（供调用方删除对应文件），不存在返回 null。
  Future<ManualSubtitleEntry?> removeByGuid(String guid) {
    return _enqueueMutation(() => _removeByGuid(guid));
  }

  Future<ManualSubtitleEntry?> _removeByGuid(String guid) async {
    if (guid.trim().isEmpty) return null;
    final payload = await _loadPayload();
    final entries = (payload['entries'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) =>
              ManualSubtitleEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: true);
    final removedIndex = entries.indexWhere((e) => e.guid == guid);
    if (removedIndex < 0) return null;
    final removed = entries.removeAt(removedIndex);
    payload['entries'] = entries.map((e) => e.toJson()).toList(growable: false);
    final selected = _selectedByScope(payload)
      ..removeWhere((_, selectedGuid) => selectedGuid == removed.guid);
    payload['selectedByScope'] = selected;
    await _savePayload(payload);
    _revision.value++;
    return removed;
  }

  /// 删除某媒体的全部本地字幕；返回被删项列表（供调用方删除对应文件）。
  Future<List<ManualSubtitleEntry>> removeAllForMedia(String mediaGuid) {
    return _enqueueMutation(() => _removeAllForMedia(mediaGuid));
  }

  Future<List<ManualSubtitleEntry>> _removeAllForMedia(String mediaGuid) async {
    if (mediaGuid.trim().isEmpty) return const <ManualSubtitleEntry>[];
    final payload = await _loadPayload();
    final entries = (payload['entries'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) =>
              ManualSubtitleEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: true);
    final removed = <ManualSubtitleEntry>[];
    entries.removeWhere((e) {
      final match = e.mediaGuid == mediaGuid;
      if (match) removed.add(e);
      return match;
    });
    payload['entries'] = entries.map((e) => e.toJson()).toList(growable: false);
    final removedGuids = removed.map((entry) => entry.guid).toSet();
    final selected = _selectedByScope(payload)
      ..removeWhere((_, selectedGuid) => removedGuids.contains(selectedGuid));
    payload['selectedByScope'] = selected;
    await _savePayload(payload);
    _revision.value++;
    return removed;
  }

  /// 删除字幕文件及其元数据。文件删除失败时保留元数据与选择，避免产生不可见孤儿文件。
  Future<bool> deleteByGuid(
    String guid, {
    Future<bool> Function(String path)? deleteFile,
  }) {
    return _enqueueMutation(() async {
      final normalized = guid.trim();
      if (normalized.isEmpty) return false;
      final payload = await _loadPayload();
      final entries =
          (payload['entries'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (item) => ManualSubtitleEntry.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: true);
      final removedIndex = entries.indexWhere(
        (entry) => entry.guid == normalized,
      );
      if (removedIndex < 0) return false;
      final removed = entries[removedIndex];
      final didDeleteFile = await (deleteFile ?? _deleteLocalFile)(
        removed.path,
      );
      if (!didDeleteFile) return false;

      entries.removeAt(removedIndex);
      payload['entries'] = entries
          .map((entry) => entry.toJson())
          .toList(growable: false);
      final selected = _selectedByScope(payload)
        ..removeWhere((_, selectedGuid) => selectedGuid == removed.guid);
      payload['selectedByScope'] = selected;
      await _savePayload(payload);
      _revision.value++;
      return true;
    });
  }

  static Future<bool> _deleteLocalFile(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return true;
    try {
      final file = File(normalized);
      if (!await file.exists()) return true;
      await file.delete();
      return !await file.exists();
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _loadPayload() async {
    final prefs = await SharedPreferences.getInstance();
    // 原生壳(Kotlin)直接写 FlutterSharedPreferences 文件,Flutter 侧 getInstance 有内存
    // 缓存不会自动刷新;reload() 强制从磁盘重读,确保详情页读到原生刚导入的字幕元数据。
    await prefs.reload();
    final raw = prefs.getString(prefKey) ?? '';
    if (raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) {
        return <String, dynamic>{
          'version': stateVersion,
          'entries': decoded,
          'selectedByScope': <String, String>{},
        };
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _savePayload(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    payload['version'] = stateVersion;
    payload.putIfAbsent('entries', () => <Object?>[]);
    payload.putIfAbsent('selectedByScope', () => <String, String>{});
    await prefs.setString(prefKey, jsonEncode(payload));
  }

  static Map<String, String> _selectedByScope(Map<String, dynamic> payload) {
    final raw = payload['selectedByScope'];
    if (raw is! Map) return <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        if (entry.key.toString().trim().isNotEmpty &&
            entry.value.toString().trim().isNotEmpty)
          entry.key.toString(): entry.value.toString(),
    };
  }

  static Future<T> _enqueueMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mutationQueue = _mutationQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

/// 一条手动导入的本地字幕元数据。
class ManualSubtitleEntry {
  /// 跨会话稳定的 guid，形如 `local:sub:<uuid>`。
  final String guid;

  /// 归属媒体标识。
  final String mediaGuid;

  /// 归属条目标识（可选）。
  final String itemGuid;

  /// 原始显示名（含扩展名）。
  final String fileName;

  /// 应用私有目录中字幕文件的绝对路径。
  final String path;

  /// 小写扩展名（srt/ass/ssa/vtt/sub/idx/lrc/sup/pgs/...）。
  final String format;

  /// 导入时间（毫秒时间戳）。
  final int importedAtMs;

  const ManualSubtitleEntry({
    required this.guid,
    required this.mediaGuid,
    this.itemGuid = '',
    required this.fileName,
    required this.path,
    required this.format,
    required this.importedAtMs,
  });

  /// 是否为位图字幕（PGS/SUP）；本地文件仍通过 mpv `sub-add` 外挂加载。
  bool get isBitmap => format == 'sup' || format == 'pgs';

  factory ManualSubtitleEntry.fromJson(Map<String, dynamic> json) {
    return ManualSubtitleEntry(
      guid: (json['guid'] ?? '').toString(),
      mediaGuid: (json['mediaGuid'] ?? '').toString(),
      itemGuid: (json['itemGuid'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      format: (json['format'] ?? '').toString().trim().toLowerCase(),
      importedAtMs: (json['importedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'guid': guid,
      'mediaGuid': mediaGuid,
      'itemGuid': itemGuid,
      'fileName': fileName,
      'path': path,
      'format': format,
      'importedAtMs': importedAtMs,
    };
  }
}
