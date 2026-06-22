import '../media_backend_kind.dart';

class MediaBackendConnection {
  const MediaBackendConnection({
    required this.kind,
    required this.serverUrl,
    this.displayName = '',
    this.userName = '',
    this.userId = '',
    this.accessToken = '',
    this.secret = '',
    this.rememberSecret = true,
    this.updatedAtMillis = 0,
  });

  final MediaBackendKind kind;
  final String serverUrl;
  final String displayName;
  final String userName;
  final String userId;
  final String accessToken;
  final String secret;
  final bool rememberSecret;
  final int updatedAtMillis;

  bool get isAuthenticated =>
      serverUrl.trim().isNotEmpty && accessToken.trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'serverUrl': serverUrl,
    'displayName': displayName,
    'userName': userName,
    'userId': userId,
    'accessToken': accessToken,
    'secret': secret,
    'rememberSecret': rememberSecret,
    'updatedAtMillis': updatedAtMillis,
  };

  factory MediaBackendConnection.fromJson(Map<String, Object?> json) {
    final kindName = (json['kind'] ?? '').toString();
    final kind = MediaBackendKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => MediaBackendKind.feiniu,
    );
    return MediaBackendConnection(
      kind: kind,
      serverUrl: (json['serverUrl'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      userName: (json['userName'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      accessToken: (json['accessToken'] ?? '').toString(),
      secret: (json['secret'] ?? '').toString(),
      rememberSecret: json['rememberSecret'] != false,
      updatedAtMillis: (json['updatedAtMillis'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaBackendConnection &&
          other.kind == kind &&
          other.serverUrl == serverUrl &&
          other.displayName == displayName &&
          other.userName == userName &&
          other.userId == userId &&
          other.accessToken == accessToken &&
          other.secret == secret &&
          other.rememberSecret == rememberSecret &&
          other.updatedAtMillis == updatedAtMillis;

  @override
  int get hashCode => Object.hash(
    kind,
    serverUrl,
    displayName,
    userName,
    userId,
    accessToken,
    secret,
    rememberSecret,
    updatedAtMillis,
  );
}
