import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import '../desktop/desktop_environment.dart';
import '../desktop/desktop_hover_dropdown.dart';
import '../screens/fly_account_screen.dart';
import '../screens/fly_catalog_screen.dart';
import '../screens/play_stats_report_screen.dart';
import '../services/fly_data/fly_account_controller.dart';
import '../theme/app_theme.dart';
import '../ui/app_sheet_transitions.dart';
import '../ui/app_popup_theme.dart';
import 'common/app_option_list.dart';
import 'common/track_option_sheet.dart';

enum _SourceAction { switchSource, account, catalog, stats }

class _SourceChoice {
  const _SourceChoice(this.accountKey, this.action, [this.bindingId = '']);
  final String accountKey, bindingId;
  final _SourceAction action;
}

class FlyMediaSourceMenu extends StatefulWidget {
  const FlyMediaSourceMenu({super.key});
  @override
  State<FlyMediaSourceMenu> createState() => _FlyMediaSourceMenuState();
}

class _FlyMediaSourceMenuState extends State<FlyMediaSourceMenu> {
  List<(_SourceAction, IconData, String)> get _actions => [
    (
      _SourceAction.account,
      Icons.account_circle_outlined,
      AppLocalizations.of(context).flyAccountTitle,
    ),
    (
      _SourceAction.catalog,
      Icons.video_library_outlined,
      AppLocalizations.of(context).flyCatalogSyncedTitles,
    ),
    (
      _SourceAction.stats,
      Icons.bar_chart_rounded,
      AppLocalizations.of(context).flySourceWatchStatistics,
    ),
  ];

  final _desktopMenu = GlobalKey<DesktopHoverDropdownState>();
  String? _desktopOpenedAccountKey;
  bool switching = false;
  bool menuOpen = false;

  void _toggleDesktopMenu() {
    final account = context.read<FlyAccountController>();
    if (switching || account.busy) return;
    if (!menuOpen) {
      setState(() => _desktopOpenedAccountKey = account.accountKey);
    }
    _desktopMenu.currentState?.toggle();
  }

  DesktopHoverDropdownSpec _desktopSpec(FlyAccountController account) {
    final colors = context.appColors;
    final accountKey = _desktopOpenedAccountKey ?? account.accountKey;
    final canSelect =
        account.accountKey == accountKey && !account.busy && !switching;
    final bindings = account.bindings
        .where((binding) => binding['status'] != 'unbound')
        .toList();
    return DesktopHoverDropdownSpec(
      title: AppLocalizations.of(context).flySourceMediaSources,
      groups: [
        if (bindings.isNotEmpty)
          DesktopDropdownOptionGroup(
            items: [
              for (final binding in bindings)
                TrackOptionSheetItem(
                  id: binding['id'] as String,
                  title:
                      binding['label'] as String? ??
                      AppLocalizations.of(context).flySourceMediaSources,
                  subtitle: binding['status'] == 'reauth_required'
                      ? AppLocalizations.of(
                          context,
                        ).flySourceReauthorizationRequired
                      : '',
                ),
            ],
            selectedId: account.activeBindingId,
            disabledIds: {
              for (final binding in bindings)
                if (!canSelect || binding['status'] != 'active')
                  binding['id'] as String,
            },
            leadingById: {
              for (final binding in bindings)
                binding['id'] as String: _sourceIcon(
                  (binding['server'] as Map?)?['kind']?.toString(),
                  colors.textSecondary,
                ),
            },
            onSelected: (id) => unawaited(
              _select(
                _SourceChoice(accountKey, _SourceAction.switchSource, id),
              ),
            ),
          ),
        DesktopDropdownOptionGroup(
          items: [
            for (final action in _actions)
              TrackOptionSheetItem(id: action.$1.name, title: action.$3),
          ],
          selectedId: null,
          disabledIds: {
            if (!canSelect)
              for (final action in _actions) action.$1.name,
          },
          leadingById: {
            for (final action in _actions)
              action.$1.name: Icon(
                action.$2,
                size: 20,
                color: colors.textSecondary,
              ),
          },
          onSelected: (id) => unawaited(
            _select(_SourceChoice(accountKey, _SourceAction.values.byName(id))),
          ),
        ),
      ],
    );
  }

