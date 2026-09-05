import 'dart:async';

import 'package:flutter/material.dart';

import '../danmaku/models/danmaku_settings.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../playback/bookmarks/bookmark_store.dart';
import '../playback/screenshots/screenshot_settings_store.dart';
import '../services/storage_access_service.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_top_tip.dart';
import '../utils/swallowed_error_logger.dart';
import 'bookmark_manager_screen.dart';
import 'danmaku_settings_screen.dart';
import 'screenshot_preview_screen.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

String _screenshotSavePathLabel(AppLocalizations l10n, String value) {
  return switch (value) {
    'pictures' => l10n.settingsScreenshotSavePathPicturesTitle,
    'dcim' => l10n.settingsScreenshotSavePathDcimTitle,
    'app_pictures' => l10n.settingsScreenshotSavePathAppPicturesTitle,
    ScreenshotSettingsStore.customSavePathMode =>
      l10n.settingsScreenshotSavePathCustomTitle,
    _ => l10n.settingsScreenshotSavePathPicturesTitle,
  };
}

String _screenshotSavePathDescription(AppLocalizations l10n, String value) {
  return switch (value) {
    'pictures' => l10n.settingsScreenshotSavePathPicturesDescription,
    'dcim' => l10n.settingsScreenshotSavePathDcimDescription,
    'app_pictures' => l10n.settingsScreenshotSavePathAppPicturesDescription,
    ScreenshotSettingsStore.customSavePathMode =>
      l10n.settingsScreenshotSavePathCustomDescription,
    _ => l10n.settingsScreenshotSavePathPicturesDescription,
  };
}

/// 单项加载容错：任一依赖失败只把该项降级为兜底值并记录日志，
/// 不让单个异常把子页永久卡在加载态（此前桌面端 `fly_player/storage`
/// 通道抛 MissingPluginException 即触发该问题）。日志异步落盘，
/// 降级路径不等日志 IO。
Future<T> _tolerantLoad<T>(
  String action,
  Future<T> Function() load,
  T fallback,
) async {
  try {
    return await load();
  } catch (error, stackTrace) {
    unawaited(
      logSwallowedError(
        action: action,
        error: error,
        stackTrace: stackTrace,
        source: 'screenshot_settings_screen',
      ),
    );
    return fallback;
  }
}

class OtherSettingsScreen extends StatefulWidget {
  const OtherSettingsScreen({super.key});

  @override
  State<OtherSettingsScreen> createState() => _OtherSettingsScreenState();
}

class _OtherSettingsScreenState extends State<OtherSettingsScreen> {
  final ScreenshotSettingsStore _screenshotStore =
      const ScreenshotSettingsStore();
  final DanmakuSettingsStore _danmakuStore = const DanmakuSettingsStore();
  final BookmarkStore _bookmarkStore = const BookmarkStore();

