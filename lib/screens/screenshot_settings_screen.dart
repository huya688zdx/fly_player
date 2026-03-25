import 'dart:async';

import 'package:flutter/material.dart';

import '../danmaku/models/danmaku_settings.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../player/stores/bookmark_store.dart';
import '../player/stores/screenshot_settings_store.dart';
import '../services/storage_access_service.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_top_tip.dart';
import 'bookmark_manager_screen.dart';
import 'danmaku_settings_screen.dart';
import 'screenshot_preview_screen.dart';

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
      _screenshotStore.load(),
      _danmakuStore.load(),
      _bookmarkStore.loadAll(),
      StorageAccessService.getScreenshotCustomDirectory(),
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
    if (_bookmarkCount <= 0) return '还没有书签';
    return '共 $_bookmarkCount 个书签';
  }

  String _danmakuSummary() {
    final enabled = _danmakuSettings.enabled ? '默认开启' : '默认关闭';
    final source = _danmakuSettings.preferLocalSource ? '本地优先' : '网络优先';
    return '$enabled / $source';
  }

  String _screenshotSummary() {
    final savePathLabel = switch (_screenshotSettings.savePathMode) {
      ScreenshotSettingsStore.customSavePathMode =>
        _customScreenshotDirectory?.available == true
            ? _customScreenshotDirectory!.name
            : '自定义目录未就绪',
      _ => _screenshotStore.savePathLabel(_screenshotSettings.savePathMode),
    };
    return '${_screenshotStore.subtitleModeLabel(_screenshotSettings.includeSubtitles)} / $savePathLabel';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          '其他',
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
              ? Center(child: CircularProgressIndicator(color: colors.accent))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.bookmarks_outlined,
                            title: '书签管理',
                            subtitle: _bookmarkSummary(),
                            onTap: _openBookmarkManager,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.comment_bank_outlined,
                            title: '弹幕设置',
                            subtitle: _danmakuSummary(),
                            onTap: _openDanmakuSettings,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.photo_camera_back_outlined,
                            title: '截图设置',
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
        body: Center(child: CircularProgressIndicator(color: colors.accent)),
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
      _store.load(),
      StorageAccessService.getScreenshotCustomDirectory(),
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
    if (_settings.savePathMode != ScreenshotSettingsStore.customSavePathMode) {
      return _store.savePathDescription(_settings.savePathMode);
    }
    final customInfo = _customDirectoryInfo;
    if (customInfo == null) {
      return '使用用户指定的目录保存截图，当前还未选择文件夹。';
    }
    if (!customInfo.available) {
      return '已记录自定义目录“${customInfo.name}”，但授权失效，需要重新选择。';
    }
    return '当前保存到自定义目录“${customInfo.name}”。';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          '截图设置',
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
              ? Center(child: CircularProgressIndicator(color: colors.accent))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.subtitles_outlined,
                            title: '截图是否携带字幕',
                            subtitle: _settings.includeSubtitles
                                ? '当前截图会把字幕一起保存进去。'
                                : '当前截图只保存画面本身，不包含字幕层。',
                            onTap: _openIncludeSubtitles,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.folder_outlined,
                            title: '截图保存路径设置',
                            subtitle: _savePathSummary(),
                            onTap: _openSavePathMode,
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.collections_outlined,
                            title: '截图预览',
                            subtitle: '查看、筛选和管理已保存的截图。',
                            onTap: _openPreview,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _HintCard(
                      title: '说明',
                      content:
                          '这里的修改只影响后续新截图，不会改动已经保存的图片。你可以在“截图保存路径设置”里管理自定义目录，在“截图预览”里集中查看和删除已有截图。',
                      trailing: FilledButton.tonalIcon(
                        onPressed: _openCustomDirectory,
                        icon: const Icon(Icons.folder_special_outlined),
                        label: const Text('管理自定义目录'),
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          '截图是否携带字幕',
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
                title: '仅画面',
                subtitle: '不携带字幕层，保持更干净的截图。',
                selected: !_currentValue,
                onTap: () => _select(false),
              ),
              const SizedBox(height: 12),
              _ChoiceTile(
                title: '携带字幕',
                subtitle: '把当前字幕一起写进截图，适合保存台词场景。',
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
    final info = await StorageAccessService.getScreenshotCustomDirectory();
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
      widget.store.load(),
      StorageAccessService.getScreenshotCustomDirectory(),
    ]);
    if (!mounted) return;
    setState(() {
      _currentValue = (results[0] as ScreenshotSettingsData).savePathMode;
      _customDirectoryInfo = results[1] as ScreenshotCustomDirectoryInfo?;
      _loadingCustomInfo = false;
    });
  }

  Future<void> _select(String value) async {
    if (value == ScreenshotSettingsStore.customSavePathMode) {
      final info = _customDirectoryInfo;
      if (info?.available != true) {
        _topTip.show(
          context,
          message: info == null ? '请先选择截图自定义目录' : '自定义目录已失效，请重新选择',
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
    if (_loadingCustomInfo) {
      return '正在读取当前自定义目录状态…';
    }
    final info = _customDirectoryInfo;
    if (info == null) {
      return '保存到用户自己选择的文件夹，当前还未设置目录。';
    }
    if (!info.available) {
      return '已记录目录“${info.name}”，但当前授权失效，需要重新选择。';
    }
    return '当前目录：${info.name}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final customDirectoryReady = _customDirectoryInfo?.available == true;
    final customSelected =
        _currentValue == ScreenshotSettingsStore.customSavePathMode;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          '截图保存路径设置',
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
                  title: ScreenshotSettingsStore.savePathOptions[index].label,
                  subtitle:
                      ScreenshotSettingsStore.savePathOptions[index].value ==
                          ScreenshotSettingsStore.customSavePathMode
                      ? _customOptionSubtitle()
                      : ScreenshotSettingsStore
                            .savePathOptions[index]
                            .description,
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
                            '自定义目录管理',
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
                              ? '目录可用'
                              : _customDirectoryInfo == null
                              ? '未设置'
                              : '需重选',
                          color: customDirectoryReady
                              ? colors.success
                              : colors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      customDirectoryReady
                          ? '截图会保存到“${_customDirectoryInfo!.name}”，你可以把它设为当前保存目录，也可以随时更换。'
                          : _customDirectoryInfo == null
                          ? '先选择一个文件夹，再切换到“自定义目录”模式。'
                          : '原来的目录“${_customDirectoryInfo!.name}”不可用了，请重新选择。',
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
                            _customDirectoryInfo == null ? '选择目录' : '更换目录',
                          ),
                        ),
                        if (_customDirectoryInfo != null)
                          OutlinedButton.icon(
                            onPressed: _manageCustomDirectory,
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('查看详情'),
                          ),
                        if (customDirectoryReady && !customSelected)
                          FilledButton.icon(
                            onPressed: () => _select(
                              ScreenshotSettingsStore.customSavePathMode,
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('设为当前保存目录'),
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
      widget.store.load(),
      StorageAccessService.getScreenshotCustomDirectory(),
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
          message: '未选择目录',
          color: context.appColors.warning,
        );
        return;
      }
      setState(() => _directoryInfo = info);
      _topTip.show(
        context,
        message: info.available ? '已更新截图自定义目录' : '目录已记录，但当前不可用',
        color: info.available
            ? context.appColors.success
            : context.appColors.warning,
      );
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
      title: '清除截图自定义目录',
      content: '这不会删除已经保存的截图，只会移除当前目录授权。',
      cancelText: '取消',
      confirmText: '清除',
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
        message: '已清除截图自定义目录',
        color: context.appColors.success,
      );
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
      message: '截图保存目录已切换为自定义目录',
      color: context.appColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final usingCustomDirectory =
        _settings.savePathMode == ScreenshotSettingsStore.customSavePathMode;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          '截图自定义目录',
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
              ? Center(child: CircularProgressIndicator(color: colors.accent))
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
                                  _directoryInfo?.name ?? '还没有选择目录',
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
                                    ? '可写入'
                                    : _directoryInfo == null
                                    ? '未设置'
                                    : '已失效',
                                color: _directoryReady
                                    ? colors.success
                                    : colors.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _directoryReady
                                ? '新的截图会直接写入这个目录。'
                                : _directoryInfo == null
                                ? '选择一个文件夹后，就可以把截图保存到你指定的位置。'
                                : '目录授权已经失效，需要重新选择后才能继续保存截图。',
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
                                  _directoryInfo == null ? '选择目录' : '更换目录',
                                ),
                              ),
                              if (_directoryInfo != null)
                                OutlinedButton.icon(
                                  onPressed: _clearing ? null : _clearDirectory,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('清除授权'),
                                ),
                              if (_directoryReady && !usingCustomDirectory)
                                FilledButton.tonalIcon(
                                  onPressed: _activateCustomMode,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('设为当前保存目录'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _HintCard(
                      title: '当前状态',
                      content: usingCustomDirectory
                          ? '当前截图已经使用自定义目录保存。更换目录后，新截图会进入新目录，旧截图不会迁移。'
                          : '当前截图还没有切换到自定义目录。设置好目录后，可以在保存路径页或本页直接启用。',
                    ),
                    const SizedBox(height: 14),
                    const _HintCard(
                      title: '说明',
                      content:
                          '自定义目录与字幕导入使用不同的授权，不会互相覆盖。目录失效时，截图不会自动回退到固定目录，而是提示你重新选择。',
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
  final Widget? trailing;

  const _HintCard({required this.title, required this.content, this.trailing});

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
          if (trailing != null) ...<Widget>[
            const SizedBox(height: 16),
            trailing!,
          ],
        ],
      ),
    );
  }
}
