import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/storage_access_host.dart';
import 'package:fly_player/services/storage_access_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('默认宿主：测试环境选择通道宿主，兼容既有 mock', () {
    expect(
      StorageAccessService.debugHost,
      isA<MethodChannelStorageAccessHost>(),
    );
  });

  test('桌面宿主：截图与文件访问面按惰性口径返回', () async {
    // 桌面无 MediaStore/SAF 截图管线、无运行时权限模型，
    // 见 DesktopStorageAccessHost 的归零口径说明。
    const host = DesktopStorageAccessHost();

    expect(await host.hasFileAccess(), isTrue);
    expect(await host.requestFileAccess(), isTrue);
    expect(await host.getScreenshotCustomDirectory(), isNull);
    expect(await host.requestScreenshotCustomDirectory(), isNull);
    expect(await host.clearScreenshotCustomDirectory(), isTrue);
    expect(await host.listScreenshotLibrary(), isEmpty);
    expect(
      await host.readScreenshotFileBytes(
        sourceKind: 'external',
        pathOrIdentifier: '/tmp/a.png',
      ),
      isNull,
    );
    expect(
      await host.deleteScreenshotFiles(const <Map<String, String>>[]),
      <String, Object?>{'deletedCount': 0},
    );
  });

  test('桌面宿主下 StorageAccessService 不依赖原生通道', () async {
    StorageAccessService.setHostForTesting(const DesktopStorageAccessHost());
    addTearDown(() => StorageAccessService.setHostForTesting(null));

    expect(await StorageAccessService.hasFileAccess(), isTrue);
    expect(await StorageAccessService.getScreenshotCustomDirectory(), isNull);
    expect(await StorageAccessService.listScreenshotLibrary(), isEmpty);
    expect(await StorageAccessService.clearScreenshotCustomDirectory(), isTrue);
    expect(
      await StorageAccessService.deleteScreenshotFiles(
        const <ScreenshotLibraryItem>[],
      ),
      0,
    );
  });

  test('通道宿主：载荷与字段透传保持不变', () async {
    // 用既有 mock 通道验证 Android 语义未被重构改变。
    const channel = MethodChannel('fly_player/storage');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      switch (call.method) {
        case 'hasFileAccess':
          return true;
        case 'getScreenshotCustomDirectory':
          return <String, Object?>{
            'id': 'content://tree/primary',
            'name': 'Pictures',
            'locationLabel': 'SD card',
            'available': true,
          };
        case 'listScreenshotLibrary':
          return <Object?>[
            <String, Object?>{
              'id': 's1',
              'name': 'a.png',
              'sourceKind': 'external',
              'locationLabel': 'Pictures',
              'formatKind': 'png',
              'isHdr': false,
              'sizeBytes': 12,
              'modifiedAtMs': 1700000000000,
              'isScoped': false,
              'pathOrIdentifier': '/storage/a.png',
            },
          ];
      }
      return null;
    });
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    StorageAccessService.setHostForTesting(
      const MethodChannelStorageAccessHost(),
    );
    addTearDown(() => StorageAccessService.setHostForTesting(null));

    expect(await StorageAccessService.hasFileAccess(), isTrue);
    final directory = await StorageAccessService.getScreenshotCustomDirectory();
    expect(directory?.name, 'Pictures');
    expect(directory?.available, isTrue);
    final items = await StorageAccessService.listScreenshotLibrary();
    expect(items, hasLength(1));
    expect(items.single.id, 's1');
    expect(items.single.sizeBytes, 12);
  });
}
