import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/person_detail_screen.dart';
import 'package:fly_player/widgets/common/app_error_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('人物详情在会话暂不可用后显示重试并可恢复', (tester) async {
    final nas = NasProvider();
    final session = _SwitchableBackendSessionProvider();
    final theme = AppThemeProvider();
    final backend = _StubMediaBackend();
    final mediaBackend = _StubMediaBackendProvider(nas, session, backend);
    addTearDown(nas.dispose);
    addTearDown(session.dispose);
    addTearDown(mediaBackend.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<NasProvider>.value(value: nas),
          ChangeNotifierProvider<BackendSessionProvider>.value(value: session),
          ChangeNotifierProvider<AppThemeProvider>.value(value: theme),
          ChangeNotifierProvider<MediaBackendProvider>.value(
            value: mediaBackend,
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PersonDetailScreen(
            personGuid: 'person-1',
            initialName: 'Loading Person',
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byType(AppErrorState));

    expect(tester.takeException(), isNull);
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);

    session.unavailable = false;
    await tester.tap(find.byType(ElevatedButton));
    await _pumpUntilFound(tester, find.text('Recovered Person'));

    expect(tester.takeException(), isNull);
    expect(find.text('Recovered Person'), findsWidgets);
    expect(find.byType(AppErrorState), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    theme.dispose();
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _SwitchableBackendSessionProvider extends BackendSessionProvider {
  _SwitchableBackendSessionProvider() : super(autoLoad: false);

  bool unavailable = true;

  @override
  Future<void> ensureReady() async {
    if (unavailable) throw const BackendSessionUnavailableException();
  }
}

class _StubMediaBackendProvider extends MediaBackendProvider {
  _StubMediaBackendProvider(
    super.nasProvider,
    BackendSessionProvider super.sessionProvider,
    this.value,
  );

  final MediaBackend value;

  @override
  MediaBackend get backend => value;
}

class _StubMediaBackend extends Fake implements MediaBackend {
  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.server(kind: MediaBackendKind.emby);

  @override
  Future<MediaDetail> getItemDetail(String itemId) async => const MediaDetail(
    id: 'person-1',
    type: 'Person',
    title: 'Recovered Person',
    primaryImage: MediaImageRef.empty,
  );

  @override
  Future<List<MediaItemCard>> getPersonItems(String personId) async =>
      const <MediaItemCard>[];
}
