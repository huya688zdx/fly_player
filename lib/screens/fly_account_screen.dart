import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../desktop/desktop_environment.dart';
import '../desktop/desktop_floating_panel.dart';
import '../desktop/desktop_hover_dropdown.dart';
import '../services/fly_data/fly_account_controller.dart';
import '../services/fly_data/fly_data_api.dart';
import '../services/fly_data/fly_login_history_store.dart';
import '../theme/app_theme.dart';
import '../ui/app_info_popover.dart';
import '../ui/app_sheet_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/login_components.dart';
import '../widgets/common/app_ambient_page.dart';
import '../widgets/common/bird_loader.dart';
import '../widgets/common/track_option_sheet.dart';
import '../widgets/common/desktop_login_dialog.dart';
import 'emby_fn_entry_login_page.dart';

part 'fly_account_widgets.dart';

Future<FlyFnAuthorization?> _authorizeFlyFn(
  BuildContext context,
  String serverUrl,
) => showDesktopLoginDialog<FlyFnAuthorization>(
  context,
  child: EmbyFnEntryLoginPage(
    serverUrl: '${serverUrl.replaceFirst(RegExp(r'/+$'), '')}/',
    requireTargetPath: true,
  ),
);

bool _bindingStillCurrent(
  FlyAccountController account,
  String accountKey,
  Object? bindingId,
  Object? revision,
) =>
    account.accountKey == accountKey &&
    account.bindings.any(
      (item) => item['id'] == bindingId && item['revision'] == revision,
    );

/// Shared by the home source selector and the account page.
/// Navigation belongs to the caller; failure or cancellation stays put.
Future<bool> activateFlyBinding(
  BuildContext context,
  FlyAccountController account,
  Map<String, dynamic> binding,
) async {
  if (account.busy || !context.mounted) return false;
  final accountKey = account.accountKey;
  final bindingId = binding['id'], revision = binding['revision'];
  try {
    await account.activate(binding);
    return _bindingStillCurrent(account, accountKey, bindingId, revision);
  } catch (error) {
    if (context.mounted) {
      AppTopTip().show(
        context,
        message: FlyAccountController.safeMessage(error),
        color: context.appColors.surfaceStrong,
      );
    }
    return false;
  }
}

class FlyLoginScreen extends StatefulWidget {
  const FlyLoginScreen({super.key});
  @override
  State<FlyLoginScreen> createState() => _FlyLoginScreenState();
}

class _FlyLoginScreenState extends State<FlyLoginScreen> {
  final url = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController();
  final device = TextEditingController(text: 'Fly Player');
  final _form = GlobalKey<FormState>();
  FlyLoginHistoryEntry? _selectedHistory;
  bool _rememberPassword = true, _obscurePassword = true;
  bool _applyingHistory = false;
  bool _historyBusy = false, _submitting = false, _leaving = false;
  int _formRevision = 0, _historyEpoch = 0;
  String? _historyMessage;

  @override
  void initState() {
    super.initState();
    url.addListener(_identityEdited);
    username.addListener(_identityEdited);
    password.addListener(_passwordEdited);
    device.addListener(_formEdited);
    unawaited(_restoreLoginForm());
  }

  void _formEdited() {
    if (!_applyingHistory) _formRevision++;
  }

  void _passwordEdited() {
    if (_applyingHistory) return;
    _formRevision++;
  }

  void _identityEdited() {
    if (_applyingHistory) return;
    _formRevision++;
    final selected = _selectedHistory;
    if (selected == null ||
        (url.text.trim() == selected.serverUrl &&
            username.text.trim() == selected.username)) {
      return;
    }
    // A filled password belongs to the saved service/account, never to an
    // edited address. Saved identities are also verified before login.
    _selectedHistory = null;
    password.clear();
  }

  bool _canUseForm(FlyAccountController account) =>
      mounted &&
      identical(context.read<FlyAccountController>(), account) &&
      account.session == null &&
      !account.legacyMode &&
      !account.busy &&
      !_submitting &&
      !_leaving &&
      ModalRoute.of(context)?.isCurrent != false;

  void _applyHistory(FlyLoginHistoryEntry entry) {
    _applyingHistory = true;
    try {
      url.text = entry.serverUrl;
      username.text = entry.username;
      password.text = entry.rememberPassword ? entry.password : '';
      device.text = entry.deviceName;
      _selectedHistory = entry;
      _rememberPassword = entry.rememberPassword;
      _historyMessage = null;
      _formRevision++;
    } finally {
      _applyingHistory = false;
    }
    setState(() {});
  }

