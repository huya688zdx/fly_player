import 'dart:io';

import 'package:path/path.dart' as path;

import '../../l10n/generated/app_localizations.dart';
import 'external_player_adapter.dart';
import 'potplayer_session.dart';

/// PotPlayer 的路径发现、播放列表导出与原生通道适配。
class PotPlayerAdapter implements ExternalPlayerAdapter {
  const PotPlayerAdapter();

  static const _executableNames = <String>[
    'PotPlayerMini64.exe',
    'PotPlayerMini.exe',
  ];

  @override
  String get id => 'potplayer';

  @override
  String get displayName => 'PotPlayer';

  @override
  String get executableHint =>
      r'C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe';

  @override
  List<String> get fileExtensions => const <String>['exe'];

  @override
  String usageNotes(AppLocalizations l10n) =>
      l10n.externalPlaybackPotPlayerUsageNotes;

  @override
  bool get supportsSubtitles => true;

  @override
  bool get supportsPlaylist => true;

  @override
  bool get supportsMiniPlayer => true;

  @override
  Future<String?> validateExecutable(
    String executablePath, {
    required AppLocalizations l10n,
  }) async {
    if (!Platform.isWindows) return l10n.externalPlaybackWindowsOnly;
    final candidate = executablePath.trim();
    if (candidate.isEmpty) return l10n.externalPlaybackChoosePlayer;
    final name = path.windows.basename(candidate).toLowerCase();
    if (!_executableNames.any((value) => value.toLowerCase() == name)) {
      return l10n.externalPlaybackChoosePotPlayerBinary;
    }
    if (!await File(candidate).exists()) {
      return l10n.externalPlaybackPlayerMissing;
    }
    return null;
  }

  @override
  Future<String?> detectExecutable({required AppLocalizations l10n}) async {
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
            candidate = candidate.replaceAllMapped(
              RegExp(r'%([^%]+)%'),
              (match) =>
                  Platform.environment[match.group(1)!] ?? match.group(0)!,
            );
            if (await validateExecutable(candidate, l10n: l10n) == null) {
              return candidate;
            }
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
          if (await validateExecutable(candidate, l10n: l10n) == null) {
            return candidate;
          }
        }
      }
    }
    return null;
  }

  @override
  Future<String> writePlaylist({
    required Directory directory,
    required String currentUrl,
    required Map<String, String> titlesByUrl,
  }) async {
    String line(String value) => value.replaceAll(RegExp(r'[\r\n]'), ' ');
    final lines = <String>[
      '\uFEFFDAUMPLAYLIST',
      'playname=${line(currentUrl)}',
      'playtime=0',
      'topindex=0',
    ];
    var index = 1;
    for (final entry in titlesByUrl.entries) {
      lines.add('$index*file*${line(entry.key)}');
      lines.add('$index*title*${line(entry.value)}');
      index++;
    }
    final file = File('${directory.path}/playlist.dpl');
    await file.writeAsString(lines.join('\r\n'), flush: true);
    return file.path;
  }

  @override
  Future<ExternalPlayerSession> launch({
    required String executablePath,
    required String url,
    required String mediaUrl,
    required Duration startPosition,
    required String title,
    required Map<String, String> headers,
    required bool Function() isCurrentSession,
    required void Function(Duration position, Duration duration, bool paused)
    onProgress,
    required Future<void> Function() onFinished,
    required void Function(String message) onError,
    required AppLocalizations l10n,
    Future<Duration?> Function(String mediaUrl)? onMediaChanged,
  }) async {
    final pid = await PotPlayerSession.channel.invokeMethod<int>('launch', {
      'executable': executablePath,
      'url': url,
      'startMs': startPosition.inMilliseconds,
      'title': title,
      'headers': headers,
    });
    if (pid == null || pid <= 0) {
      throw StateError(l10n.externalPotPlayerLaunchFailed);
    }
    return PotPlayerSession(
      pid: pid,
      l10n: l10n,
      mediaUrl: mediaUrl,
      isCurrentSession: isCurrentSession,
      onProgress: onProgress,
      onFinished: onFinished,
      onError: onError,
      onMediaChanged: onMediaChanged,
    );
  }

  @override
  Future<void> setMiniPinned(bool pinned) =>
      PotPlayerSession.channel.invokeMethod<void>('setMiniPinned', pinned);
}
