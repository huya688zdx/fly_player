import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/api/emby_api.dart';

void main() {
  test('normalizes server URL without backend-specific fields', () {
    expect(
      EmbyApi.normalizeServerUrl(' emby.example.test/ '),
      'http://emby.example.test',
    );
    expect(
      EmbyApi.normalizeServerUrl('https://emby.example.test///'),
      'https://emby.example.test',
    );
  });

  test('loads public system info from normalized server URL', () async {
    final adapter = _FakeDioAdapter((options) {
      expect(options.method, 'GET');
      expect(
        options.uri.toString(),
        'https://emby.example.test/System/Info/Public',
      );
      return const _JsonResponse(<String, Object?>{
        'ServerName': 'Living Room',
      });
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final info = await api.getPublicSystemInfo('https://emby.example.test/');

    expect(info.serverName, 'Living Room');
  });

  test('authenticates by name and keeps only session fields', () async {
    late RequestOptions capturedOptions;
    final adapter = _FakeDioAdapter((options) {
      capturedOptions = options;
      expect(options.method, 'POST');
      expect(
        options.uri.toString(),
        'https://emby.example.test/Users/AuthenticateByName',
      );
      expect(
        options.headers['X-Emby-Authorization'],
        contains('Client=Fly Player'),
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
    });
    final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

    final result = await api.authenticateByName(
      serverUrl: 'https://emby.example.test/',
      userName: 'alice',
      password: 'secret',
    );

    expect(capturedOptions.contentType, Headers.jsonContentType);
    expect(result.serverUrl, 'https://emby.example.test');
    expect(result.serverName, 'Living Room');
    expect(result.accessToken, 'emby-access-token');
    expect(result.userId, 'user-id');
    expect(result.userName, 'Alice');
  });
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
