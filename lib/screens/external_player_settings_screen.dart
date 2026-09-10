import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../desktop/playback/external_player_settings.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/common/app_ambient_page.dart';

class ExternalPlayerSettingsScreen extends StatefulWidget {
  const ExternalPlayerSettingsScreen({super.key});

  @override
  State<ExternalPlayerSettingsScreen> createState() =>
      _ExternalPlayerSettingsScreenState();
}

class _ExternalPlayerSettingsScreenState
    extends State<ExternalPlayerSettingsScreen> {
  final _pathController = TextEditingController();
  bool _enabled = false;
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
    } catch (_) {
      _showMessage('读取外部播放器设置失败，请重新打开此页面。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              const SizedBox(height: 16),
              Text(
                '播放时请保持 Fly Player 运行，用于向 NAS 回报播放进度。\n\n'
                '当前支持 PotPlayer。弹幕随视频同步暂停和跳转，修改弹幕设置后需重新打开播放。\n\n'
                '外挂 ASS 字幕保留样式；SRT、VTT 保留文字和时间。与弹幕合并时，字幕需为 UTF-8 或 UTF-16 编码。\n\n'
                '音轨由 PotPlayer 选择。内封字幕、位图字幕不能与弹幕合并，AI 人物遮挡不支持。\n\n'
                '在 PotPlayer 内换片会停止原影片的进度回报，请从 Fly Player 选择下一集。',
                style: TextStyle(color: colors.textSecondary, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
