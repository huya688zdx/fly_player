import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../desktop/desktop_environment.dart';
import '../desktop/desktop_context_menu.dart';
import '../desktop/desktop_floating_panel.dart';
import '../desktop/desktop_hover_dropdown.dart';
import '../services/fly_data/fly_account_controller.dart';
import '../services/fly_data/fly_login_history_store.dart';
import '../theme/app_theme.dart';
import '../ui/app_info_popover.dart';
import '../ui/app_sheet_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/app_action_sheet.dart';
import '../widgets/common/app_ambient_page.dart';
import '../widgets/common/app_option_list.dart';
import '../widgets/common/track_option_sheet.dart';
import 'connection_screen.dart';
import 'fly_data_settings_screen.dart';

part 'fly_account_widgets.dart';

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

void _showChangedAccount(BuildContext context) {
  if (!context.mounted) return;
  AppTopTip().show(
    context,
    message: AppLocalizations.of(context).flyAccountSourceChanged,
    color: context.appColors.surfaceStrong,
  );
}

/// Shared by the home source selector and the account page.
/// Navigation belongs to the caller; failure or cancellation stays put.
Future<bool> activateFlyBinding(
  BuildContext context,
  FlyAccountController account,
  Map<String, dynamic> binding, {
  bool chooseAddress = false,
}) async {
  if (account.busy || !context.mounted) return false;
  final accountKey = account.accountKey;
  final bindingId = binding['id'], revision = binding['revision'];
  bool current() =>
      _bindingStillCurrent(account, accountKey, bindingId, revision);
  try {
    if (!chooseAddress) {
      await account.activate(binding);
      return current();
    }
    final server = binding['server'] as Map? ?? const {};
    final addresses =
        (server['addresses'] as List? ?? const [])
            .whereType<Map>()
            .where((address) => address['purpose'] != 'nas_api')
            .where(
              (address) => (address['base_url'] as String? ?? '').isNotEmpty,
            )
            .toList()
          ..sort(
            (a, b) => ((a['priority'] as num?)?.toInt() ?? 0).compareTo(
              (b['priority'] as num?)?.toInt() ?? 0,
            ),
          );
    if (addresses.isEmpty) {
      AppTopTip().show(
        context,
        message: AppLocalizations.of(context).flyAccountNoPlaybackAddresses,
        color: context.appColors.surfaceStrong,
      );
      return false;
    }
    String? selectedId;
    final connection = account.backendSession.currentConnection;
    if (connection != null &&
        connection.accountKey == accountKey &&
        connection.bindingId == bindingId &&
        connection.bindingRevision == revision) {
      String normalized(String value) =>
          value.trim().replaceFirst(RegExp(r'/+$'), '');
      for (final address in addresses) {
        final url = address['base_url'] as String;
        if (normalized(url) == normalized(connection.serverUrl)) {
          selectedId = url;
          break;
        }
      }
    }
    final selected = await _showFlyOptions(
      context,
      title: AppLocalizations.of(context).flyAccountConnectionSettings,
      selectedId: selectedId,
      items: [
        for (final address in addresses)
          TrackOptionSheetItem(
            id: address['base_url'] as String,
            title: _addressLabel(context, address['purpose']),
            subtitle: address['base_url'] as String,
          ),
      ],
    );
    if (selected == null || !context.mounted || account.busy) return false;
    if (!current()) {
      _showChangedAccount(context);
      return false;
    }
    await account.activate(binding, address: selected);
    return current();
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
  bool _rememberPassword = true;
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
    setState(() => _submitting = true);
    try {
      await account.login(
        url: url.text,
        username: username.text,
        password: password.text,
        deviceName: device.text,
        rememberPassword: _rememberPassword,
        expectedInstanceId: _selectedHistory?.serviceInstanceId.isEmpty == true
            ? null
            : _selectedHistory?.serviceInstanceId,
      );
    } catch (_) {
      // The controller publishes the error below the form.
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

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    final blocked = account.busy || _historyBusy || _submitting || _leaving;
    return _FlyLoginPage(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              url,
              AppLocalizations.of(context).flyAccountServiceAddress,
              hint: AppLocalizations.of(context).flyAccountServiceAddressHelp,
              enabled: !blocked,
              keyboard: TextInputType.url,
            ),
            _field(
              username,
              AppLocalizations.of(context).flyAccountUsername,
              hint: AppLocalizations.of(context).flyAccountAdminSharedHint,
              enabled: !blocked,
            ),
            _field(
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
                              (states) => states.contains(WidgetState.selected)
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
                TextButton.icon(
                  onPressed: blocked ? null : () => _openHistory(account),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: Text(AppLocalizations.of(context).flyAccountHistory),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                AppLocalizations.of(
                  context,
                ).flyAccountDeviceNameSummary(device.text),
                style: const TextStyle(fontSize: 13),
              ),
              children: [
                _field(
                  device,
                  AppLocalizations.of(context).flyAccountCurrentDeviceName,
                  enabled: !blocked,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: blocked ? null : () => _login(account),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.login_rounded, size: 20),
              label: Text(AppLocalizations.of(context).flyAccountLogin),
            ),
            if (account.busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (account.message != null) _FlyMessage(account.message!),
            if (_historyMessage != null) _FlyMessage(_historyMessage!),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: blocked ? null : () => _enterMediaMode(account),
              icon: const Icon(Icons.lan_outlined, size: 18),
              label: Text(AppLocalizations.of(context).flyAccountMediaLogin),
            ),
          ],
        ),
      ),
    );
  }
}

