import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_backend.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets(
    'MediaBackendProvider exposes Feiniu backend for current NAS session',
    (tester) async {
      final nasProvider = NasProvider();
      await tester.pump();

      final provider = MediaBackendProvider(nasProvider);

      addTearDown(provider.dispose);
      addTearDown(nasProvider.dispose);

      final backend = provider.backend;

      expect(provider.nasProvider, same(nasProvider));
      expect(backend, isA<FeiniuMediaBackend>());
      expect(backend.capabilities.kind, MediaBackendKind.feiniu);
    },
  );
}
