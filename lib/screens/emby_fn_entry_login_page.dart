import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 抓取 FN Connect 入口令牌（cookie `entry-token`）的 WebView 页。
///
/// 藏在飞牛反向代理后面的 Emby 发布服务（`*.fnos.net`）受云端 FN Connect 边缘闸保护，
/// 唯一被认的凭据是 `.<fnId>.fnos.net` 作用域的 `entry-token` cookie——它由真实入口流程
/// （`fnos.net/<fnId>` SPA）登录后签发，无法用纯 API 复刻。本页用 WebView 跑真实流程：
/// 加载目标地址 → 入口要求登录时用户在网页内登录（可选自动填充 FN 账号）→ 落回
/// `*.fnos.net` 域后，`entry-token`（非 httpOnly）出现在 `document.cookie`，轮询抓出即返回。
class EmbyFnEntryLoginPage extends StatefulWidget {
  const EmbyFnEntryLoginPage({
    super.key,
    required this.serverUrl,
    this.userName = '',
    this.password = '',
  });

  /// 目标 Emby 服务器地址（已归一化的 `https://<sub>.<fnId>.fnos.net`）。
  final String serverUrl;

  /// 可选：FN 账号用户名 / 密码，用于在入口登录页自动填充（留空则纯手动登录）。
  final String userName;
  final String password;

  @override
  State<EmbyFnEntryLoginPage> createState() => _EmbyFnEntryLoginPageState();
}

class _EmbyFnEntryLoginPageState extends State<EmbyFnEntryLoginPage> {
  static const String _bridgeName = 'FnEntryBridge';

  late final WebViewController _controller;

  /// 目标 Emby 主机（如 `embyserver4-9.geqian688.fnos.net`）。只有当 WebView 真正落回
  /// 该主机、且 cookie 里有 entry-token 时才算抓到——这是"已过服务闸"的证明，避免在入口/
  /// 授权中途的页面（NAS 桌面等同域页）上抓到尚未生效的早期 entry-token。
  String _targetHost = '';

  bool _isReady = false;
  bool _isClosing = false;
  bool _autoRedirectedToTarget = false;
  int _progress = 0;
  String _statusText = '正在打开 FN Connect 入口...';