  ScreenshotSettingsData _screenshotSettings = const ScreenshotSettingsData(
    includeSubtitles: ScreenshotSettingsStore.defaultIncludeSubtitles,
    savePathMode: ScreenshotSettingsStore.defaultSavePathMode,
  );
  ScreenshotCustomDirectoryInfo? _customScreenshotDirectory;
  DanmakuSettings _danmakuSettings = DanmakuSettings.defaults;
  int _bookmarkCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bookmarkStore.changes.addListener(_handleBookmarkStoreChanged);
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _bookmarkStore.changes.removeListener(_handleBookmarkStoreChanged);
    super.dispose();
  }

  void _handleBookmarkStoreChanged() {
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _tolerantLoad(
        'load screenshot settings',
        _screenshotStore.load,
        const ScreenshotSettingsData(
          includeSubtitles: ScreenshotSettingsStore.defaultIncludeSubtitles,
          savePathMode: ScreenshotSettingsStore.defaultSavePathMode,
        ),
      ),
      _tolerantLoad(
        'load danmaku settings',
        _danmakuStore.load,
        DanmakuSettings.defaults,
      ),
      _tolerantLoad(
        'load bookmarks',
        _bookmarkStore.loadAll,
        const <PlayerBookmarkEntry>[],
      ),
      _tolerantLoad<ScreenshotCustomDirectoryInfo?>(
        'load screenshot custom directory',
        StorageAccessService.getScreenshotCustomDirectory,
        null,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _screenshotSettings = results[0] as ScreenshotSettingsData;
      _danmakuSettings = results[1] as DanmakuSettings;
      _bookmarkCount = (results[2] as List<PlayerBookmarkEntry>).length;
      _customScreenshotDirectory = results[3] as ScreenshotCustomDirectoryInfo?;
      _loading = false;
    });
  }

  Future<void> _openBookmarkManager() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        const BookmarkManagerScreen(),
      ),
    );
    await _loadSettings();
  }

  Future<void> _openDanmakuSettings() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        const DanmakuSettingsScreen(),
      ),
    );
    await _loadSettings();
  }

  Future<void> _openScreenshotSettings() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        const ScreenshotSettingsScreen(),
      ),
    );
    await _loadSettings();
  }

  String _bookmarkSummary() {
    final l10n = AppLocalizations.of(context);
    if (_bookmarkCount <= 0) return l10n.settingsBookmarkEmptySummary;
    return l10n.settingsBookmarkCountSummary(_bookmarkCount);
  }

  String _danmakuSummary() {
    final l10n = AppLocalizations.of(context);
    final enabled = _danmakuSettings.enabled
        ? l10n.settingsDanmakuDefaultEnabled
        : l10n.settingsDanmakuDefaultDisabled;
    final source = _danmakuSettings.preferLocalSource
        ? l10n.settingsDanmakuLocalFirst
        : l10n.settingsDanmakuNetworkFirst;
    return '$enabled / $source';
  }

  String _screenshotSummary() {
    final l10n = AppLocalizations.of(context);
    final savePathLabel = switch (_screenshotSettings.savePathMode) {
      ScreenshotSettingsStore.customSavePathMode =>
        _customScreenshotDirectory?.available == true
            ? _customScreenshotDirectory!.name
            : l10n.settingsScreenshotCustomDirectoryNotReady,
      _ => _screenshotSavePathLabel(l10n, _screenshotSettings.savePathMode),
    };
    final subtitleMode = _screenshotSettings.includeSubtitles
        ? l10n.settingsScreenshotWithSubtitles
        : l10n.settingsScreenshotImageOnly;
    return '$subtitleMode / $savePathLabel';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          l10n.settingsOtherTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.bookmarks_outlined,
                            title: AppLocalizations.of(
                              context,
                            ).settingsBookmarkManagerTitle,
                            subtitle: _bookmarkSummary(),
                            onTap: _openBookmarkManager,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.comment_bank_outlined,
                            title: AppLocalizations.of(
                              context,
                            ).settingsDanmakuTitle,
                            subtitle: _danmakuSummary(),
                            onTap: _openDanmakuSettings,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.photo_camera_back_outlined,
                            title: AppLocalizations.of(
                              context,
                            ).settingsScreenshotTitle,
                            subtitle: _screenshotSummary(),
                            onTap: _openScreenshotSettings,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class ScreenshotSettingsScreen extends StatefulWidget {
  static const String targetIncludeSubtitles = 'include_subtitles';
  static const String targetSavePath = 'save_path';
  static const String targetPreview = 'preview';
  static const String targetCustomDirectory = 'custom_directory';

  final String? initialTarget;

  const ScreenshotSettingsScreen({super.key, this.initialTarget});

  @override
  State<ScreenshotSettingsScreen> createState() =>
      _ScreenshotSettingsScreenState();
}

class ScreenshotSettingsDestinationScreen extends StatefulWidget {
  final String? target;

  const ScreenshotSettingsDestinationScreen({super.key, this.target});

  @override
  State<ScreenshotSettingsDestinationScreen> createState() =>
      _ScreenshotSettingsDestinationScreenState();
}

class _ScreenshotSettingsDestinationScreenState
    extends State<ScreenshotSettingsDestinationScreen> {
  final ScreenshotSettingsStore _store = const ScreenshotSettingsStore();
  ScreenshotSettingsData? _settings;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final settings = await _store.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      final colors = context.appColors;
      return Scaffold(
        backgroundColor: colors.backgroundBase,
        body: const Center(child: BirdLoader(size: 120)),
      );
    }
    return switch (widget.target) {
      ScreenshotSettingsScreen.targetIncludeSubtitles =>
        _ScreenshotSubtitleModeScreen(
          initialValue: settings.includeSubtitles,
          store: _store,
        ),
      ScreenshotSettingsScreen.targetSavePath => _ScreenshotSavePathScreen(
        initialValue: settings.savePathMode,
        store: _store,
      ),
      ScreenshotSettingsScreen.targetPreview => const ScreenshotPreviewScreen(),
      ScreenshotSettingsScreen.targetCustomDirectory =>
        _ScreenshotCustomDirectoryScreen(store: _store),
      _ => const ScreenshotSettingsScreen(),
    };
  }
}