  Future<void> _restoreLoginForm() async {
    final account = context.read<FlyAccountController>();
    final revision = _formRevision, epoch = _historyEpoch;
    try {
      final entries = await FlyLoginHistoryStore.load();
      if (!_canUseForm(account) || epoch != _historyEpoch || _historyBusy) {
        return;
      }
      if (entries.isNotEmpty && revision == _formRevision) {
        _applyHistory(entries.first);
      }
    } catch (_) {
      if (_canUseForm(account) && epoch == _historyEpoch) {
        setState(
          () => _historyMessage = AppLocalizations.of(
            context,
          ).flyAccountHistoryReadFailed,
        );
      }
    }
  }

  Future<void> _openHistory(FlyAccountController account) async {
    if (!_canUseForm(account) || _historyBusy) return;
    _historyEpoch++;
    setState(() {
      _historyBusy = true;
      _historyMessage = null;
    });
    try {
      final entries = await FlyLoginHistoryStore.load();
      if (!_canUseForm(account)) return;
      if (entries.isEmpty) {
        setState(
          () => _historyMessage = AppLocalizations.of(
            context,
          ).flyAccountHistoryEmpty,
        );
        return;
      }
      if (!mounted) return;
      final selected = await _showFlyOptions(
        context,
        title: AppLocalizations.of(context).flyAccountHistory,
        selectedId: _selectedHistory?.id,
        items: [
          for (final entry in entries)
            TrackOptionSheetItem(
              id: entry.id,
              title: entry.username,
              subtitle: entry.serverUrl,
            ),
          TrackOptionSheetItem(
            id: 'clear-history',
            title: AppLocalizations.of(context).flyAccountClearHistory,
          ),
        ],
      );
      if (selected == null || !_canUseForm(account)) return;
      if (selected == 'clear-history') {
        if (!mounted) return;
        final confirmed = await showAppConfirmDialog(
          context,
          title: AppLocalizations.of(context).flyAccountClearHistory,
          content: AppLocalizations.of(context).flyAccountClearHistoryConfirm,
          cancelText: AppLocalizations.of(context).commonCancel,
          confirmText: AppLocalizations.of(context).flyAccountClear,
        );
        if (!confirmed || !_canUseForm(account)) return;
        await FlyLoginHistoryStore.clear();
        if (!_canUseForm(account)) return;
        _selectedHistory = null;
        url.clear();
        username.clear();
        password.clear();
        setState(() {});
      } else {
        _applyHistory(entries.firstWhere((entry) => entry.id == selected));
      }
    } catch (_) {
      if (_canUseForm(account)) {
        setState(
          () => _historyMessage = AppLocalizations.of(
            context,
          ).flyAccountHistoryUnavailable,
        );
      }
    } finally {
      if (mounted) setState(() => _historyBusy = false);
    }
  }

