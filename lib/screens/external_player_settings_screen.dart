import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../danmaku/settings/danmaku_settings_store.dart';
import '../desktop/playback/external_player_settings.dart';
import '../desktop/playback/external_playback_host.dart';
import '../desktop/playback/external_playback_mini_controller.dart';
import '../theme/app_theme.dart';
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
    final colors = context.appColors;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(context, title: const Text('外部播放器接入')),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: <Widget>[
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.open_in_new_rounded,
                          color: colors.accent,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PotPlayer 接入',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '由 Fly Player 管理片源、弹幕与播放进度',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (_enabled ? colors.success : colors.textMuted)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _enabled ? '已启用' : '未启用',
                          style: TextStyle(
                            color: _enabled ? colors.success : colors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: AppAmbientPage.cardColorOf(
                        context,
                        colors.surface,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 2,
                          ),
                          title: Text(
                            '使用 PotPlayer 播放',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '启用后，此电脑上的视频将交给 PotPlayer。',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                          value: _enabled,
                          activeThumbColor: colors.accent,
                          onChanged: _busy
                              ? null
                              : (value) => _save(enabled: value),
                        ),
                        Divider(height: 1, color: colors.borderSubtle),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '程序路径',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _pathController,
                                enabled: !_busy,
                                style: TextStyle(color: colors.textPrimary),
                                decoration: const InputDecoration(
                                  hintText:
                                      r'C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe',
                                  prefixIcon: Icon(Icons.route_rounded),
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _save(),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _selectExecutable,
                                    icon: const Icon(
                                      Icons.folder_open_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('选择'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _detectExecutable,
                                    icon: const Icon(
                                      Icons.search_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('自动查找'),
                                  ),
                                  FilledButton(
                                    onPressed: _busy ? null : () => _save(),
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                              if (_message != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      _isError
                                          ? Icons.error_outline_rounded
                                          : Icons.check_circle_outline_rounded,
                                      size: 17,
                                      color: _isError
                                          ? colors.danger
                                          : colors.success,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        _message!,
                                        style: TextStyle(
                                          color: _isError
                                              ? colors.danger
                                              : colors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 7),
                    child: Text(
                      '常用操作',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppAmbientPage.cardColorOf(
                        context,
                        colors.surface,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.subtitles_rounded,
                            color: colors.accent,
                          ),
                          title: Text(
                            '弹幕设置',
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          subtitle: Text(switch (_danmakuEnabled) {
                            true => '已开启，匹配后会带入 PotPlayer',
                            false => '已关闭，开启后才会显示弹幕',
                            null => '暂未读取到弹幕状态',
                          }, style: TextStyle(color: colors.textSecondary)),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: colors.textSecondary,
                          ),
                          onTap: _busy ? null : _openDanmakuSettings,
                        ),
                        Divider(height: 1, color: colors.borderSubtle),
                        _buildMiniModeTile(colors),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppAmbientPage.cardColorOf(
                          context,
                          colors.surface,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ExpansionTile(
                        leading: Icon(
                          Icons.help_outline_rounded,
                          color: colors.textSecondary,
                        ),
                        title: Text(
                          '使用说明',
                          style: TextStyle(color: colors.textPrimary),
                        ),
                        subtitle: Text(
                          '进度同步、播放列表与字幕限制',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          Text(
                            '播放时请保持 Fly Player 运行，用于向 NAS 回报进度。影片详情页和外部播放控制页可暂停、跳转、更换片源、搜索弹幕和选择外挂字幕。\n\n'
                            '飞牛原画剧集会带入各季播放列表；切集时会同步对应字幕、弹幕和进度。连续播放由 PotPlayer 的播放列表设置控制。\n\n'
                            '弹幕与外挂 ASS、SRT、VTT 会合成为临时 ASS。音轨、内封字幕和位图字幕请在 PotPlayer 菜单中切换；AI 人物遮挡暂不支持。',
                            style: TextStyle(
                              color: colors.textSecondary,
                              height: 1.55,
                              fontSize: 12,
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

  Widget _buildMiniModeTile(AppThemeColors colors) {
    return ValueListenableBuilder<ExternalPlaybackStatus?>(
      valueListenable: ExternalPlaybackHost.status,
      builder: (context, status, _) => ValueListenableBuilder<bool>(
        valueListenable: ExternalPlaybackMiniController.available,
        builder: (context, available, _) => ValueListenableBuilder<bool>(
          valueListenable: ExternalPlaybackMiniController.active,
          builder: (context, active, _) => ListTile(
            dense: true,
            enabled: available && status != null,
            leading: Icon(
              active ? Icons.picture_in_picture_alt : Icons.push_pin_outlined,
              color: available && status != null
                  ? colors.accent
                  : colors.textMuted,
            ),
            title: Text(
              active ? '极简模式已开启' : '打开极简模式',
              style: TextStyle(color: colors.textPrimary),
            ),
            subtitle: Text(
              status == null
                  ? '开始外部播放后可用'
                  : available
                  ? '顶部居中显示，可拖动并保持置顶'
                  : '当前窗口暂不可用',
              style: TextStyle(color: colors.textSecondary),
            ),
            trailing: Icon(
              Icons.north_east_rounded,
              size: 18,
              color: colors.textSecondary,
            ),
            onTap: available && status != null
                ? () async {
                    try {
                      await ExternalPlaybackMiniController.enter();
                    } catch (_) {
                      _showMessage('无法打开极简模式，请重试', error: true);
                    }
                  }
                : null,
          ),
        ),
      ),
    );
  }
}