class _ScreenshotSettingsScreenState extends State<ScreenshotSettingsScreen> {
  final ScreenshotSettingsStore _store = const ScreenshotSettingsStore();
  ScreenshotSettingsData _settings = const ScreenshotSettingsData(
    includeSubtitles: ScreenshotSettingsStore.defaultIncludeSubtitles,
    savePathMode: ScreenshotSettingsStore.defaultSavePathMode,
  );
  ScreenshotCustomDirectoryInfo? _customDirectoryInfo;
  bool _loading = true;
  bool _initialTargetHandled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _tolerantLoad(
        'load screenshot settings',
        _store.load,
        const ScreenshotSettingsData(
          includeSubtitles: ScreenshotSettingsStore.defaultIncludeSubtitles,
          savePathMode: ScreenshotSettingsStore.defaultSavePathMode,
        ),
      ),
      _tolerantLoad<ScreenshotCustomDirectoryInfo?>(
        'load screenshot custom directory',
        StorageAccessService.getScreenshotCustomDirectory,
        null,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = results[0] as ScreenshotSettingsData;
      _customDirectoryInfo = results[1] as ScreenshotCustomDirectoryInfo?;
      _loading = false;
    });
    if (!_initialTargetHandled && widget.initialTarget != null) {
      _initialTargetHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openInitialTarget());
      });
    }
  }

  Route<void> _buildAutoRoute(
    Widget page, {
    required bool animated,
    bool keepReverseAnimation = false,
  }) {
    if (animated) {
      return AppTransitions.leftToRightPageTurnRoute<void>(page);
    }
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: keepReverseAnimation
          ? const Duration(milliseconds: 220)
          : Duration.zero,
      transitionsBuilder: (_, animation, __, child) {
        if (!keepReverseAnimation) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.linear,
          reverseCurve: Curves.easeInOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<void> _openIncludeSubtitles({bool animated = true}) async {
    await Navigator.of(context).push(
      _buildAutoRoute(
        _ScreenshotSubtitleModeScreen(
          initialValue: _settings.includeSubtitles,
          store: _store,
        ),
        animated: animated,
      ),
    );
    await _loadSettings();
  }

  Future<void> _openSavePathMode({bool animated = true}) async {
    await Navigator.of(context).push(
      _buildAutoRoute(
        _ScreenshotSavePathScreen(
          initialValue: _settings.savePathMode,
          store: _store,
        ),
        animated: animated,
      ),
    );
    await _loadSettings();
  }

  Future<void> _openPreview({bool animated = true}) async {
    await Navigator.of(context).push(
      _buildAutoRoute(const ScreenshotPreviewScreen(), animated: animated),
    );
    await _loadSettings();
  }

  Future<void> _openCustomDirectory({bool animated = true}) async {
    await Navigator.of(context).push(
      _buildAutoRoute(
        _ScreenshotCustomDirectoryScreen(store: _store),
        animated: animated,
      ),
    );
    await _loadSettings();
  }

  Future<void> _openInitialTarget() async {
    if (!mounted) return;
    switch (widget.initialTarget) {
      case ScreenshotSettingsScreen.targetIncludeSubtitles:
        await Navigator.of(context).pushReplacement(
          _buildAutoRoute(
            _ScreenshotSubtitleModeScreen(
              initialValue: _settings.includeSubtitles,
              store: _store,
            ),
            animated: false,
            keepReverseAnimation: true,
          ),
        );
        break;
      case ScreenshotSettingsScreen.targetSavePath:
        await Navigator.of(context).pushReplacement(
          _buildAutoRoute(
            _ScreenshotSavePathScreen(
              initialValue: _settings.savePathMode,
              store: _store,
            ),
            animated: false,
            keepReverseAnimation: true,
          ),
        );
        break;
      case ScreenshotSettingsScreen.targetPreview:
        await Navigator.of(context).pushReplacement(
          _buildAutoRoute(
            const ScreenshotPreviewScreen(),
            animated: false,
            keepReverseAnimation: true,
          ),
        );
        break;
      case ScreenshotSettingsScreen.targetCustomDirectory:
        await Navigator.of(context).pushReplacement(
          _buildAutoRoute(
            _ScreenshotCustomDirectoryScreen(store: _store),
            animated: false,
            keepReverseAnimation: true,
          ),
        );
        break;
      default:
        break;
    }
  }

  String _savePathSummary() {
    final l10n = AppLocalizations.of(context);
    if (_settings.savePathMode != ScreenshotSettingsStore.customSavePathMode) {
      return _screenshotSavePathDescription(l10n, _settings.savePathMode);
    }
    final customInfo = _customDirectoryInfo;
    if (customInfo == null) {
      return l10n.settingsScreenshotCustomDirectoryUnsetSummary;
    }
    if (!customInfo.available) {
      return l10n.settingsScreenshotCustomDirectoryInvalidSummary(
        customInfo.name,
      );
    }
    return l10n.settingsScreenshotCustomDirectoryActiveSummary(customInfo.name);
  }

  String _customDirectorySummary() {
    final l10n = AppLocalizations.of(context);
    final customInfo = _customDirectoryInfo;
    if (customInfo == null) return l10n.settingsScreenshotDirectoryUnset;
    if (!customInfo.available) return l10n.settingsScreenshotDirectoryInvalid;
    return customInfo.name;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          l10n.settingsScreenshotTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.subtitles_outlined,
                            title: AppLocalizations.of(
                              context,
                            ).settingsScreenshotIncludeSubtitlesTitle,
                            subtitle: _settings.includeSubtitles
                                ? AppLocalizations.of(
                                    context,
                                  ).settingsScreenshotWithSubtitleLayer
                                : AppLocalizations.of(
                                    context,
                                  ).settingsScreenshotImageOnlySummary,
                            onTap: _openIncludeSubtitles,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.folder_outlined,
                            title: AppLocalizations.of(
                              context,
                            ).settingsScreenshotSavePathTitle,
                            subtitle: _savePathSummary(),
                            onTap: _openSavePathMode,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.collections_outlined,
                            title: AppLocalizations.of(
                              context,
                            ).settingsScreenshotPreviewTitle,
                            subtitle: AppLocalizations.of(
                              context,
                            ).settingsScreenshotPreviewSubtitle,
                            onTap: _openPreview,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.folder_special_outlined,
                            title: AppLocalizations.of(
                              context,
                            ).settingsScreenshotCustomDirectoryTitle,
                            subtitle: _customDirectorySummary(),
                            onTap: _openCustomDirectory,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ScreenshotSubtitleModeScreen extends StatefulWidget {
  final bool initialValue;
  final ScreenshotSettingsStore store;

  const _ScreenshotSubtitleModeScreen({
    required this.initialValue,
    required this.store,
  });

  @override
  State<_ScreenshotSubtitleModeScreen> createState() =>
      _ScreenshotSubtitleModeScreenState();
}

class _ScreenshotSubtitleModeScreenState
    extends State<_ScreenshotSubtitleModeScreen> {
  late bool _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
  }

  Future<void> _select(bool value) async {
    if (_currentValue == value) return;
    await widget.store.saveIncludeSubtitles(value);
    if (!mounted) return;
    setState(() => _currentValue = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          l10n.settingsScreenshotIncludeSubtitlesTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _ChoiceTile(
                title: l10n.settingsScreenshotImageOnly,
                subtitle: l10n.settingsScreenshotImageOnlyDescription,
                selected: !_currentValue,
                onTap: () => _select(false),
              ),
              const SizedBox(height: 12),
              _ChoiceTile(
                title: l10n.settingsScreenshotWithSubtitles,
                subtitle: l10n.settingsScreenshotWithSubtitlesDescription,
                selected: _currentValue,
                onTap: () => _select(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenshotSavePathScreen extends StatefulWidget {
  final String initialValue;
  final ScreenshotSettingsStore store;

  const _ScreenshotSavePathScreen({
    required this.initialValue,
    required this.store,
  });

  @override
  State<_ScreenshotSavePathScreen> createState() =>
      _ScreenshotSavePathScreenState();
}

class _ScreenshotSavePathScreenState extends State<_ScreenshotSavePathScreen> {
  final AppTopTip _topTip = AppTopTip();

  late String _currentValue;
  ScreenshotCustomDirectoryInfo? _customDirectoryInfo;
  bool _loadingCustomInfo = true;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
    unawaited(_loadCustomDirectoryInfo());
  }

  @override
  void dispose() {
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _loadCustomDirectoryInfo() async {
    final info = await _tolerantLoad<ScreenshotCustomDirectoryInfo?>(
      'load screenshot custom directory',
      StorageAccessService.getScreenshotCustomDirectory,
      null,
    );
    if (!mounted) return;
    setState(() {
      _customDirectoryInfo = info;
      _loadingCustomInfo = false;
    });
  }

  Future<void> _manageCustomDirectory() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        _ScreenshotCustomDirectoryScreen(store: widget.store),
      ),
    );
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _tolerantLoad(
        'load screenshot settings',
        widget.store.load,
        const ScreenshotSettingsData(
          includeSubtitles: ScreenshotSettingsStore.defaultIncludeSubtitles,
          savePathMode: ScreenshotSettingsStore.defaultSavePathMode,
        ),
      ),
      _tolerantLoad<ScreenshotCustomDirectoryInfo?>(
        'load screenshot custom directory',
        StorageAccessService.getScreenshotCustomDirectory,
        null,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _currentValue = (results[0] as ScreenshotSettingsData).savePathMode;
      _customDirectoryInfo = results[1] as ScreenshotCustomDirectoryInfo?;
      _loadingCustomInfo = false;
    });
  }

  Future<void> _select(String value) async {
    final l10n = AppLocalizations.of(context);
    if (value == ScreenshotSettingsStore.customSavePathMode) {
      final info = _customDirectoryInfo;
      if (info?.available != true) {
        _topTip.show(
          context,
          message: info == null
              ? l10n.settingsScreenshotSelectCustomDirectoryFirst
              : l10n.settingsScreenshotCustomDirectoryInvalidRetry,
          color: context.appColors.warning,
        );
        await _manageCustomDirectory();
        if (!mounted) return;
        if (_customDirectoryInfo?.available != true) {
          return;
        }
      }
    }
    if (_currentValue == value) return;
    await widget.store.savePathMode(value);
    if (!mounted) return;
    setState(() => _currentValue = value);
  }

  String _customOptionSubtitle() {
    final l10n = AppLocalizations.of(context);
    if (_loadingCustomInfo) {
      return l10n.settingsScreenshotReadingCustomDirectory;
    }
    final info = _customDirectoryInfo;
    if (info == null) {
      return l10n.settingsScreenshotDirectoryUnsetSentence;
    }
    if (!info.available) {
      return l10n.settingsScreenshotDirectoryInvalidWithName(info.name);
    }
    return l10n.settingsScreenshotCurrentDirectory(info.name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final customDirectoryReady = _customDirectoryInfo?.available == true;
    final customSelected =
        _currentValue == ScreenshotSettingsStore.customSavePathMode;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          l10n.settingsScreenshotSavePathTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              for (
                var index = 0;
                index < ScreenshotSettingsStore.savePathOptions.length;
                index++
              ) ...[
                _ChoiceTile(
                  title: _screenshotSavePathLabel(
                    l10n,
                    ScreenshotSettingsStore.savePathOptions[index].value,
                  ),
                  subtitle:
                      ScreenshotSettingsStore.savePathOptions[index].value ==
                          ScreenshotSettingsStore.customSavePathMode
                      ? _customOptionSubtitle()
                      : _screenshotSavePathDescription(
                          l10n,
                          ScreenshotSettingsStore.savePathOptions[index].value,
                        ),
                  selected:
                      ScreenshotSettingsStore.savePathOptions[index].value ==
                      _currentValue,
                  onTap: () => _select(
                    ScreenshotSettingsStore.savePathOptions[index].value,
                  ),
                ),
                if (index != ScreenshotSettingsStore.savePathOptions.length - 1)
                  const SizedBox(height: 12),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: colors.surfaceSubtle,
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l10n.settingsScreenshotCustomDirectoryManagement,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: AdaptiveText.roleSize(
                                16,
                                role: AdaptiveFontRole.title,
                              ),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _StatusBadge(
                          label: customDirectoryReady
                              ? l10n.settingsScreenshotDirectoryAvailable
                              : _customDirectoryInfo == null
                              ? l10n.settingsScreenshotDirectoryUnset
                              : l10n.settingsScreenshotDirectoryNeedsReselect,
                          color: customDirectoryReady
                              ? colors.success
                              : colors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      customDirectoryReady
                          ? l10n.settingsScreenshotDirectoryActiveDetail(
                              _customDirectoryInfo!.name,
                            )
                          : _customDirectoryInfo == null
                          ? l10n.settingsScreenshotDirectorySetupHint
                          : l10n.settingsScreenshotDirectoryInvalidDetail(
                              _customDirectoryInfo!.name,
                            ),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(
                          13,
                          role: AdaptiveFontRole.body,
                        ),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: _manageCustomDirectory,
                          icon: Icon(
                            _customDirectoryInfo == null
                                ? Icons.create_new_folder_outlined
                                : Icons.folder_open_outlined,
                          ),
                          label: Text(
                            _customDirectoryInfo == null
                                ? l10n.settingsScreenshotChooseDirectory
                                : l10n.settingsScreenshotChangeDirectory,
                          ),
                        ),
                        if (_customDirectoryInfo != null)
                          OutlinedButton.icon(
                            onPressed: _manageCustomDirectory,
                            icon: const Icon(Icons.tune_rounded),
                            label: Text(l10n.commonView),
                          ),
                        if (customDirectoryReady && !customSelected)
                          FilledButton.icon(
                            onPressed: () => _select(
                              ScreenshotSettingsStore.customSavePathMode,
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(
                              l10n.settingsScreenshotSetAsCurrentDirectory,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenshotCustomDirectoryScreen extends StatefulWidget {
  final ScreenshotSettingsStore store;

  const _ScreenshotCustomDirectoryScreen({required this.store});

  @override
  State<_ScreenshotCustomDirectoryScreen> createState() =>
      _ScreenshotCustomDirectoryScreenState();
}

class _ScreenshotCustomDirectoryScreenState
    extends State<_ScreenshotCustomDirectoryScreen> {
  final AppTopTip _topTip = AppTopTip();

  ScreenshotSettingsData _settings = const ScreenshotSettingsData(
    includeSubtitles: ScreenshotSettingsStore.defaultIncludeSubtitles,
    savePathMode: ScreenshotSettingsStore.defaultSavePathMode,
  );
  ScreenshotCustomDirectoryInfo? _directoryInfo;
  bool _loading = true;
  bool _selecting = false;
  bool _clearing = false;

  bool get _directoryReady => _directoryInfo?.available == true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _tolerantLoad(
        'load screenshot settings',
        widget.store.load,
        const ScreenshotSettingsData(
          includeSubtitles: ScreenshotSettingsStore.defaultIncludeSubtitles,
          savePathMode: ScreenshotSettingsStore.defaultSavePathMode,
        ),
      ),
      _tolerantLoad<ScreenshotCustomDirectoryInfo?>(
        'load screenshot custom directory',
        StorageAccessService.getScreenshotCustomDirectory,
        null,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = results[0] as ScreenshotSettingsData;
      _directoryInfo = results[1] as ScreenshotCustomDirectoryInfo?;
      _loading = false;
    });
  }

  Future<void> _pickDirectory() async {
    if (_selecting) return;
    setState(() => _selecting = true);
    try {
      final info =
          await StorageAccessService.requestScreenshotCustomDirectory();
      if (!mounted) return;
      if (info == null) {
        _topTip.show(
          context,
          message: AppLocalizations.of(
            context,
          ).settingsScreenshotNoDirectorySelected,
          color: context.appColors.warning,
        );
        return;
      }
      setState(() => _directoryInfo = info);
      _topTip.show(
        context,
        message: info.available
            ? AppLocalizations.of(
                context,
              ).settingsScreenshotCustomDirectoryUpdated
            : AppLocalizations.of(
                context,
              ).settingsScreenshotCustomDirectoryRecordedUnavailable,
        color: info.available
            ? context.appColors.success
            : context.appColors.warning,
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'pick screenshot custom directory',
        error: error,
        stackTrace: stackTrace,
        source: 'screenshot_settings_screen',
      );
      if (mounted) {
        _topTip.show(
          context,
          message: AppLocalizations.of(context).commonOperationFailedRetryLater,
          color: context.appColors.danger,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _selecting = false);
      }
    }
  }

  Future<void> _clearDirectory() async {
    if (_clearing || _directoryInfo == null) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppLocalizations.of(
        context,
      ).settingsScreenshotClearCustomDirectoryTitle,
      content: AppLocalizations.of(
        context,
      ).settingsScreenshotClearCustomDirectoryContent,
      cancelText: AppLocalizations.of(context).commonCancel,
      confirmText: AppLocalizations.of(context).commonClear,
      confirmColor: context.appColors.warning,
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearing = true);
    try {
      await StorageAccessService.clearScreenshotCustomDirectory();
      if (!mounted) return;
      if (_settings.savePathMode ==
          ScreenshotSettingsStore.customSavePathMode) {
        final nextSettings = await widget.store.savePathMode(
          ScreenshotSettingsStore.defaultSavePathMode,
        );
        if (!mounted) return;
        _settings = nextSettings;
      }
      setState(() => _directoryInfo = null);
      _topTip.show(
        context,
        message: AppLocalizations.of(
          context,
        ).settingsScreenshotCustomDirectoryCleared,
        color: context.appColors.success,
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'clear screenshot custom directory',
        error: error,
        stackTrace: stackTrace,
        source: 'screenshot_settings_screen',
      );
      if (mounted) {
        _topTip.show(
          context,
          message: AppLocalizations.of(context).commonOperationFailedRetryLater,
          color: context.appColors.danger,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  Future<void> _activateCustomMode() async {
    if (!_directoryReady) return;
    final nextSettings = await widget.store.savePathMode(
      ScreenshotSettingsStore.customSavePathMode,
    );
    if (!mounted) return;
    setState(() => _settings = nextSettings);
    _topTip.show(
      context,
      message: AppLocalizations.of(
        context,
      ).settingsScreenshotCustomDirectoryActivated,
      color: context.appColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final usingCustomDirectory =
        _settings.savePathMode == ScreenshotSettingsStore.customSavePathMode;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          l10n.settingsScreenshotCustomDirectoryTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            colors.accent.withValues(alpha: 0.22),
                            colors.surfaceSubtle,
                          ],
                        ),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  _directoryInfo?.name ??
                                      l10n.settingsScreenshotNoDirectoryChosen,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: AdaptiveText.roleSize(
                                      22,
                                      role: AdaptiveFontRole.title,
                                    ),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              _StatusBadge(
                                label: _directoryReady
                                    ? l10n.settingsScreenshotDirectoryWritable
                                    : _directoryInfo == null
                                    ? l10n.settingsScreenshotDirectoryUnset
                                    : l10n.settingsScreenshotDirectoryExpired,
                                color: _directoryReady
                                    ? colors.success
                                    : colors.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _directoryReady
                                ? l10n.settingsScreenshotDirectoryWriteHint
                                : _directoryInfo == null
                                ? l10n.settingsScreenshotDirectoryPickHint
                                : l10n.settingsScreenshotDirectoryExpiredHint,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: AdaptiveText.roleSize(
                                14,
                                role: AdaptiveFontRole.body,
                              ),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              FilledButton.icon(
                                onPressed: _selecting ? null : _pickDirectory,
                                icon: Icon(
                                  _directoryInfo == null
                                      ? Icons.create_new_folder_outlined
                                      : Icons.sync_alt_rounded,
                                ),
                                label: Text(
                                  _directoryInfo == null
                                      ? l10n.settingsScreenshotChooseDirectory
                                      : l10n.settingsScreenshotChangeDirectory,
                                ),
                              ),
                              if (_directoryInfo != null)
                                OutlinedButton.icon(
                                  onPressed: _clearing ? null : _clearDirectory,
                                  icon: const Icon(Icons.delete_outline),
                                  label: Text(
                                    l10n.settingsScreenshotClearAuthorization,
                                  ),
                                ),
                              if (_directoryReady && !usingCustomDirectory)
                                FilledButton.tonalIcon(
                                  onPressed: _activateCustomMode,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: Text(
                                    l10n.settingsScreenshotSetAsCurrentDirectory,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _HintCard(
                      title: l10n.settingsScreenshotCurrentStatus,
                      content: usingCustomDirectory
                          ? l10n.settingsScreenshotCustomDirectoryEnabledStatus
                          : l10n.settingsScreenshotCustomDirectoryDisabledStatus,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CardBlock extends StatelessWidget {
  final Widget child;

  const _CardBlock({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: colors.surfaceSubtle,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: child,
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.backgroundElevated,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: colors.textPrimary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(
                        17,
                        role: AdaptiveFontRole.title,
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(
                        13,
                        role: AdaptiveFontRole.body,
                      ),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: selected
                ? colors.accent.withValues(alpha: 0.18)
                : colors.surfaceSubtle,
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? colors.accent : colors.textPrimary,
                        fontSize: AdaptiveText.roleSize(
                          18,
                          role: AdaptiveFontRole.title,
                        ),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(
                          14,
                          role: AdaptiveFontRole.body,
                        ),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? colors.accent : colors.textSecondary,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: AdaptiveText.roleSize(12, role: AdaptiveFontRole.body),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: context.appColors.borderSubtle,
    );
  }
}

class _HintCard extends StatelessWidget {
  final String title;
  final String content;

  const _HintCard({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: colors.surfaceSubtle,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(16, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13, role: AdaptiveFontRole.body),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
