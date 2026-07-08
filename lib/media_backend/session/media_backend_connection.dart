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
    this.entryToken = '',
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

  /// FN Connect 入口签发的会话令牌（cookie `entry-token` 的值）。
  ///
  /// 当 [serverUrl] 是飞牛中转域名（`*.fnos.net`，如 Emby 发布服务藏在飞牛反向代理后面）
  /// 时，所有请求必须携带 `Cookie: entry-token=<值>` 才能过云端 FN Connect 边缘闸；该令牌
  /// 由 WebView 走真实入口流程登录后从 cookie 抓取。会话级、会过期 → 失效需重新抓取。
  /// 直连地址（非 fnos）不需要、留空。
  final String entryToken;

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
    'entryToken': entryToken,
  };

  static MediaBackendConnection? tryFromJson(Map<String, Object?> json) {
    try {
      return MediaBackendConnection.fromJson(json);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  factory MediaBackendConnection.fromJson(Map<String, Object?> json) {
    final kindName = (json['kind'] ?? '').toString();
    MediaBackendKind? kind;
    for (final candidate in MediaBackendKind.values) {
      if (candidate.name == kindName) {
        kind = candidate;
        break;
      }
    }
    if (kind == null) {
      throw FormatException('Unknown media backend kind: $kindName');
    }
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
      entryToken: (json['entryToken'] ?? '').toString(),
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
          other.updatedAtMillis == updatedAtMillis &&
          other.entryToken == entryToken;

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
    entryToken,
  );
}
