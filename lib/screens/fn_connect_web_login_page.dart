import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/login_error_resolver.dart';

class FnConnectWebLoginSessionPolicy {
  static const bool preserveCookiesByDefault = true;

  const FnConnectWebLoginSessionPolicy._();
}

class FnConnectWebLoginEntry {
  static const String officialPrimaryHost = '5ddd.com';
  static const String officialSecondaryHost = 'fnos.net';

  final String initialUrl;
  final String officialUrl;
  final List<String> relayBaseUrls;
  final List<String> cookieHosts;

  const FnConnectWebLoginEntry({
    required this.initialUrl,
    required this.officialUrl,
    required this.relayBaseUrls,
    required this.cookieHosts,
  });

  static FnConnectWebLoginEntry resolve({
    required String fnConnectId,
    required List<String> relayHosts,
  }) {
    final normalizedFnId = fnConnectId.trim();
    final officialUrl = 'https://$officialPrimaryHost/$normalizedFnId';
    final relayBaseUrls = relayHosts
        .map(_originFromRelayHost)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final hosts = <String>{
      for (final relayUrl in relayBaseUrls) Uri.parse(relayUrl).host,
      officialPrimaryHost,
      officialSecondaryHost,
    }.toList(growable: false);

    return FnConnectWebLoginEntry(
      initialUrl: officialUrl,
      officialUrl: officialUrl,
      relayBaseUrls: relayBaseUrls,
      cookieHosts: hosts,
    );
  }

  static String _originFromRelayHost(String rawHost) {
    final trimmed = rawHost.trim();
    if (trimmed.isEmpty) return '';
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) return '';
    return Uri(
      scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString().replaceAll(RegExp(r'/$'), '');
  }
}

class FnConnectWebLoginPageResult {
  final LoginWithBaseUrlResult? loginResult;
  final String? errorMessage;

  const FnConnectWebLoginPageResult.success(this.loginResult)
    : errorMessage = null;

  const FnConnectWebLoginPageResult.failure(this.errorMessage)
    : loginResult = null;

  bool get isSuccess => loginResult != null;
}

class FnConnectWebLoginPage extends StatefulWidget {
  final String fnConnectId;
  final String userName;
  final String password;
  final List<String> relayHosts;

  const FnConnectWebLoginPage({
    super.key,
    required this.fnConnectId,
    required this.userName,
    required this.password,
    this.relayHosts = const <String>[],
  });

  @override
  State<FnConnectWebLoginPage> createState() => _FnConnectWebLoginPageState();
}

class _FnConnectWebLoginPageState extends State<FnConnectWebLoginPage> {
  static const String _bridgeName = 'FnConnectBridge';

  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  late final FnConnectWebLoginEntry _entry;
  late final WebViewController _controller;

  bool _isReady = false;
  bool _isClosing = false;
  bool _isFetchingOauthConfig = false;
  bool _isExchangingCode = false;
  int _progress = 0;
  String _statusText = 'Opening FN Connect...';
  String _cookieString = '';
  String _resolvedBaseUrl = '';
  String _lastSigninUrl = '';

