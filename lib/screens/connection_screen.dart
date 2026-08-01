import 'dart:async';

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
import '../utils/api_url_helper.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
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

  /// 表单滑动切换方向：+1 = 新表单从右进（向右侧后端切换），-1 反向。
  double _slideDx = 1;
  String _baseUrlScheme = 'http';
  double _swipeStartX = 0;
  double _swipeStartY = 0;
  double _swipeLastX = 0;
  double _swipeLastY = 0;
  bool _rememberPassword = true;
  bool _obscurePassword = true;
  bool _obscureAccessCode = true;
  bool _isSubmitting = false;
  List<LoginHistoryEntry> _historyEntries = const <LoginHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    final provider = context.read<NasProvider>();
    _baseUrlController.text = _displayBaseUrlForLogin(provider.sourceBaseUrl);
    _baseUrlScheme = _schemeForLogin(provider.sourceBaseUrl);
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
    _showTopTip(
      LoginErrorResolver.resolve(error, l10n: AppLocalizations.of(context)),
      context.appColors.danger,
    );
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
    final baseUrl = _normalizeServerBaseUrlInput(form.baseUrl.text);
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
      _showTopTip(
        AppLocalizations.of(
          context,
        ).connectionServerAddressRequired(descriptor.displayName),
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
    _baseUrlController.text = _displayBaseUrlForLogin(entry.baseUrl);
    _userNameController.text = entry.userName;
    _passwordController.text = entry.rememberPassword ? entry.password : '';
    _accessCodeController.text = entry.rememberPassword ? entry.accessCode : '';
    setState(() {
      _baseUrlScheme = _schemeForLogin(entry.baseUrl);
      _rememberPassword = entry.rememberPassword;
    });
    _selectBackend(MediaBackendKind.feiniu);
  }

  /// 切换选中后端并记录滑动方向（新表单从目标方向滑入）。
  void _selectBackend(MediaBackendKind next) {
    if (next == _selectedBackend) return;
    final oldIndex = _backendOrder.indexOf(_selectedBackend);
    final newIndex = _backendOrder.indexOf(next);
    if (newIndex < 0) return;
    setState(() {
      _slideDx = newIndex > oldIndex ? 1 : -1;
      _selectedBackend = next;
      if (next.isServerFamily) {
        _accessCodeController.clear();
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

  void _syncBaseUrlScheme(String raw) {
    final scheme = Uri.tryParse(raw.trim())?.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || scheme == _baseUrlScheme) {
      return;
    }
    setState(() {
      _baseUrlScheme = scheme!;
    });
  }

  void _selectBaseUrlScheme(String scheme) {
    if (scheme != 'http' && scheme != 'https') return;
    final raw = _baseUrlController.text;
    final updated = raw.replaceFirst(
      RegExp(r'^\s*https?://', caseSensitive: false),
      '$scheme://',
    );
    if (updated != raw) {
      _baseUrlController.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: updated.length),
      );
    }
    setState(() {
      _baseUrlScheme = scheme;
    });
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

  String _normalizeServerBaseUrlInput(String raw) {
    // MediaBrowser 家族（Emby / Jellyfin）网页客户端路径形状一致，共用内核的规整逻辑。
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
                        onChanged: _selectBackend,
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
    final currentIndex = _backendOrder.indexOf(_selectedBackend);
    final nextIndex = dx < 0 ? currentIndex + 1 : currentIndex - 1;
    if (nextIndex < 0 || nextIndex >= _backendOrder.length) return;
    _selectBackend(_backendOrder[nextIndex]);
  }

  /// 后端表单：单一持久面板 + 内部字段的方向性滑动切换。
  ///
  /// 不再用 `AnimatedSwitcher` 跨淡「两整套带阴影的表单」——`FadeTransition` 的
  /// opacity 会强制离屏 `saveLayer`，叠在海报墙背景上直接 GPU 超支（极卡），叠加
  /// `ScaleTransition` 与 layoutBuilder 对齐不一致还会抖。这里面板常驻（阴影只栅格化
  /// 一次），只对内部字段做**纯位移**滑动（无 opacity/scale，无离屏层），顺滑不抖。
  Widget _buildForm(ThemeData theme, AppLocalizations l10n) {
    final isFeiniu = _selectedBackend == MediaBackendKind.feiniu;
    return Column(
      mainAxisSize: MainAxisSize.min,
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
                    key is ValueKey<MediaBackendKind> &&
                    key.value == _selectedBackend;
                // 向右侧后端切换时新卡从右进、旧卡向左出；向左侧后端切换反向。
                final dx = _slideDx;
                final position = isIncoming
                    ? Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
                    : Tween<Offset>(begin: Offset(-dx, 0), end: Offset.zero);
                return SlideTransition(
                  position: position.animate(animation),
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey<MediaBackendKind>(_selectedBackend),
                child: _buildFormFields(theme, l10n, backend: _selectedBackend),
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
        const SizedBox(height: 10),
        Visibility(
          visible: isFeiniu,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          maintainInteractivity: false,
          maintainSemantics: false,
          child: _buildFeiniuFooter(theme, l10n),
        ),
      ],
    );
  }

  /// 单套表单字段（服务器/账号/密码/记住）。飞牛与服务器族结构一致，仅控制器与文案不同，
  /// 共用此构建以保证各态高度严格相等——滑动切换时面板不重排、不抖。
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
    final remember = form?.rememberPassword ?? _rememberPassword;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlassField(
          controller: baseController,
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
          onChanged: form != null ? null : _syncBaseUrlScheme,
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
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final isStacked = constraints.maxWidth < 300 || textScale > 1.2;
            return SizedBox(
              height: isStacked ? 96 : 40,
              child: form != null
                  ? const SizedBox.shrink()
                  : _buildProtocolSelector(theme, l10n, isStacked: isStacked),
            );
          },
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
                if (form != null) {
                  form.obscurePassword = !form.obscurePassword;
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
        const SizedBox(height: 12),
        if (form == null)
          _GlassField(
            key: const Key('feiniuAccessCodeField'),
            controller: _accessCodeController,
            labelText: l10n.connectionAccessCodeOptional,
            hintText: '',
            leadingIcon: Icons.key_rounded,
            obscureText: _obscureAccessCode,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            suffix: IconButton(
              onPressed: () {
                setState(() {
                  _obscureAccessCode = !_obscureAccessCode;
                });
              },
              icon: Icon(
                _obscureAccessCode
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFF8795AD),
              ),
            ),
          )
        else
          const ExcludeSemantics(
            child: IgnorePointer(child: SizedBox(height: 64)),
          ),
        const SizedBox(height: 14),
        _buildRememberRow(
          theme,
          l10n,
          value: remember,
          onChanged: (value) {
            setState(() {
              if (form != null) {
                form.rememberPassword = value;
              } else {
                _rememberPassword = value;
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildProtocolSelector(
    ThemeData theme,
    AppLocalizations l10n, {
    required bool isStacked,
  }) {
    final label = Text(
      l10n.connectionProtocolLabel,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: const Color(0xFFB6C1D4),
        fontWeight: FontWeight.w500,
      ),
    );
    final selector = SegmentedButton<String>(
      segments: <ButtonSegment<String>>[
        ButtonSegment<String>(
          value: 'http',
          label: Text(l10n.connectionProtocolHttp),
        ),
        ButtonSegment<String>(
          value: 'https',
          label: Text(l10n.connectionProtocolHttps),
        ),
      ],
      selected: <String>{_baseUrlScheme},
      onSelectionChanged: (selected) {
        if (selected.isEmpty) return;
        _selectBaseUrlScheme(selected.first);
      },
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        foregroundColor: const Color(0xFF91A0BB),
        selectedForegroundColor: Colors.white,
        backgroundColor: const Color(0xD80B1624),
        selectedBackgroundColor: const Color(0xFF263A58),
        side: const BorderSide(color: Color(0xFF405675)),
        visualDensity: VisualDensity.compact,
      ),
    );
    if (isStacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const SizedBox(height: 6),
          Expanded(child: selector),
        ],
      );
    }
    return Row(
      children: [
        label,
        const SizedBox(width: 12),
        Expanded(child: selector),
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
  final MediaBackendKind selected;
  final ValueChanged<MediaBackendKind> onChanged;

  @override
  Widget build(BuildContext context) {
    // 选项 = 飞牛（遗留族）+ 注册表登记的服务器族后端，新增后端自动出现。
    final options = <({MediaBackendKind kind, String label, String asset})>[
      (
        kind: MediaBackendKind.feiniu,
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
        color: const Color(0xC10B1726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF253651)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            // 滑动高亮：跟随选中项在各分区间平滑移动。
            AnimatedAlign(
              duration: AppTransitions.contentSwitchDuration,
              curve: Curves.easeOutCubic,
              alignment: Alignment(alignmentX, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: AnimatedDefaultTextStyle(
          duration: AppTransitions.contentSwitchDuration,
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFB6C0D1),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                assetName,
                width: 28,
                height: 28,
                fit: BoxFit.contain,
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
    this.onChanged,
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
  final ValueChanged<String>? onChanged;
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
              onChanged: onChanged,
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
