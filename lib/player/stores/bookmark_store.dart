import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerBookmarkEntry {
  final String id;
  final String itemGuid;
  final String mediaGuid;
  final String mediaType;
  final String ancestorName;
  final String title;
  final String seriesTitle;
  final int seasonNumber;
  final int episodeNumber;
  final int positionMs;
  final int durationSeconds;
  final int createdAtMs;
  final String note;

  const PlayerBookmarkEntry({
    required this.id,
    required this.itemGuid,
    required this.mediaGuid,
    required this.mediaType,
    required this.ancestorName,
    required this.title,
    required this.seriesTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.positionMs,
    required this.durationSeconds,
    required this.createdAtMs,
    this.note = '',
  });

  Duration get position => Duration(milliseconds: positionMs);

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: false);

  String get identityKey {
    final item = itemGuid.trim();
    final media = mediaGuid.trim();
    if (item.isNotEmpty && media.isNotEmpty) return '$item::$media';
    if (item.isNotEmpty) return item;
    return media;
  }

  PlayerBookmarkEntry copyWith({
    String? id,
    String? itemGuid,
    String? mediaGuid,
    String? mediaType,
    String? ancestorName,
    String? title,
    String? seriesTitle,
    int? seasonNumber,
    int? episodeNumber,
    int? positionMs,
    int? durationSeconds,
    int? createdAtMs,
    String? note,
  }) {
    return PlayerBookmarkEntry(
      id: id ?? this.id,
      itemGuid: itemGuid ?? this.itemGuid,
      mediaGuid: mediaGuid ?? this.mediaGuid,
      mediaType: mediaType ?? this.mediaType,
      ancestorName: ancestorName ?? this.ancestorName,
      title: title ?? this.title,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      positionMs: positionMs ?? this.positionMs,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'itemGuid': itemGuid,
      'mediaGuid': mediaGuid,
      'mediaType': mediaType,
      'ancestorName': ancestorName,
      'title': title,
      'seriesTitle': seriesTitle,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'positionMs': positionMs,
      'durationSeconds': durationSeconds,
      'createdAtMs': createdAtMs,
      'note': note,
    };
  }

  static PlayerBookmarkEntry? fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim() ?? '';
    final itemGuid = json['itemGuid']?.toString().trim() ?? '';
    final mediaGuid = json['mediaGuid']?.toString().trim() ?? '';
    final positionMs = _readInt(json['positionMs']);
    if (id.isEmpty || positionMs == null) return null;
    return PlayerBookmarkEntry(
      id: id,
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
      mediaType: json['mediaType']?.toString() ?? '',
      ancestorName: json['ancestorName']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      seriesTitle: json['seriesTitle']?.toString() ?? '',
      seasonNumber: _readInt(json['seasonNumber']) ?? 0,
      episodeNumber: _readInt(json['episodeNumber']) ?? 0,
      positionMs: positionMs,
      durationSeconds: _readInt(json['durationSeconds']) ?? 0,
      createdAtMs:
          _readInt(json['createdAtMs']) ??
          DateTime.now().millisecondsSinceEpoch,
      note: json['note']?.toString() ?? '',
    );
  }

  static int? _readInt(Object? value) {
    return switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v),
      _ => null,
    };
  }
}

class BookmarkStore {
  static const String _prefKey = 'player_bookmarks_v1';
  static const int duplicateMergeToleranceMs = 3000;
  static const int maxPerMedia = 30;
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  const BookmarkStore();

  ValueListenable<int> get changes => _revision;

  Future<List<PlayerBookmarkEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey) ?? '';
    if (raw.trim().isEmpty) return <PlayerBookmarkEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <PlayerBookmarkEntry>[];
      final entries = <PlayerBookmarkEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final parsed = PlayerBookmarkEntry.fromJson(
          Map<String, Object?>.from(item),
        );
        if (parsed != null) entries.add(parsed);
      }
      entries.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return entries;
    } catch (_) {
      return <PlayerBookmarkEntry>[];
    }
  }

  Future<List<PlayerBookmarkEntry>> loadForMedia({
    required String itemGuid,
    required String mediaGuid,
  }) async {
    final identityKey = _identityKey(itemGuid: itemGuid, mediaGuid: mediaGuid);
    final all = await loadAll();
    return all
        .where((entry) => entry.identityKey == identityKey)
        .toList(growable: false)
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
  }

  Future<PlayerBookmarkEntry> add({
    required String itemGuid,
    required String mediaGuid,
    required String mediaType,
    required String ancestorName,
    required String title,
    required String seriesTitle,
    required int seasonNumber,
    required int episodeNumber,
    required Duration position,
    required int durationSeconds,
    String note = '',
  }) async {
    final all = await loadAll();
    final now = DateTime.now().millisecondsSinceEpoch;
    final identityKey = _identityKey(itemGuid: itemGuid, mediaGuid: mediaGuid);
    final positionMs = position.inMilliseconds;
    final existingIndex = all.indexWhere(
      (entry) =>
          entry.identityKey == identityKey &&
          (entry.positionMs - positionMs).abs() <= duplicateMergeToleranceMs,
    );
    final nextEntry = PlayerBookmarkEntry(
      id: existingIndex >= 0 ? all[existingIndex].id : 'bookmark_$now',
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
      mediaType: mediaType,
      ancestorName: ancestorName,
      title: title,
      seriesTitle: seriesTitle,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      positionMs: positionMs,
      durationSeconds: durationSeconds,
      createdAtMs: now,
      note: note.trim(),
    );
    if (existingIndex >= 0) {
      all[existingIndex] = nextEntry;
    } else {
      all.add(nextEntry);
    }
    _trimPerMedia(all, identityKey);
    await _saveAll(all);
    _notifyChanged();
    return nextEntry;
  }

  Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((entry) => entry.id == id);
    await _saveAll(all);
    _notifyChanged();
  }

  Future<void> updateNote({required String id, required String note}) async {
    final all = await loadAll();
    final index = all.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    all[index] = all[index].copyWith(note: note.trim());
    await _saveAll(all);
    _notifyChanged();
  }

  Future<void> clearForMedia({
    required String itemGuid,
    required String mediaGuid,
  }) async {
    final identityKey = _identityKey(itemGuid: itemGuid, mediaGuid: mediaGuid);
    final all = await loadAll();
    all.removeWhere((entry) => entry.identityKey == identityKey);
    await _saveAll(all);
    _notifyChanged();
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    _notifyChanged();
  }

  Future<void> _saveAll(List<PlayerBookmarkEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(entries.map((entry) => entry.toJson()).toList());
    await prefs.setString(_prefKey, raw);
  }

  void _trimPerMedia(List<PlayerBookmarkEntry> entries, String identityKey) {
    final matching =
        entries
            .where((entry) => entry.identityKey == identityKey)
            .toList(growable: false)
          ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    if (matching.length <= maxPerMedia) return;
    final removeIds = matching
        .skip(maxPerMedia)
        .map((entry) => entry.id)
        .toSet();
    entries.removeWhere((entry) => removeIds.contains(entry.id));
  }

  String _identityKey({required String itemGuid, required String mediaGuid}) {
    final item = itemGuid.trim();
    final media = mediaGuid.trim();
    if (item.isNotEmpty && media.isNotEmpty) return '$item::$media';
    if (item.isNotEmpty) return item;
    return media;
  }

  void _notifyChanged() {
    _revision.value++;
  }
}
