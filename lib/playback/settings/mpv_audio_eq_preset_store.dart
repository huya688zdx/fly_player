import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'mpv_settings_store.dart';

class MpvAudioEqPresetEntry {
  final String id;
  final String name;
  final Map<String, String> bands;
  final int updatedAtMillis;

  const MpvAudioEqPresetEntry({
    required this.id,
    required this.name,
    required this.bands,
    required this.updatedAtMillis,
  });

  factory MpvAudioEqPresetEntry.fromJson(Map<String, dynamic> json) {
    final rawBands = json['bands'];
    final nextBands = <String, String>{};
    if (rawBands is Map) {
      for (final band in MpvSettingsCatalog.audioEqBands) {
        final rawValue = rawBands[band.key]?.toString() ?? '0';
        nextBands[band.key] = MpvSettingsCatalog.normalizeAudioEqBandValue(
          double.tryParse(rawValue) ?? 0,
        );
      }
    }
    return MpvAudioEqPresetEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed preset',
      bands: nextBands,
      updatedAtMillis:
          int.tryParse(json['updatedAtMillis']?.toString() ?? '') ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'bands': bands,
    'updatedAtMillis': updatedAtMillis,
  };
}

class MpvAudioEqPresetStore {
  static const String _prefKey = 'player_mpv_audio_eq_presets';

  const MpvAudioEqPresetStore();

  Future<List<MpvAudioEqPresetEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.trim().isEmpty) return <MpvAudioEqPresetEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <MpvAudioEqPresetEntry>[];
      return decoded
          .whereType<Map>()
          .map(
            (entry) => MpvAudioEqPresetEntry.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .where((entry) => entry.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return <MpvAudioEqPresetEntry>[];
    }
  }

  Future<List<MpvAudioEqPresetEntry>> savePreset({
    required String name,
    required Map<String, String> bands,
    String? id,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return load();
    }
    final next = (await load()).toList(growable: true);
    final entry = MpvAudioEqPresetEntry(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmedName,
      bands: _normalizeBands(bands),
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final index = next.indexWhere((item) => item.id == entry.id);
    if (index >= 0) {
      next[index] = entry;
    } else {
      next.insert(0, entry);
    }
    await _saveAll(next);
    return next;
  }

  Future<List<MpvAudioEqPresetEntry>> deletePreset(String id) async {
    final next = (await load())
        .where((entry) => entry.id != id)
        .toList(growable: false);
    await _saveAll(next);
    return next;
  }

  Map<String, String> _normalizeBands(Map<String, String> bands) {
    final next = <String, String>{};
    for (final band in MpvSettingsCatalog.audioEqBands) {
      final rawValue = bands[band.key] ?? '0';
      next[band.key] = MpvSettingsCatalog.normalizeAudioEqBandValue(
        double.tryParse(rawValue) ?? 0,
      );
    }
    return next;
  }

  Future<void> _saveAll(List<MpvAudioEqPresetEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      entries.map((entry) => entry.toJson()).toList(growable: false),
    );
    await prefs.setString(_prefKey, payload);
  }
}
