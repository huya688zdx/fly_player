import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_bif_service.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_oped.dart';

Uint8List bifBytes() {
  final bytes = Uint8List(84);
  bytes.setAll(0, [0x89, 0x42, 0x49, 0x46, 13, 10, 26, 10]);
  final b = ByteData.sublistView(bytes);
  b.setUint32(12, 1, Endian.little);
  b.setUint32(16, 1000, Endian.little);
  b.setUint32(68, 80, Endian.little);
  b.setUint32(72, 0xffffffff, Endian.little);
  b.setUint32(76, 84, Endian.little);
  bytes.setAll(80, [255, 216, 255, 217]);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const source = FlySourceRef(
    bindingId: 'binding',
    remoteItemId: 'item',
    remoteMediaSourceId: 'version',
  );
  const id = 'e0f07686-66e0-4331-abcd-675476aac219';
  final session = FlyDataSession(
    serverUrl: 'http://localhost:8787',
    userId: 'user',
    username: 'u',
    deviceId: 'd',
    deviceName: 'd',
    token: 'private',
    installationId: 'i',
    serviceInstanceId: 'service',
  );
  late Directory cache;
  Map<String, dynamic> manifest() => {
    'status': 'ready',
    'file_context': {
      'identity_state': 'verified',
      'source_ref': source.toJson(),
      'file_revision_id': 'file',
      'media_coordinate_id': 'coordinate',
      'duration_ms': 1000,
    },
    'asset': {
      'id': id,
      'url':
          '/api/v1/bif/assets/$id/content?binding_id=binding&remote_item_id=item&remote_media_source_id=version',
      'sha256': sha256.convert(bifBytes()).toString(),
      'bytes': 84,
      'frame_count': 1,
      'coverage_start_ms': 0,
      'coverage_end_ms': 1000,
      'duration_ms': 1000,
      'width': 320,
      'height': 180,
      'interval_ms': 1000,
    },
  };
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('fly-bif-test-');
  });
  test('missing local binding never creates a Fly request', () {
    expect(FlyBifAccess.capture(statsScope: '', itemGuid: '', mediaGuid: '', isCurrent: () => true), isNull);
  });
  tearDown(() async {
    await cache.delete(recursive: true);
  });
  test(
    'requires exact verified file, whole duration and source scoped same-service path',
    () {
      expect(FlyBifAsset.parse(manifest(), source), isNotNull);
      for (final change in <void Function(Map<String, dynamic>)>[
        (m) => m['status'] = 'stale',
        (m) => m['file_context']['identity_state'] = 'unverified',
        (m) => m['asset']['url'] = 'https://evil.invalid/file',
        (m) => m['asset']['url'] = '//evil.invalid/file',
        (m) => m['asset']['url'] += '&remote_item_id=other',
        (m) => m['asset']['coverage_end_ms'] = 900,
        (m) => m['asset']['bytes'] = 128 * 1024 * 1024 + 1,
        (m) => m['asset']['sha256'] = 'not-a-hash',
      ]) {
        final value = manifest();
        change(value);
        expect(FlyBifAsset.parse(value, source), isNull);
      }
    },
  );
  test(
    'verifies digest before publishing private cache; rechecks cached integrity',
    () async {
      var downloads = 0;
      final service = FlyBifService(
        cacheDirectory: () async => cache,
        request: (_, __) async => manifest(),
        download: (_, __) async {
          downloads++;
          return bifBytes();
        },
      );
      final access = FlyBifAccess(
        session: session,
        source: source,
        isCurrent: () => true,
      );
      final path = await service.resolve(access);
      expect(path, isNotNull);
      expect(await File(path!).readAsBytes(), bifBytes());
      expect(await service.resolve(access), path);
      expect(downloads, 1);
      await File(path).writeAsBytes([1, 2]);
      expect(await service.resolve(access), path);
      expect(downloads, 2);
      final bad = FlyBifService(
        cacheDirectory: () async => cache,
        request: (_, __) async => manifest(),
        download: (_, __) async => Uint8List(84),
      );
      await File(path).delete();
      expect(await bad.resolve(access), isNull);
      expect(
        await cache
            .list(recursive: true)
            .where((f) => f.path.endsWith('.bif'))
            .length,
        0,
      );
    },
  );
  test(
    'late download after account or source changes never installs a file',
    () async {
      var current = true;
      final pending = Completer<Uint8List>();
      final started = Completer<void>();
      final service = FlyBifService(
        cacheDirectory: () async => cache,
        request: (_, __) async => manifest(),
        download: (_, __) {
          started.complete();
          return pending.future;
        },
      );
      final result = service.resolve(
        FlyBifAccess(
          session: session,
          source: source,
          isCurrent: () => current,
        ),
      );
      await started.future;
      current = false;
      pending.complete(bifBytes());
      expect(await result, isNull);
    },
  );
}
