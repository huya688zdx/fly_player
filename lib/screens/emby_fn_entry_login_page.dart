import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;

import '../l10n/generated/app_localizations.dart';
import 'fn_web_login_bridge_script.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

/// 飞翔授权结果；普通 Emby 仍返回裸入口令牌。
typedef FlyFnAuthorization = ({
  String entryToken,
  Map<String, String> gatewayCookies,
});

/// 从 Android CookieManager 为精确身份接口返回的 Cookie 请求头中筛选授权项。
Map<String, String> _parseFlyGatewayCookieHeader(String rawCookies) {
  final selected = <String, String>{};
  for (final raw in rawCookies.split(';')) {
    final separator = raw.indexOf('=');
    if (separator <= 0) continue;
    final name = raw.substring(0, separator).trim();
    if (const {'entry-token', 'mode', 'ost'}.contains(name)) {
      selected.putIfAbsent(name, () => raw.substring(separator + 1).trim());
    }
  }
  return selected;
}

/// 在真实 FN 登录流程中取得所选服务的入口凭据。
/// 飞翔应用还需交接飞牛网关的 HttpOnly Cookie，由账号登录流程验证应用身份。
class EmbyFnEntryLoginPage extends StatefulWidget {
  const EmbyFnEntryLoginPage({
    super.key,
    required this.serverUrl,
    this.userName = '',
    this.password = '',
    this.requireTargetPath = false,
  });

  /// 目标 Emby 服务器地址（已归一化的 `https://<sub>.<fnId>.fnos.net`）。
  final String serverUrl;

  /// 可选：FN 账号用户名 / 密码，用于在入口登录页自动填充（留空则纯手动登录）。
  final String userName;
  final String password;

  /// 应用入口与 NAS 桌面同主机，需匹配应用路径后才能读取令牌。
  final bool requireTargetPath;

  @override
  State<EmbyFnEntryLoginPage> createState() => _EmbyFnEntryLoginPageState();
}

class _EmbyFnEntryLoginPageState extends State<EmbyFnEntryLoginPage> {
  static const String _bridgeName = 'FnEntryBridge';
  static const MethodChannel _androidFlyGatewayCookieChannel = MethodChannel(
    'fly_player/fn_web_cookies',
  );

  WebViewController? _controller;
  windows_webview.WebviewController? _windowsController;
  StreamSubscription<String>? _windowsUrlSubscription;
  StreamSubscription<windows_webview.LoadingState>? _windowsLoadingSubscription;
  StreamSubscription<dynamic>? _windowsMessageSubscription;
  StreamSubscription<windows_webview.WebErrorStatus>? _windowsErrorSubscription;

  /// 目标 Emby 主机（如 `embyserver4-9.geqian688.fnos.net`）。只有当 WebView 真正落回
  /// 该主机、且 cookie 里有 entry-token 时才算抓到——这是"已过服务闸"的证明，避免在入口/
  /// 授权中途的页面（NAS 桌面等同域页）上抓到尚未生效的早期 entry-token。
  String _targetHost = '';
  String _targetOrigin = '';
  String _fnIdFamily = '';

