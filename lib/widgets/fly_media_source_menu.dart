import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/fly_account_screen.dart';
import '../screens/fly_catalog_screen.dart';
import '../screens/play_stats_report_screen.dart';
import '../services/fly_data/fly_account_controller.dart';
import '../theme/app_theme.dart';

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
  bool switching = false;

  Future<void> _select(_SourceChoice choice) async {
    final account = context.read<FlyAccountController>();
    // Popup routes can outlive the account that opened them.
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
    final accountKey = account.accountKey;
    return PopupMenuButton<_SourceChoice>(
      tooltip: '切换媒体来源',
      enabled: !switching && !account.busy,
      position: PopupMenuPosition.under,
      color: context.appModalBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 300),
      onSelected: (choice) => unawaited(_select(choice)),
      itemBuilder: (_) => [
        const PopupMenuItem<_SourceChoice>(
          enabled: false,
          height: 32,
          child: Text('媒体来源', style: TextStyle(fontSize: 12)),
        ),
        for (final binding in account.bindings.where(
          (b) => b['status'] != 'unbound',
        ))
          PopupMenuItem<_SourceChoice>(
            value: _SourceChoice(
              accountKey,
              _SourceAction.switchSource,
              binding['id'] as String,
            ),
            enabled: binding['status'] == 'active',
            child: Row(
              children: [
                _sourceIcon(
                  (binding['server'] as Map?)?['kind']?.toString(),
                  colors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    binding['label'] as String? ?? '媒体来源',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (binding['id'] == account.activeBindingId) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check_rounded, size: 18, color: colors.accent),
                ],
              ],
            ),
          ),
        const PopupMenuDivider(),
        for (final entry in [
          (_SourceAction.account, Icons.account_circle_outlined, '账号与媒体来源'),
          (_SourceAction.catalog, Icons.video_library_outlined, '已同步节目'),
          (_SourceAction.stats, Icons.bar_chart_rounded, '观看统计'),
        ])
          PopupMenuItem<_SourceChoice>(
            value: _SourceChoice(accountKey, entry.$1),
            child: Row(
              children: [
                Icon(entry.$2, size: 20, color: colors.textSecondary),
                const SizedBox(width: 12),
                Expanded(child: Text(entry.$3)),
              ],
            ),
          ),
      ],
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
                  label?.isNotEmpty == true ? label! : '影视',
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
