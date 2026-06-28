import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/emby_api.dart';
import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/session/media_backend_connection.dart';
import '../providers/backend_session_provider.dart';
import '../providers/nas_provider.dart';
import '../services/media_backend_connection_store.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
import '../utils/action_rate_limiter.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../utils/login_error_resolver.dart';
import '../utils/nas_image_headers.dart';
import '../services/login_history_store.dart';
import '../services/fn_connect_web_session_service.dart';
import 'download_list_screen.dart';
import 'emby_fn_entry_login_page.dart';
import 'fn_connect_web_login_page.dart';
import 'login_history_screen.dart';
import '../utils/app_confirm_dialog.dart';

enum _ConnectionBackend { feiniu, emby }

String effectivePersistedBaseUrlForLogin({
  required String sourceBaseUrl,
  required LoginWithBaseUrlResult loginResult,
}) {
  final resolvedBaseUrl = loginResult.resolvedBaseUrl.trim();
  if (loginResult.usedFnConnect && resolvedBaseUrl.isNotEmpty) {
    return resolvedBaseUrl;
  }
  return sourceBaseUrl;
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, this.embyApi});

  final EmbyApi? embyApi;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _embyBaseUrlController = TextEditingController();
  final TextEditingController _embyUserNameController = TextEditingController();
  final TextEditingController _embyPasswordController = TextEditingController();
  final DetailTopTip _topTip = DetailTopTip();
  final ActionRateLimiter _submitLimiter = ActionRateLimiter(
    cooldown: const Duration(milliseconds: 900),
  );

  _ConnectionBackend _selectedBackend = _ConnectionBackend.feiniu;
  String _baseUrlScheme = 'http';
  double _swipeStartX = 0;
  double _swipeStartY = 0;
  double _swipeLastX = 0;
  double _swipeLastY = 0;
  bool _rememberPassword = true;
  bool _embyRememberPassword = true;
  bool _obscurePassword = true;
  bool _obscureEmbyPassword = true;
  bool _isSubmitting = false;
  List<LoginHistoryEntry> _historyEntries = const <LoginHistoryEntry>[];
  final String _embyConnectionStatus = '';

  /// 已保存/已抓取的 FN Connect 入口令牌（entry-token）。fnos 中转 Emby 登录复用它过边缘闸。
  String _embyEntryToken = '';

  @override
  void initState() {
    super.initState();
    final provider = context.read<NasProvider>();
    _baseUrlController.text = _displayBaseUrlForLogin(provider.sourceBaseUrl);
    _baseUrlScheme = _schemeForLogin(provider.sourceBaseUrl);
    _userNameController.text = provider.userName;
    _passwordController.text = provider.password;
    _rememberPassword = provider.rememberPassword;
    _loadLoginHistory();
    unawaited(_loadStoredBackendConnection());
  }

  @override
  void dispose() {
    _topTip.dispose();
    _baseUrlController.dispose();
    _userNameController.dispose();
    _passwordController.dispose();
    _embyBaseUrlController.dispose();
    _embyUserNameController.dispose();
    _embyPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadLoginHistory() async {
    final entries = await LoginHistoryStore.load();
    if (!mounted) return;
    setState(() {
      _historyEntries = entries;
    });
  }

  void _showTopTip(String message, Color color) {
    if (!mounted || message.trim().isEmpty) return;
    _topTip.show(context, message: message, color: color);
  }

  Future<void> _loadStoredBackendConnection() async {
    final snapshot = await MediaBackendConnectionStore.load();
    final embyConnection = snapshot.connectionFor(MediaBackendKind.emby);
    if (!mounted || embyConnection == null) return;
    setState(() {
      if (snapshot.activeKind == MediaBackendKind.emby) {
        _selectedBackend = _ConnectionBackend.emby;
      }
      if (_embyBaseUrlController.text.trim().isEmpty) {
        _embyBaseUrlController.text = embyConnection.serverUrl;
      }
      if (_embyUserNameController.text.trim().isEmpty) {
        _embyUserNameController.text = embyConnection.userName;
      }
      _embyRememberPassword = embyConnection.rememberSecret;
      if (embyConnection.rememberSecret &&
          _embyPasswordController.text.isEmpty) {
        _embyPasswordController.text = embyConnection.secret;
      }
      _embyEntryToken = embyConnection.entryToken;
    });
  }

  Future<void> _reportAndShowLoginError(
    Object error, {
    StackTrace? stackTrace,
    String? details,
  }) async {
    await AppErrorReporter.report(
      error,
      action: 'login',
      source: 'connection_screen',
      stackTrace: stackTrace,
      fallbackKind: AppExceptionKind.unauthorized,
      details: details,
    );
    if (!mounted) return;
    _showTopTip(
      LoginErrorResolver.resolve(error, l10n: AppLocalizations.of(context)),
      context.appColors.danger,
    );
  }

  Future<void> _submit() async {
    switch (_selectedBackend) {
      case _ConnectionBackend.feiniu:
        await _submitWithUnifiedErrors();
        return;
      case _ConnectionBackend.emby:
        await _verifyEmbyConnection();
        return;
    }
  }

  Future<void> _verifyEmbyConnection() async {
    FocusScope.of(context).unfocus();
    final baseUrl = _normalizeEmbyBaseUrlInput(_embyBaseUrlController.text);
    final userName = _embyUserNameController.text.trim();
    final password = _embyPasswordController.text;

    if (_isSubmitting || _submitLimiter.shouldBlock()) {
      _showTopTip(
        AppLocalizations.of(context).connectionOperationFailedRetryLater,
        const Color(0xFFB8860B),
      );
      return;
    }
    if (baseUrl.isEmpty) {
      _showTopTip(
        AppLocalizations.of(context).connectionEmbyServerRequired,
        context.appColors.danger,
      );
      return;
    }
    if (userName.isEmpty) {
      _showTopTip(
        AppLocalizations.of(context).connectionUserNameRequired,
        context.appColors.danger,
      );
      return;
    }
    if (password.isEmpty) {
      _showTopTip(
        AppLocalizations.of(context).connectionPasswordRequired,
        context.appColors.danger,
      );
      return;
    }

    final isRelay = usesFnConnectRelayCookie(baseUrl);

    setState(() {
      _isSubmitting = true;
      _embyBaseUrlController.text = baseUrl;
    });

    try {
      var entryToken = _embyEntryToken;
      // fnos 中转域：Emby 藏在飞牛反向代理后面，请求必须带 FN Connect 入口令牌
      // （entry-token cookie）过云端边缘闸。没有就先用 WebView 走真实入口登录抓取。
      if (isRelay && entryToken.isEmpty) {
        final captured = await _captureEmbyEntryToken(baseUrl);
        if (!mounted) return;
        if (captured == null) return; // 取消/失败，提示已在 helper 内给出
        entryToken = captured;
      }

      final result = await _authenticateEmby(
        baseUrl: baseUrl,
        userName: userName,
        password: password,
        entryToken: entryToken,
        allowRecapture: isRelay && widget.embyApi == null,
        onEntryTokenRefreshed: (refreshed) => entryToken = refreshed,
      );
      if (!mounted) return;

      if (result.accessToken.trim().isEmpty || result.userId.trim().isEmpty) {
        throw AppException.api(
          action: 'emby login',
          message: AppLocalizations.of(context).connectionEmbySessionIncomplete,
        );
      }
      _embyEntryToken = entryToken;
      final connection = MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: result.serverUrl,
        displayName: result.serverName,
        userName: result.userName,
        userId: result.userId,
        accessToken: result.accessToken,
        secret: _embyRememberPassword ? password : '',
        rememberSecret: _embyRememberPassword,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        entryToken: entryToken,
      );
      await (_backendSessionProvider()?.saveActive(connection) ??
          MediaBackendConnectionStore.saveActive(connection));
      final entries = await LoginHistoryStore.save(
        LoginHistoryEntry(
          kind: MediaBackendKind.emby,
          baseUrl: connection.serverUrl,
          userName: connection.userName,
          password: _embyRememberPassword ? password : '',
          rememberPassword: _embyRememberPassword,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      setState(() {
        _embyBaseUrlController.text = connection.serverUrl;
        _embyUserNameController.text = connection.userName;
        _embyPasswordController.text = password;
        _historyEntries = entries;
      });
    } catch (error, stackTrace) {
      await _reportAndShowLoginError(
        error,
        stackTrace: stackTrace,
        details: 'emby_login',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// 调用 Emby 登录；fnos 中转域命中云端边缘闸（403）时，自动重抓一次入口令牌再试。
  ///
  /// 注意：403 = 云端 FN Connect 边缘闸（入口令牌缺失/过期）；Emby 自身用户名密码错误是
  /// 401，不触发重抓。注入了自定义 [widget.embyApi]（单测）时不重抓。
  Future<EmbyAuthenticateResult> _authenticateEmby({
    required String baseUrl,
    required String userName,
    required String password,
    required String entryToken,
    required bool allowRecapture,
    required ValueChanged<String> onEntryTokenRefreshed,
  }) async {
    EmbyApi build(String token) =>
        widget.embyApi ?? EmbyApi(entryTokenProvider: () => token);
    Future<EmbyAuthenticateResult> attempt(String token) =>
        build(token).authenticateByName(
          serverUrl: baseUrl,
          userName: userName,
          password: password,
        );
    try {
      return await attempt(entryToken);
    } on DioException catch (error) {
      if (allowRecapture && error.response?.statusCode == 403) {
        final recaptured = await _captureEmbyEntryToken(baseUrl);
        if (recaptured == null) rethrow;
        onEntryTokenRefreshed(recaptured);
        return attempt(recaptured);
      }
      rethrow;
    }
  }

  /// 打开 WebView 走真实 FN Connect 入口流程，抓取 `entry-token`。取消/失败返回 null。
  Future<String?> _captureEmbyEntryToken(String baseUrl) async {
    if (!mounted) return null;
    final nas = context.read<NasProvider>();
    final token = await Navigator.of(context).push<String>(
      AppTransitions.leftToRightPageTurnRoute<String>(
        EmbyFnEntryLoginPage(
          serverUrl: baseUrl,
          // 入口认的是 FN 账号；若已填飞牛账号则尝试自动填充，否则在网页内手动登录。
          userName: nas.userName,
          password: nas.password,
        ),
        fullscreenDialog: true,
      ),
    );
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) {
      if (mounted) {
        _showTopTip(
          AppLocalizations.of(context).fnConnectEntryTokenMissing,
          context.appColors.warning,
        );
      }
      return null;
    }
    return trimmed;
  }

  Future<void> _submitWithUnifiedErrors() async {
    FocusScope.of(context).unfocus();

    if (_isSubmitting || _submitLimiter.shouldBlock()) {
      _showTopTip(
        AppLocalizations.of(context).connectionOperationFailedRetryLater,
        const Color(0xFFB8860B),
      );
      return;
    }

    final baseUrl = _normalizeBaseUrlInput(_baseUrlController.text);
    final userName = _userNameController.text.trim();
    final password = _passwordController.text;

    if (baseUrl.isEmpty) {
      _showTopTip(
        AppLocalizations.of(context).connectionServerRequired,
        context.appColors.danger,
      );
      return;
    }
    if (userName.isEmpty) {
      _showTopTip(
        AppLocalizations.of(context).connectionUserNameRequired,
        context.appColors.danger,
      );
      return;
    }
    if (password.isEmpty) {
      _showTopTip(
        AppLocalizations.of(context).connectionPasswordRequired,
        context.appColors.danger,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _baseUrlScheme = _schemeForLogin(baseUrl);
      _baseUrlController.text = _displayBaseUrlForLogin(baseUrl);
    });

    try {
      final loginResult = await FeiniuApi.loginWithBaseUrl(
        baseUrl: baseUrl,
        userName: userName,
        password: password,
      );
      if (!mounted) return;
      await _applyLoginResult(
        sourceBaseUrl: baseUrl,
        userName: userName,
        password: password,
        loginResult: loginResult,
      );
    } on FnConnectLoginException catch (error) {
      final fallbackResult = await _tryFnConnectWebFallback(
        baseUrl: baseUrl,
        userName: userName,
        password: password,
        error: error,
      );
      if (!mounted) return;
      if (fallbackResult?.isSuccess == true) {
        await _applyLoginResult(
          sourceBaseUrl: baseUrl,
          userName: userName,
          password: password,
          loginResult: fallbackResult!.loginResult!,
        );
      } else if (fallbackResult?.errorMessage?.trim().isNotEmpty == true) {
        await _reportAndShowLoginError(
          fallbackResult!.errorMessage!.trim(),
          details: 'fn_connect_web_fallback',
        );
      } else {
        await _reportAndShowLoginError(error, details: 'fn_connect_direct');
      }
    } catch (error, stackTrace) {
      await _reportAndShowLoginError(
        error,
        stackTrace: stackTrace,
        details: 'direct_login',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _applyLoginResult({
    required String sourceBaseUrl,
    required String userName,
    required String password,
    required LoginWithBaseUrlResult loginResult,
  }) async {
    final persistedBaseUrl = effectivePersistedBaseUrlForLogin(
      sourceBaseUrl: sourceBaseUrl,
      loginResult: loginResult,
    );
    await context.read<NasProvider>().updateSettings(
      baseUrl: persistedBaseUrl,
      resolvedBaseUrl: loginResult.usedFnConnect
          ? ''
          : loginResult.resolvedBaseUrl,
      userName: userName,
      password: password,
      rememberPassword: _rememberPassword,
      token: loginResult.token,
    );
    final entries = await LoginHistoryStore.save(
      LoginHistoryEntry(
        baseUrl: sourceBaseUrl,
        userName: userName,
        password: _rememberPassword ? password : '',
        rememberPassword: _rememberPassword,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (!mounted) return;
    setState(() {
      _historyEntries = entries;
    });
  }

  Future<void> _openLoginHistory() async {
    FocusScope.of(context).unfocus();
    // 进入历史页前先刷新一次，确保拿到最新（含其它后端）的登录历史。
    final latest = await LoginHistoryStore.load();
    if (!mounted) return;
    setState(() {
      _historyEntries = latest;
    });
    final selected = await Navigator.of(context).push<LoginHistoryEntry>(
      AppTransitions.leftToRightPageTurnRoute<LoginHistoryEntry>(
        LoginHistoryScreen(entries: _historyEntries),
        fullscreenDialog: true,
      ),
    );
    // 历史页内可能删除/清空，回来时同步最新列表。
    final refreshed = await LoginHistoryStore.load();
    if (!mounted) return;
    setState(() {
      _historyEntries = refreshed;
    });
    if (selected == null) return;
    _applyHistorySelection(selected);
  }

  /// 把历史记录回填到对应后端表单，并切换到该后端 Tab。
  void _applyHistorySelection(LoginHistoryEntry entry) {
    if (entry.kind == MediaBackendKind.emby) {
      _embyBaseUrlController.text = entry.baseUrl;
      _embyUserNameController.text = entry.userName;
      _embyPasswordController.text = entry.rememberPassword
          ? entry.password
          : '';
      // 历史记录不含 entry-token；切到不同服务器时清空旧令牌，鉴权流程会按需重抓。
      _embyEntryToken = '';
      setState(() {
        _embyRememberPassword = entry.rememberPassword;
        _selectedBackend = _ConnectionBackend.emby;
      });
      return;
    }
    _baseUrlController.text = _displayBaseUrlForLogin(entry.baseUrl);
    _userNameController.text = entry.userName;
    _passwordController.text = entry.rememberPassword ? entry.password : '';
    setState(() {
      _baseUrlScheme = _schemeForLogin(entry.baseUrl);
      _rememberPassword = entry.rememberPassword;
      _selectedBackend = _ConnectionBackend.feiniu;
    });
  }

  Future<void> _resetFnConnectWebLoginState() async {
    if (_isSubmitting) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.fnConnectReloginTitle,
      content: l10n.fnConnectReloginContent,
      cancelText: l10n.commonCancel,
      confirmText: l10n.fnConnectReloginConfirm,
      confirmColor: context.appColors.warning,
    );
    if (!mounted || !confirmed) return;
    setState(() {
      _isSubmitting = true;
    });
    try {
      await FnConnectWebSessionService.clearLoginState();
      if (mounted) {
        await context.read<NasProvider>().logout();
      }
      if (!mounted) return;
      _showTopTip(l10n.fnConnectReloginSuccess, context.appColors.accent);
    } catch (error, stackTrace) {
      await AppErrorReporter.report(
        error,
        action: 'clear fn connect web login state',
        source: 'connection_screen',
        stackTrace: stackTrace,
        fallbackKind: AppExceptionKind.transient,
      );
      if (!mounted) return;
      _showTopTip(l10n.fnConnectReloginFailure, context.appColors.danger);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _openDownloadedData() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        const DownloadListScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<FnConnectWebLoginPageResult?> _tryFnConnectWebFallback({
    required String baseUrl,
    required String userName,
    required String password,
    required FnConnectLoginException error,
  }) async {
    final fnConnectId = FeiniuApi.extractFnConnectIdFromInput(baseUrl);
    if (fnConnectId == null || error.error.isUnauthorized) {
      return null;
    }
    if (!_shouldUseFnConnectWebFallback(error)) {
      return null;
    }
    if (!mounted) {
      return null;
    }
    return Navigator.of(context).push<FnConnectWebLoginPageResult>(
      AppTransitions.leftToRightPageTurnRoute<FnConnectWebLoginPageResult>(
        FnConnectWebLoginPage(
          fnConnectId: fnConnectId,
          userName: userName,
          password: password,
          relayHosts:
              error.diagnostic.discovery?.relayHosts ?? const <String>[],
        ),
        fullscreenDialog: true,
      ),
    );
  }

  bool _shouldUseFnConnectWebFallback(FnConnectLoginException error) {
    final message = error.error.message.toLowerCase();
    if (message.contains('relay-only')) return true;
    if (message.contains('web-only')) return true;
    if (message.contains('none of them were reachable')) return true;
    if (message.contains('direct api address')) return true;

    final hasAttempts = error.diagnostic.attempts.isNotEmpty;
    final hasReachabilityFailure = error.diagnostic.attempts.any((attempt) {
      final status = attempt.status.toLowerCase();
      return status == 'connection' ||
          status == 'timeout' ||
          status == 'transient' ||
          status == 'redirect' ||
          status.startsWith('http-');
    });
    return hasAttempts && hasReachabilityFailure;
  }

  // ignore: unused_element
  String _resolveLoginError(Object error) {
    final raw = error is FnConnectLoginException
        ? error.error.message.trim()
        : error.toString().replaceFirst('Exception: ', '').trim();
    final message = raw.toLowerCase();

    if (message.contains('password incorrect') ||
        message.contains('incorrect password') ||
        message.contains('incorrect') ||
        message.contains('username or password') ||
        message.contains('password error') ||
        message.contains('auth failed') ||
        message.contains('forbidden') ||
        message.contains('unauthorized') ||
        message.contains('401')) {
      return AppLocalizations.of(context).connectionInvalidCredential;
    }

    if (message.contains('socketexception') ||
        message.contains('timed out') ||
        message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable')) {
      return AppLocalizations.of(context).connectionNetworkError;
    }

    if (message.contains('format') ||
        message.contains('invalid uri') ||
        message.contains('invalid argument')) {
      return AppLocalizations.of(context).connectionValidationFailed;
    }

    if (message.contains('fn connect') ||
        message.contains('302') ||
        message.contains('redirection')) {
      return raw;
    }

    if (_containsChinese(raw)) {
      return raw;
    }

    return AppLocalizations.of(context).connectionOperationFailedRetry;
  }

  bool _containsChinese(String value) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
  }

  String _normalizeBaseUrlInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final fnConnectId = FeiniuApi.extractFnConnectIdFromInput(trimmed);
    if (fnConnectId != null) {
      return fnConnectId;
    }
    final explicitUri = Uri.tryParse(trimmed);
    final explicitScheme = explicitUri?.scheme.toLowerCase() ?? '';
    final scheme = explicitScheme == 'http' || explicitScheme == 'https'
        ? explicitScheme
        : _baseUrlScheme;
    final withScheme = trimmed.contains('://') ? trimmed : '$scheme://$trimmed';
    try {
      final uri = Uri.parse(withScheme);
      if (uri.host.isEmpty && !withScheme.contains(RegExp(r'^\w+://[^/]+'))) {
        return '';
      }
      final normalized = uri.replace(scheme: scheme).toString();
      return ApiUrlHelper.normalizeBaseUrl(normalized);
    } catch (_) {
      return '';
    }
  }

  String _schemeForLogin(String raw) {
    final scheme = Uri.tryParse(raw.trim())?.scheme.toLowerCase();
    return scheme == 'https' ? 'https' : 'http';
  }

  String _displayBaseUrlForLogin(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return trimmed;
    }
    if (uri.scheme.toLowerCase() != 'http' &&
        uri.scheme.toLowerCase() != 'https') {
      return trimmed;
    }
    final buffer = StringBuffer(uri.host);
    if (uri.hasPort) {
      buffer.write(':${uri.port}');
    }
    final path = uri.path.trim();
    if (path.isNotEmpty && path != '/') {
      buffer.write(path);
    }
    if (uri.hasQuery) {
      buffer.write('?${uri.query}');
    }
    return buffer.toString();
  }

  String _normalizeEmbyBaseUrlInput(String raw) {
    final normalized = EmbyApi.normalizeServerUrl(raw);
    if (normalized.isEmpty) return '';
    try {
      final uri = Uri.parse(normalized);
      if (uri.host.isEmpty) return '';
      return normalized;
    } catch (_) {
      return '';
    }
  }

  BackendSessionProvider? _backendSessionProvider() {
    try {
      return context.read<BackendSessionProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF08111A),
      body: Listener(
        onPointerDown: _handleSwipePointerDown,
        onPointerMove: _handleSwipePointerMove,
        onPointerUp: _handleSwipePointerUp,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 0),
                      _LogoHeader(title: l10n.connectionAppName),
                      const SizedBox(height: 16),
                      _BackendSelector(
                        l10n: l10n,
                        selected: _selectedBackend,
                        onChanged: (backend) {
                          setState(() {
                            _selectedBackend = backend;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      _buildForm(theme, l10n),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSwipePointerDown(PointerDownEvent event) {
    _swipeStartX = event.position.dx;
    _swipeStartY = event.position.dy;
    _swipeLastX = event.position.dx;
    _swipeLastY = event.position.dy;
  }

  void _handleSwipePointerMove(PointerMoveEvent event) {
    _swipeLastX = event.position.dx;
    _swipeLastY = event.position.dy;
  }

  void _handleSwipePointerUp(PointerUpEvent event) {
    final dx = _swipeLastX - _swipeStartX;
    final dy = _swipeLastY - _swipeStartY;
    if (dx.abs() < 80 || dx.abs() < dy.abs() * 1.4) return;
    final next = dx < 0 ? _ConnectionBackend.emby : _ConnectionBackend.feiniu;
    if (next == _selectedBackend) return;
    setState(() {
      _selectedBackend = next;
    });
  }

  /// 后端表单：单一持久面板 + 内部字段的方向性滑动切换。
  ///
  /// 不再用 `AnimatedSwitcher` 跨淡「两整套带阴影的表单」——`FadeTransition` 的
  /// opacity 会强制离屏 `saveLayer`，叠在海报墙背景上直接 GPU 超支（极卡），叠加
  /// `ScaleTransition` 与 layoutBuilder 对齐不一致还会抖。这里面板常驻（阴影只栅格化
  /// 一次），只对内部字段做**纯位移**滑动（无 opacity/scale，无离屏层），顺滑不抖。
  Widget _buildForm(ThemeData theme, AppLocalizations l10n) {
    final isEmby = _selectedBackend == _ConnectionBackend.emby;
    return SizedBox(
      height: 432,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LoginFormPanel(
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                transitionBuilder: (child, animation) {
                  final key = child.key;
                  final isIncoming =
                      key is ValueKey<_ConnectionBackend> &&
                      key.value == _selectedBackend;
                  // 选 Emby（右侧）时新卡从右进、旧卡向左出；选飞牛（左侧）反向。
                  final dx = isEmby ? 1.0 : -1.0;
                  final position = isIncoming
                      ? Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
                      : Tween<Offset>(begin: Offset(-dx, 0), end: Offset.zero);
                  return SlideTransition(
                    position: position.animate(animation),
                    child: child,
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<_ConnectionBackend>(_selectedBackend),
                  child: _buildFormFields(theme, l10n, isEmby: isEmby),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _SubmitButton(
            isSubmitting: _isSubmitting,
            label: l10n.connectionLogin,
            onPressed: _isSubmitting ? null : _submit,
          ),
          if (!isEmby) ...[
            const SizedBox(height: 10),
            _buildFeiniuFooter(theme, l10n),
          ],
        ],
      ),
    );
  }

  /// 单套表单字段（服务器/账号/密码/记住）。飞牛与 Emby 结构一致，仅控制器与文案不同，
  /// 共用此构建以保证两态高度严格相等——滑动切换时面板不重排、不抖。
  Widget _buildFormFields(
    ThemeData theme,
    AppLocalizations l10n, {
    required bool isEmby,
  }) {
    final baseController = isEmby ? _embyBaseUrlController : _baseUrlController;
    final userController = isEmby
        ? _embyUserNameController
        : _userNameController;
    final passwordController = isEmby
        ? _embyPasswordController
        : _passwordController;
    final obscure = isEmby ? _obscureEmbyPassword : _obscurePassword;
    final remember = isEmby ? _embyRememberPassword : _rememberPassword;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlassField(
          controller: baseController,
          labelText: isEmby
              ? l10n.connectionEmbyServerLabel
              : l10n.connectionServerLabel,
          hintText: isEmby
              ? l10n.connectionEmbyServerExample
              : l10n.connectionServerExample,
          leadingIcon: Icons.dns_outlined,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.url],
          suffix: IconButton(
            onPressed: _openLoginHistory,
            icon: Icon(
              Icons.history_rounded,
              color: _historyEntries.isEmpty
                  ? const Color(0xFF58687C)
                  : const Color(0xFF7C8DA5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GlassField(
          controller: userController,
          labelText: l10n.connectionAccountLabel,
          hintText: l10n.connectionUserNameHint,
          leadingIcon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.username],
        ),
        const SizedBox(height: 12),
        _GlassField(
          controller: passwordController,
          labelText: l10n.connectionPasswordHint,
          hintText: '',
          leadingIcon: Icons.lock_outline_rounded,
          obscureText: obscure,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.password],
          onSubmitted: (_) => _submit(),
          suffix: IconButton(
            onPressed: () {
              setState(() {
                if (isEmby) {
                  _obscureEmbyPassword = !_obscureEmbyPassword;
                } else {
                  _obscurePassword = !_obscurePassword;
                }
              });
            },
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFF8795AD),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildRememberRow(
          theme,
          l10n,
          value: remember,
          onChanged: (value) {
            setState(() {
              if (isEmby) {
                _embyRememberPassword = value;
              } else {
                _rememberPassword = value;
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildFeiniuFooter(ThemeData theme, AppLocalizations l10n) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 2,
        children: [
          TextButton(
            onPressed: _openDownloadedData,
            style: _footerButtonStyle(
              theme,
              foregroundColor: const Color(0xFF8FA6C7),
            ),
            child: Text(l10n.connectionOpenDownloads),
          ),
          TextButton(
            onPressed: _isSubmitting ? null : _resetFnConnectWebLoginState,
            style: _footerButtonStyle(
              theme,
              foregroundColor: const Color(0xFFB6A06A),
              disabledForegroundColor: const Color(0xFF5D5A52),
              fontWeight: FontWeight.w600,
            ),
            child: Text(l10n.fnConnectReloginTitle),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildEmbyFormLegacy(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlassField(
          controller: _embyBaseUrlController,
          hintText: l10n.connectionEmbyServerLabel,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.url],
          suffix: IconButton(
            onPressed: _openLoginHistory,
            icon: Icon(
              Icons.history_rounded,
              color: _historyEntries.isEmpty
                  ? const Color(0xFF58687C)
                  : const Color(0xFF7C8DA5),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _GlassField(
          controller: _embyUserNameController,
          hintText: l10n.connectionUserNameHint,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.username],
        ),
        const SizedBox(height: 14),
        _GlassField(
          controller: _embyPasswordController,
          hintText: l10n.connectionPasswordHint,
          obscureText: _obscureEmbyPassword,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.password],
          onSubmitted: (_) => _submit(),
          suffix: IconButton(
            onPressed: () {
              setState(() {
                _obscureEmbyPassword = !_obscureEmbyPassword;
              });
            },
            icon: Icon(
              _obscureEmbyPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFF7C8DA5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildRememberRow(
          theme,
          l10n,
          value: _embyRememberPassword,
          onChanged: (value) {
            setState(() {
              _embyRememberPassword = value;
            });
          },
        ),
        if (_embyConnectionStatus.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _embyConnectionStatus,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF8FB7FF),
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 22),
        _SubmitButton(
          isSubmitting: _isSubmitting,
          label: l10n.connectionLogin,
          onPressed: _isSubmitting ? null : _verifyEmbyConnection,
        ),
      ],
    );
  }

  Widget _buildRememberRow(
    ThemeData theme,
    AppLocalizations l10n, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(!value),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: value,
                  onChanged: (next) => onChanged(next ?? false),
                  side: const BorderSide(color: Color(0xFF4D5C6F)),
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? const Color(0xFF2D74D9)
                        : Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                l10n.connectionRememberLogin,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFB3C0D4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ButtonStyle _footerButtonStyle(
    ThemeData theme, {
    required Color foregroundColor,
    Color? disabledForegroundColor,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    return TextButton.styleFrom(
      foregroundColor: foregroundColor,
      disabledForegroundColor: disabledForegroundColor,
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: theme.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: fontWeight,
      ),
    );
  }
}

class _BackendSelector extends StatelessWidget {
  const _BackendSelector({
    required this.l10n,
    required this.selected,
    required this.onChanged,
  });

  final AppLocalizations l10n;
  final _ConnectionBackend selected;
  final ValueChanged<_ConnectionBackend> onChanged;

  @override
  Widget build(BuildContext context) {
    final isEmby = selected == _ConnectionBackend.emby;
    final selectedAlignment = isEmby ? Alignment.center : Alignment.centerLeft;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xC10B1726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF253651)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            // 滑动高亮：跟随选中项在左右半区间平滑移动。
            AnimatedAlign(
              duration: AppTransitions.contentSwitchDuration,
              curve: Curves.easeOutCubic,
              alignment: selectedAlignment,
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0x182D74D9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF3F84FF)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x552D74D9),
                        blurRadius: 16,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _BackendSelectorButton(
                    label: l10n.connectionFeiniuMedia,
                    selected: !isEmby,
                    onTap: () => onChanged(_ConnectionBackend.feiniu),
                  ),
                ),
                Expanded(
                  child: _BackendSelectorButton(
                    label: 'Emby',
                    selected: isEmby,
                    onTap: () => onChanged(_ConnectionBackend.emby),
                  ),
                ),
                const Expanded(
                  child: _BackendSelectorButton(
                    label: 'Jellyfin',
                    assetName: 'lib/img/jellyfin_logo.png',
                    selected: false,
                    enabled: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BackendSelectorButton extends StatelessWidget {
  const _BackendSelectorButton({
    required this.label,
    required this.selected,
    this.assetName,
    this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final String? assetName;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effectiveAssetName =
        assetName ??
        (label == 'Emby' ? 'lib/img/Emby_logo.png' : 'lib/img/feiniu_Logo.png');
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: AnimatedDefaultTextStyle(
          duration: AppTransitions.contentSwitchDuration,
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: selected
                ? Colors.white
                : enabled
                ? const Color(0xFFB6C0D1)
                : const Color(0xFF8390A5),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                effectiveAssetName,
                width: 28,
                height: 28,
                fit: BoxFit.contain,
                opacity: AlwaysStoppedAnimation<double>(enabled ? 1 : 0.58),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.isSubmitting,
    required this.label,
    required this.onPressed,
  });

  final bool isSubmitting;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2D74D9),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF1E4B89),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        child: isSubmitting
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _LogoHeader extends StatelessWidget {
  final String title;

  const _LogoHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'lib/img/app_logo.png',
          width: 68,
          height: 68,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context).connectionTagline,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFA7B6D2),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _LoginFormPanel extends StatelessWidget {
  const _LoginFormPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xC90B1726),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF405675)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 36,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: child,
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  const _GlassField({
    required this.controller,
    required this.hintText,
    this.labelText,
    this.leadingIcon,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final IconData? leadingIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final label = labelText?.trim() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xD80B1624),
        border: Border.all(color: const Color(0xFF24344C)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            const SizedBox(width: 18),
            Icon(leadingIcon, color: const Color(0xFF91A0BB), size: 24),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofillHints: autofillHints,
              onSubmitted: onSubmitted,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: label.isEmpty ? null : label,
                hintText: hintText,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: const TextStyle(
                  color: Color(0xFFB6C1D4),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: const TextStyle(
                  color: Color(0xFF6E7C92),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: suffix,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF9FB0C7),
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