  @override
  void initState() {
    super.initState();
    _targetHost = (Uri.tryParse(widget.serverUrl)?.host ?? '')
        .trim()
        .toLowerCase();
    _controller = WebViewController();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(const Color(0xFF08111A));
      await _controller.addJavaScriptChannel(
        _bridgeName,
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      );
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted || _isClosing) return;
            setState(() => _statusText = '加载 ${_friendlyUrl(url)}');
          },
          onPageFinished: (url) {
            unawaited(_injectBridgeScript());
            if (!mounted || _isClosing) return;
            setState(() {
              _isReady = true;
              _statusText = '处理 ${_friendlyUrl(url)}';
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
          onSslAuthError: (error) => error.proceed(),
        ),
      );
      await _controller.loadRequest(Uri.parse(widget.serverUrl));
    } catch (error) {
      _completeFailure('打开入口失败：$error');
    }
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
  const BRIDGE = ${jsonEncode(_bridgeName)};
  const AUTO_USER = $user;
  const AUTO_PASS = $password;

  function post(payload) {
    try {
      payload = payload || {};
      payload.cookie = document.cookie || '';
      payload.pageUrl = String(window.location.href || '');
      payload.title = String(document.title || '');
      var bodyText = (document.body && document.body.innerText) || '';
      // 被拦截页（"FN Connect 访问提示 / 暂无权限"）= 当前令牌对该服务无效。
      payload.blocked =
        payload.title.indexOf('FN Connect') !== -1 ||
        bodyText.indexOf('\\u6682\\u65e0\\u6743\\u9650') !== -1;
      window[BRIDGE].postMessage(JSON.stringify(payload));
    } catch (_) {}
  }

  function triggerInput(input, value) {
    if (!input) return;
    const d = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
    if (d && d.set) { d.set.call(input, value); } else { input.value = value; }
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    input.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  function autoLogin() {
    if (!AUTO_USER && !AUTO_PASS) return;
    if (window.location.href.indexOf('/login') === -1) return;
    setTimeout(() => {
      const userInput =
        document.querySelector('#username') ||
        document.querySelector('input[name="username"]') ||
        document.querySelector('input[autocomplete="username"]') ||
        document.querySelector('input[type="text"]');
      const passInput =
        document.querySelector('#password') ||
        document.querySelector('input[name="password"]') ||
        document.querySelector('input[autocomplete="current-password"]') ||
        document.querySelector('input[type="password"]');
      if (userInput && AUTO_USER) triggerInput(userInput, AUTO_USER);
      if (passInput && AUTO_PASS) triggerInput(passInput, AUTO_PASS);
      setTimeout(() => {
        const submit = document.querySelector('button[type="submit"]');
        if (submit && !submit.disabled) submit.click();
      }, 250);
    }, 250);
  }

  function findText(elements, patterns) {
    for (let i = 0; i < elements.length; i += 1) {
      const t = String((elements[i] && (elements[i].innerText || elements[i].textContent)) || '')
        .trim().toLowerCase();
      for (let j = 0; j < patterns.length; j += 1) {
        if (t.indexOf(patterns[j].toLowerCase()) !== -1) return elements[i];
      }
    }
    return null;
  }

  function autoAuthorize() {
    // 入口的授权页：自动点"授权/同意/Authorize"，让流程走完并跳回目标服务。
    if (window.location.href.indexOf('/signin') === -1 &&
        window.location.href.indexOf('/authorize') === -1 &&
        window.location.href.indexOf('/oauth') === -1) return;
    setTimeout(() => {
      const btn = findText(
        document.querySelectorAll('button'),
        ['\\u6388\\u6743', '\\u540c\\u610f', 'Authorize', 'Agree', 'Continue', 'Allow']
      );
      if (btn && !btn.disabled) btn.click();
    }, 250);
  }

  function reportCookie() { post({ type: 'cookie' }); }

  autoLogin();
  autoAuthorize();
  reportCookie();
  let ticks = 0;
  const timer = setInterval(() => {
    ticks += 1;
    autoLogin();
    autoAuthorize();
    reportCookie();
    if (ticks >= 240) clearInterval(timer);
  }, 750);
})();
''';
  }

  void _handleBridgeMessage(String rawMessage) {
    if (_isClosing || rawMessage.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) return;
      final pageUrl = decoded['pageUrl']?.toString() ?? '';
      final pageHost = (Uri.tryParse(pageUrl)?.host ?? '').trim().toLowerCase();
      final cookie = decoded['cookie']?.toString() ?? '';
      final blocked = decoded['blocked'] == true;
      if (pageHost.isEmpty) return;

      final isEntryDomain =
          pageHost == 'fnos.net' ||
          pageHost == 'www.fnos.net' ||
          pageHost == '5ddd.com';
      final lower = pageUrl.toLowerCase();
      final isAuthPage =
          lower.contains('/login') ||
          lower.contains('/signin') ||
          lower.contains('/oauth') ||
          lower.contains('/authorize');
      if (isEntryDomain || isAuthPage) return;

      final names = cookie
          .split(';')
          .map((e) => e.split('=').first.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      debugPrint(
        '[EmbyEntry] host=$pageHost blocked=$blocked cookies=$names url=$pageUrl',
      );

      // 只在真正落到目标 Emby 主机、且不是被拦截页时抓取——此时的 entry-token 才是对
      // Emby 服务已生效的那个（桌面/同域页上的可能对该子服务无效）。
      if (pageHost == _targetHost) {
        if (blocked) {
          if (mounted && !_isClosing) {
            setState(() {
              _statusText = 'Emby 访问被拦截：请在页面里从飞牛桌面打开 Emby 应用完成授权';
            });
          }
          return;
        }
        final token = _extractEntryToken(cookie);
        if (token.isNotEmpty) {
          _completeSuccess(token);
        }
        return;
      }

      // 已登录的同域页（飞牛桌面）：自动跳一次目标 Emby 地址去触发该服务的令牌签发/校验。
      if (pageHost.endsWith('.fnos.net') && !_autoRedirectedToTarget) {
        _autoRedirectedToTarget = true;
        debugPrint('[EmbyEntry] redirect → ${widget.serverUrl}');
        unawaited(_controller.loadRequest(Uri.parse(widget.serverUrl)));
      }
    } catch (_) {}
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

  void _completeSuccess(String entryToken) {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    Navigator.of(context).pop(entryToken);
  }

  void _completeFailure(String message) {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop(null);
  }

  String _friendlyUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.host}$path';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress.clamp(0, 100) / 100.0;
    return Scaffold(
      backgroundColor: const Color(0xFF08111A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1724),
        foregroundColor: Colors.white,
        title: const Text('登录 FN Connect（Emby）'),
        actions: [
          IconButton(
            tooltip: '我已授权 · 回到 Emby',
            onPressed: _isReady
                ? () => _controller.loadRequest(Uri.parse(widget.serverUrl))
                : null,
            icon: const Icon(Icons.check_circle_outline_rounded),
          ),
          IconButton(
            tooltip: '重新加载',
            onPressed: _isReady ? () => _controller.reload() : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '取消',
            onPressed: () {
              if (_isClosing) return;
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
