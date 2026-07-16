import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/api/emby_api.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/connection_screen.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('Emby authentication saves only neutral backend session', (
    tester,
  ) async {
    final api = EmbyApi(
      dio: Dio(BaseOptions())
        ..httpClientAdapter = _FakeDioAdapter((options) {
          expect(
            options.uri.toString(),
            'https://emby.example.test/Users/AuthenticateByName',
          );
          expect(options.data, <String, Object?>{
            'Username': 'alice',
            'Pw': 'secret',
          });
          return const _JsonResponse(<String, Object?>{
            'AccessToken': 'emby-access-token',
            'User': <String, Object?>{'Id': 'user-id', 'Name': 'Alice'},
            'ServerName': 'Living Room',
          });
        }),
    );

    await tester.pumpWidget(_connectionScreen(embyApi: api));
    await tester.pump();

    await tester.tap(find.text('Emby'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'https://emby.example.test/');
    await tester.enterText(fields.at(1), 'alice');
    await tester.enterText(fields.at(2), 'secret');
    final loginButton = find.byType(ElevatedButton);
    await tester.ensureVisible(loginButton);
    await tester.pumpAndSettle();
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    final snapshot = await MediaBackendConnectionStore.load();
    expect(snapshot.activeKind, MediaBackendKind.emby);
    expect(snapshot.activeConnection.serverUrl, 'https://emby.example.test');
    expect(snapshot.activeConnection.displayName, 'Living Room');
    expect(snapshot.activeConnection.userName, 'Alice');
    expect(snapshot.activeConnection.userId, 'user-id');
    expect(snapshot.activeConnection.accessToken, 'emby-access-token');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('base_url'), isNull);
    expect(prefs.getString('token'), isNull);
  });

  testWidgets('Connection screen restores current Emby connection', (
    tester,
  ) async {
    await MediaBackendConnectionStore.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        displayName: 'Living Room',
        userName: 'Alice',
        userId: 'user-id',
        accessToken: 'emby-access-token',
      ),
    );

    await tester.pumpWidget(_connectionScreen(embyApi: EmbyApi()));
    await tester.pumpAndSettle();

    expect(find.textContaining('已连接 Emby'), findsNothing);
    final fields = find.byType(TextField);
    expect(
      tester.widget<TextField>(fields.at(0)).controller?.text,
      'https://emby.example.test',
    );
    expect(tester.widget<TextField>(fields.at(1)).controller?.text, 'Alice');
  });
}

Widget _connectionScreen({required EmbyApi embyApi}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => NasProvider()),
      ChangeNotifierProvider(create: (_) => BackendSessionProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
      home: ConnectionScreen(embyApi: embyApi),
    ),
  );
}

class _JsonResponse {
  const _JsonResponse(this.body);

  final Map<String, Object?> body;
}

class _FakeDioAdapter implements HttpClientAdapter {
  _FakeDioAdapter(this.handler);

  final _JsonResponse Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = handler(options);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
