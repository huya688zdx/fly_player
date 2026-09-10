import 'package:webview_flutter/webview_flutter.dart';

typedef FnConnectCookieClearer = Future<bool> Function();

class FnConnectWebSessionService {
  const FnConnectWebSessionService._();

  static Future<bool> clearLoginState({FnConnectCookieClearer? clearCookies}) {
    final clearer = clearCookies ?? () => WebViewCookieManager().clearCookies();
    return clearer();
  }
}
