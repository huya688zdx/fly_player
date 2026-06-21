import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/nas_provider.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
import '../utils/action_rate_limiter.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../utils/login_error_resolver.dart';
import '../services/login_history_store.dart';
import '../services/fn_connect_web_session_service.dart';
import 'download_list_screen.dart';
import 'fn_connect_web_login_page.dart';
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
  const ConnectionScreen({super.key});

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
  bool _rememberPassword = true;
  bool _useHttps = false;
  bool _obscurePassword = true;
  bool _obscureEmbyPassword = true;
  bool _isSubmitting = false;
  List<LoginHistoryEntry> _historyEntries = const <LoginHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    final provider = context.read<NasProvider>();
    _baseUrlController.text = provider.sourceBaseUrl;
    _userNameController.text = provider.userName;
    _passwordController.text = provider.password;
    _rememberPassword = provider.rememberPassword;
    _useHttps = _looksLikeHttps(provider.sourceBaseUrl);
    _loadLoginHistory();
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
    _showTopTip(LoginErrorResolver.resolve(error), context.appColors.danger);
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

    if (baseUrl.isEmpty) {
      _showTopTip('请输入 Emby 服务器地址', context.appColors.danger);
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

    _embyBaseUrlController.text = baseUrl;
    _showTopTip('Emby 连接验证将在下一阶段开放', context.appColors.accent);
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
      _baseUrlController.text = baseUrl;
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

  Future<void> _showLoginHistorySheet() async {
    final selected = await showModalBottomSheet<LoginHistoryEntry>(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      barrierColor: Colors.black.withValues(alpha: 0.56),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return _LoginHistorySheet(
          entries: _historyEntries,
          onDelete: (entry) async {
            final entries = await LoginHistoryStore.remove(entry);
            if (!mounted) return;
            setState(() {
              _historyEntries = entries;
            });
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
          },
          onClear: () async {
            await LoginHistoryStore.clear();
            if (!mounted) return;
            setState(() {
              _historyEntries = const <LoginHistoryEntry>[];
            });
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
    if (!mounted || selected == null) return;
    _baseUrlController.text = selected.baseUrl;
    _userNameController.text = selected.userName;
    _passwordController.text = selected.rememberPassword
        ? selected.password
        : '';
    setState(() {
      _rememberPassword = selected.rememberPassword;
      _useHttps = _looksLikeHttps(selected.baseUrl);
    });
  }

  Future<void> _resetFnConnectWebLoginState() async {
    if (_isSubmitting) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '重新登录 FN Connect',
      content: '将清除 FN Connect 网页登录态，并退出当前连接。服务器地址、用户名和已记住的密码会保留，之后可重新发起网页登录。',
      cancelText: '取消',
      confirmText: '清除并重新登录',
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
      _showTopTip('已清除 FN Connect 网页登录态，请重新登录', context.appColors.accent);
    } catch (error, stackTrace) {
      await AppErrorReporter.report(
        error,
        action: 'clear fn connect web login state',
        source: 'connection_screen',
        stackTrace: stackTrace,
        fallbackKind: AppExceptionKind.transient,
      );
      if (!mounted) return;
      _showTopTip('清除 FN Connect 网页登录态失败，请重试', context.appColors.danger);
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
    final withScheme = trimmed.contains('://')
        ? trimmed
        : '${_useHttps ? 'https' : 'http'}://$trimmed';
    try {
      final uri = Uri.parse(withScheme);
      if (uri.host.isEmpty && !withScheme.contains(RegExp(r'^\w+://[^/]+'))) {
        return '';
      }
      final normalized = uri
          .replace(scheme: _useHttps ? 'https' : 'http')
          .toString();
      return ApiUrlHelper.normalizeBaseUrl(normalized);
    } catch (_) {
      return '';
    }
  }

  String _normalizeEmbyBaseUrlInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    try {
      final uri = Uri.parse(withScheme);
      if (uri.host.isEmpty) return '';
      return ApiUrlHelper.normalizeBaseUrl(uri.toString());
    } catch (_) {
      return '';
    }
  }

  bool _looksLikeHttps(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri?.scheme.toLowerCase() == 'https';
  }

  void _toggleHttps(bool value) {
    setState(() {
      _useHttps = value;
      final normalized = _rewriteScheme(_baseUrlController.text, value);
      if (normalized.isNotEmpty) {
        _baseUrlController.text = normalized;
      }
    });
  }

  String _rewriteScheme(String raw, bool useHttps) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    try {
      final uri = Uri.parse(withScheme);
      if (uri.host.isEmpty) return trimmed;
      return uri.replace(scheme: useHttps ? 'https' : 'http').toString();
    } catch (_) {
      return trimmed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF08111A),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _LoginBackdrop(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        _LogoHeader(title: l10n.connectionAppName),
                        const SizedBox(height: 28),
                        _BackendSelector(
                          selected: _selectedBackend,
                          onChanged: (backend) {
                            setState(() {
                              _selectedBackend = backend;
                            });
                          },
                        ),
                        const SizedBox(height: 18),
                        if (_selectedBackend == _ConnectionBackend.feiniu)
                          _buildFeiniuForm(theme, l10n)
                        else
                          _buildEmbyForm(theme, l10n),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeiniuForm(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlassField(
          controller: _baseUrlController,
          hintText: 'http://192.168.6.120:5666',
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.url],
          suffix: IconButton(
            onPressed: _showLoginHistorySheet,
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
          controller: _userNameController,
          hintText: l10n.connectionUserNameHint,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.username],
        ),
        const SizedBox(height: 14),
        _GlassField(
          controller: _passwordController,
          hintText: l10n.connectionPasswordHint,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.password],
          onSubmitted: (_) => _submit(),
          suffix: IconButton(
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFF7C8DA5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                setState(() {
                  _rememberPassword = !_rememberPassword;
                });
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Checkbox(
                      value: _rememberPassword,
                      onChanged: (value) {
                        setState(() {
                          _rememberPassword = value ?? false;
                        });
                      },
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
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: _SettingRow(label: l10n.connectionHttpsAccess)),
            Switch(
              value: _useHttps,
              onChanged: _toggleHttps,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF2D74D9),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFF415064),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SubmitButton(
          isSubmitting: _isSubmitting,
          label: l10n.connectionLogin,
          onPressed: _isSubmitting ? null : _submit,
        ),
        const SizedBox(height: 10),
        Center(
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
                child: const Text('重新登录 FN Connect'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmbyForm(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlassField(
          controller: _embyBaseUrlController,
          hintText: 'Emby 服务器地址',
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.url],
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
        const SizedBox(height: 14),
        Text(
          '当前只加入 Emby 登录入口；验证通过后仍不会接入媒体列表、详情或播放。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF9EADBE),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
        _SubmitButton(
          isSubmitting: false,
          label: '验证 Emby 连接',
          onPressed: _verifyEmbyConnection,
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
  const _BackendSelector({required this.selected, required this.onChanged});

  final _ConnectionBackend selected;
  final ValueChanged<_ConnectionBackend> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF182331),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2D3948)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _BackendSelectorButton(
                label: '飞牛 NAS',
                selected: selected == _ConnectionBackend.feiniu,
                onTap: () => onChanged(_ConnectionBackend.feiniu),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _BackendSelectorButton(
                label: 'Emby',
                selected: selected == _ConnectionBackend.emby,
                onTap: () => onChanged(_ConnectionBackend.emby),
              ),
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
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF2D74D9) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF9FB0C7),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
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
      height: 64,
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
    return Text(
      title,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0C1825), Color(0xFF07111A), Color(0xFF040A12)],
            ),
          ),
        ),
        Positioned(
          top: -60,
          left: -40,
          child: Container(
            width: 220,
            height: 220,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x332D74D9), Color(0x002D74D9)],
              ),
            ),
          ),
        ),
        Positioned(
          right: -70,
          top: 120,
          child: Transform.rotate(
            angle: -0.22,
            child: Container(
              width: 240,
              height: 280,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                color: const Color(0x0F6AA7FF),
                border: Border.all(color: const Color(0x146AA7FF)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x001D2B3A), Color(0x2216212F)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginHistorySheet extends StatelessWidget {
  final List<LoginHistoryEntry> entries;
  final ValueChanged<LoginHistoryEntry> onDelete;
  final Future<void> Function() onClear;

  const _LoginHistorySheet({
    required this.entries,
    required this.onDelete,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF415064),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    l10n.connectionLoginHistory,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: () => onClear(),
                      child: Text(
                        l10n.connectionClear,
                        style: const TextStyle(color: Color(0xFF8FB7FF)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
                  child: Text(
                    l10n.connectionNoLoginHistory,
                    style: const TextStyle(
                      color: Color(0xFF9EADBE),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Material(
                        color: const Color(0xFF232D3A),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(context).pop(entry),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.dns_rounded,
                                  color: Color(0xFF8FB7FF),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.baseUrl,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        entry.userName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF9EADBE),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => onDelete(entry),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFF7C8DA5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  const _GlassField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF232D3A),
        border: Border.all(color: const Color(0xFF2D3948)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
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
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF9EADBE),
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

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
