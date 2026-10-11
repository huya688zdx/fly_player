import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../danmaku/settings/danmaku_settings_store.dart';
import '../desktop/desktop_environment.dart';
import '../desktop/playback/external_player_adapter.dart';
import '../desktop/playback/external_player_adapters.dart';
import '../desktop/playback/external_player_settings.dart';
import '../desktop/playback/external_playback_host.dart';
import '../desktop/playback/external_playback_mini_controller.dart';
import '../l10n/generated/app_localizations.dart';
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
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).externalPlayerSettingsLoadFailed,
          error: true,
        );
      }
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
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).externalPlayerSettingsDanmakuLoadFailed,
          error: true,
        );
      }
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
    final l10n = AppLocalizations.of(context);
    final nextEnabled = enabled ?? _enabled;
    final executablePath = _pathController.text.trim();
    setState(() => _busy = true);
    try {
      // 关闭始终可用，避免程序被移动后无法退出外部播放模式。
      if (enabled != false && (nextEnabled || executablePath.isNotEmpty)) {
        final error = await _player.validateExecutable(
          executablePath,
          l10n: l10n,
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
        playerId: _player.id,
      ).save(l10n: l10n);
      if (!mounted) return;
      setState(() {
        _enabled = nextEnabled;
        _playerChanged = false;
      });
      _showMessage(
        nextEnabled
            ? l10n.externalPlayerSettingsEnabledToast(_player.displayName)
            : l10n.externalPlayerSettingsSavedToast,
      );
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : l10n.externalPlayerSettingsSaveFailed,
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectExecutable() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: l10n.externalPlayerSettingsPickDialogTitle(
          _player.displayName,
        ),
        type: FileType.custom,
        allowedExtensions: _player.fileExtensions,
      );
      if (!mounted) return;
      final selected = result?.files.single.path;
      if (selected == null) return;
      _pathController.text = selected;
      await _save();
    } catch (_) {
      _showMessage(
        l10n.externalPlayerSettingsPickFailed(_player.displayName),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detectExecutable() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final detected = await _player.detectExecutable(l10n: l10n);
      if (!mounted) return;
      if (detected == null) {
        _showMessage(
          l10n.externalPlayerSettingsDetectNotFound(_player.displayName),
          error: true,
        );
        return;
      }
      _pathController.text = detected;
      await _save();
    } catch (_) {
      _showMessage(
        l10n.externalPlayerSettingsDetectFailed(_player.displayName),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final l10n = AppLocalizations.of(context);
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
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(l10n.externalPlayerSettingsTitle),
        ),
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
                              l10n.externalPlayerSettingsPlayerTitle(
                                _player.displayName,
                              ),
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.externalPlayerSettingsSubtitle,
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
                          _enabled
                              ? l10n.externalPlayerSettingsEnabledBadge
                              : l10n.externalPlayerSettingsDisabledBadge,
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
                                  decoration: InputDecoration(
                                    labelText: l10n
                                        .externalPlayerSettingsPlayerFieldLabel,
                                  ),
                                ),
                          ),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          title: Text(
                            l10n.externalPlayerSettingsUseToggleTitle(
                              _player.displayName,
                            ),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            l10n.externalPlayerSettingsUseToggleSubtitle(
                              _player.displayName,
                            ),
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
                                l10n.externalPlayerSettingsPathLabel,
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
                                    label: Text(
                                      l10n.externalPlayerSettingsPickButton,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _detectExecutable,
                                    style: secondaryButtonStyle,
                                    icon: const Icon(
                                      Icons.search_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      l10n.externalPlayerSettingsDetectButton,
                                    ),
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
                                    child: Text(l10n.commonSave),
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
                      l10n.externalPlayerSettingsCommonActions,
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
                            _player.supportsSubtitles
                                ? l10n.danmakuSettingsTitle
                                : l10n.externalPlayerSettingsDanmakuUnavailable,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            _player.supportsSubtitles
                                ? switch (_danmakuEnabled) {
                                    true =>
                                      l10n.externalPlayerSettingsDanmakuOnWithPlayer(
                                        _player.displayName,
                                      ),
                                    false =>
                                      l10n.externalPlayerSettingsDanmakuOffHint,
                                    null =>
                                      l10n.externalPlayerSettingsDanmakuStatusUnknown,
                                  }
                                : l10n.externalPlayerSettingsDanmakuUnsupported(
                                    _player.displayName,
                                  ),
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
                          l10n.externalPlayerSettingsUsageTitle,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          l10n.externalPlayerSettingsUsageSubtitle,
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
                            _player.usageNotes(l10n),
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
          builder: (context, active, _) {
            final l10n = AppLocalizations.of(context);
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              enabled:
                  available &&
                  status != null &&
                  status.player.supportsMiniPlayer,
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
                active
                    ? l10n.externalPlaybackMiniModeOnTooltip
                    : l10n.externalPlaybackMiniModeOpenTooltip,
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
                    ? l10n.externalPlayerSettingsMiniNeedsPlayback
                    : available
                    ? status.player.supportsMiniPlayer
                          ? l10n.externalPlayerSettingsMiniPinnedHint
                          : l10n.externalPlayerSettingsMiniUnsupported(
                              status.player.displayName,
                            )
                    : l10n.externalPlayerSettingsMiniWindowUnavailable,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              trailing: Icon(
                Icons.north_east_rounded,
                size: 18,
                color: colors.textSecondary,
              ),
              onTap:
                  available &&
                      status != null &&
                      status.player.supportsMiniPlayer
                  ? () async {
                      try {
                        await ExternalPlaybackMiniController.enter();
                      } catch (_) {
                        _showMessage(
                          l10n.externalPlaybackMiniModeOpenFailed,
                          error: true,
                        );
                      }
                    }
                  : null,
            );
          },
        ),
      ),
    );
  }
}
