import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';

void main() {
  test('connection serializes neutral fields', () {
    const connection = MediaBackendConnection(
      kind: MediaBackendKind.emby,
      serverUrl: 'https://media.example.test',
      displayName: 'Home Media',
      userName: 'alice',
      userId: 'user-1',
      accessToken: 'token',
      secret: 'password',
      rememberSecret: false,
      updatedAtMillis: 123,
    );

    expect(connection.isAuthenticated, isTrue);
    expect(connection.toJson(), <String, Object?>{
      'kind': 'emby',
      'serverUrl': 'https://media.example.test',
      'displayName': 'Home Media',
      'userName': 'alice',
      'userId': 'user-1',
      'accessToken': 'token',
      'secret': 'password',
      'rememberSecret': false,
      'updatedAtMillis': 123,
    });
    expect(MediaBackendConnection.fromJson(connection.toJson()), connection);
  });

  test('empty token is not authenticated', () {
    const connection = MediaBackendConnection(
      kind: MediaBackendKind.feiniu,
      serverUrl: 'https://nas.example.test',
    );

    expect(connection.isAuthenticated, isFalse);
  });
}