class FlyBindingsScreen extends StatelessWidget {
  const FlyBindingsScreen({super.key});
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  void _returnToMedia(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent && !route.isFirst) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _enterSource(
    BuildContext context,
    FlyAccountController account,
    Map<String, dynamic> binding,
  ) async {
    final current = account.activeBindingId == binding['id'];
    if (current || await activateFlyBinding(context, account, binding)) {
      if (context.mounted) _returnToMedia(context);
    }
  }

  Future<void> _sourceAction(
    BuildContext context,
    FlyAccountController account,
    Map<String, dynamic> binding,
    String action,
  ) async {
    if (account.busy || !context.mounted) return;
    final accountKey = account.accountKey;
    final bindingId = binding['id'], revision = binding['revision'];
    switch (action) {
      case 'address':
        await activateFlyBinding(
          context,
          account,
          binding,
          chooseAddress: true,
        );
      case 'reauthorize':
        await _bindingForm(context, account, binding: binding);
      case 'sync':
        await _run(() => account.syncCatalog(binding));
      case 'unbind':
        final yes = await showAppConfirmDialog(
          context,
          title: AppLocalizations.of(context).flyAccountRemoveSourceTitle,
          content: AppLocalizations.of(context).flyAccountRemoveSourceMessage,
          cancelText: AppLocalizations.of(context).commonCancel,
          confirmText: AppLocalizations.of(context).flyAccountRemove,
        );
        if (yes && context.mounted) {
          if (!_bindingStillCurrent(account, accountKey, bindingId, revision)) {
            _showChangedAccount(context);
            return;
          }
          await _run(() => account.unbind(binding));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    if (account.session == null) return const FlyLoginScreen();
    final session = account.session!;
    final colors = context.appColors;
    final accountKey = account.accountKey;
    return _page(AppLocalizations.of(context).flyAccountTitle, [
      _FlySurface(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.person_outline_rounded, color: colors.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.username,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context).flyAccountAdminSharedSubtitle,
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: account.busy ? null : () => _run(account.logout),
              child: Text(AppLocalizations.of(context).flyAccountLogout),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      _FlySectionTitle(
        title: AppLocalizations.of(context).flyAccountMySources,
        subtitle: AppLocalizations.of(
          context,
        ).flyAccountSourceCount(account.bindings.length.toString()),
        action: IconButton(
          tooltip: AppLocalizations.of(context).flyAccountRefreshSources,
          onPressed: account.busy ? null : () => _run(account.refresh),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
      const SizedBox(height: 12),
      if (account.bindings.isEmpty)
        _FlySurface(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                const Icon(Icons.video_library_outlined, size: 36),
                const SizedBox(height: 12),
                Text(AppLocalizations.of(context).flyAccountAddFirstSource),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context).flyAccountAddFirstSourceSubtitle,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      for (final binding in account.bindings) ...[
        _FlySourceCard(
          binding: binding,
          current: account.activeBindingId == binding['id'],
          busy: account.busy,
          onEnter: () => _enterSource(context, account, binding),
          onReauthorize: () => _bindingForm(context, account, binding: binding),
          onAction: (action) {
            if (!_bindingStillCurrent(
              account,
              accountKey,
              binding['id'],
              binding['revision'],
            )) {
              _showChangedAccount(context);
              return;
            }
            _sourceAction(context, account, binding, action);
          },
        ),
        const SizedBox(height: 12),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (!account.legacyMode)
              FilledButton.icon(
                onPressed: account.busy
                    ? null
                    : () => _localServiceForm(context, account),
                icon: const Icon(Icons.home_work_outlined),
                label: Text(
                  AppLocalizations.of(context).flyAccountBindNasMedia,
                ),
              ),
            OutlinedButton.icon(
              onPressed: account.busy
                  ? null
                  : () => _bindingForm(context, account),
              icon: const Icon(Icons.add_rounded),
              label: Text(AppLocalizations.of(context).flyAccountAddSource),
            ),
          ],
        ),
      ),
      if (account.busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: LinearProgressIndicator(),
        ),
      if (account.message != null) _FlyMessage(account.message!),
      const SizedBox(height: 24),
      _FlySurface(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(Icons.tune_rounded),
          title: Text(AppLocalizations.of(context).nativePlayerText0071),
          children: [
            if (session.role == 'admin')
              _managementRow(
                icon: Icons.dns_outlined,
                title: AppLocalizations.of(context).flyAccountAddServer,
                onTap: account.busy
                    ? null
                    : () => _serverForm(context, account),
              ),
            _managementRow(
              icon: Icons.public_rounded,
              title: AppLocalizations.of(context).flyDataServiceAddressLabel,
              subtitle: session.serverUrl,
              onTap: account.busy
                  ? null
                  : () => _serviceAddress(context, account),
            ),
            _managementRow(
              icon: Icons.cloud_sync_outlined,
              title: AppLocalizations.of(context).flySyncRecords,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FlyDataSettingsScreen(),
                ),
              ),
            ),
            _managementRow(
              icon: Icons.lan_outlined,
              title: AppLocalizations.of(context).flyAccountMediaLogin,
              onTap: account.busy
                  ? null
                  : () async {
                      await _run(account.enterLegacyMode);
                      if (context.mounted) {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ConnectionScreen(),
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    ]);
  }

  Future<void> _serviceAddress(
    BuildContext context,
    FlyAccountController account,
  ) async {
    final session = account.session;
    if (session == null || account.busy) return;
    final accountKey = account.accountKey;
    final address = await _showFlyOptions(
      context,
      title: AppLocalizations.of(context).flyDataServiceAddressLabel,
      selectedId: session.serverUrl,
      items: [
        for (final url in {session.serverUrl, ...session.addresses})
          TrackOptionSheetItem(id: url, title: url),
        TrackOptionSheetItem(
          id: 'add',
          title: AppLocalizations.of(context).flyAccountAddAddress,
        ),
      ],
    );
    if (address == null || !context.mounted || account.busy) return;
    if (account.accountKey != accountKey) {
      _showChangedAccount(context);
      return;
    }
    if (address == 'add') {
      final values = await flyForm(
        context,
        AppLocalizations.of(context).flyAccountAddAddress,
        {'url': AppLocalizations.of(context).flyDataServiceAddressLabel},
      );
      if (values == null || !context.mounted || account.busy) return;
      if (account.accountKey != accountKey) {
        _showChangedAccount(context);
        return;
      }
      await _run(() => account.switchAddress(values['url']!));
    } else if (address != account.session?.serverUrl) {
      await _run(() => account.switchAddress(address));
    }
  }

  Future<void> _localServiceForm(
    BuildContext context,
    FlyAccountController account,
  ) async {
    final accountKey = account.accountKey, epoch = account.accountEpoch;
    bool current() => account.isCurrentFlyAccount(accountKey, epoch);
    void tip(String text) => AppTopTip().show(
      context,
      message: text,
      color: context.appColors.surfaceStrong,
    );
    try {
      final response = await account.loadLocalServices();
      if (!context.mounted) return;
      if (!current()) {
        _showChangedAccount(context);
        return;
      }
      if (response['enabled'] != true) {
        tip(
          response['message'] as String? ??
              AppLocalizations.of(context).flyAccountDiscoveryDisabled,
        );
        return;
      }
      final items = (response['items'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => (item['key'] as String? ?? '').isNotEmpty)
          .toList();
      if (items.isEmpty) {
        tip(AppLocalizations.of(context).flyAccountDiscoveryEmpty);
        return;
      }
      final selected = await _showFlyOptions(
        context,
        title: AppLocalizations.of(context).flyAccountChooseNasMedia,
        items: [
          for (final item in items)
            TrackOptionSheetItem(
              id: item['key'] as String,
              title:
                  item['name'] as String? ??
                  _backendLabel(context, item['kind']),
              subtitle: item['status'] != 'available'
                  ? AppLocalizations.of(context).flyAccountLocalServiceStopped
                  : (item['server_id'] as String? ?? '').isNotEmpty
                  ? AppLocalizations.of(context).flyAccountLocalServiceReady
                  : account.session?.role == 'admin'
                  ? AppLocalizations.of(context).flyAccountEnableThenBind
                  : AppLocalizations.of(context).flyAccountAskAdminEnable,
            ),
        ],
      );
      if (selected == null || !context.mounted) return;
      if (!current()) {
        _showChangedAccount(context);
        return;
      }
      final item = items.firstWhere((item) => item['key'] == selected);
      if (item['status'] != 'available') {
        tip(AppLocalizations.of(context).flyAccountLocalServiceUnavailable);
        return;
      }
      var serverId = item['server_id'] as String? ?? '';
      if (serverId.isEmpty) {
        if (account.session?.role != 'admin') {
          tip(AppLocalizations.of(context).flyAccountLocalServiceNeedsAdmin);
          return;
        }
        final server = await account.registerLocalService(
          selected,
          expectedAccountKey: accountKey,
          expectedEpoch: epoch,
        );
        if (!context.mounted) return;
        if (!current()) {
          _showChangedAccount(context);
          return;
        }
        serverId = server['id'] as String? ?? '';
        if (serverId.isEmpty) {
          tip(AppLocalizations.of(context).flyAccountLocalServiceIncomplete);
          return;
        }
      }
      await _bindingForm(context, account, selectedServerId: serverId);
    } catch (_) {
      // Controller provides the safe error message in the account page.
    }
  }

  Future<void> _bindingForm(
    BuildContext context,
    FlyAccountController account, {
    Map<String, dynamic>? binding,
    String? selectedServerId,
  }) async {
    final accountKey = account.accountKey;
    final epoch = account.accountEpoch;
    final bindingId = binding?['id'], revision = binding?['revision'];
    bool current() =>
        account.isCurrentFlyAccount(accountKey, epoch) &&
        (binding == null ||
            _bindingStillCurrent(account, accountKey, bindingId, revision));
    String? serverId = binding?['server_id'] as String? ?? selectedServerId;
    if (serverId == null) {
      if (account.servers.isEmpty) {
        await _run(account.refresh);
        if (!context.mounted) return;
      }
      if (account.servers.isEmpty) {
        AppTopTip().show(
          context,
          message: AppLocalizations.of(context).flyAccountNoRegisteredServers,
          color: context.appColors.surfaceStrong,
        );
        return;
      }
      serverId = await _showFlyOptions(
        context,
        title: AppLocalizations.of(context).flyAccountChooseRegisteredServer,
        items: [
          for (final server in account.servers)
            TrackOptionSheetItem(
              id: server['id'] as String,
              title:
                  server['name'] as String? ??
                  AppLocalizations.of(context).flyAccountMediaServer,
              subtitle: _backendLabel(context, server['kind']),
            ),
        ],
      );
    }
    if (serverId == null || !context.mounted) return;
    if (!current()) {
      _showChangedAccount(context);
      return;
    }
    final values = await flyForm(
      context,
      binding == null
          ? AppLocalizations.of(context).flyAccountLinkMediaAccount
          : AppLocalizations.of(context).flyAccountReauthorize,
      {
        if (binding == null)
          'label': AppLocalizations.of(context).flyAccountBindingName,
        'username': AppLocalizations.of(context).flyAccountMediaUsername,
        'password': AppLocalizations.of(context).flyAccountMediaPassword,
      },
      secretKeys: {'password'},
    );
    if (values == null || !context.mounted) return;
    if (!current()) {
      _showChangedAccount(context);
      return;
    }
    if (binding == null) {
      await _run(
        () => account.createBinding({'server_id': serverId, ...values}),
      );
    } else {
      await _run(
        () => account.reauthorize(
          binding,
          username: values['username']!,
          password: values['password']!,
        ),
      );
    }
  }

  Future<void> _serverForm(
    BuildContext context,
    FlyAccountController account,
  ) async {
    final accountKey = account.accountKey;
    const kinds = ['feiniu', 'emby', 'jellyfin'];
    final selection = DesktopEnvironment.isDesktopPlatform
        ? _showFlyOptions(
            context,
            title: AppLocalizations.of(context).flyAccountMediaServerType,
            items: [
              for (final kind in kinds)
                TrackOptionSheetItem(
                  id: kind,
                  title: _backendLabel(context, kind),
                ),
            ],
          )
        : showAppActionSheet<String>(
            context,
            title: AppLocalizations.of(context).flyAccountMediaServerType,
            options: [
              for (final kind in kinds)
                AppActionSheetOption(
                  value: kind,
                  label: _backendLabel(context, kind),
                ),
            ],
          );
    final kind = await selection;
    if (kind == null || !context.mounted) return;
    if (account.accountKey != accountKey) {
      _showChangedAccount(context);
      return;
    }
    final values = await flyForm(
      context,
      AppLocalizations.of(context).flyAccountRegisterServer,
      {
        'name': AppLocalizations.of(context).flyAccountServerName,
        'nas_api': AppLocalizations.of(context).flyAccountNasAddressRequired,
        'client_lan': AppLocalizations.of(
          context,
        ).flyAccountAppLanAddressOptional,
        'client_remote': AppLocalizations.of(
          context,
        ).flyAccountAppHttpsAddressOptional,
        'vpn': AppLocalizations.of(context).flyAccountAppVpnAddressOptional,
      },
      optionalKeys: {'client_lan', 'client_remote', 'vpn'},
    );
    if (values != null && context.mounted) {
      if (account.accountKey != accountKey) {
        _showChangedAccount(context);
        return;
      }
      await _run(
        () => account.createServer({
          'kind': kind,
          'name': values['name'],
          'addresses': [
            for (final purpose in [
              'nas_api',
              'client_lan',
              'client_remote',
              'vpn',
            ])
              if (values[purpose]!.trim().isNotEmpty)
                {
                  'purpose': purpose,
                  'base_url': values[purpose]!.trim(),
                  'priority': 0,
                },
          ],
        }),
      );
    }
  }
}

Widget _page(String title, List<Widget> children) =>
    _FlyAccountPage(title: title, children: children);

Widget _managementRow({
  required IconData icon,
  required String title,
  String? subtitle,
  required VoidCallback? onTap,
}) => ListTile(
  contentPadding: EdgeInsets.zero,
  leading: Icon(icon, size: 22),
  title: Text(
    title,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ),
  subtitle: subtitle == null
      ? null
      : Text(subtitle, style: const TextStyle(fontSize: 12)),
  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
  onTap: onTap,
);

Widget _field(
  TextEditingController controller,
  String label, {
  String? hint,
  bool secret = false,
  bool enabled = true,
  bool optional = false,
  TextInputType? keyboard,
  ValueChanged<String>? onSubmitted,
}) => Builder(
  builder: (context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: !secret,
        keyboardType: keyboard,
        onFieldSubmitted: onSubmitted,
        validator: (value) =>
            !optional && (value == null || value.trim().isEmpty)
            ? AppLocalizations.of(context).flyAccountFieldRequired(label)
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: colors.surfaceSubtle,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.accent),
          ),
        ),
      ),
    );
  },
);

Future<Map<String, String>?> flyForm(
  BuildContext context,
  String title,
  Map<String, String> fields, {
  Set<String> secretKeys = const {},
  Set<String> optionalKeys = const {},
}) {
  final desktop = DesktopEnvironment.isDesktopPlatform;
  Widget form(BuildContext _) => _FlyAccountForm(
    title: title,
    fields: fields,
    secretKeys: secretKeys,
    optionalKeys: optionalKeys,
    floating: desktop,
  );
  if (desktop) {
    return _showFlyDesktopPanel<Map<String, String>>(
      context,
      title: title,
      builder: form,
    );
  }
  return AppSheetTransitions.showBottomSurface<Map<String, String>>(
    context,
    barrierColor: context.appColors.overlayScrim,
    barrierLabel: title,
    builder: form,
  );
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
class _FlyAccountForm extends StatefulWidget {
  const _FlyAccountForm({
    required this.title,
    required this.fields,
    required this.secretKeys,
    required this.optionalKeys,
    required this.floating,
  });
  final String title;
  final Map<String, String> fields;
  final Set<String> secretKeys, optionalKeys;
  final bool floating;

  @override
  State<_FlyAccountForm> createState() => _FlyAccountFormState();
}

class _FlyAccountFormState extends State<_FlyAccountForm> {
  final _form = GlobalKey<FormState>();
  late final controllers = {
    for (final key in widget.fields.keys) key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in widget.fields.entries)
                    _field(
                      controllers[entry.key]!,
                      entry.value,
                      secret: widget.secretKeys.contains(entry.key),
                      optional: widget.optionalKeys.contains(entry.key),
                    ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context).commonCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (_form.currentState?.validate() != true) return;
                    Navigator.pop(context, {
                      for (final entry in controllers.entries)
                        entry.key: entry.value.text,
                    });
                  },
                  child: Text(AppLocalizations.of(context).flyAccountConfirm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (widget.floating) {
      return _FlyDesktopPanel(title: widget.title, child: content);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: AppOptionSheetPanel(title: widget.title, child: content),
    );
  }
}
