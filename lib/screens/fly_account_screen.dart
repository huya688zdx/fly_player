import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../desktop/desktop_environment.dart';
import '../services/fly_data/fly_account_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common/app_ambient_page.dart';
import 'connection_screen.dart';
import 'fly_data_settings_screen.dart';

part 'fly_account_widgets.dart';

/// Shared by the home source selector and the account page.
/// Navigation belongs to the caller; failure or cancellation stays put.
Future<bool> activateFlyBinding(
  BuildContext context,
  FlyAccountController account,
  Map<String, dynamic> binding,
) async {
  if (account.busy) return false;
  try {
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
    String? selected;
    if (addresses.length == 1) {
      selected = addresses.single['base_url'] as String;
    } else if (addresses.length > 1) {
      selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择播放连接'),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text('选择当前网络可访问的地址。'),
            ),
            for (final address in addresses)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(context, address['base_url'] as String),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_addressIcon(address['purpose'])),
                  title: Text(_addressLabel(address['purpose'])),
                  subtitle: Text(address['base_url'] as String),
                ),
              ),
          ],
        ),
      );
      if (selected == null || !context.mounted) return false;
    }
    if (!context.mounted) return false;
    await account.activate(binding, address: selected);
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(FlyAccountController.safeMessage(error))),
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
    switch (action) {
      case 'address':
        await activateFlyBinding(context, account, binding);
      case 'reauthorize':
        await _bindingForm(context, account, binding: binding);
      case 'sync':
        await _run(() => account.syncCatalog(binding));
      case 'unbind':
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('移除媒体来源'),
            content: const Text('停止同步此来源并清除其媒体凭据，已有播放历史保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移除'),
              ),
            ],
          ),
        );
        if (yes == true) await _run(() => account.unbind(binding));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    if (account.session == null) return const FlyLoginScreen();
    final session = account.session!;
    final colors = context.appColors;
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
                    '飞翔账号 · App 与 NAS 共用',
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
        subtitle: '选择一个来源，回到熟悉的媒体库继续观看。',
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
          onAction: (action) =>
              _sourceAction(context, account, binding, action),
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
                      if (values != null) {
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
    String? serverId = binding?['server_id'] as String?;
    if (serverId == null) {
      if (account.servers.isEmpty) {
        await _run(account.refresh);
        if (!context.mounted) return;
      }
      serverId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择已登记服务器'),
          children: [
            if (account.servers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('没有可用服务器，请管理员先登记。'),
              ),
            for (final server in account.servers)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, server['id'] as String),
                child: Text(
                  '${server['name']} · ${_backendLabel(server['kind'])}',
                ),
              ),
          ],
        ),
      );
    }
    if (serverId == null || !context.mounted) return;
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
    if (values == null) return;
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
    final kind = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('媒体服务器类型'),
        children: [
          for (final kind in ['feiniu', 'emby', 'jellyfin'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, kind),
              child: Text(_backendLabel(kind)),
            ),
        ],
      ),
    );
    if (kind == null || !context.mounted) return;
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
    if (values != null) {
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
            value == null || value.trim().isEmpty ? '请填写$label' : null,
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
}) async {
  final controllers = {
    for (final key in fields.keys) key: TextEditingController(),
  };
  try {
    return await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 470,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in fields.entries)
                  _field(
                    controllers[entry.key]!,
                    entry.value,
                    secret: secretKeys.contains(entry.key),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controllers.entries.any(
                (e) =>
                    !optionalKeys.contains(e.key) &&
                    e.value.text.trim().isEmpty,
              )) {
                return;
              }
              Navigator.pop(context, {
                for (final e in controllers.entries) e.key: e.value.text,
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  } finally {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }
}
