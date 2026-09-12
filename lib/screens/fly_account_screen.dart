import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../desktop/desktop_environment.dart';
import '../desktop/desktop_context_menu.dart';
import '../desktop/desktop_floating_panel.dart';
import '../desktop/desktop_hover_dropdown.dart';
import '../services/fly_data/fly_account_controller.dart';
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
    message: '账号或媒体来源已改变，请重新打开设置。',
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
        message: '暂无可手动选择的播放地址，请刷新媒体来源后重试。',
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
      title: '连接设置',
      selectedId: selectedId,
      items: [
        for (final address in addresses)
          TrackOptionSheetItem(
            id: address['base_url'] as String,
            title: _addressLabel(address['purpose']),
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

  @override
  void dispose() {
    for (final c in [url, username, password, device]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _login(FlyAccountController account) async {
    if (account.busy || _form.currentState?.validate() != true) return;
    try {
      await account.login(
        url: url.text,
        username: username.text,
        password: password.text,
        deviceName: device.text,
      );
    } catch (_) {
      // The controller publishes the error below the form.
    } finally {
      if (mounted) password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    return _FlyLoginPage(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              url,
              '飞翔服务地址',
              hint: 'HTTPS、VPN 或局域网地址',
              enabled: !account.busy,
              keyboard: TextInputType.url,
            ),
            _field(username, '飞翔账号', enabled: !account.busy),
            _field(
              password,
              '密码',
              secret: true,
              enabled: !account.busy,
              onSubmitted: (_) => _login(account),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                '设备名称 · ${device.text}',
                style: const TextStyle(fontSize: 13),
              ),
              children: [_field(device, '当前设备名称', enabled: !account.busy)],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: account.busy ? null : () => _login(account),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('登录飞翔'),
            ),
            if (account.busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (account.message != null) _FlyMessage(account.message!),
            const SizedBox(height: 16),
            TextButton(
              onPressed: account.busy
                  ? null
                  : () => account.enterLegacyMode().catchError((Object _) {}),
              child: const Text('暂用原本地媒体连接'),
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
          title: '移除媒体来源',
          content: '停止同步此来源并清除其媒体凭据，已有播放历史保留。',
          cancelText: '取消',
          confirmText: '移除',
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
    return _page('账号与媒体来源', [
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
                    '飞翔账号 · 与管理后台共用',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: account.busy ? null : () => _run(account.logout),
              child: const Text('退出账号'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      _FlySectionTitle(
        title: '我的媒体来源',
        subtitle: '已同步绑定，选择来源即可连接。',
        action: IconButton(
          tooltip: '刷新媒体来源',
          onPressed: account.busy ? null : () => _run(account.refresh),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
      const SizedBox(height: 12),
      if (account.bindings.isEmpty)
        const _FlySurface(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(Icons.video_library_outlined, size: 36),
                SizedBox(height: 12),
                Text('添加第一个媒体来源'),
                SizedBox(height: 6),
                Text(
                  '绑定飞牛、Emby 或 Jellyfin 账号后即可进入媒体库。',
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
        child: OutlinedButton.icon(
          onPressed: account.busy ? null : () => _bindingForm(context, account),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加媒体来源'),
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
          title: const Text('管理与连接设置'),
          subtitle: const Text('服务地址、历史同步和本地连接'),
          children: [
            if (session.role == 'admin')
              _managementRow(
                icon: Icons.dns_outlined,
                title: '登记媒体服务器',
                subtitle: '为账号添加可绑定的飞牛、Emby 或 Jellyfin 服务',
                onTap: account.busy
                    ? null
                    : () => _serverForm(context, account),
              ),
            _managementRow(
              icon: Icons.public_rounded,
              title: '飞翔服务地址',
              subtitle: '当前入口：${session.serverUrl}',
              onTap: account.busy
                  ? null
                  : () async {
                      final values = await flyForm(context, '添加飞翔服务地址', {
                        'url': 'HTTPS / VPN / 局域网根地址',
                      });
                      if (values != null && context.mounted) {
                        if (account.accountKey != accountKey) {
                          _showChangedAccount(context);
                          return;
                        }
                        await _run(() => account.switchAddress(values['url']!));
                      }
                    },
            ),
            for (final address in session.addresses)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 16),
                title: Text(address, style: const TextStyle(fontSize: 12)),
                trailing: address == session.serverUrl
                    ? const Icon(Icons.check_rounded, size: 18)
                    : TextButton(
                        onPressed: account.busy
                            ? null
                            : () => _run(() => account.switchAddress(address)),
                        child: const Text('使用此地址'),
                      ),
              ),
            _managementRow(
              icon: Icons.cloud_sync_outlined,
              title: '历史关联与统计同步',
              subtitle: '新记录自动补传；在这里查看同步状态或关联旧历史',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FlyDataSettingsScreen(),
                ),
              ),
            ),
            _managementRow(
              icon: Icons.lan_outlined,
              title: '本地媒体直连',
              subtitle: '使用原来的本机连接配置',
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
      const SizedBox(height: 14),
      Text(
        '播放直接连接媒体服务，离线时观看记录先保存在本机。',
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
    ]);
  }

  Future<void> _bindingForm(
    BuildContext context,
    FlyAccountController account, {
    Map<String, dynamic>? binding,
  }) async {
    final accountKey = account.accountKey;
    final bindingId = binding?['id'], revision = binding?['revision'];
    bool current() =>
        account.accountKey == accountKey &&
        (binding == null ||
            _bindingStillCurrent(account, accountKey, bindingId, revision));
    String? serverId = binding?['server_id'] as String?;
    if (serverId == null) {
      if (account.servers.isEmpty) {
        await _run(account.refresh);
        if (!context.mounted) return;
      }
      if (account.servers.isEmpty) {
        AppTopTip().show(
          context,
          message: '没有可用服务器，请管理员先登记。',
          color: context.appColors.surfaceStrong,
        );
        return;
      }
      serverId = await _showFlyOptions(
        context,
        title: '选择已登记服务器',
        items: [
          for (final server in account.servers)
            TrackOptionSheetItem(
              id: server['id'] as String,
              title: server['name'] as String? ?? '媒体服务器',
              subtitle: _backendLabel(server['kind']),
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
      binding == null ? '绑定媒体账号' : '重新授权',
      {
        if (binding == null) 'label': '绑定名称',
        'username': '媒体账号',
        'password': '媒体密码',
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
            title: '媒体服务器类型',
            items: [
              for (final kind in kinds)
                TrackOptionSheetItem(id: kind, title: _backendLabel(kind)),
            ],
          )
        : showAppActionSheet<String>(
            context,
            title: '媒体服务器类型',
            options: [
              for (final kind in kinds)
                AppActionSheetOption(value: kind, label: _backendLabel(kind)),
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
      '登记服务器',
      {
        'name': '服务器名称',
        'nas_api': 'NAS 访问地址（必填）',
        'client_lan': 'App 局域网地址（选填）',
        'client_remote': 'App HTTPS 地址（选填）',
        'vpn': 'App VPN 地址（选填）',
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
  required String subtitle,
  required VoidCallback? onTap,
}) => ListTile(
  contentPadding: EdgeInsets.zero,
  leading: Icon(icon, size: 22),
  title: Text(
    title,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ),
  subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
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
            ? '请填写$label'
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
                tooltip: '关闭',
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
                  child: const Text('取消'),
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
                  child: const Text('确定'),
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
