import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fly_data/fly_account_controller.dart';

import '../services/fly_data/fly_data_service.dart';
import '../theme/app_theme.dart';
import '../ui/app_info_popover.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/common/app_ambient_page.dart';

class FlyDataSettingsScreen extends StatefulWidget {
  const FlyDataSettingsScreen({super.key});
  @override
  State<FlyDataSettingsScreen> createState() => _FlyDataSettingsScreenState();
}

class _FlyDataSettingsScreenState extends State<FlyDataSettingsScreen> {
  final _service = FlyDataService.instance;
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _device = TextEditingController(text: 'Fly Player');
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _ownership = false;
  String? _message;
  List<Map<String, dynamic>> _remote = [];
  List<Map<String, Object?>> _local = [];
  Map<String, Object?>? _syncState;
  String? _displayedScope;

  @override
  void initState() {
    super.initState();
    _run(() async {
      await _service.restoreSession();
      await _refreshLocal();
    });
  }

  @override
  void dispose() {
    for (final controller in [_url, _username, _password, _device]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshLocal() async {
    final session = _service.session;
    if (session == null) return;
    final scope = _service.scopeIdentity;
    _local = await _service.store.localDatasets();
    _syncState = await _service.store.state(session.accountKey);
    if (_service.scopeIdentity != scope) {
      _displayedScope = null;
      throw StateError('媒体帐号范围正在改变，请重新打开数据服务页面。');
    }
    _displayedScope = scope;
    if (!mounted) return;
    _url.text = session.serverUrl;
    _username.text = session.username;
    _device.text = session.deviceName;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      _message = error is StateError
          ? error.message.toString()
          : error is FormatException
          ? error.message
          : '操作未完成。请检查连接或安全凭据存储后重试；已有待重试快照保留。';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _login() async {
    if (_form.currentState?.validate() != true) return;
    await _run(() async {
      try {
        await _service.login(
          serverUrl: _url.text,
          username: _username.text,
          password: _password.text,
          deviceName: _device.text,
        );
      } finally {
        if (mounted) _password.clear();
      }
      await _refreshLocal();
      _message = '登录成功。请核对当前本地范围，再关联旧历史。';
    });
  }

  Future<void> _verifyDisplayedScope() async {
    if (_displayedScope != _service.scopeIdentity) {
      _ownership = false;
      await _refreshLocal();
      throw StateError('媒体帐号范围已改变，已刷新本地范围。请重新核对归属后操作。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _service.session;
    final pending = _syncState?['pending_json'] != null;
    final colors = context.appColors;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(context, title: const Text('飞翔数据服务')),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    color: AppAmbientPage.cardColorOf(context, colors.surface),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Text('飞翔统一账号的历史关联与同步。绑定账号下的新记录会自动补传。'),
                          ),
                          AppInfoPopoverAnchor(
                            title: '历史同步说明',
                            description:
                                '当前统计是旧版媒体播放量估计；精确观看时间未知。媒体播放进度继续由原媒体服务处理。',
                            detail: '旧本地历史需要核对归属后再关联；正常观看不需要在此重新登录媒体来源。',
                            child: Tooltip(
                              message: '历史同步说明',
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.info_outline_rounded,
                                  size: 20,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (session == null)
                    Form(
                      key: _form,
                      child: Column(
                        children: [
                          _field(
                            _url,
                            '服务地址',
                            hint: 'http://nas:8787',
                            keyboard: TextInputType.url,
                          ),
                          _field(_username, '数据服务帐号'),
                          _field(_password, '密码', secret: true),
                          _field(_device, '当前设备名称'),
                          FilledButton(
                            onPressed: _busy ? null : _login,
                            child: const Text('登录数据服务'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: Text(
                        '${session.username} · ${session.deviceName}',
                      ),
                      subtitle: Text(session.serverUrl),
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final account = context
                                    .read<FlyAccountController?>();
                                if (account == null) {
                                  await _service.logout();
                                } else {
                                  await account.logout();
                                }
                                _remote = [];
                                _local = [];
                                _syncState = null;
                                _ownership = false;
                              }),
                        child: const Text('退出'),
                      ),
                    ),
                    const Divider(),
                    const Text(
                      '当前本地统计范围',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _service.currentScope.isEmpty
                          ? '未登录媒体帐号时的本机历史'
                          : _service.currentScope,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_local.fold<int>(0, (sum, row) => sum + (row['record_count'] as int))} 条历史 · ${_local.length} 个来源',
                    ),
                    const Text('已绑定媒体账号的新记录自动继承归属。旧本地历史仍需明确关联或确认；已有记录保留原来源。'),
                    for (final dataset in _local)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(dataset['label'] as String),
                        subtitle: Text(
                          '${dataset['record_count']} 条 · ${dataset['confirmed_account'] == session.accountKey ? '已确认归属' : '待关联 / 确认'}',
                        ),
                      ),
                    const Divider(),
                    const Text(
                      '先关联已导入历史',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '如果曾通过网页导入播放历史，先读取并选择对应来源。只关联历史身份与原始记录匹配的内容；冲突会停止关联。各来源不会按标题合并。',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy || pending
                          ? null
                          : () => _run(() async {
                              _remote = await _service.remoteDatasets();
                              _message = _remote.isEmpty
                                  ? '帐号中没有可关联的数据集。'
                                  : '选择原先导入的对应来源进行关联。';
                            }),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('读取服务端数据集'),
                    ),
                    for (final dataset in _remote)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(dataset['label'] as String),
                        subtitle: Text(
                          '${dataset['origin_kind']} · ${dataset['status']}',
                        ),
                        trailing: TextButton(
                          onPressed:
                              _busy || pending || dataset['status'] != 'active'
                              ? null
                              : () => _run(() async {
                                  await _verifyDisplayedScope();
                                  final count = await _service.adopt(dataset);
                                  await _refreshLocal();
                                  _message = '已关联 $count 条历史，保留原数据集身份。';
                                }),
                          child: const Text('关联匹配历史'),
                        ),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _ownership,
                      onChanged: _busy || pending
                          ? null
                          : (value) =>
                                setState(() => _ownership = value ?? false),
                      title: const Text('我确认当前本地历史属于此数据帐号，且剩余未关联历史未曾导入。'),
                      subtitle: const Text(
                        '确认时还会检查服务端历史身份；检测到已有记录时必须先关联。旧版文件命名可能使不同媒体帐号共用文件；本次确认会锁定当前范围，但不能自动分离过去混入的历史，请先核对。',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !_ownership || pending
                          ? null
                          : () => _run(() async {
                              await _verifyDisplayedScope();
                              await _service.confirmCurrentScope();
                              await _refreshLocal();
                              _message = '当前范围已确认，可以手动同步。';
                            }),
                      child: const Text('核对并确认剩余来源'),
                    ),
                    const Divider(height: 32),
                    Text(
                      pending
                          ? '有待重试快照。重试发送完全相同的内容；之后再同步新变化。'
                          : _syncState?['last_success_ms'] == null
                          ? '尚无成功同步。'
                          : '最近成功：${DateTime.fromMillisecondsSinceEpoch(_syncState!['last_success_ms'] as int).toLocal()}',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await _verifyDisplayedScope();
                              try {
                                final receipt = await _service.syncNow();
                                _message =
                                    '服务端已应用快照 #${receipt['snapshot_seq']}。';
                              } finally {
                                await _refreshLocal();
                              }
                            }),
                      icon: const Icon(Icons.sync),
                      label: Text(pending ? '手动重试原快照' : '立即同步'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '恢复统计数据库会保留原历史来源，新记录使用新的写入来源。完整应用备份与跨设备安全凭据恢复仍需平台验证。服务器删除的历史不会因旧备份重试而恢复。',
                    ),
                  ],
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: SelectableText(_message!),
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

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool secret = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: context.appColors.surfaceSubtle,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.appColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.appColors.accent),
        ),
      ),
      validator: (value) =>
          value == null || value.trim().isEmpty ? '请填写$label' : null,
    ),
  );
}
