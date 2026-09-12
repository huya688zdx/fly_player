import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

/// Optional process-local profile. An unset value keeps the installed profile.
/// No files are copied, migrated or removed by selecting another profile.
String? resolveFlyDataHome([String? value]) {
  final root = (value ?? Platform.environment['FLY_PLAYER_DATA_HOME'] ?? '')
      .trim();
  if (root.isEmpty) return null;
  if (!p.isAbsolute(root) || p.isRootRelative(root)) {
    throw const FormatException(
      'FLY_PLAYER_DATA_HOME must be an absolute path.',
    );
  }
  return p.normalize(root);
}

Future<void> initializeWindowsDataHome({String? rootOverride}) async {
  if (!Platform.isWindows) return;
  final root = resolveFlyDataHome(rootOverride);
  if (root == null) return;
  final provider = _FlyWindowsPaths(root);
  await provider.getApplicationSupportPath();
  await provider.getApplicationCachePath();
  await provider.getTemporaryPath();
  PathProviderPlatform.instance = provider;

  // The existing Windows plugins construct private path providers instead of
  // consulting PathProviderPlatform. Their public injection seam keeps the real
  // JSON persistence/DPAPI behavior intact, with only its directory changed.
  final legacy = SharedPreferencesWindows();
  // ignore: invalid_use_of_visible_for_testing_member
  legacy.pathProvider = provider;
  SharedPreferencesStorePlatform.instance = legacy;
  final asyncPreferences = SharedPreferencesAsyncWindows();
  // ignore: invalid_use_of_visible_for_testing_member
  asyncPreferences.pathProvider = provider;
  SharedPreferencesAsyncPlatform.instance = asyncPreferences;
}

class _FlyWindowsPaths extends PathProviderWindows {
  _FlyWindowsPaths(this.root);
  final String root;

  Future<String> _directory(String name) async {
    final directory = Directory(p.join(root, name));
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> getApplicationSupportPath() => _directory('support');

  @override
  Future<String?> getApplicationCachePath() => _directory('cache');

  @override
  Future<String?> getTemporaryPath() => _directory('tmp');
}
