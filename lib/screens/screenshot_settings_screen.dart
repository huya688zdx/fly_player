import 'dart:async';

import 'package:flutter/material.dart';

import '../danmaku/models/danmaku_settings.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../player/stores/bookmark_store.dart';
import '../player/stores/screenshot_settings_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import 'bookmark_manager_screen.dart';
import 'danmaku_settings_screen.dart';

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
    final results = await Future.wait<Object>(<Future<Object>>[
      _screenshotStore.load(),
      _danmakuStore.load(),
      _bookmarkStore.loadAll(),
    ]);
    if (!mounted) return;
    setState(() {
      _screenshotSettings = results[0] as ScreenshotSettingsData;
      _danmakuSettings = results[1] as DanmakuSettings;
      _bookmarkCount = (results[2] as List<PlayerBookmarkEntry>).length;
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
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
                            subtitle:
                                '${_screenshotStore.subtitleModeLabel(_screenshotSettings.includeSubtitles)} / ${_screenshotStore.savePathLabel(_screenshotSettings.savePathMode)}',
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
  bool _loading = true;
  bool _initialTargetHandled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = await _store.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
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
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
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
                            subtitle: _store.savePathDescription(
                              _settings.savePathMode,
                            ),
                            onTap: _openSavePathMode,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _HintCard(
                      title: '说明',
                      content:
                          '这里的修改只影响后续新截图，不会改动已经保存的图片。三级页现在改成即时保存但不自动返回，你可以连续切换对比后再手动返回。',
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
      appBar: AppBar(
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
  late String _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
  }

  Future<void> _select(String value) async {
    if (_currentValue == value) return;
    await widget.store.savePathMode(value);
    if (!mounted) return;
    setState(() => _currentValue = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
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
                  subtitle: ScreenshotSettingsStore
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
