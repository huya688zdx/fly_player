import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../danmaku/settings/danmaku_settings_store.dart';
import '../desktop/desktop_environment.dart';
import '../desktop/playback/external_player_adapter.dart';
import '../desktop/playback/external_player_adapters.dart';
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
  ExternalPlayerAdapter _player = ExternalPlayerAdapters.defaultPlayer;
  bool _enabled = false;
  bool _playerChanged = false;
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
      setState(() {
        _player = settings.adapter;
        _enabled = settings.enabled;
      });
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
        final error = await _player.validateExecutable(executablePath);
        if (!mounted) return;
        if (error != null) {
          _showMessage(error, error: true);
          return;
        }
      }
      await ExternalPlayerSettings(
        enabled: nextEnabled,
        executablePath: executablePath,
        playerId: _player.id,
      ).save();
      if (!mounted) return;
      setState(() {
        _enabled = nextEnabled;
        _playerChanged = false;
      });
      _showMessage(
        nextEnabled ? '已启用 ${_player.displayName}，下一次播放时生效。' : '设置已保存。',
      );
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
        dialogTitle: '选择 ${_player.displayName} 程序',
        type: FileType.custom,
        allowedExtensions: _player.fileExtensions,
      );
      if (!mounted) return;
      final selected = result?.files.single.path;
      if (selected == null) return;
      _pathController.text = selected;
      await _save();
    } catch (_) {
      _showMessage('无法选择程序，请手动填写 ${_player.displayName} 路径。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detectExecutable() async {
    setState(() => _busy = true);
    try {
      final detected = await _player.detectExecutable();
      if (!mounted) return;
      if (detected == null) {
        _showMessage('未找到 ${_player.displayName}，请选择程序或填写安装路径。', error: true);
        return;
      }
      _pathController.text = detected;
      await _save();
    } catch (_) {
      _showMessage('自动查找失败，请手动选择 ${_player.displayName} 程序。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final desktop = DesktopEnvironment.isDesktopPlatform;
    final controlTheme = AppThemeBuilder.buildFromColors(
      colors,
      baseTheme: Theme.of(context),
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final secondaryButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: colors.textSecondary,
      backgroundColor: colors.surface.withValues(alpha: 0.24),
      side: BorderSide(color: colors.borderSubtle),
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      shape: buttonShape,
    );
    final page = Theme(
      data: controlTheme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(context, title: const Text('外部播放器接入')),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: desktop ? 720 : 820),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  desktop ? 18 : 20,
                  desktop ? 12 : 16,
                  desktop ? 18 : 20,
                  desktop ? 24 : 32,
                ),
                children: <Widget>[
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.open_in_new_rounded,
                          color: colors.accentStrong,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_player.displayName} 接入',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '由 Fly Player 管理片源、弹幕与播放进度',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _enabled
                              ? colors.accentSoft
                              : colors.surface.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _enabled ? '已启用' : '未启用',
                          style: TextStyle(
                            color: _enabled
                                ? colors.accentStrong
                                : colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.36),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (ExternalPlayerAdapters.available.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child:
                                DropdownButtonFormField<ExternalPlayerAdapter>(
                                  key: ValueKey(_player.id),
                                  initialValue: _player,
                                  items: [
                                    for (final player
                                        in ExternalPlayerAdapters.available)
                                      DropdownMenuItem(
                                        value: player,
                                        child: Text(player.displayName),
                                      ),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (player) {
                                          if (player == null ||
                                              identical(player, _player)) {
                                            return;
                                          }
                                          setState(() {
                                            _player = player;
                                            _pathController.clear();
                                            _enabled = false;
                                            _playerChanged = true;
                                          });
                                        },
                                  decoration: const InputDecoration(
                                    labelText: '播放器',
                                  ),
                                ),
                          ),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          title: Text(
                            '使用 ${_player.displayName} 播放',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '启用后，此电脑上的视频将交给 ${_player.displayName}。',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                          value: _enabled,
                          activeThumbColor: colors.accentStrong,
                          activeTrackColor: colors.accentSoft,
                          inactiveThumbColor: colors.textMuted,
                          inactiveTrackColor: colors.textMuted.withValues(
                            alpha: 0.12,
                          ),
                          trackOutlineColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          onChanged: _busy || _playerChanged
                              ? null
                              : (value) => _save(enabled: value),
                        ),
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: colors.borderSubtle,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '程序路径',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _pathController,
                                enabled: !_busy,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13,
                                ),
                                cursorColor: colors.accent,
                                decoration: InputDecoration(
                                  hintText: _player.executableHint,
                                  prefixIcon: Icon(
                                    Icons.folder_open_rounded,
                                    color: colors.textMuted,
                                    size: 18,
                                  ),
                                  isDense: true,
                                  filled: true,
                                  fillColor: colors.backgroundBase.withValues(
                                    alpha: 0.32,
                                  ),
                                  hintStyle: TextStyle(
                                    color: colors.textMuted,
                                    fontSize: 12,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: colors.borderSubtle,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: colors.accent,
                                      width: 1.5,
                                    ),
                                  ),
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
                                    style: secondaryButtonStyle,
                                    icon: const Icon(
                                      Icons.folder_open_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('选择'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _detectExecutable,
                                    style: secondaryButtonStyle,
                                    icon: const Icon(
                                      Icons.search_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('自动查找'),
                                  ),
                                  FilledButton(
                                    onPressed: _busy ? null : () => _save(),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colors.accent,
                                      foregroundColor:
                                          controlTheme.colorScheme.onPrimary,
                                      minimumSize: const Size(72, 38),
                                      textStyle: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      shape: buttonShape,
                                    ),
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
                  const SizedBox(height: 22),
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
                      color: colors.surface.withValues(alpha: 0.36),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Icon(
                            Icons.subtitles_rounded,
                            color: colors.accentStrong,
                            size: 21,
                          ),
                          title: Text(
                            _player.supportsSubtitles ? '弹幕设置' : '弹幕设置不可用',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            _player.supportsSubtitles
                                ? switch (_danmakuEnabled) {
                                    true => '已开启，匹配后会带入 ${_player.displayName}',
                                    false => '已关闭，开启后才会显示弹幕',
                                    null => '暂未读取到弹幕状态',
                                  }
                                : '${_player.displayName} 不支持由 Fly Player 注入弹幕',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: colors.textMuted,
                            size: 18,
                          ),
                          onTap: _busy || !_player.supportsSubtitles
                              ? null
                              : _openDanmakuSettings,
                        ),
                        Divider(
                          height: 1,
                          indent: 52,
                          endIndent: 16,
                          color: colors.borderSubtle,
                        ),
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
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        iconColor: colors.accent,
                        collapsedIconColor: colors.textSecondary,
                        leading: Icon(
                          Icons.help_outline_rounded,
                          color: colors.textSecondary,
                          size: 21,
                        ),
                        title: Text(
                          '使用说明',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
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
                            _player.usageNotes,
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
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: AppAmbientPage(child: page),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            enabled:
                available && status != null && status.player.supportsMiniPlayer,
            leading: Icon(
              active ? Icons.picture_in_picture_alt : Icons.push_pin_outlined,
              color:
                  available &&
                      status != null &&
                      status.player.supportsMiniPlayer
                  ? colors.accentStrong
                  : colors.textMuted,
              size: 21,
            ),
            title: Text(
              active ? '极简模式已开启' : '打开极简模式',
              style: TextStyle(
                color:
                    available &&
                        status != null &&
                        status.player.supportsMiniPlayer
                    ? colors.textPrimary
                    : colors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              status == null
                  ? '开始外部播放后可用'
                  : available
                  ? status.player.supportsMiniPlayer
                        ? '顶部居中显示，可拖动并保持置顶'
                        : '${status.player.displayName} 不支持极简模式'
                  : '当前窗口暂不可用',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            trailing: Icon(
              Icons.north_east_rounded,
              size: 18,
              color: colors.textSecondary,
            ),
            onTap:
                available && status != null && status.player.supportsMiniPlayer
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
