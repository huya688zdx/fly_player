import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/emby_api.dart';
import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_backend_registry.dart';
import '../media_backend/session/media_backend_connection.dart';
import '../providers/backend_session_provider.dart';
import '../providers/nas_provider.dart';
import '../services/media_backend_connection_store.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
import '../utils/action_rate_limiter.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/connection_server_address.dart';
import '../utils/detail_top_tip.dart';
import '../utils/login_error_resolver.dart';
import '../utils/nas_image_headers.dart';
import '../utils/swallowed_error_logger.dart';
import '../services/login_history_store.dart';
import '../services/fn_connect_web_session_service.dart';
import 'download_list_screen.dart';
import 'emby_fn_entry_login_page.dart';
import 'fn_connect_web_login_page.dart';
import 'login_history_screen.dart';
import '../utils/app_confirm_dialog.dart';

/// 服务器族后端（Emby / Jellyfin…）共用的一套登录表单状态。
///
/// 每个注册表登记的服务器族后端各持一份，表单结构一致（地址 / 账号 / 密码 / 记住 /
/// entry-token），新增后端零表单代码。
class _ServerLoginFormState {
  final TextEditingController baseUrl = TextEditingController();
  final TextEditingController userName = TextEditingController();
  final TextEditingController password = TextEditingController();
  bool obscurePassword = true;
  bool rememberPassword = true;

  /// 已保存/已抓取的 FN Connect 入口令牌（entry-token）。fnos 中转地址登录复用它过边缘闸。
  String entryToken = '';

  void dispose() {
    baseUrl.dispose();
    userName.dispose();
    password.dispose();
  }
}

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

typedef FeiniuLoginCallback =
    Future<LoginWithBaseUrlResult> Function({
      required String baseUrl,
      required String userName,
      required String password,
      required String accessCode,
    });

const Color _connectionMistBlueDark = Color(0xFF567A98);
const Color _connectionMistBlueLight = Color(0xFF456B86);

