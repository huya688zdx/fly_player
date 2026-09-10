import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../danmaku/settings/danmaku_settings_store.dart';
import '../desktop/playback/external_player_settings.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/common/app_ambient_page.dart';
import 'settings_destination_routes.dart';

class ExternalPlayerSettingsScreen extends StatefulWidget {
  const ExternalPlayerSettingsScreen({super.key});

  @override
  State<ExternalPlayerSettingsScreen> createState() =>
      _ExternalPlayerSettingsScreenState();
}

class _ExternalPlayerSettingsScreenState
    extends State<ExternalPlayerSettingsScreen> {
  final _pathController = TextEditingController();
  final _danmakuSettingsStore = const DanmakuSettingsStore();
  bool _enabled = false;
  bool? _danmakuEnabled;
  bool _busy = true;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await ExternalPlayerSettings.load();
      if (!mounted) return;
      _pathController.text = settings.executablePath;
      setState(() => _enabled = settings.enabled);
      await _loadDanmakuSettings();
    } catch (_) {
      _showMessage('读取外部播放器设置失败，请重新打开此页面。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDanmakuSettings() async {
    try {
      final settings = await _danmakuSettingsStore.load();
      if (!mounted) return;
      setState(() => _danmakuEnabled = settings.enabled);
    } catch (_) {
      _showMessage('读取弹幕设置失败，请重新打开此页面。', error: true);
    }
  }

  Future<void> _openDanmakuSettings() async {
    await Navigator.of(context).pushNamed(SettingsDestinationRoutes.danmaku);
    if (!mounted) return;
    await _loadDanmakuSettings();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = error;
    });
  }

  Future<void> _save({bool? enabled}) async {
    final nextEnabled = enabled ?? _enabled;
    final executablePath = _pathController.text.trim();
    setState(() => _busy = true);
    try {
      // 关闭始终可用，避免程序被移动后无法退出外部播放模式。
      if (enabled != false && (nextEnabled || executablePath.isNotEmpty)) {
        final error = await ExternalPlayerSettings.validateExecutable(
          executablePath,
        );
        if (!mounted) return;
        if (error != null) {
          _showMessage(error, error: true);
          return;
        }
      }
      await ExternalPlayerSettings(
        enabled: nextEnabled,
        executablePath: executablePath,
      ).save();
      if (!mounted) return;
      setState(() => _enabled = nextEnabled);
      _showMessage(nextEnabled ? '已启用 PotPlayer，下一次播放时生效。' : '设置已保存。');
    } catch (error) {
      _showMessage(
        error is StateError ? error.message.toString() : '保存失败，请重试。',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectExecutable() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 PotPlayer 程序',
        type: FileType.custom,
        allowedExtensions: const <String>['exe'],
      );
      if (!mounted) return;
      final selected = result?.files.single.path;
      if (selected == null) return;
      _pathController.text = selected;
      await _save();
    } catch (_) {
      _showMessage('无法选择程序，请手动填写 PotPlayer 路径。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detectExecutable() async {
    setState(() => _busy = true);
    try {
      final detected = await ExternalPlayerSettings.detectExecutable();
      if (!mounted) return;
      if (detected == null) {
        _showMessage('未找到 PotPlayer，请选择程序或填写安装路径。', error: true);
        return;
      }
      _pathController.text = detected;
      await _save();
    } catch (_) {
      _showMessage('自动查找失败，请手动选择 PotPlayer 程序。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppAmbientPage.controlColorsOf(context);
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(context, title: const Text('外部播放器接入')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              Card(
                color: AppAmbientPage.cardColorOf(context, colors.surface),
                child: SwitchListTile(
                  title: Text(
                    '使用 PotPlayer 播放',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  subtitle: Text(
                    '启用后，在此电脑上通过 PotPlayer 打开视频。',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  value: _enabled,
                  activeThumbColor: colors.accent,
                  onChanged: _busy ? null : (value) => _save(enabled: value),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: AppAmbientPage.cardColorOf(context, colors.surface),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: _pathController,
                        enabled: !_busy,
                        style: TextStyle(color: colors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'PotPlayer 程序路径',
                          hintText:
                              r'C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _selectExecutable,
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('选择程序'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _detectExecutable,
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('自动查找'),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : () => _save(),
                            child: const Text('保存路径'),
                          ),
                        ],
                      ),
                      if (_message != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: _isError ? colors.danger : colors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: AppAmbientPage.cardColorOf(context, colors.surface),
                child: ListTile(
                  title: Text(
                    '弹幕设置',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  subtitle: Text(switch (_danmakuEnabled) {
                    true => '当前已开启，匹配到弹幕源后会带入 PotPlayer。',
                    false => '当前已关闭，开启后才能在 PotPlayer 显示弹幕。',
                    null => '暂未读取到弹幕状态。',
                  }, style: TextStyle(color: colors.textSecondary)),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                  onTap: _busy ? null : _openDanmakuSettings,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '播放时请保持 Fly Player 运行，用于向 NAS 回报播放进度。\n\n'
                '当前支持 PotPlayer。播放时可在影片详情页暂停、跳转、搜索或更换弹幕源，并应用所选片源与外挂字幕。弹幕随视频同步暂停和跳转。\n\n'
                '飞牛原画剧集会带入各季播放列表；在列表内切集会同步对应字幕、弹幕和播放进度，切换到列表外视频会结束跟踪。\n\n'
                '外挂 ASS 字幕保留样式；SRT、VTT 保留文字和时间。与弹幕合并时，字幕需为 UTF-8 或 UTF-16 编码。\n\n'
                '音轨和内封字幕请在 PotPlayer 的声音、字幕菜单中选择。内封字幕、位图字幕不能与弹幕合并，AI 人物遮挡不支持。',
                style: TextStyle(color: colors.textSecondary, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
