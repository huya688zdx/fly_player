import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/services/storage_management_host.dart';
import 'package:fly_player/services/storage_management_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认宿主：测试环境选择通道宿主，兼容既有 mock', () {
    expect(
      StorageManagementService.debugHost,
      isA<MethodChannelStorageManagementHost>(),
    );
  });

  test('桌面宿主下 loadOverview 不依赖原生通道且播放缓存项归零', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    StorageManagementService.setHostForTesting(
      const DesktopStorageManagementHost(),
    );
    addTearDown(() => StorageManagementService.setHostForTesting(null));

    final overview = await StorageManagementService.instance.loadOverview(
      lookupAppLocalizations(const Locale('zh')),
    );

    final playback = overview.items.firstWhere(
      (item) => item.kind == StorageItemKind.playbackCache,
    );
    expect(playback.bytes, 0);
    expect(playback.clearDisabled, isFalse);
    expect(playback.note, isNull);
  });
}
