import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import '../services/fly_data/fly_account_controller.dart';
import '../services/fly_data/fly_data_service.dart';
import '../services/fly_data/fly_data_sync_store.dart';
import '../theme/app_theme.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/common/app_ambient_page.dart';
import 'fly_account_screen.dart';

class FlyDataSettingsScreen extends StatefulWidget {
  const FlyDataSettingsScreen({super.key, this.service});

  final FlyDataService? service;

  @override
  State<FlyDataSettingsScreen> createState() => _FlyDataSettingsScreenState();
}

class _FlyDataSettingsScreenState extends State<FlyDataSettingsScreen> {
  FlyDataService? _service;
  FlyDataSession? _session;
  String? _scope;
  int _generation = 0;
  bool _busy = false, _loaded = false, _failed = false;
  bool _hasSource = false;
  Map<String, Object?>? _syncState;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.watch<FlyAccountController?>();
    _observe(
      widget.service ?? account?.service ?? FlyDataService.instance,
      hasSource: _hasSelectedSource(account),
    );
  }

  @override
  void didUpdateWidget(FlyDataSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final account = context.read<FlyAccountController?>();
    _observe(
      widget.service ?? account?.service ?? FlyDataService.instance,
      hasSource: _hasSelectedSource(account),
    );
  }

  bool _hasSelectedSource(FlyAccountController? account) =>
      account != null &&
      !account.legacyMode &&
      account.activeBindingId.isNotEmpty;

  void _observe(FlyDataService service, {required bool hasSource}) {
    if (identical(_service, service) &&
        identical(_session, service.session) &&
        _scope == service.scopeIdentity &&
        _hasSource == hasSource) {
      return;
    }
    _service = service;
    _session = service.session;
    _scope = service.scopeIdentity;
    _hasSource = hasSource;
    _generation++;
    _syncState = null;
    _message = null;
    _failed = false;
    _loaded = false;
    _busy = _session != null && _hasSource;
    if (_busy) unawaited(_load(_generation));
  }

  bool _current(int generation) =>
      mounted &&
      _hasSource &&
      generation == _generation &&
      identical(_service?.session, _session) &&
      _service?.scopeIdentity == _scope;

  Future<void> _load(int generation, {bool sync = false}) async {
    final service = _service!;
    final session = _session;
    if (session == null || !_current(generation)) return;
    final l10n = AppLocalizations.of(context);
    String? message;
    var failed = false;
    if (sync) {
      try {
        await service.syncNow();
        message = l10n.flySyncCompleted;
      } on FlyNoFactsToSync {
        message = l10n.flySyncNoPendingRecords;
      } catch (_) {
        message = l10n.flySyncFailed;
        failed = true;
      }
    }
    if (!_current(generation)) return;
    Map<String, Object?>? state;
    var loaded = true;
    try {
      state = await service.store.state(session.accountKey);
    } catch (_) {
      message = l10n.flySyncStatusUnavailable;
      failed = true;
      loaded = false;
    }
    if (!_current(generation)) return;
    setState(() {
      _syncState = state;
      _message = message;
      _failed = failed;
      _loaded = loaded;
      _busy = false;
    });
  }

  void _sync(int generation) {
    final account = context.read<FlyAccountController?>();
    if (_busy ||
        !_current(generation) ||
        !_hasSelectedSource(account) ||
        account?.busy == true) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    unawaited(_load(generation, sync: _loaded));
  }

  void _openAccount() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const FlyBindingsScreen()));
  }

  String _lastSync(BuildContext context) {
    final milliseconds = _syncState?['last_success_ms'];
    if (milliseconds is! int) {
      return AppLocalizations.of(context).flySyncNeverSynced;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    final localizations = MaterialLocalizations.of(context);
    return AppLocalizations.of(context).flySyncLastSync(
      '${localizations.formatCompactDate(date)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController?>();
    final colors = context.appColors;
    final session = _session;
    final generation = _generation;
    final pending = _syncState?['pending_json'] != null;
    final status =
        _message ??
        (_busy
            ? (_loaded
                  ? AppLocalizations.of(context).flySyncInProgress
                  : AppLocalizations.of(context).flySyncReading)
            : pending
            ? AppLocalizations.of(context).flySyncPending
            : AppLocalizations.of(context).flySyncSignedIn);
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(AppLocalizations.of(context).flySyncRecords),
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: AppAmbientPage.cardColorOf(context, colors.surface),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              session == null
                                  ? Icons.person_outline
                                  : Icons.cloud_sync_outlined,
                            ),
                            title: Text(
                              session?.username ??
                                  AppLocalizations.of(context).flySyncSignIn,
                            ),
                            subtitle: session == null
                                ? null
                                : Semantics(
                                    liveRegion: true,
                                    child: Text(status),
                                  ),
                          ),
                          if (session != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _lastSync(context),
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (!_hasSource)
                              FilledButton(
                                onPressed: account?.busy == true
                                    ? null
                                    : _openAccount,
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).flySyncChooseSource,
                                ),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _busy || account?.busy == true
                                    ? null
                                    : () => _sync(generation),
                                icon: const Icon(Icons.sync),
                                label: Text(
                                  _failed || pending
                                      ? AppLocalizations.of(context).commonRetry
                                      : AppLocalizations.of(
                                          context,
                                        ).flyDataSyncNowAction,
                                ),
                              ),
                            if (_busy)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: LinearProgressIndicator(),
                              ),
                          ] else
                            FilledButton(
                              onPressed: account?.busy == true
                                  ? null
                                  : _openAccount,
                              child: Text(
                                AppLocalizations.of(context).flyAccountLogin,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
