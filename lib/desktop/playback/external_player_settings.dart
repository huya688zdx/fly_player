import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'external_player_adapter.dart';
import 'external_player_adapters.dart';

class ExternalPlayerSettings {
  static const _preferenceKey = 'desktop_external_player_v1';
  const ExternalPlayerSettings({
    this.enabled = false,
    this.executablePath = '',
    this.playerId = ExternalPlayerAdapters.defaultId,
  });

  final bool enabled;
  final String executablePath;
  final String playerId;

  ExternalPlayerAdapter get adapter => ExternalPlayerAdapters.forId(playerId);

  static Future<ExternalPlayerSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_preferenceKey);
    if (stored == null) return const ExternalPlayerSettings();
    try {
      final value = jsonDecode(stored);
      if (value is! Map<String, dynamic>) {
        return const ExternalPlayerSettings();
      }
      final settings = ExternalPlayerSettings(
        enabled: value['enabled'] == true,
        executablePath: value['executablePath'] is String
            ? (value['executablePath'] as String).trim()
            : '',
        playerId: value['playerId'] is String
            ? (value['playerId'] as String).trim()
            : ExternalPlayerAdapters.defaultId,
      );
      settings.adapter;
      return settings;
    } on FormatException {
      return const ExternalPlayerSettings();
    }
  }

  Future<void> save() async {
    final player = adapter;
    if (enabled) {
      final error = await player.validateExecutable(executablePath);
      if (error != null) throw StateError(error);
    }
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _preferenceKey,
      jsonEncode(<String, Object>{
        'enabled': enabled,
        'executablePath': executablePath.trim(),
        'playerId': playerId,
      }),
    );
    if (!saved) throw StateError('无法保存外部播放器设置，请重试。');
  }
}
