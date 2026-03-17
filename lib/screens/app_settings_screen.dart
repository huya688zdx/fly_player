import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../player/stores/mpv_settings_store.dart';
import '../providers/app_theme_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import 'app_log_screen.dart';
import 'bookmark_manager_screen.dart';
import 'danmaku_settings_screen.dart';
import 'mpv_player_settings_screen.dart';
import 'parallel_window_settings_screen.dart';
import 'screenshot_settings_screen.dart';
import 'settings_search_screen.dart';
import 'theme_settings_screen.dart';

class AppSettingsScreen extends StatelessWidget {
  final bool secondaryHost;

  const AppSettingsScreen({super.key, this.secondaryHost = false});

  void _pushPage(BuildContext context, Widget page) {
    Navigator.of(
      context,
    ).push(AppTransitions.leftToRightPageTurnRoute<void>(page));
  }

  Future<void> _openSettingsSearch(
    BuildContext context,
    AppThemeProvider themeProvider,
    String parallelSummary,
  ) {
    return Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        SettingsSearchScreen(
          entries: _buildSearchEntries(context, themeProvider, parallelSummary),
        ),
      ),
    );
  }

  List<SettingsSearchEntry> _buildSearchEntries(
    BuildContext context,
    AppThemeProvider themeProvider,
    String parallelSummary,
  ) {
    final entries = <SettingsSearchEntry>[
      SettingsSearchEntry(
        id: 'theme_settings',
        title: '主题设置',
        subtitle:
            '${themeProvider.preset.title} · ${themeProvider.accentTone.title}',
        location: '设置',
        keywords: const <String>['主题', '配色', '颜色', '外观'],
        destinationBuilder: () => const ThemeSettingsScreen(),
        onSelect: () => _pushPage(context, const ThemeSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'mpv_settings',
        title: 'MPV播放器设置',
        subtitle: '外部播放器调整入口',
        location: '设置',
        keywords: const <String>['mpv', '播放器', '外部播放'],
        destinationBuilder: () => const MpvPlayerSettingsScreen(),
        onSelect: () => _pushPage(context, const MpvPlayerSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'parallel_window_settings',
        title: '并行窗口设置',
        subtitle: parallelSummary,
        location: '设置',
        keywords: const <String>['并行窗口', '双屏', '分屏'],
        destinationBuilder: () => const ParallelWindowSettingsScreen(),
        onSelect: () =>
            _pushPage(context, const ParallelWindowSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'other_settings',
        title: '其他',
        subtitle: '书签、弹幕、截图等辅助设置',
        location: '设置',
        keywords: const <String>['其他', '辅助设置'],
        destinationBuilder: () => const OtherSettingsScreen(),
        onSelect: () => _pushPage(context, const OtherSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'app_log',
        title: '日志信息',
        subtitle: '查看应用报错日志，并支持导出 TXT',
        location: '设置',
        keywords: const <String>['日志', '报错', 'txt', '导出'],
        destinationBuilder: () => const AppLogScreen(),
        onSelect: () => _pushPage(context, const AppLogScreen()),
      ),
      SettingsSearchEntry(
        id: 'bookmark_manager',
        title: '书签管理',
        subtitle: '查看、编辑和跳转书签',
        location: '设置 > 其他',
        keywords: const <String>['书签', 'bookmark'],
        destinationBuilder: () => const BookmarkManagerScreen(),
        onSelect: () => _pushPage(context, const BookmarkManagerScreen()),
      ),
      SettingsSearchEntry(
        id: 'danmaku_settings',
        title: '弹幕设置',
        subtitle: '调整默认弹幕样式和来源偏好',
        location: '设置 > 其他',
        keywords: const <String>['弹幕', 'danmaku'],
        destinationBuilder: () => const DanmakuSettingsScreen(),
        onSelect: () => _pushPage(context, const DanmakuSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'screenshot_settings',
        title: '截图设置',
        subtitle: '字幕携带和保存路径',
        location: '设置 > 其他',
        keywords: const <String>['截图', '相册目录', '保存路径'],
        destinationBuilder: () => const ScreenshotSettingsScreen(),
        onSelect: () => _pushPage(context, const ScreenshotSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'screenshot_include_subtitles',
        title: '截图是否携带字幕',
        subtitle: '直接进入字幕携带设置',
        location: '设置 > 其他 > 截图设置',
        keywords: const <String>['截图', '字幕', '携带字幕'],
        destinationBuilder: () => const ScreenshotSettingsDestinationScreen(
          target: ScreenshotSettingsScreen.targetIncludeSubtitles,
        ),
        onSelect: () => _pushPage(
          context,
          const ScreenshotSettingsScreen(
            initialTarget: ScreenshotSettingsScreen.targetIncludeSubtitles,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'screenshot_save_path',
        title: '截图保存路径设置',
        subtitle: '直接进入截图保存路径设置',
        location: '设置 > 其他 > 截图设置',
        keywords: const <String>['截图', '保存路径', '相册目录'],
        destinationBuilder: () => const ScreenshotSettingsDestinationScreen(
          target: ScreenshotSettingsScreen.targetSavePath,
        ),
        onSelect: () => _pushPage(
          context,
          const ScreenshotSettingsScreen(
            initialTarget: ScreenshotSettingsScreen.targetSavePath,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_quick_mode',
        title: 'MPV 快速模式',
        subtitle: '快速模式、高保真模式和一键预设',
        location: '设置 > MPV播放器设置',
        keywords: const <String>['mpv', '快速模式', '高保真', '极速模式'],
        destinationBuilder: () => const MpvPlayerSettingsScreen(),
        onSelect: () => _pushPage(context, const MpvPlayerSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'mpv_picture',
        title: 'MPV 画面调节',
        subtitle: '滤镜、HDR、插帧和即时调节',
        location: '设置 > MPV播放器设置',
        keywords: const <String>['mpv', '画面', 'hdr', '插帧', '滤镜'],
        destinationBuilder: () => const MpvPlayerSettingsDestinationScreen(
          section: MpvPlayerSettingsScreen.sectionPicture,
        ),
        onSelect: () => _pushPage(
          context,
          const MpvPlayerSettingsScreen(
            initialSection: MpvPlayerSettingsScreen.sectionPicture,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_audio',
        title: 'MPV 音频调节',
        subtitle: 'EQ、限幅、低音增强和人声增强',
        location: '设置 > MPV播放器设置',
        keywords: const <String>['mpv', '音频', 'eq', '高保真', '限幅'],
        destinationBuilder: () => const MpvPlayerSettingsDestinationScreen(
          section: MpvPlayerSettingsScreen.sectionAudio,
        ),
        onSelect: () => _pushPage(
          context,
          const MpvPlayerSettingsScreen(
            initialSection: MpvPlayerSettingsScreen.sectionAudio,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_playback',
        title: 'MPV 播放与缓存',
        subtitle: '同步模式、缓存策略和缓存大小',
        location: '设置 > MPV播放器设置',
        keywords: const <String>['mpv', '缓存', '缓冲', '同步'],
        destinationBuilder: () => const MpvPlayerSettingsDestinationScreen(
          section: MpvPlayerSettingsScreen.sectionPlayback,
        ),
        onSelect: () => _pushPage(
          context,
          const MpvPlayerSettingsScreen(
            initialSection: MpvPlayerSettingsScreen.sectionPlayback,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_compatibility',
        title: 'MPV 兼容与诊断',
        subtitle: '兼容模式和播放器诊断信息',
        location: '设置 > MPV播放器设置',
        keywords: const <String>['mpv', '兼容', '诊断', '播放信息'],
        destinationBuilder: () => const MpvPlayerSettingsDestinationScreen(
          section: MpvPlayerSettingsScreen.sectionCompatibility,
        ),
        onSelect: () => _pushPage(
          context,
          const MpvPlayerSettingsScreen(
            initialSection: MpvPlayerSettingsScreen.sectionCompatibility,
          ),
        ),
      ),
    ];

    for (final definition in MpvSettingsCatalog.definitions) {
      entries.add(
        SettingsSearchEntry(
          id: 'mpv:${definition.key}',
          title: definition.title,
          subtitle: definition.description,
          location: '设置 > MPV播放器设置 > ${_mpvLocationLabel(definition.key)}',
          keywords: <String>[
            'mpv',
            definition.shortTitle,
            definition.key,
            _mpvLocationLabel(definition.key),
          ],
          destinationBuilder: () =>
              MpvPlayerSettingsDestinationScreen(settingKey: definition.key),
          onSelect: () => _pushPage(
            context,
            MpvPlayerSettingsScreen(initialSettingKey: definition.key),
          ),
        ),
      );
    }

    return entries;
  }

  String _mpvLocationLabel(String key) {
    const pictureKeys = <String>{
      MpvSettingsCatalog.debandKey,
      MpvSettingsCatalog.sharpenKey,
      MpvSettingsCatalog.denoiseKey,
      MpvSettingsCatalog.deinterlaceKey,
      MpvSettingsCatalog.scaleProfileKey,
      MpvSettingsCatalog.hdrModeKey,
      MpvSettingsCatalog.frameInterpolationKey,
    };
    const audioKeys = <String>{
      MpvSettingsCatalog.volumeGainKey,
      MpvSettingsCatalog.audioHighFidelityKey,
      MpvSettingsCatalog.dynamicRangeKey,
      MpvSettingsCatalog.audioEqKey,
      MpvSettingsCatalog.audioLimiterKey,
      MpvSettingsCatalog.audioBassBoostKey,
      MpvSettingsCatalog.audioVoiceEnhanceKey,
      MpvSettingsCatalog.channelMixKey,
    };
    const playbackKeys = <String>{
      MpvSettingsCatalog.videoSyncKey,
      MpvSettingsCatalog.cacheProfileKey,
      MpvSettingsCatalog.cacheSizeMbKey,
    };
    if (pictureKeys.contains(key)) return '画面调节';
    if (audioKeys.contains(key)) return '音频调节';
    if (playbackKeys.contains(key)) return '播放与缓存';
    if (key == MpvSettingsCatalog.compatibilityKey) return '兼容与诊断';
    return 'MPV播放器设置';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final themeProvider = context.watch<AppThemeProvider>();
    final parallelSettings = context.watch<ParallelWindowSettingsProvider>();
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720;
    final titleSize = AdaptiveText.roleSize(
      compact ? 19 : 21,
      role: AdaptiveFontRole.title,
    );

    final parallelSummary = parallelSettings.enabled
        ? '已开启 · ${parallelSettings.primaryOnLeft ? '左侧主屏' : '右侧主屏'}'
        : '已关闭 · 当前使用单屏模式';

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        leading: secondaryHost
            ? IconButton(
                onPressed: () {
                  EmbeddedDetailLauncher.closeHostOrPop(context);
                },
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              )
            : null,
        title: Text(
          '设置',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () =>
                _openSettingsSearch(context, themeProvider, parallelSummary),
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索设置项',
          ),
        ],
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxContentWidth = constraints.maxWidth >= 1080
                  ? 960.0
                  : 760.0;
              return Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    10,
                    compact ? 16 : 24,
                    compact ? 24 : 32,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _SettingsHero(
                          compact: compact,
                          themeTitle: themeProvider.preset.title,
                          accentTitle: themeProvider.accentTone.title,
                          parallelSummary: parallelSummary,
                        ),
                        const SizedBox(height: 18),
                        _SettingsGroupCard(
                          children: <Widget>[
                            _SettingsEntryTile(
                              icon: Icons.palette_outlined,
                              title: '主题设置',
                              subtitle:
                                  '${themeProvider.preset.title} · ${themeProvider.accentTone.title}',
                              onTap: () {
                                _pushPage(context, const ThemeSettingsScreen());
                              },
                            ),
                            const _SettingsGroupDivider(),
                            _SettingsEntryTile(
                              icon: Icons.video_settings_rounded,
                              title: 'MPV播放器设置',
                              subtitle: '外部播放器调整入口，具体参数下沉到三级页',
                              onTap: () {
                                _pushPage(
                                  context,
                                  const MpvPlayerSettingsScreen(),
                                );
                              },
                            ),
                            const _SettingsGroupDivider(),
                            _SettingsEntryTile(
                              icon: Icons.splitscreen_outlined,
                              title: '并行窗口设置',
                              subtitle: parallelSummary,
                              onTap: () {
                                _pushPage(
                                  context,
                                  const ParallelWindowSettingsScreen(),
                                );
                              },
                            ),
                            const _SettingsGroupDivider(),
                            _SettingsEntryTile(
                              icon: Icons.more_horiz_rounded,
                              title: '其他',
                              subtitle: '收纳截图、弹幕、书签等辅助设置',
                              onTap: () {
                                _pushPage(context, const OtherSettingsScreen());
                              },
                            ),
                            const _SettingsGroupDivider(),
                            _SettingsEntryTile(
                              icon: Icons.receipt_long_outlined,
                              title: '日志信息',
                              subtitle: '查看应用报错日志，并支持导出 TXT',
                              onTap: () {
                                _pushPage(context, const AppLogScreen());
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const _SettingsHintCard(
                          title: '说明',
                          content: '二级页只保留总入口，具体配置下沉到三级页面。后续继续加设置项时，也按这个层级扩展。',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsHero extends StatelessWidget {
  final bool compact;
  final String themeTitle;
  final String accentTitle;
  final String parallelSummary;

  const _SettingsHero({
    required this.compact,
    required this.themeTitle,
    required this.accentTitle,
    required this.parallelSummary,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.surfaceSubtle, colors.backgroundElevated],
        ),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: compact ? 62 : 72,
                height: compact ? 62 : 72,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.78),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '设',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(28),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '设置中心',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: AdaptiveText.roleSize(
                          compact ? 24 : 26,
                          role: AdaptiveFontRole.title,
                        ),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '统一管理外观和多窗口行为',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _HeroBadge(
                icon: Icons.color_lens_outlined,
                text: '$themeTitle · $accentTitle',
              ),
              _HeroBadge(
                icon: Icons.splitscreen_outlined,
                text: parallelSummary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeroBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.backgroundBase.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: colors.accentStrong, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsGroupDivider extends StatelessWidget {
  const _SettingsGroupDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      height: 1,
      color: colors.borderSubtle,
    );
  }
}

class _SettingsEntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.textPrimary, size: 22),
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
                      fontSize: AdaptiveText.roleSize(16),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(13.2),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textMuted,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHintCard extends StatelessWidget {
  final String title;
  final String content;

  const _SettingsHintCard({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(15.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13.4),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
