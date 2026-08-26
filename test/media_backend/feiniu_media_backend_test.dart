import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';

void main() {
  test('Feiniu capability preset stays NAS-specific', () {
    const capabilities = MediaBackendCapabilities.feiniu();

    expect(capabilities.kind, MediaBackendKind.feiniu);
    expect(capabilities.supportsDownloadTasks, isTrue);
    expect(capabilities.supportsFnConnect, isTrue);
  });
}
