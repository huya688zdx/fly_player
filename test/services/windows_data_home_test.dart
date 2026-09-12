import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/services/windows_data_home.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unset data home preserves legacy provider and relative paths fail',
    () async {
      final original = PathProviderPlatform.instance;
      await initializeWindowsDataHome(rootOverride: '');
      expect(identical(PathProviderPlatform.instance, original), isTrue);
      expect(resolveFlyDataHome(''), isNull);
      expect(() => resolveFlyDataHome('relative/data'), throwsFormatException);
      if (Platform.isWindows) {
        expect(() => resolveFlyDataHome(r'\profile'), throwsFormatException);
      }
    },
  );

  test(
    'opt-in E home directs preferences and application paths without moving legacy files',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'fly-data-home-test-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final old = File(p.join(temporary.path, 'existing-original.txt'));
      await old.writeAsString('preserve original');
      final root = p.join(temporary.path, 'isolated');
      await initializeWindowsDataHome(rootOverride: root);
      expect(
        (await getApplicationSupportDirectory()).path,
        p.join(root, 'support'),
      );
      expect(
        (await getApplicationCacheDirectory()).path,
        p.join(root, 'cache'),
      );
      expect((await getTemporaryDirectory()).path, p.join(root, 'tmp'));
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('isolated_test_only', 'no credentials');
      expect(
        await File(p.join(root, 'support', 'shared_preferences.json')).exists(),
        isTrue,
      );
      expect(await old.readAsString(), 'preserve original');
      expect(resolveFlyDataHome(root), root);
    },
    skip: !Platform.isWindows,
  );
}