  Future<void> _setRememberPassword(
    FlyAccountController account,
    bool remember,
  ) async {
    if (!_canUseForm(account) || _historyBusy) return;
    _historyEpoch++;
    _formRevision++;
    final selected = _selectedHistory;
    setState(() {
      _rememberPassword = remember;
      _historyMessage = null;
      _historyBusy = !remember && selected != null;
    });
    if (!_historyBusy) return;
    try {
      await FlyLoginHistoryStore.forgetPassword(selected!);
    } catch (_) {
      if (_canUseForm(account)) {
        setState(() {
          _rememberPassword = true;
          _historyMessage = AppLocalizations.of(
            context,
          ).flyAccountPasswordClearFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _historyBusy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [url, username, password, device]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _login(FlyAccountController account) async {
    if (!_canUseForm(account) ||
        _historyBusy ||
        _form.currentState?.validate() != true) {
      return;
    }
    _historyEpoch++;
    setState(() {
      _submitting = true;
      _historyMessage = null;
    });
    var accountLoginStarted = false;
    try {
      final serverUrl = normalizeServerUrl(url.text);
      var entryToken = '';
      var gatewayCookies = const <String, String>{};
      if (isFlyFnApplicationUrl(serverUrl)) {
        final result = await _authorizeFlyFn(context, serverUrl);
        if (!mounted) return;
        if (result == null || result.entryToken.isEmpty) {
          setState(() => _historyMessage = 'FN 访问授权未完成，可重新点击登录。');
          return;
        }
        if (account.session != null || account.legacyMode) return;
        entryToken = result.entryToken;
        gatewayCookies = result.gatewayCookies;
      }
      accountLoginStarted = true;
      await account.login(
        url: serverUrl,
        username: username.text,
        password: password.text,
        deviceName: device.text,
        fnEntryToken: entryToken,
        fnGatewayCookies: gatewayCookies,
        rememberPassword: _rememberPassword,
        expectedInstanceId: _selectedHistory?.serviceInstanceId.isEmpty == true
            ? null
            : _selectedHistory?.serviceInstanceId,
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _historyMessage = accountLoginStarted
              ? account.message ?? FlyAccountController.safeMessage(error)
              : FlyAccountController.safeMessage(error),
        );
      }
    } finally {
      if (mounted) {
        password.clear();
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _enterMediaMode(FlyAccountController account) async {
    if (!_canUseForm(account) || _historyBusy) return;
    _historyEpoch++;
    setState(() => _leaving = true);
    try {
      await account.enterLegacyMode();
      // Keep handlers locked until the provider gate replaces this page.
    } catch (_) {
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _editDeviceName(FlyAccountController account) async {
    if (!_canUseForm(account) || _historyBusy) return;
    _formRevision++;
    final form = GlobalKey<FormState>();
    final l10n = AppLocalizations.of(context);
    var name = device.text;
    final value = await _showFlyDesktopPanel<String>(
      context,
      title: l10n.flyAccountCurrentDeviceName,
      builder: (context) {
        void save() {
          if (form.currentState!.validate()) {
            AppSheetTransitions.close(context, name.trim());
          }
        }

        return _FlyDesktopPanel(
          title: l10n.flyAccountCurrentDeviceName,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: name,
                    autofocus: true,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: l10n.flyAccountCurrentDeviceName,
                    ),
                    onChanged: (value) => name = value,
                    onFieldSubmitted: (_) => save(),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? l10n.flyAccountFieldRequired(
                            l10n.flyAccountCurrentDeviceName,
                          )
                        : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: save, child: Text(l10n.commonSave)),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (value != null && _canUseForm(account)) device.text = value;
  }

  Widget _loginField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool secret = false,
    bool enabled = true,
    TextInputType? keyboard,
    ValueChanged<String>? onSubmitted,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LoginField(
      controller: controller,
      labelText: label,
      externalLabel: true,
      hintText: hint ?? label,
      enabled: enabled,
      leadingIcon: controller == url
          ? Icons.dns_outlined
          : secret
          ? Icons.lock_outline_rounded
          : Icons.person_outline_rounded,
      keyboardType: keyboard,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      obscureText: secret && _obscurePassword,
      onSubmitted: onSubmitted,
      validator: (value) => value == null || value.trim().isEmpty
          ? AppLocalizations.of(context).flyAccountFieldRequired(label)
          : null,
      suffix: secret
          ? IconButton(
              tooltip: _obscurePassword
                  ? AppLocalizations.of(context).connectionShowPassword
                  : AppLocalizations.of(context).connectionHidePassword,
              onPressed: enabled
                  ? () => setState(() => _obscurePassword = !_obscurePassword)
                  : null,
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            )
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    final blocked = account.busy || _historyBusy || _submitting || _leaving;
    return _FlyLoginPage(
      onSwitch: blocked ? null : () => _enterMediaMode(account),
      onEditDeviceName: blocked ? null : () => _editDeviceName(account),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _loginField(
              url,
              AppLocalizations.of(context).flyAccountServiceAddress,
              hint: AppLocalizations.of(context).flyAccountServiceAddressHint,
              enabled: !blocked,
              keyboard: TextInputType.url,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                AppLocalizations.of(
                  context,
                ).flyAccountServiceAddressExplanation,
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            _loginField(
              username,
              AppLocalizations.of(context).flyAccountUsername,
              hint: AppLocalizations.of(context).flyAccountAdminSharedHint,
              enabled: !blocked,
            ),
            _loginField(
              password,
              AppLocalizations.of(context).connectionPasswordHint,
              hint: AppLocalizations.of(context).flyAccountPasswordHint,
              secret: true,
              enabled: !blocked,
              onSubmitted: (_) => _login(account),
            ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: blocked
                        ? null
                        : () =>
                              _setRememberPassword(account, !_rememberPassword),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Checkbox(
                              value: _rememberPassword,
                              onChanged: blocked
                                  ? null
                                  : (value) => _setRememberPassword(
                                      account,
                                      value ?? false,
                                    ),
                              side: BorderSide(
                                color: context.appColors.borderStrong,
                              ),
                              fillColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? context.appColors.selection
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              AppLocalizations.of(
                                context,
                              ).flyAccountRememberPassword,
                              style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: blocked ? null : () => _openHistory(account),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: Text(
                        AppLocalizations.of(context).flyAccountHistory,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_historyMessage != null || account.message != null) ...[
              _FlyMessage(_historyMessage ?? account.message!),
              const SizedBox(height: 12),
            ],
            LoginSubmitButton(
              isSubmitting: account.busy || _submitting,
              accountStyle: true,
              busyLabel: _submitting
                  ? AppLocalizations.of(context).connectionLoggingIn
                  : AppLocalizations.of(context).accountProcessing,
              onPressed: blocked ? null : () => _login(account),
              label: AppLocalizations.of(context).flyAccountLoginSelectSource,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).flyAccountIndependentCredentials,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FlyBindingsScreen extends StatefulWidget {
  const FlyBindingsScreen({super.key});

  @override
  State<FlyBindingsScreen> createState() => _FlyBindingsScreenState();
}

class _FlyBindingsScreenState extends State<FlyBindingsScreen> {
  bool _confirmingLogout = false, _refreshing = false, _renewingFn = false;
  Object? _activatingBindingId;

  bool _blocked(FlyAccountController account) =>
      account.busy ||
      _confirmingLogout ||
      _refreshing ||
      _renewingFn ||
      _activatingBindingId != null;

  Future<void> _renewFn(FlyAccountController account) async {
    final session = account.session;
    final epoch = account.accountEpoch;
    if (_blocked(account) || session == null) return;
    setState(() => _renewingFn = true);
    try {
      final token = await _authorizeFlyFn(context, session.serverUrl);
      if (!mounted ||
          !identical(session, account.session) ||
          epoch != account.accountEpoch ||
          account.legacyMode) {
        return;
      }
      if (token == null || token.entryToken.isEmpty) {
        AppTopTip().show(
          context,
          message: 'FN 访问授权未完成，可重新授权。',
          color: context.appColors.surfaceStrong,
        );
        return;
      }
      await account.renewFnAccess(
        token.entryToken,
        fnGatewayCookies: token.gatewayCookies,
      );
    } catch (_) {
      // 控制器保留授权失败提示，页面只结束局部忙碌反馈。
    } finally {
      if (mounted) setState(() => _renewingFn = false);
    }
  }

  void _returnToMedia() {
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent && !route.isFirst) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _refresh(FlyAccountController account) async {
    if (_blocked(account)) return;
    setState(() => _refreshing = true);
    try {
      await account.refresh();
    } catch (_) {
      // 控制器保留安全化错误和现有来源，页面只结束局部忙碌反馈。
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout(FlyAccountController account) async {
    final session = account.session;
    if (_blocked(account) || session == null) return;
    final epoch = account.accountEpoch;
    setState(() => _confirmingLogout = true);
    try {
      final l10n = AppLocalizations.of(context);
      final confirmed = await showAppConfirmDialog(
        context,
        title: l10n.flyAccountLogoutConfirmTitle,
        content: l10n.flyAccountLogoutConfirmMessage,
        cancelText: l10n.commonCancel,
        confirmText: l10n.flyAccountLogoutConfirmAction,
      );
      if (!confirmed || !mounted || account.busy) return;
      final current = account.session;
      if (current == null ||
          current.accountKey != session.accountKey ||
          current.token != session.token ||
          current.deviceId != session.deviceId ||
          account.accountEpoch != epoch) {
        return;
      }
      await account.logout();
    } catch (_) {
      // 退出失败信息由控制器显示，不把关闭确认弹窗当作退出。
    } finally {
      if (mounted) setState(() => _confirmingLogout = false);
    }
  }

  Future<void> _enterSource(
    FlyAccountController account,
    Map<String, dynamic> binding,
  ) async {
    if (_blocked(account)) return;
    if (account.activeBindingId == binding['id']) {
      _returnToMedia();
      return;
    }
    setState(() => _activatingBindingId = binding['id']);
    try {
      if (await activateFlyBinding(context, account, binding) && mounted) {
        _returnToMedia();
      }
    } finally {
      if (mounted) setState(() => _activatingBindingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    if (account.session == null) return const FlyLoginScreen();
    final session = account.session!;
    final bindings = account.bindings
        .where((binding) => binding['status'] != 'unbound')
        .toList();
    final currentIndex = bindings.indexWhere(
      (binding) => binding['id'] == account.activeBindingId,
    );
    final current = currentIndex < 0 ? null : bindings[currentIndex];
    final otherBindings = bindings
        .where((binding) => binding['id'] != current?['id'])
        .toList();
    final blocked = _blocked(account);
    final l10n = AppLocalizations.of(context);

    Widget sourceCard(Map<String, dynamic> binding) => _FlySourceCard(
      binding: binding,
      current: binding['id'] == current?['id'],
      hasCurrentSource: current != null,
      busy: blocked,
      connecting: _activatingBindingId == binding['id'],
      onEnter: () => _enterSource(account, binding),
    );

    return _FlyAccountPage(
      title: l10n.flyAccountTitle,
      identityBuilder: (desktop) => _FlyAccountIdentity(
        desktop: desktop,
        username: session.username,
        serverUrl: session.serverUrl,
        deviceName: session.deviceName,
        onLogout: blocked ? null : () => _logout(account),
      ),
      children: [
        _FlySectionTitle(
          title: l10n.flyAccountMySources,
          subtitle: l10n.flyAccountSourceCount(bindings.length.toString()),
          action: IconButton(
            tooltip: l10n.flyAccountRefreshSources,
            onPressed: blocked ? null : () => _refresh(account),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: 18),
        if (bindings.isEmpty &&
            !account.busy &&
            !_refreshing &&
            account.message == null)
          LoginFormPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  const Icon(Icons.video_library_outlined, size: 36),
                  const SizedBox(height: 12),
                  Text(l10n.flyAccountAddFirstSource),
                  const SizedBox(height: 8),
                  Text(
                    l10n.flyAccountAddFirstSourceSubtitle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        if (current != null) ...[
          sourceCard(current),
          if (otherBindings.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              l10n.flyAccountOtherSources,
              style: TextStyle(
                color: context.appColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
        for (final binding in otherBindings) ...[
          sourceCard(binding),
          const SizedBox(height: 12),
        ],
        if (_refreshing || account.busy && _activatingBindingId == null) ...[
          const SizedBox(height: 12),
          const Center(child: BirdLoader()),
          Center(
            child: _FlyMessage(
              _refreshing ? l10n.flyAccountRefreshing : l10n.accountProcessing,
            ),
          ),
        ],
        if (account.message != null) _FlyMessage(account.message!),
        if (isFlyFnApplicationUrl(session.serverUrl))
          TextButton.icon(
            onPressed: blocked ? null : () => _renewFn(account),
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('重新授权 FN 访问'),
          ),
        if (bindings.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            l10n.flyAccountSourceHelpDetail,
            style: TextStyle(
              color: context.appColors.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

Future<String?> _showFlyOptions(
  BuildContext context, {
  required String title,
  required List<TrackOptionSheetItem> items,
  String? selectedId,
}) {
  if (!DesktopEnvironment.isDesktopPlatform) {
    return TrackOptionSheet.show(
      context,
      title: title,
      items: items,
      selectedId: selectedId,
    );
  }
  return _showFlyDesktopPanel<String>(
    context,
    title: title,
    builder: (context) => _FlyDesktopPanel(
      title: title,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) => DesktopDropdownOptionRow(
          item: items[index],
          selected: items[index].id == selectedId,
          onTap: () => AppSheetTransitions.close(context, items[index].id),
        ),
      ),
    ),
  );
}

// Same centered glass-panel route as the desktop catalog filters. Platform
// chooses the shell; window dimensions only constrain its available space.
Future<T?> _showFlyDesktopPanel<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) => AppSheetTransitions.showAdaptiveSheet<T>(
  context,
  barrierLabel: title,
  barrierColor: context.appColors.overlayScrim.withValues(alpha: .18),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      minimum: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 470,
              maxHeight: constraints.maxHeight * .9,
            ),
            child: builder(context),
          ),
        ),
      ),
    ),
  ),
);

class _FlyDesktopPanel extends StatelessWidget {
  const _FlyDesktopPanel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => DesktopFloatingPanel(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).commonClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => AppSheetTransitions.close(context),
              ),
            ],
          ),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: child,
          ),
        ),
      ],
    ),
  );
}

/// Form state stays alive through the shared modal's closing transition.
