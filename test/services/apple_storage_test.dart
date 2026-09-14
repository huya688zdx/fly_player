import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/storage_access_host.dart';
import 'package:fly_player/services/app_log_service.dart';
import 'package:fly_player/services/storage_access_service.dart';
import 'package:fly_player/services/storage_management_host.dart';
import 'package:fly_player/services/storage_management_service.dart';

class _SandboxPaths extends PathProviderPlatform {
  _SandboxPaths(this.documents);

  final String documents;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;

  @override
  Future<String?> getDownloadsPath() async => p.join(documents, 'Downloads');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fly_player/storage');
  late List<String> androidCalls;

  setUp(() {
    androidCalls = [];
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      androidCalls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    StorageAccessService.setHostForTesting(null);
    StorageManagementService.setHostForTesting(null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'iOS creates Downloads inside the application Documents sandbox',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final sandbox = await Directory.systemTemp.createTemp('fly-ios-storage-');
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _SandboxPaths(sandbox.path);
      addTearDown(() async {
        PathProviderPlatform.instance = oldPaths;
        await sandbox.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({
        DesktopStorageAccessHost.downloadDirectoryKey: '/desktop-only',
      });

      final directory = await StorageAccessService.downloadDirectory();

      expect(directory, p.join(sandbox.path, 'Downloads'));
      expect(await Directory(directory).exists(), isTrue);
      expect(androidCalls, isEmpty);
    },
  );

  test(
    'macOS does not reuse a custom path without a security scoped bookmark',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _SandboxPaths('/sandbox/Documents');
      addTearDown(() => PathProviderPlatform.instance = oldPaths);
      SharedPreferences.setMockInitialValues({
        DesktopStorageAccessHost.downloadDirectoryKey: '/external/custom',
      });

      expect(
        await StorageAccessService.downloadDirectory(),
        p.join('/sandbox/Documents', 'Downloads'),
      );
    },
  );

  test(
    'iOS log export writes under Downloads/FlyPlayer/logs without Android storage',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final sandbox = await Directory.systemTemp.createTemp('fly-ios-export-');
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _SandboxPaths(sandbox.path);
      addTearDown(() async {
        PathProviderPlatform.instance = oldPaths;
        await sandbox.delete(recursive: true);
      });

      final result = await AppLogService.instance.exportToTxt();

      expect(
        File(result.path).parent.path,
        p.join(sandbox.path, 'Downloads', 'FlyPlayer', 'logs'),
      );
      expect(
        await File(result.path).readAsString(),
        contains('Fly Player Log Export'),
      );
      expect(androidCalls, isEmpty);
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test(
      '$platform file access and native cache queries avoid Android channels',
      () async {
        debugDefaultTargetPlatformOverride = platform;

        expect(
          StorageAccessService.debugHost,
          isNot(isA<MethodChannelStorageAccessHost>()),
        );
        expect(
          StorageManagementService.debugHost,
          isNot(isA<MethodChannelStorageManagementHost>()),
        );
        expect(await StorageAccessService.hasFileAccess(), isTrue);
        expect(await StorageAccessService.requestFileAccess(), isTrue);
        expect(await StorageAccessService.listScreenshotLibrary(), isEmpty);
        expect(
          await StorageAccessService.getScreenshotCustomDirectory(),
          isNull,
        );
        final overview = await StorageManagementService.debugHost
            .getStorageOverview();
        expect((overview!['screenshots'] as Map)['restricted'], isFalse);
        expect(
          await StorageManagementService.debugHost.hasFileAccess(),
          isTrue,
        );
        expect(
          await StorageManagementService.debugHost.listPlaybackCacheEntries(),
          isEmpty,
        );
        expect(androidCalls, isEmpty);
      },
    );

    test(
      '$platform never requests Android SAF or permission settings',
      () async {
        debugDefaultTargetPlatformOverride = platform;

        expect(await StorageAccessService.openFileAccessSettings(), isFalse);
        expect(await StorageAccessService.getScopedTreeRoot(), isNull);
        expect(await StorageAccessService.requestScopedTreeAccess(), isNull);
        expect(await StorageAccessService.listScopedTreeEntries(), isNull);
        expect(
          await StorageAccessService.readScopedFileBytes(
            'content://android/file',
          ),
          isNull,
        );
        await expectLater(
          StorageAccessService.primaryStorageRoot(),
          throwsA(isA<FileSystemException>()),
        );
        expect(androidCalls, isEmpty);
      },
    );
  }
}