  @override
  void initState() {
    super.initState();
    _entry = FnConnectWebLoginEntry.resolve(
      fnConnectId: widget.fnConnectId,
      relayHosts: widget.relayHosts,
    );
    _controller = WebViewController();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final l10n = AppLocalizations.of(context);
    try {
      if (!FnConnectWebLoginSessionPolicy.preserveCookiesByDefault) {
        await _cookieManager.clearCookies();
      }
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(const Color(0xFF08111A));
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            unawaited(_handlePossibleOauthResultUrl(request.url));
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            if (!mounted || _isClosing) return;
            setState(() {
              _statusText = l10n.fnConnectEntryLoading(_friendlyUrl(url));
            });
          },
          onPageFinished: (url) {
            unawaited(_injectBridgeScript());
            if (!mounted || _isClosing) return;
            setState(() {
              _isReady = true;
              _statusText = l10n.fnConnectEntryProcessing(_friendlyUrl(url));
            });
          },
          onProgress: (progress) {
            if (!mounted || _isClosing) return;
            setState(() {
              _progress = progress;
            });
          },
          onWebResourceError: (error) {
            if ((error.isForMainFrame ?? false) && mounted && !_isClosing) {
              setState(() {
                _statusText = error.description;
              });
            }
          },
          onSslAuthError: (error) {
            error.proceed();
          },
        ),
      );
      await _controller.addJavaScriptChannel(
        _bridgeName,
        onMessageReceived: (message) {
          unawaited(_handleBridgeMessage(message.message));
        },
      );
      await _setRelayCookiesForEntryHosts();
      if (await _tryNavigateToSigninFromRelayConfig()) {
        return;
      }
      await _controller.loadRequest(Uri.parse(_entry.initialUrl));
    } catch (error) {
      _completeFailure(LoginErrorResolver.resolve(error, l10n: l10n));
    }
  }

  Future<void> _setRelayCookiesForEntryHosts() async {
    for (final host in _entry.cookieHosts) {
      await _cookieManager.setCookie(
        WebViewCookie(name: 'mode', value: 'relay', domain: host, path: '/'),
      );
    }
  }

  Future<bool> _tryNavigateToSigninFromRelayConfig() async {
    if (_entry.relayBaseUrls.isEmpty || _isClosing) return false;
    for (final baseUrl in _entry.relayBaseUrls) {
      if (!mounted || _isClosing) return false;
      setState(() {
        _statusText = 'Requesting FN Connect authorization...';
      });
      try {
        final config = await FeiniuApi.fetchFnConnectOauthConfig(
          baseUrl: baseUrl,
          cookie: 'mode=relay',
        );
        _cookieString = 'mode=relay';
        await _navigateToSignin(baseUrl: config.baseUrl, appId: config.appId);
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> _injectBridgeScript() async {
    try {
      await _controller.runJavaScript(_buildInjectionScript());
    } catch (_) {}
  }

  String _buildInjectionScript() {
    final user = jsonEncode(widget.userName);
    final password = jsonEncode(widget.password);
    return '''
(() => {
  const BRIDGE_NAME = ${jsonEncode(_bridgeName)};
  const AUTO_LOGIN_USER = $user;
  const AUTO_LOGIN_PASS = $password;

  function post(payload) {
    try {
      payload = payload || {};
      payload.cookie = document.cookie || '';
      payload.pageUrl = String(window.location.href || '');
      window[BRIDGE_NAME].postMessage(JSON.stringify(payload));
    } catch (_) {}
  }

  function triggerInput(input, value) {
    if (!input) return;
    const descriptor =
        Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
    if (descriptor && descriptor.set) {
      descriptor.set.call(input, value);
    } else {
      input.value = value;
    }
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    input.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  function normalizedText(element) {
    return String(
      (element && (
        element.innerText ||
        element.textContent ||
        element.placeholder ||
        element.name ||
        element.id ||
        element.autocomplete ||
        element.getAttribute && element.getAttribute('aria-label')
      )) || ''
    ).trim().toLowerCase();
  }

  function findInput(candidates, patterns) {
    for (let i = 0; i < candidates.length; i += 1) {
      const input = candidates[i];
      const text = normalizedText(input);
      for (let j = 0; j < patterns.length; j += 1) {
        if (text.indexOf(patterns[j]) !== -1) {
          return input;
        }
      }
    }
    return null;
  }

  function findText(elements, patterns) {
    for (let i = 0; i < elements.length; i += 1) {
      const text = normalizedText(elements[i]);
      for (let j = 0; j < patterns.length; j += 1) {
        if (text.indexOf(patterns[j].toLowerCase()) !== -1) {
          return elements[i];
        }
      }
    }
    return null;
  }

  function autoLogin() {
    if (window.location.href.indexOf('/login') === -1) return;
    setTimeout(() => {
      const inputs = Array.from(document.querySelectorAll('input'));
      const userInput =
          document.querySelector('#username') ||
          document.querySelector('input[name="username"]') ||
          document.querySelector('input[autocomplete="username"]') ||
          findInput(inputs, ['username', 'user', 'account', 'login', '\\u7528\\u6237', '\\u8d26\\u53f7']) ||
          document.querySelector('input[type="text"]');
      const passInput =
          document.querySelector('#password') ||
          document.querySelector('input[name="password"]') ||
          document.querySelector('input[autocomplete="current-password"]') ||
          findInput(inputs, ['password', 'passwd', 'pass', '\\u5bc6\\u7801']) ||
          document.querySelector('input[type="password"]');
      if (userInput && AUTO_LOGIN_USER) {
        triggerInput(userInput, AUTO_LOGIN_USER);
      }
      if (passInput && AUTO_LOGIN_PASS) {
        triggerInput(passInput, AUTO_LOGIN_PASS);
      }
      setTimeout(() => {
        const submit =
            document.querySelector('button[type="submit"]') ||
            findText(
              document.querySelectorAll('button'),
              ['\\u767b\\u5f55', 'Login', 'Sign in', 'Sign In']
            );
        if (submit && !submit.disabled && submit.getAttribute('aria-disabled') !== 'true') {
          submit.click();
        }
      }, 250);
    }, 250);
  }

  function autoAuthorize() {
    if (window.location.href.indexOf('/signin') === -1) return;
    setTimeout(() => {
      const button = findText(
        document.querySelectorAll('button'),
        [
          '\\u6388\\u6743',
          '\\u540c\\u610f',
          'Authorize',
          'Agree',
          'Continue',
          'Allow'
        ]
      );
      if (button) {
        button.click();
      }
    }, 250);
  }

  function installXhrHook() {
    if (window.__flyFnConnectXhrInstalled) return;
    window.__flyFnConnectXhrInstalled = true;

    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__fly_url = url;
      return originalOpen.apply(this, arguments);
    };

    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function(body) {
      const self = this;
      const originalReadyStateChange = self.onreadystatechange;
      self.onreadystatechange = function() {
        if (self.readyState === 4) {
          const url = String(self.__fly_url || '');
          if (url.indexOf('/oauthapi/authorize') !== -1) {
            let code = '';
            try {
              const json = JSON.parse(self.responseText || '{}');
              code = String(json && json.data ? json.data.code || '' : '');
            } catch (_) {}
            post({
              type: 'Response',
              url: url,
              code: code,
              body: self.responseText || ''
            });
          }
        }
        if (originalReadyStateChange) {
          originalReadyStateChange.apply(this, arguments);
        }
      };

      const url = String(this.__fly_url || '');
      if (url.indexOf('/sac/rpcproxy/v1/new-user-guide/status') !== -1) {
        post({ type: 'XHR', url: url });
      }
      return originalSend.apply(this, arguments);
    };
  }

  function installFetchHook() {
    if (window.__flyFnConnectFetchInstalled) return;
    window.__flyFnConnectFetchInstalled = true;

    const originalFetch = window.fetch;
    window.fetch = function(input, init) {
      let url = input;
      if (typeof input === 'object' && input && input.url) {
        url = input.url;
      }
      url = String(url || '');

      if (url.indexOf('/sac/rpcproxy/v1/new-user-guide/status') !== -1) {
        post({ type: 'XHR', url: url });
      }

      return originalFetch.apply(this, arguments).then((response) => {
        if (url.indexOf('/oauthapi/authorize') !== -1) {
          const clone = response.clone();
          clone.text().then((text) => {
            let code = '';
            try {
              const json = JSON.parse(text || '{}');
              code = String(json && json.data ? json.data.code || '' : '');
            } catch (_) {}
            post({ type: 'Response', url: url, code: code, body: text || '' });
          });
        }
        return response;
      });
    };
  }

  function fetchSysConfigOnce() {
    if (window.__flyFnConnectSysConfigRequested) return;
    if (window.location.href.indexOf('/login') !== -1) return;
    window.__flyFnConnectSysConfigRequested = true;
    fetch('/v/api/v1/sys/config', { credentials: 'include' })
      .then((response) => response.text())
      .then((text) => {
        post({
          type: 'SysConfig',
          url: '/v/api/v1/sys/config',
          body: text || ''
        });
        if (String(text || '').indexOf('nas_oauth') === -1) {
          window.__flyFnConnectSysConfigRequested = false;
        }
      })
      .catch(() => {
        window.__flyFnConnectSysConfigRequested = false;
      });
  }

  installXhrHook();
  installFetchHook();
  autoLogin();
  autoAuthorize();
  setTimeout(fetchSysConfigOnce, 800);
  let tickCount = 0;
  const tickTimer = setInterval(() => {
    tickCount += 1;
    autoLogin();
    autoAuthorize();
    fetchSysConfigOnce();
    if (tickCount >= 160) {
      clearInterval(tickTimer);
    }
  }, 750);
})();
''';
  }

  Future<void> _handleBridgeMessage(String rawMessage) async {
    if (_isClosing || rawMessage.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type']?.toString() ?? '';
      final url = decoded['url']?.toString() ?? '';

      if (type == 'XHR' &&
          url.contains('/sac/rpcproxy/v1/new-user-guide/status')) {
        final cookie = decoded['cookie']?.toString().trim() ?? '';
        if (cookie.isNotEmpty) {
          _cookieString = cookie;
          await _loadOauthConfigFromCookie(
            cookie: cookie,
            pageUrl: decoded['pageUrl']?.toString(),
          );
        }
        return;
      }

      if (type == 'SysConfig') {
        final body = decoded['body']?.toString() ?? '';
        await _handleSysConfigBody(
          body,
          pageUrl: decoded['pageUrl']?.toString(),
        );
        return;
      }

      if (type == 'Response' && url.contains('/oauthapi/authorize')) {
        final code = _extractCodeFromBridgePayload(decoded);
        if (code.isNotEmpty) {
          await _exchangeOauthCode(code);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadOauthConfigFromCookie({
    required String cookie,
    String? pageUrl,
  }) async {
    if (_isFetchingOauthConfig || _isClosing) return;
    _isFetchingOauthConfig = true;
    try {
      final currentUrl = pageUrl ?? await _controller.currentUrl();
      final currentBaseUrl = _originFromUrl(currentUrl ?? '');
      if (currentBaseUrl.isEmpty) {
        throw const FormatException(
          'Unable to determine the current FN Connect host',
        );
      }
      final config = await FeiniuApi.fetchFnConnectOauthConfig(
        baseUrl: currentBaseUrl,
        cookie: cookie,
      );
      await _navigateToSignin(baseUrl: config.baseUrl, appId: config.appId);
    } catch (_) {
      _isFetchingOauthConfig = false;
    }
  }

  Future<void> _handleSysConfigBody(String body, {String? pageUrl}) async {
    if (_isClosing || body.trim().isEmpty) return;
    try {
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic>) return;
      final data = payload['data'];
      if (data is! Map<String, dynamic>) return;
      final oauth = data['nas_oauth'];
      if (oauth is! Map<String, dynamic>) return;
      final appId = oauth['app_id']?.toString().trim() ?? '';
      if (appId.isEmpty) return;

      final oauthUrl = oauth['url']?.toString().trim() ?? '';
      final fallbackBaseUrl = _originFromUrl(pageUrl ?? '');
      final targetBaseUrl = oauthUrl.isNotEmpty && oauthUrl != '://'
          ? _originFromUrl(oauthUrl)
          : fallbackBaseUrl;
      if (targetBaseUrl.isEmpty) return;
      await _navigateToSignin(baseUrl: targetBaseUrl, appId: appId);
    } catch (_) {}
  }

  Future<void> _navigateToSignin({
    required String baseUrl,
    required String appId,
  }) async {
    final finalBaseUrl = _originFromUrl(baseUrl);
    if (finalBaseUrl.isEmpty) return;

    final redirectUri = '$finalBaseUrl/v/oauth/result';
    final signinUrl =
        '$finalBaseUrl/signin?client_id=${Uri.encodeQueryComponent(appId)}'
        '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}';
    if (_lastSigninUrl == signinUrl) return;

    _resolvedBaseUrl = finalBaseUrl;
    _lastSigninUrl = signinUrl;
    await _copyRelayCookiesToBaseUrl(finalBaseUrl);
    if (!mounted || _isClosing) return;
    setState(() {
      _statusText = 'Requesting FN Connect authorization...';
    });
    await _controller.loadRequest(Uri.parse(signinUrl));
  }

  Future<void> _copyRelayCookiesToBaseUrl(String baseUrl) async {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    if (host.isEmpty) return;
    if (_cookieString.isNotEmpty) {
      for (final rawEntry in _cookieString.split(';')) {
        final separator = rawEntry.indexOf('=');
        if (separator <= 0) continue;
        final name = rawEntry.substring(0, separator).trim();
        final value = rawEntry.substring(separator + 1).trim();
        if (name.isEmpty) continue;
        await _cookieManager.setCookie(
          WebViewCookie(name: name, value: value, domain: host, path: '/'),
        );
      }
    }
    await _cookieManager.setCookie(
      WebViewCookie(name: 'mode', value: 'relay', domain: host, path: '/'),
    );
  }

  Future<void> _handlePossibleOauthResultUrl(String url) async {
    if (_isClosing || _isExchangingCode) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.path != '/v/oauth/result') return;
    final code = uri.queryParameters['code']?.trim() ?? '';
    if (code.isEmpty) return;
    await _exchangeOauthCode(code);
  }

  Future<void> _exchangeOauthCode(String code) async {
    if (_isExchangingCode || _isClosing) return;
    final l10n = AppLocalizations.of(context);
    final baseUrl = _resolvedBaseUrl;
    if (baseUrl.isEmpty) {
      _completeFailure(l10n.fnConnectNasAddressFailed);
      return;
    }

    _isExchangingCode = true;
    if (mounted) {
      setState(() {
        _statusText = l10n.fnConnectEntryExchangingOauth;
      });
    }

    try {
      final result = await FeiniuApi.loginWithFnConnectOauthCode(
        baseUrl: baseUrl,
        code: code,
      );
      _completeSuccess(result);
    } catch (error) {
      _completeFailure(LoginErrorResolver.resolve(error, l10n: l10n));
    }
  }

  String _extractCodeFromBridgePayload(Map<String, dynamic> payload) {
    final directCode = payload['code']?.toString().trim() ?? '';
    if (directCode.isNotEmpty) return directCode;
    final body = payload['body']?.toString().trim() ?? '';
    if (body.isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return '';
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return '';
      return data['code']?.toString().trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  void _completeSuccess(LoginWithBaseUrlResult result) {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    Navigator.of(context).pop(FnConnectWebLoginPageResult.success(result));
  }

  void _completeFailure(String message) {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    Navigator.of(context).pop(FnConnectWebLoginPageResult.failure(message));
  }

  String _friendlyUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.host}$path';
  }

  String _originFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    return Uri(
      scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString().replaceAll(RegExp(r'/$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress.clamp(0, 100) / 100.0;
    return Scaffold(
      backgroundColor: const Color(0xFF08111A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1724),
        foregroundColor: Colors.white,
        title: Text('FN Connect: ${widget.fnConnectId}'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _isReady ? () => _controller.reload() : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () {
              if (_isClosing) return;
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress <= 0 || progress >= 1 ? null : progress,
                  backgroundColor: const Color(0xFF203042),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF2D74D9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB4C3D7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isReady
          ? WebViewWidget(controller: _controller)
          : const Center(
              child: CircularProgressIndicator(color: Color(0xFF2D74D9)),
            ),
    );
  }
}
