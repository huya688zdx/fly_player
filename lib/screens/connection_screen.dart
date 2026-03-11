import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../providers/nas_provider.dart';
import '../utils/action_rate_limiter.dart';
import '../utils/api_url_helper.dart';
import '../utils/detail_top_tip.dart';
import '../utils/media_locale_store.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final DetailTopTip _topTip = DetailTopTip();
  final ActionRateLimiter _submitLimiter = ActionRateLimiter(
    cooldown: const Duration(milliseconds: 900),
  );

  bool _rememberPassword = true;
  bool _useHttps = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  Map<String, dynamic> _localeMap = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    final provider = context.read<NasProvider>();
    _baseUrlController.text = provider.baseUrl;
    _userNameController.text = provider.userName;
    _passwordController.text = provider.password;
    _rememberPassword = provider.rememberPassword;
    _useHttps = _looksLikeHttps(provider.baseUrl);
    _loadLocaleMap();
  }

  @override
  void dispose() {
    _topTip.dispose();
    _baseUrlController.dispose();
    _userNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static String _t(
    Map<String, dynamic> localeMap,
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _loadLocaleMap() async {
    try {
      final data = await rootBundle.load('list2.json');
      final text = utf8.decode(data.buffer.asUint8List(), allowMalformed: true);
      final decoded = jsonDecode(text);
      if (!mounted || decoded is! Map<String, dynamic>) return;
      setState(() {
        _localeMap = decoded;
      });
    } catch (_) {}
  }

  void _showTopTip(String message, Color color) {
    if (!mounted || message.trim().isEmpty) return;
    _topTip.show(context, message: message, color: color);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_isSubmitting || _submitLimiter.shouldBlock()) {
      _showTopTip(
        _t(_localeMap, 'common.actions.default.failed', '操作失败，请稍后重试'),
        const Color(0xFFB8860B),
      );
      return;
    }

    final baseUrl = _normalizeBaseUrlInput(_baseUrlController.text);
    final userName = _userNameController.text.trim();
    final password = _passwordController.text;

    if (baseUrl.isEmpty) {
      _showTopTip(
        _t(_localeMap, 'layout.editMetadata.validation.required', '请输入服务器地址'),
        const Color(0xFFD64545),
      );
      return;
    }
    if (userName.isEmpty) {
      _showTopTip(
        _t(_localeMap, 'common.validation.userName.empty', '请输入用户名'),
        const Color(0xFFD64545),
      );
      return;
    }
    if (password.isEmpty) {
      _showTopTip(
        _t(_localeMap, 'common.validation.password.empty', '请输入密码'),
        const Color(0xFFD64545),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _baseUrlController.text = baseUrl;
    });

    try {
      final token = await FeiniuApi.loginWithBaseUrl(
        baseUrl: baseUrl,
        userName: userName,
        password: password,
      );
      if (!mounted) return;
      await context.read<NasProvider>().updateSettings(
        baseUrl: baseUrl,
        userName: userName,
        password: password,
        rememberPassword: _rememberPassword,
        token: token,
      );
    } catch (e) {
      _showTopTip(_resolveLoginError(e), const Color(0xFFD64545));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _resolveLoginError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
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
      return _t(_localeMap, 'auth.login.usernameOrPasswordError', '用户名或密码错误');
    }

    if (message.contains('socketexception') ||
        message.contains('timed out') ||
        message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable')) {
      return _t(_localeMap, 'layout.globalError.message', '网络异常，请检查后重试');
    }

    if (message.contains('format') ||
        message.contains('invalid uri') ||
        message.contains('invalid argument')) {
      return _t(_localeMap, 'auth.login.validationFailed', '验证失败');
    }

    if (_containsChinese(raw)) {
      return raw;
    }

    return _t(_localeMap, 'common.actions.default.failed', '操作失败，请重试');
  }

  bool _containsChinese(String value) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
  }

  String _normalizeBaseUrlInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
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
                        const _LogoHeader(),
                        const SizedBox(height: 36),
                        _GlassField(
                          controller: _baseUrlController,
                          hintText: 'http://192.168.6.120:5666',
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          autofillHints: const <String>[AutofillHints.url],
                          suffix: IconButton(
                            onPressed: () {
                              final normalized = _rewriteScheme(
                                _baseUrlController.text,
                                _useHttps,
                              );
                              _baseUrlController.value = TextEditingValue(
                                text: normalized,
                                selection: TextSelection.collapsed(
                                  offset: normalized.length,
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.history_rounded,
                              color: Color(0xFF7C8DA5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _GlassField(
                          controller: _userNameController,
                          hintText: _t(_localeMap, 'server.username', '用户名'),
                          textInputAction: TextInputAction.next,
                          autofillHints: const <String>[AutofillHints.username],
                        ),
                        const SizedBox(height: 14),
                        _GlassField(
                          controller: _passwordController,
                          hintText: _t(
                            _localeMap,
                            'common.validation.password.label',
                            '密码',
                          ),
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
                                      side: const BorderSide(
                                        color: Color(0xFF4D5C6F),
                                      ),
                                      fillColor:
                                          WidgetStateProperty.resolveWith(
                                            (states) =>
                                                states.contains(
                                                  WidgetState.selected,
                                                )
                                                ? const Color(0xFF2D74D9)
                                                : Colors.transparent,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _t(
                                      _localeMap,
                                      'auth.login.remember',
                                      '保持登录',
                                    ),
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
                            const Expanded(
                              child: _SettingRow(label: 'HTTPS 安全访问'),
                            ),
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
                        SizedBox(
                          height: 64,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
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
                            child: _isSubmitting
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  )
                                : Text(
                                    _t(_localeMap, 'auth.login.login', '登录'),
                                  ),
                          ),
                        ),
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
}

class _LogoHeader extends StatelessWidget {
  const _LogoHeader();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '飞牛播放器',
      textAlign: TextAlign.center,
      style: TextStyle(
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