  Future<void> _openMenu() async {
    if (!mounted) return;
    final account = context.read<FlyAccountController>();
    if (menuOpen || switching || account.busy) return;
    final accountKey = account.accountKey;
    final media = MediaQuery.of(context);
    final floating = media.size.width > media.size.height;
    final colors = context.appColors;
    final popupTheme = AppPopupTheme.capture(context);
    final body = ListenableBuilder(
      listenable: account,
      builder: (sheetContext, _) =>
          _options(sheetContext, account, accountKey, floating: floating),
    );
    menuOpen = true;
    try {
      final selection = floating
          ? showDialog<_SourceChoice>(
              context: context,
              useRootNavigator: false,
              barrierColor: colors.overlayScrim,
              builder: (_) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: (media.size.width * .62).clamp(520.0, 760.0),
                  child: popupTheme.wrap(body),
                ),
              ),
            )
          : AppSheetTransitions.showBottomSurface<_SourceChoice>(
              context,
              enableDrag: true,
              barrierLabel: AppLocalizations.of(context).flySourceMediaSources,
              barrierColor: colors.overlayScrim,
              builder: (_) => body,
            );
      final choice = await selection;
      if (mounted && choice != null) await _select(choice);
    } finally {
      menuOpen = false;
    }
  }

  Widget _options(
    BuildContext sheetContext,
    FlyAccountController account,
    String accountKey, {
    required bool floating,
  }) {
    final colors = sheetContext.appColors;
    final media = MediaQuery.of(sheetContext);
    final bindings = account.bindings
        .where((binding) => binding['status'] != 'unbound')
        .toList();
    final canSelect =
        account.accountKey == accountKey && !account.busy && !switching;
    return AppOptionSheetPanel(
      surfaceKey: const ValueKey('app-modal-surface-media-sources'),
      title: AppLocalizations.of(context).flySourceMediaSources,
      floating: floating,
      maxHeight: floating
          ? (media.size.height * .78).clamp(320.0, 560.0)
          : media.size.height * .7,
      child: ListView.separated(
        key: const ValueKey('media-source-options'),
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: bindings.length + _actions.length,
        separatorBuilder: (_, index) =>
            SizedBox(height: index == bindings.length - 1 ? 16 : 4),
        itemBuilder: (context, index) {
          final binding = index < bindings.length ? bindings[index] : null;
          final action = binding == null
              ? _actions[index - bindings.length]
              : null;
          final enabled =
              canSelect && (binding == null || binding['status'] == 'active');
          final choice = binding != null
              ? _SourceChoice(
                  accountKey,
                  _SourceAction.switchSource,
                  binding['id'] as String,
                )
              : _SourceChoice(accountKey, action!.$1);
          final tile = AppOptionListTile(
            tileKey: ValueKey(
              binding != null
                  ? 'media-source-${binding['id']}'
                  : 'media-source-action-${action!.$1.name}',
            ),
            title: binding != null
                ? binding['label'] as String? ??
                      AppLocalizations.of(context).flySourceMediaSources
                : action!.$3,
            subtitle: binding?['status'] == 'reauth_required'
                ? AppLocalizations.of(context).flySourceReauthorizationRequired
                : '',
            selected:
                binding != null && binding['id'] == account.activeBindingId,
            showIndicator: binding != null,
            outlined: binding == null,
            trailing: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: binding != null
                  ? _sourceIcon(
                      (binding['server'] as Map?)?['kind']?.toString(),
                      colors.textSecondary,
                    )
                  : Icon(action!.$2, size: 20, color: colors.textSecondary),
            ),
            onTap: () {
              if (!enabled) return;
              if (!AppSheetTransitions.maybeClose<_SourceChoice>(
                context,
                choice,
              )) {
                Navigator.of(context).pop(choice);
              }
            },
          );
          return Semantics(
            enabled: enabled,
            child: IgnorePointer(
              ignoring: !enabled,
              child: Opacity(opacity: enabled ? 1 : .45, child: tile),
            ),
          );
        },
      ),
    );
  }

  Future<void> _select(_SourceChoice choice) async {
    if (!mounted) return;
    final account = context.read<FlyAccountController>();
    // Option sheet routes can outlive the account that opened them.
    if (account.accountKey != choice.accountKey || account.busy || switching) {
      return;
    }
    if (choice.action == _SourceAction.switchSource) {
      if (account.activeBindingId == choice.bindingId) return;
      final matches = account.bindings.where(
        (b) => b['id'] == choice.bindingId,
      );
      if (matches.length != 1 || matches.single['status'] != 'active') return;
      setState(() => switching = true);
      try {
        await activateFlyBinding(context, account, matches.single);
      } finally {
        if (mounted) setState(() => switching = false);
      }
      return;
    }
    final page = switch (choice.action) {
      _SourceAction.account => const FlyBindingsScreen(),
      _SourceAction.catalog => const FlyCatalogScreen(),
      _SourceAction.stats => const PlayStatsReportScreen(),
      _SourceAction.switchSource => throw StateError('Handled above'),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    final colors = context.appColors;
    final active = account.activeBinding;
    final label = (active?['label'] as String?)?.trim();
    final enabled = !switching && !account.busy;
    final desktop = DesktopEnvironment.isDesktopPlatform;
    final trigger = Tooltip(
      message: AppLocalizations.of(context).flySourceSwitchTooltip,
      child: InkWell(
        onTap: enabled
            ? desktop
                  ? _toggleDesktopMenu
                  : () => unawaited(_openMenu())
            : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (switching || account.busy)
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accent,
                    ),
                  )
                else
                  _sourceIcon(
                    (active?['server'] as Map?)?['kind']?.toString(),
                    colors.accent,
                  ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label?.isNotEmpty == true
                        ? label!
                        : AppLocalizations.of(context).navMovies,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!desktop) return trigger;
    return DesktopHoverDropdown(
      key: _desktopMenu,
      activation: DesktopDropdownActivation.tap,
      spec: _desktopSpec(account),
      onOpenChanged: (open) {
        menuOpen = open;
        if (!open) _desktopOpenedAccountKey = null;
      },
      child: trigger,
    );
  }
}

Widget _sourceIcon(String? kind, Color fallbackColor) {
  final asset = switch (kind) {
    'feiniu' => 'lib/img/feiniu_Logo.png',
    'emby' => 'lib/img/Emby_logo.png',
    'jellyfin' => 'lib/img/jellyfin_logo.png',
    _ => null,
  };
  return asset == null
      ? Icon(Icons.video_library_outlined, size: 22, color: fallbackColor)
      : Image.asset(asset, width: 22, height: 22, fit: BoxFit.contain);
}
