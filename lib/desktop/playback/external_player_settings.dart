import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class ExternalPlayerSettings {
  static const _preferenceKey = 'desktop_external_player_v1';
  static const _executableNames = <String>[
    'PotPlayerMini64.exe',
    'PotPlayerMini.exe',
  ];

  const ExternalPlayerSettings({
    this.enabled = false,
    this.executablePath = '',
  });

  final bool enabled;
  final String executablePath;

  static Future<ExternalPlayerSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_preferenceKey);
    if (stored == null) return const ExternalPlayerSettings();
    try {
      final value = jsonDecode(stored);
      if (value is! Map<String, dynamic>) {
        return const ExternalPlayerSettings();
      }
      return ExternalPlayerSettings(
        enabled: value['enabled'] == true,
        executablePath: value['executablePath'] is String
            ? (value['executablePath'] as String).trim()
            : '',
      );
    } on FormatException {
      return const ExternalPlayerSettings();
    }
  }

  Future<void> save() async {
    if (enabled) {
      final error = await validateExecutable(executablePath);
      if (error != null) throw StateError(error);
    }
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _preferenceKey,
      jsonEncode(<String, Object>{
        'enabled': enabled,
        'executablePath': executablePath.trim(),
      }),
    );
    if (!saved) throw StateError('无法保存外部播放器设置，请重试。');
  }

  static Future<String?> validateExecutable(String executablePath) async {
    if (!Platform.isWindows) return '外部播放器接入目前仅支持 Windows。';
    final candidate = executablePath.trim();
    if (candidate.isEmpty) return '请先选择或自动查找 PotPlayer 程序。';
    final name = path.windows.basename(candidate).toLowerCase();
    if (!_executableNames.any((value) => value.toLowerCase() == name)) {
      return '请选择 PotPlayerMini64.exe 或 PotPlayerMini.exe。';
    }
    if (!await File(candidate).exists()) return '程序文件不存在，请重新选择 PotPlayer。';
    return null;
  }

  static Future<String?> detectExecutable() async {
    if (!Platform.isWindows) return null;
    for (final hive in const <String>['HKCU', 'HKLM']) {
      for (final name in _executableNames) {
        for (final view in const <String>['64', '32']) {
          try {
            final result = await Process.run('reg.exe', <String>[
              'query',
              '$hive\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\$name',
              '/ve',
              '/reg:$view',
            ]);
            if (result.exitCode != 0) continue;
            final match = RegExp(
              r'REG_(?:EXPAND_)?SZ\s+(.+)',
            ).firstMatch(result.stdout as String);
            var candidate = match?.group(1)?.trim() ?? '';
            candidate = candidate.replaceAll('"', '');
            candidate = candidate.replaceAllMapped(RegExp(r'%([^%]+)%'), (
              match,
            ) {
              return Platform.environment[match.group(1)!] ?? match.group(0)!;
            });
            if (await validateExecutable(candidate) == null) return candidate;
          } on ProcessException {
            // 注册表不可用时继续检查常见安装目录。
          }
        }
      }
    }
    for (final variable in const <String>[
      'ProgramFiles',
      'ProgramFiles(x86)',
    ]) {
      final root = Platform.environment[variable];
      if (root == null || root.isEmpty) continue;
      for (final directory in const <String>[
        'DAUM\\PotPlayer',
        'DAUM\\PotPlayer-64',
        'PotPlayer',
      ]) {
        for (final name in _executableNames) {
          final candidate = path.windows.join(root, directory, name);
          if (await validateExecutable(candidate) == null) return candidate;
        }
      }
    }
    return null;
  }
}