  bool _isReady = false;
  bool _isClosing = false;
  bool _flyAuthorizationStarted = false;
  bool _openedFnDesktop = false;
  int _progress = 0;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    final target = Uri.tryParse(widget.serverUrl);
    _targetHost = (target?.host ?? '').trim().toLowerCase();
    _targetOrigin = _originOf(target);
    _fnIdFamily = _fnIdFamilyFor(_targetHost);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    final l10n = AppLocalizations.of(context);
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await _initializeWindows();
        return;
      }
      final controller = WebViewController();
      _controller = controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(const Color(0xFF08111A));
      await controller.addJavaScriptChannel(
        _bridgeName,
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted || _isClosing) return;
            _flyAuthorizationStarted = false;
            setState(() {
              _statusText = AppLocalizations.of(
                context,
              ).fnConnectEntryLoading(_friendlyUrl(url));
            });
          },
          onPageFinished: (url) {
            unawaited(_injectBridgeScript());
            if (!mounted || _isClosing) return;
            setState(() {
              _isReady = true;
              _statusText = AppLocalizations.of(
                context,
              ).fnConnectEntryProcessing(_friendlyUrl(url));
            });
          },
          onProgress: (progress) {
            if (!mounted || _isClosing) return;
            setState(() => _progress = progress);
          },
          onWebResourceError: (error) {
            if ((error.isForMainFrame ?? false) && mounted && !_isClosing) {
              setState(() => _statusText = error.description);
            }
          },
          onSslAuthError: (error) {
            unawaited(error.cancel());
            if (!mounted || _isClosing) return;
            setState(() {
              _statusText = AppLocalizations.of(
                context,
              ).commonSslCertificateError(error.platform.description);
            });
          },
        ),
      );
      await controller.loadRequest(Uri.parse(_initialUrl));
    } catch (error) {
      _completeInitializationFailure(l10n, error);
    }
  }

  Future<void> _initializeWindows() async {
    final l10n = AppLocalizations.of(context);
    try {
      final controller = windows_webview.WebviewController();
      await controller.initialize();
      if (!mounted || _isClosing) {
        await controller.dispose();
        return;
      }
      _windowsController = controller;
      await controller.setBackgroundColor(const Color(0xFF08111A));
      await controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.sameWindow,
      );
      await controller.addScriptToExecuteOnDocumentCreated(
        _buildInjectionScript(),
      );
      if (!mounted || _isClosing) return;
      _windowsUrlSubscription = controller.url.listen((url) {
        if (!mounted || _isClosing) return;
        setState(() {
          _statusText = AppLocalizations.of(
            context,
          ).fnConnectEntryLoading(_friendlyUrl(url));
        });
      });
      _windowsLoadingSubscription = controller.loadingState.listen((state) {
        if (!mounted || _isClosing) return;
        if (state == windows_webview.LoadingState.navigationCompleted) {
          setState(() {
            _isReady = true;
            _statusText = AppLocalizations.of(
              context,
            ).fnConnectEntryProcessing(_friendlyUrl(widget.serverUrl));
          });
          unawaited(_injectBridgeScript());
        } else if (state == windows_webview.LoadingState.loading) {
          _flyAuthorizationStarted = false;
          setState(() => _isReady = false);
        }
      });
      _windowsMessageSubscription = controller.webMessage.listen((message) {
        _handleBridgeMessage(message is String ? message : jsonEncode(message));
      });
      _windowsErrorSubscription = controller.onLoadError.listen((error) {
        if (mounted && !_isClosing) setState(() => _statusText = error.name);
      });
      await controller.loadUrl(_initialUrl);
    } catch (error) {
      _completeInitializationFailure(l10n, error);
    }
  }

  Future<void> _injectBridgeScript() async {
    try {
      final controller = _windowsController;
      if (controller != null) {
        await controller.executeScript(_buildInjectionScript());
      } else {
        await _controller?.runJavaScript(_buildInjectionScript());
      }
    } catch (_) {}
  }

  String _buildInjectionScript() {
    return FnWebLoginBridgeScript.build(
      bridgeName: _bridgeName,
      userName: widget.userName,
      password: widget.password,
      requireCredentialsForAutoLogin: true,
      reportBlockedState: true,
      useWindowsWebViewMessage: defaultTargetPlatform == TargetPlatform.windows,
    );
  }

  void _handleBridgeMessage(String rawMessage) {
    if (_isClosing || rawMessage.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) return;
      final pageUrl = decoded['pageUrl']?.toString() ?? '';
      final page = Uri.tryParse(pageUrl);
      final pageHost = (page?.host ?? '').trim().toLowerCase();
      final cookie = decoded['cookie']?.toString() ?? '';
      final blocked = decoded['blocked'] == true;
      if (pageHost.isEmpty) return;

      final isEntryDomain =
          pageHost == 'fnos.net' ||
          pageHost == 'www.fnos.net' ||
          pageHost == '5ddd.com';
      // Emby 的 #!/login.html 是应用内路由；网关已放行时可交接入口令牌。
      final lower = (page?.path ?? '').toLowerCase();
      final isAuthPage =
          lower.contains('/login') ||
          lower.contains('/signin') ||
          lower.contains('/oauth') ||
          lower.contains('/authorize');
      if (isEntryDomain || isAuthPage) return;

      // 只在真正落到目标 Emby 主机、且不是被拦截页时抓取——此时的 entry-token 才是对
      // Emby 服务已生效的那个（桌面/同域页上的可能对该子服务无效）。
      if (pageHost == _targetHost) {
        if (blocked) {
          if (mounted && !_isClosing) {
            setState(() {
              _statusText = AppLocalizations.of(context).fnConnectEntryBlocked;
            });
          }
          // FN 发布应用需要从 NAS 桌面启动才能签发该应用的入口令牌。
          if (!_requiresSecureTarget &&
              !_openedFnDesktop &&
              _fnIdFamily.isNotEmpty) {
            _openedFnDesktop = true;
            unawaited(_openFnDesktop());
          }
          return;
        }
        final token = _extractEntryToken(cookie);
        if (token.isNotEmpty && _allowsTargetToken(page, isAuthPage, blocked)) {
          if (_requiresSecureTarget) {
            unawaited(_completeFlyAuthorization(token));
          } else {
            _completeSuccess(token);
          }
          return;
        }
        // 飞翔的 NAS 桌面可能与应用入口同主机，但仍需转到精确应用路径。
        if (!_requiresSecureTarget) return;
      }
    } catch (_) {}
  }

  Future<void> _openFnDesktop() async {
    final desktopUrl = 'https://$_fnIdFamily/';
    final controller = _windowsController;
    if (controller != null) {
      // 当前页面是该 NAS 的应用子域，先为同一 NAS 选择中继再进入桌面。
      await controller.executeScript(
        'document.cookie=${jsonEncode('mode=relay; domain=$_fnIdFamily; path=/; Secure')};',
      );
      if (!mounted || _isClosing) return;
      await controller.loadUrl(desktopUrl);
    } else {
      await WebViewCookieManager().setCookie(
        WebViewCookie(
          name: 'mode',
          value: 'relay',
          domain: _fnIdFamily,
          path: '/',
        ),
      );
      if (!mounted || _isClosing) return;
      await _controller?.loadRequest(Uri.parse(desktopUrl));
    }
  }

  static String _extractEntryToken(String cookie) {
    for (final raw in cookie.split(';')) {
      final entry = raw.trim();
      if (entry.toLowerCase().startsWith('entry-token=')) {
        return entry.substring('entry-token='.length).trim();
      }
    }
    return '';
  }

  Future<void> _completeFlyAuthorization(String entryToken) async {
    if (_flyAuthorizationStarted || _isClosing) return;
    _flyAuthorizationStarted = true;
    final gatewayCookies = <String, String>{};
    try {
      final controller = _windowsController;
      if (controller != null) {
        final cookies = await controller.getCookies(
          '$_targetOrigin/app/fly-data-service/api/v1/system/identity',
        );
        // 同名 Cookie 按浏览器发送顺序，优先使用路径更具体的值。
        cookies.sort(
          (a, b) => (b['path'] as String).length.compareTo(
            (a['path'] as String).length,
          ),
        );
        final selected = <String, String>{};
        for (final cookie in cookies) {
          final name = cookie['name'] as String;
          if (const {'entry-token', 'mode', 'ost'}.contains(name)) {
            selected.putIfAbsent(name, () => cookie['value'] as String);
          }
        }
        entryToken = selected['entry-token'] ?? entryToken;
        for (final name in const ['mode', 'ost']) {
          final value = selected[name];
          if (value == null || value.isEmpty) {
            throw StateError('飞牛网关授权尚未完成。');
          }
          gatewayCookies[name] = value;
        }
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        // Android 的 document.cookie 读不到 HttpOnly 网关 Cookie，必须从同一
        // WebView CookieManager 按精确身份接口 URL 读取浏览器实际会发送的值。
        final rawCookies =
            await _androidFlyGatewayCookieChannel.invokeMethod<
              String
            >('getFlyGatewayCookies', <String, String>{
              'url':
                  '$_targetOrigin/app/fly-data-service/api/v1/system/identity',
            }) ??
            '';
        final selected = _parseFlyGatewayCookieHeader(rawCookies);
        entryToken = selected['entry-token'] ?? entryToken;
        for (final name in const ['mode', 'ost']) {
          final value = selected[name];
          if (value == null || value.isEmpty) {
            throw StateError('飞牛网关授权尚未完成。');
          }
          gatewayCookies[name] = value;
        }
      }
      _completeSuccess((
        entryToken: entryToken,
        gatewayCookies: Map<String, String>.unmodifiable(gatewayCookies),
      ));
    } catch (_) {
      if (mounted && !_isClosing) {
        setState(() => _statusText = 'FN 访问授权尚未完成，请登录飞牛 OS 后点击“进入飞翔”，或刷新重试。');
      }
    }
  }

  bool get _requiresSecureTarget => widget.requireTargetPath;

  String get _initialUrl => _requiresSecureTarget && _targetOrigin.isNotEmpty
      ? '$_targetOrigin/'
      : widget.serverUrl;

  bool _allowsTargetToken(Uri? page, bool isAuthPage, bool blocked) {
    if (!_requiresSecureTarget) return true;
    if (page == null || page.scheme != 'https' || isAuthPage || blocked) {
      return false;
    }
    final path = page.path;
    return _originOf(page) == _targetOrigin &&
        (path == '/app/fly-data-service' ||
            path.startsWith('/app/fly-data-service/'));
  }

  static String _originOf(Uri? uri) {
    if (uri == null || uri.host.isEmpty) return '';
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
    ).toString().replaceFirst(RegExp(r'/$'), '');
  }

  static String _fnIdFamilyFor(String host) {
    final labels = host.split('.');
    if (labels.length < 3 || labels[labels.length - 2] != 'fnos') return '';
    return '${labels[labels.length - 3]}.fnos.net';
  }

  void _completeSuccess(Object result) {
    if (!mounted || _isClosing || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _isClosing = true;
    Navigator.of(context).pop(result);
  }

  void _completeFailure(String message) {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop(null);
  }

  void _completeInitializationFailure(AppLocalizations l10n, Object error) {
    _completeFailure(
      _requiresSecureTarget
          ? l10n.loginErrorGenericFailure
          : l10n.fnConnectEntryOpenFailed('$error'),
    );
  }

  String _friendlyUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.host}$path';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = _progress.clamp(0, 100) / 100.0;
    return Scaffold(
      backgroundColor: const Color(0xFF08111A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1724),
        foregroundColor: Colors.white,
        title: Text(
          _requiresSecureTarget
              ? '登录 FN Connect（飞翔）'
              : l10n.fnConnectEntryLoginTitle,
        ),
        actions: [
          if (_requiresSecureTarget)
            TextButton.icon(
              onPressed: _isReady ? _loadTargetUrl : null,
              icon: const Icon(Icons.login_rounded),
              label: const Text('进入飞翔'),
            )
          else
            IconButton(
              tooltip: l10n.fnConnectEntryAuthorizedBack,
              onPressed: _isReady ? _loadTargetUrl : null,
              icon: const Icon(Icons.check_circle_outline_rounded),
            ),
          IconButton(
            tooltip: l10n.fnConnectEntryReload,
            onPressed: _isReady ? () => _reload() : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: l10n.commonCancel,
            onPressed: () {
              if (_isClosing) return;
              _isClosing = true;
              Navigator.of(context).pop(null);
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
                  _statusText.isEmpty
                      ? l10n.fnConnectEntryOpening
                      : _statusText,
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
          ? (_windowsController != null
                ? windows_webview.Webview(_windowsController!)
                : WebViewWidget(controller: _controller!))
          : const Center(child: BirdLoader(size: 120)),
    );
  }

  void _loadTargetUrl() {
    final windowsController = _windowsController;
    if (windowsController != null) {
      unawaited(windowsController.loadUrl(widget.serverUrl));
    } else {
      unawaited(_controller?.loadRequest(Uri.parse(widget.serverUrl)));
    }
  }

  void _reload() {
    final windowsController = _windowsController;
    if (windowsController != null) {
      unawaited(windowsController.reload());
    } else {
      unawaited(_controller?.reload());
    }
  }

  @override
  void dispose() {
    _isClosing = true;
    unawaited(_windowsUrlSubscription?.cancel());
    unawaited(_windowsLoadingSubscription?.cancel());
    unawaited(_windowsMessageSubscription?.cancel());
    unawaited(_windowsErrorSubscription?.cancel());
    unawaited(_windowsController?.dispose());
    super.dispose();
  }
}
