class DanDanPlayConfig {
  static const String appId = '';
  static const String appSecret = '';

  static bool get configured =>
      appId.trim().isNotEmpty && appSecret.trim().isNotEmpty;
}