Color _connectionMistBlue(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? _connectionMistBlueLight
      : _connectionMistBlueDark;
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, this.embyApi, this.feiniuLogin});

  final EmbyApi? embyApi;
  final FeiniuLoginCallback? feiniuLogin;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _accessCodeController = TextEditingController();

  /// 服务器族后端各持一套表单状态，按注册表生成（新增后端自动出现）。
  final Map<MediaBackendKind, _ServerLoginFormState> _serverForms =
      <MediaBackendKind, _ServerLoginFormState>{
        for (final descriptor in MediaBackendRegistry.serverDescriptors)
          descriptor.kind: _ServerLoginFormState(),
      };

  /// 后端选择条 / 滑动切换的顺序：飞牛（遗留族）在首位，服务器族按注册表顺序。
  static final List<MediaBackendKind> _backendOrder = <MediaBackendKind>[
    MediaBackendKind.feiniu,
    for (final descriptor in MediaBackendRegistry.serverDescriptors)
      descriptor.kind,
  ];

  final DetailTopTip _topTip = DetailTopTip();
  final ActionRateLimiter _submitLimiter = ActionRateLimiter(
    cooldown: const Duration(milliseconds: 900),
  );

  MediaBackendKind _selectedBackend = MediaBackendKind.feiniu;

  double _swipeStartX = 0;
  double _swipeStartY = 0;
  double _swipeLastX = 0;
  double _swipeLastY = 0;
  bool _rememberPassword = true;
  bool _obscurePassword = true;
  bool _obscureAccessCode = true;
  bool _isSubmitting = false;
  bool _showFeiniuAdvanced = false;
  String? _inlineError;
  List<LoginHistoryEntry> _historyEntries = const <LoginHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    final provider = context.read<NasProvider>();
    _baseUrlController.text = provider.sourceBaseUrl;
    _userNameController.text = provider.userName;
    _passwordController.text = provider.password;
    _accessCodeController.text = provider.accessCode;
    _rememberPassword = provider.rememberPassword;
    unawaited(_loadLoginHistorySafely());
    unawaited(_loadStoredBackendConnectionSafely());
  }

  @override
  void dispose() {
    _topTip.dispose();
    _baseUrlController.dispose();
    _userNameController.dispose();
    _passwordController.dispose();
    _accessCodeController.dispose();
    for (final form in _serverForms.values) {
      form.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLoginHistory() async {
    final entries = await LoginHistoryStore.load();
    if (!mounted) return;
    setState(() {
      _historyEntries = entries;
    });
  }

  Future<void> _loadLoginHistorySafely() async {
    try {
      await _loadLoginHistory();
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load login history',
        error: error,
        stackTrace: stackTrace,
        source: 'connection_screen',
      );
    }
  }

  void _showTopTip(String message, Color color) {
    if (!mounted || message.trim().isEmpty) return;
    _topTip.show(context, message: message, color: color);
  }

  void _setInlineError(String? message) {
    if (!mounted) return;
    setState(() {
      _inlineError = message?.trim().isEmpty == true ? null : message?.trim();
    });
  }

  void _showValidationError(String message) {
    _setInlineError(message);
    _showTopTip(message, context.appColors.danger);
  }

  Future<void> _loadStoredBackendConnection() async {
    final snapshot = await MediaBackendConnectionStore.load();
    if (!mounted) return;
    setState(() {
      if (_serverForms.containsKey(snapshot.activeKind)) {
        _selectedBackend = snapshot.activeKind;
      }
      for (final entry in _serverForms.entries) {
        final connection = snapshot.connectionFor(entry.key);
        if (connection == null) continue;
        final form = entry.value;
        if (form.baseUrl.text.trim().isEmpty) {
          form.baseUrl.text = connection.serverUrl;
        }
        if (form.userName.text.trim().isEmpty) {
          form.userName.text = connection.userName;
        }
        form.rememberPassword = connection.rememberSecret;
        if (connection.rememberSecret && form.password.text.isEmpty) {
          form.password.text = connection.secret;
        }
        form.entryToken = connection.entryToken;
      }
    });
  }

  Future<void> _loadStoredBackendConnectionSafely() async {
    try {
      await _loadStoredBackendConnection();
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load stored backend connection',
        error: error,
        stackTrace: stackTrace,
        source: 'connection_screen',
      );
    }
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
    final message = LoginErrorResolver.resolve(
      error,
      l10n: AppLocalizations.of(context),
    );
    _setInlineError(message);
    _showTopTip(message, context.appColors.danger);
  }

  Future<void> _submit() async {
    if (_selectedBackend.isServerFamily) {
      await _verifyServerConnection(
        MediaBackendRegistry.requireDescriptor(_selectedBackend),
      );
      return;
    }
    await _submitWithUnifiedErrors();
  }

  /// 服务器族（Emby / Jellyfin…）统一登录流程：表单校验 → fnos 中转地址按需抓
  /// entry-token → 家族 API 认证 → 落连接与登录历史。差异全部来自 [descriptor]。
  Future<void> _verifyServerConnection(
    MediaBackendDescriptor descriptor,
  ) async {
    FocusScope.of(context).unfocus();
    final form = _serverForms[descriptor.kind]!;
    final baseUrl = normalizeConnectionServerAddress(
      form.baseUrl.text,
      stripEmbyWebClientPath: true,
    );
    final userName = form.userName.text.trim();
    final password = form.password.text;

    if (_isSubmitting || _submitLimiter.shouldBlock()) {
      _showTopTip(
        AppLocalizations.of(context).connectionOperationFailedRetryLater,
        const Color(0xFFB8860B),
      );
      return;
    }
    if (baseUrl.isEmpty) {
      _showValidationError(
        AppLocalizations.of(
          context,
        ).connectionServerAddressRequired(descriptor.displayName),
      );
      return;
    }
    if (userName.isEmpty) {
      _showValidationError(
        AppLocalizations.of(context).connectionUserNameRequired,
      );
      return;
    }
    if (password.isEmpty) {
      _showValidationError(
        AppLocalizations.of(context).connectionPasswordRequired,
      );
      return;
    }

    final isRelay = usesFnConnectRelayCookie(baseUrl);

    setState(() {
      _inlineError = null;
      _isSubmitting = true;
      form.baseUrl.text = baseUrl;
    });

    try {
      var entryToken = form.entryToken;
      // fnos 中转域：服务器藏在飞牛反向代理后面，请求必须带 FN Connect 入口令牌
      // （entry-token cookie）过云端边缘闸。没有就先用 WebView 走真实入口登录抓取。
      if (isRelay && entryToken.isEmpty) {
        final captured = await _captureServerEntryToken(baseUrl);
        if (!mounted) return;
        if (captured == null) return; // 取消/失败，提示已在 helper 内给出
        entryToken = captured;
      }

      final result = await _authenticateServer(
        descriptor,
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
          action: '${descriptor.kind.name} login',
          message: AppLocalizations.of(
            context,
          ).connectionServerSessionIncomplete(descriptor.displayName),
        );
      }
      form.entryToken = entryToken;
      final connection = MediaBackendConnection(
        kind: descriptor.kind,
        serverUrl: result.serverUrl,
        displayName: result.serverName,
        userName: result.userName,
        userId: result.userId,
        accessToken: result.accessToken,
        secret: form.rememberPassword ? password : '',
        rememberSecret: form.rememberPassword,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        entryToken: entryToken,
      );
      await (_backendSessionProvider()?.saveActive(connection) ??
          MediaBackendConnectionStore.saveActive(connection));
      final entries = await LoginHistoryStore.save(
        LoginHistoryEntry(
          kind: descriptor.kind,
          baseUrl: connection.serverUrl,
          userName: connection.userName,
          password: form.rememberPassword ? password : '',
          rememberPassword: form.rememberPassword,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      setState(() {
        form.baseUrl.text = connection.serverUrl;
        form.userName.text = connection.userName;
        form.password.text = password;
        _historyEntries = entries;
      });
    } catch (error, stackTrace) {
      await _reportAndShowLoginError(
        error,
        stackTrace: stackTrace,
        details: '${descriptor.kind.name}_login',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// 调用服务器族登录；fnos 中转域命中云端边缘闸（403）时，自动重抓一次入口令牌再试。
  ///
  /// 注意：403 = 云端 FN Connect 边缘闸（入口令牌缺失/过期）；服务器自身用户名密码错误是
  /// 401，不触发重抓。注入了自定义 [widget.embyApi]（单测，仅 Emby）时不重抓。
  Future<EmbyAuthenticateResult> _authenticateServer(
    MediaBackendDescriptor descriptor, {
    required String baseUrl,
    required String userName,
    required String password,
    required String entryToken,
    required bool allowRecapture,
    required ValueChanged<String> onEntryTokenRefreshed,
  }) async {
    EmbyApi build(String token) =>
        (descriptor.kind == MediaBackendKind.emby ? widget.embyApi : null) ??
        descriptor.createApiClient(entryTokenProvider: () => token);
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
        final recaptured = await _captureServerEntryToken(baseUrl);
        if (recaptured == null) rethrow;
        onEntryTokenRefreshed(recaptured);
        return attempt(recaptured);
      }
      rethrow;
    }
  }

  /// 打开 WebView 走真实 FN Connect 入口流程，抓取 `entry-token`。取消/失败返回 null。
  Future<String?> _captureServerEntryToken(String baseUrl) async {
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

    _setInlineError(null);

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
    final accessCode = _accessCodeController.text;

    if (baseUrl.isEmpty) {
      _showValidationError(
        AppLocalizations.of(context).connectionServerRequired,
      );
      return;
    }
    if (userName.isEmpty) {
      _showValidationError(
        AppLocalizations.of(context).connectionUserNameRequired,
      );
      return;
    }
    if (password.isEmpty) {
      _showValidationError(
        AppLocalizations.of(context).connectionPasswordRequired,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _baseUrlController.text = baseUrl;
    });

    try {
      final loginResult =
          await (widget.feiniuLogin ?? FeiniuApi.loginWithBaseUrl)(
            baseUrl: baseUrl,
            userName: userName,
            password: password,
            accessCode: accessCode,
          );
      if (!mounted) return;
      await _applyLoginResult(
        sourceBaseUrl: baseUrl,
        userName: userName,
        password: password,
        accessCode: accessCode,
        loginResult: loginResult,
      );
    } on FnConnectLoginException catch (error) {
      final fallbackResult = await _tryFnConnectWebFallback(
        baseUrl: baseUrl,
        userName: userName,
        password: password,
        accessCode: accessCode,
        error: error,
      );
      if (!mounted) return;
      if (fallbackResult?.isSuccess == true) {
        await _applyLoginResult(
          sourceBaseUrl: baseUrl,
          userName: userName,
          password: password,
          accessCode: accessCode,
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
    required String accessCode,
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
      accessCode: accessCode,
      rememberPassword: _rememberPassword,
      token: loginResult.token,
    );
    final entries = await LoginHistoryStore.save(
      LoginHistoryEntry(
        baseUrl: sourceBaseUrl,
        userName: userName,
        password: _rememberPassword ? password : '',
        accessCode: _rememberPassword ? accessCode : '',
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
    final form = _serverForms[entry.kind];
    if (form != null) {
      form.baseUrl.text = entry.baseUrl;
      form.userName.text = entry.userName;
      form.password.text = entry.rememberPassword ? entry.password : '';
      _accessCodeController.clear();
      // 历史记录不含 entry-token；切到不同服务器时清空旧令牌，鉴权流程会按需重抓。
      form.entryToken = '';
      setState(() {
        form.rememberPassword = entry.rememberPassword;
      });
      _selectBackend(entry.kind);
      return;
    }
    _baseUrlController.text = entry.baseUrl;
    _userNameController.text = entry.userName;
    _passwordController.text = entry.rememberPassword ? entry.password : '';
    _accessCodeController.text = entry.rememberPassword ? entry.accessCode : '';
    setState(() {
      _rememberPassword = entry.rememberPassword;
    });
    _selectBackend(MediaBackendKind.feiniu);
  }

  /// 切换选中后端并记录滑动方向（新表单从目标方向滑入）。
  void _selectBackend(MediaBackendKind next) {
    if (next == _selectedBackend) {
      if (_inlineError != null) {
        setState(() {
          _inlineError = null;
        });
      }
      return;
    }
    final newIndex = _backendOrder.indexOf(next);
    if (newIndex < 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedBackend = next;
      _inlineError = null;
      if (next.isServerFamily) {
        _showFeiniuAdvanced = false;
      }
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
    required String accessCode,
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
          accessCode: accessCode,
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
    return normalizeConnectionServerAddress(trimmed);
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
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Listener(
        onPointerDown: _handleSwipePointerDown,
        onPointerMove: _handleSwipePointerMove,
        onPointerUp: _handleSwipePointerUp,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: _buildResponsiveConnectionBody(context, theme, l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveConnectionBody(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;
        final minHeight = math.max(0.0, constraints.maxHeight - 48);
        final formColumn = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_buildForm(theme, l10n)],
        );

        final content = isWide
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    key: const Key('connectionWideBrandPane'),
                    width: 280,
                    child: _LogoHeader(title: l10n.connectionAppName),
                  ),
                  const SizedBox(width: 32),
                  SizedBox(
                    key: const Key('connectionWideFormPane'),
                    width: 460,
                    child: formColumn,
                  ),
                ],
              )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LogoHeader(title: l10n.connectionAppName),
                      const SizedBox(height: 18),
                      formColumn,
                    ],
                  ),
                ),
              );

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: content),
          ),
        );
      },
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
    final currentIndex = _backendOrder.indexOf(_selectedBackend);
    final nextIndex = dx < 0 ? currentIndex + 1 : currentIndex - 1;
    if (nextIndex < 0 || nextIndex >= _backendOrder.length) return;
    _selectBackend(_backendOrder[nextIndex]);
  }

  Widget _buildForm(ThemeData theme, AppLocalizations l10n) {
    final isFeiniu = _selectedBackend == MediaBackendKind.feiniu;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final switchDuration = animationsDisabled
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LoginFormPanel(
          key: const Key('connectionLoginFormPanel'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BackendSelector(
                key: const Key('connectionBackendSelector'),
                l10n: l10n,
                selected: _selectedBackend,
                onChanged: _selectBackend,
              ),
              const SizedBox(height: 10),
              _buildConnectionCardHeader(l10n),
              const SizedBox(height: 10),
              AnimatedSize(
                duration: switchDuration,
                curve: Curves.easeOutCubic,
                child: AnimatedSwitcher(
                  duration: switchDuration,
                  reverseDuration: animationsDisabled
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.topCenter,
                    children: <Widget>[
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    );
                    final position = Tween<Offset>(
                      begin: const Offset(0.025, 0),
                      end: Offset.zero,
                    ).animate(curved);
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(position: position, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<MediaBackendKind>(_selectedBackend),
                    child: _buildFormFields(
                      theme,
                      l10n,
                      backend: _selectedBackend,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildRememberRow(
                        theme,
                        l10n,
                        value: isFeiniu
                            ? _rememberPassword
                            : _serverForms[_selectedBackend]!.rememberPassword,
                        onChanged: (value) {
                          setState(() {
                            if (isFeiniu) {
                              _rememberPassword = value;
                            } else {
                              _serverForms[_selectedBackend]!.rememberPassword =
                                  value;
                            }
                          });
                        },
                      ),
                    ),
                    if (isFeiniu)
                      TextButton(
                        key: const Key('feiniuAdvancedOptionsButton'),
                        onPressed: () {
                          setState(() {
                            _showFeiniuAdvanced = !_showFeiniuAdvanced;
                          });
                        },
                        style: _footerButtonStyle(
                          theme,
                          foregroundColor: context.appColors.textMuted,
                        ),
                        child: Text(
                          _showFeiniuAdvanced
                              ? l10n.connectionCollapseOptions
                              : l10n.connectionMoreOptions,
                        ),
                      ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: switchDuration,
                curve: Curves.easeOutCubic,
                child: _inlineError == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            key: const Key('connectionInlineErrorText'),
                            _inlineError!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.appColors.danger,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 9),
              _SubmitButton(
                key: const Key('connectionSubmitButton'),
                isSubmitting: _isSubmitting,
                label: l10n.connectionLogin,
                onPressed: _isSubmitting ? null : _submit,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: isFeiniu ? _buildFeiniuFooter(theme, l10n) : null,
        ),
      ],
    );
  }

  Widget _buildConnectionCardHeader(AppLocalizations l10n) {
    final colors = context.appColors;
    final descriptor = _selectedBackend.isServerFamily
        ? MediaBackendRegistry.requireDescriptor(_selectedBackend)
        : null;
    final serviceName = descriptor?.displayName ?? l10n.connectionFeiniuMedia;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: colors.accentStrong,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '${l10n.connectionLogin} $serviceName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormFields(
    ThemeData theme,
    AppLocalizations l10n, {
    required MediaBackendKind backend,
  }) {
    final form = _serverForms[backend];
    final descriptor = form != null
        ? MediaBackendRegistry.requireDescriptor(backend)
        : null;
    final baseController = form?.baseUrl ?? _baseUrlController;
    final userController = form?.userName ?? _userNameController;
    final passwordController = form?.password ?? _passwordController;
    final obscure = form?.obscurePassword ?? _obscurePassword;
    final colors = context.appColors;
    final serverKey = form == null
        ? const Key('connectionServerAddressField')
        : Key('serverAddress_${backend.name}');
    final userKey = form == null
        ? const Key('connectionUserNameField')
        : Key('userName_${backend.name}');
    final passwordKey = form == null
        ? const Key('connectionPasswordField')
        : Key('password_${backend.name}');
    final fields = <Widget>[
      _GlassField(
        controller: baseController,
        textFieldKey: serverKey,
        labelText: descriptor != null
            ? l10n.connectionServerAddressLabel(descriptor.displayName)
            : l10n.connectionServerLabel,
        hintText: descriptor != null
            ? l10n.connectionServerAddressExample(descriptor.serverUrlExample)
            : l10n.connectionServerExample,
        leadingIcon: Icons.dns_outlined,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        autofillHints: const <String>[AutofillHints.url],
        suffix: IconButton(
          tooltip: l10n.connectionLoginHistory,
          onPressed: _openLoginHistory,
          icon: Icon(
            Icons.history_rounded,
            color: _historyEntries.isEmpty
                ? colors.textMuted.withValues(alpha: 0.55)
                : colors.textMuted,
          ),
        ),
      ),
      const SizedBox(height: 12),
      _GlassField(
        controller: userController,
        textFieldKey: userKey,
        labelText: l10n.connectionAccountLabel,
        hintText: l10n.connectionUserNameHint,
        leadingIcon: Icons.person_outline_rounded,
        textInputAction: TextInputAction.next,
        autofillHints: const <String>[AutofillHints.username],
      ),
      const SizedBox(height: 12),
      _GlassField(
        controller: passwordController,
        textFieldKey: passwordKey,
        labelText: l10n.connectionPasswordHint,
        hintText: '',
        leadingIcon: Icons.lock_outline_rounded,
        obscureText: obscure,
        textInputAction: TextInputAction.done,
        autofillHints: const <String>[AutofillHints.password],
        onSubmitted: (_) => _submit(),
        suffix: IconButton(
          tooltip: l10n.connectionPasswordHint,
          onPressed: () {
            setState(() {
              if (form != null) {
                form.obscurePassword = !form.obscurePassword;
              } else {
                _obscurePassword = !_obscurePassword;
              }
            });
          },
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: colors.textMuted,
          ),
        ),
      ),
    ];

    if (form == null && _showFeiniuAdvanced) {
      fields
        ..add(const SizedBox(height: 12))
        ..add(
          _GlassField(
            key: const Key('feiniuAccessCodeFieldContainer'),
            textFieldKey: const Key('feiniuAccessCodeField'),
            controller: _accessCodeController,
            labelText: l10n.connectionAccessCodeOptional,
            hintText: '',
            leadingIcon: Icons.key_rounded,
            obscureText: _obscureAccessCode,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            suffix: IconButton(
              tooltip: l10n.connectionAccessCodeOptional,
              onPressed: () {
                setState(() {
                  _obscureAccessCode = !_obscureAccessCode;
                });
              },
              icon: Icon(
                _obscureAccessCode
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: colors.textMuted,
              ),
            ),
          ),
        );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: fields,
    );
  }

  Widget _buildFeiniuFooter(ThemeData theme, AppLocalizations l10n) {
    final colors = context.appColors;
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 2,
        children: [
          TextButton(
            onPressed: _openDownloadedData,
            style: _footerButtonStyle(theme, foregroundColor: colors.textMuted),
            child: Text(l10n.connectionOpenDownloads),
          ),
          TextButton(
            onPressed: _isSubmitting ? null : _resetFnConnectWebLoginState,
            style: _footerButtonStyle(
              theme,
              foregroundColor: colors.textMuted,
              disabledForegroundColor: colors.textMuted.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
            ),
            child: Text(l10n.fnConnectReloginTitle),
          ),
        ],
      ),
    );
  }

  Widget _buildRememberRow(
    ThemeData theme,
    AppLocalizations l10n, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = context.appColors;
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
                  side: BorderSide(color: colors.borderStrong),
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? colors.selection
                        : Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                l10n.connectionRememberLogin,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
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
    super.key,
    required this.l10n,
    required this.selected,
    required this.onChanged,
  });

  final AppLocalizations l10n;
  final MediaBackendKind selected;
  final ValueChanged<MediaBackendKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectionColor = _connectionMistBlue(context);
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    // 选项 = 飞牛（遗留族）+ 注册表登记的服务器族后端，新增后端自动出现。
    final legacyBackend = MediaBackendKind.values.firstWhere(
      (kind) => !kind.isServerFamily,
    );
    final options = <({MediaBackendKind kind, String label, String asset})>[
      (
        kind: legacyBackend,
        label: l10n.connectionFeiniuMedia,
        asset: 'lib/img/feiniu_Logo.png',
      ),
      for (final descriptor in MediaBackendRegistry.serverDescriptors)
        (
          kind: descriptor.kind,
          label: descriptor.displayName,
          asset: descriptor.logoAsset,
        ),
    ];
    final count = options.length;
    final selectedIndex = options.indexWhere(
      (option) => option.kind == selected,
    );
    final alignmentX = count <= 1
        ? 0.0
        : -1 + 2 * (selectedIndex < 0 ? 0 : selectedIndex) / (count - 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Stack(
          children: [
            // 滑动高亮：跟随选中项在各分区间平滑移动。
            AnimatedAlign(
              duration: animationDuration,
              curve: Curves.easeOutCubic,
              alignment: Alignment(alignmentX, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: selectionColor.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: selectionColor.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final option in options)
                  Expanded(
                    child: _BackendSelectorButton(
                      label: option.label,
                      assetName: option.asset,
                      selected: option.kind == selected,
                      onTap: () => onChanged(option.kind),
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
    required this.assetName,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final String assetName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        child: AnimatedDefaultTextStyle(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: selected
                ? context.appColors.textPrimary
                : context.appColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                assetName,
                width: 19,
                height: 19,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, textAlign: TextAlign.center),
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
    super.key,
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
    final buttonColor = _connectionMistBlue(context);
    final buttonForeground =
        ThemeData.estimateBrightnessForColor(buttonColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: buttonForeground,
          disabledBackgroundColor: buttonColor.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
                  valueColor: AlwaysStoppedAnimation<Color>(buttonForeground),
                  backgroundColor: buttonForeground.withValues(alpha: 0.18),
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
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'lib/img/app_logo.png',
          width: 44,
          height: 44,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const Key('connectionBrandTitle'),
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).connectionTagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginFormPanel extends StatelessWidget {
  const _LoginFormPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: child,
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  const _GlassField({
    super.key,
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
    this.textFieldKey,
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
  final Key? textFieldKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = labelText?.trim() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colors.surfaceSubtle,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            const SizedBox(width: 18),
            Icon(leadingIcon, color: colors.textMuted, size: 21),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: TextField(
              key: textFieldKey,
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofillHints: autofillHints,
              onSubmitted: onSubmitted,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: label.isEmpty ? null : label,
                hintText: hintText,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: colors.textMuted,
                  fontSize: 14,
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
