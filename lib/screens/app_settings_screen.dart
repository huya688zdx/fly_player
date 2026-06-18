import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../player/mpv_settings_l10n.dart';
import '../player/stores/mpv_settings_store.dart';
import '../providers/app_locale_provider.dart';
import '../providers/app_theme_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_l10n.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import 'mpv_player_settings_screen.dart';
import 'screenshot_settings_screen.dart';
import 'settings_search_screen.dart';
import 'settings_destination_routes.dart';

class AppSettingsScreen extends StatelessWidget {
  final bool secondaryHost;

  const AppSettingsScreen({super.key, this.secondaryHost = false});

  Future<void> _openSettingsDestination(
    BuildContext context,
    String routeName,
  ) async {
    await EmbeddedDetailLauncher.openSettings(
      context: context,
      destinationRoute: routeName,
    );
  }

  Future<void> _openLanguageSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = sheetContext.appColors;
        final l10n = AppLocalizations.of(sheetContext);
        final selectedMode = sheetContext.watch<AppLocaleProvider>().mode;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 4, bottom: 10),
                    decoration: BoxDecoration(
                      color: colors.borderStrong,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.languageSheetTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(
                            17,
                            role: AdaptiveFontRole.title,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  _LanguageOptionTile(
                    mode: AppLocaleMode.system,
                    groupValue: selectedMode,
                    title: l10n.languageSystem,
                    subtitle: l10n.languageSystemSubtitle,
                    onSelected: () {
                      unawaited(
                        sheetContext.read<AppLocaleProvider>().setMode(
                          AppLocaleMode.system,
                        ),
                      );
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  _LanguageOptionTile(
                    mode: AppLocaleMode.zhCN,
                    groupValue: selectedMode,
                    title: l10n.languageZhCN,
                    subtitle: l10n.languageZhCNSubtitle,
                    onSelected: () {
                      unawaited(
                        sheetContext.read<AppLocaleProvider>().setMode(
                          AppLocaleMode.zhCN,
                        ),
                      );
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettingsSearch(
    BuildContext context,
    AppThemeProvider themeProvider,
    String parallelSummary,
    bool parallelWindowSupported,
  ) {
    return Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        SettingsSearchScreen(
          entries: _buildSearchEntries(
            context,
            themeProvider,
            parallelSummary,
            parallelWindowSupported,
          ),
        ),
      ),
    );
  }

  List<SettingsSearchEntry> _buildSearchEntries(
    BuildContext context,
    AppThemeProvider themeProvider,
    String parallelSummary,
    bool parallelWindowSupported,
  ) {
    final l10n = AppLocalizations.of(context);
    final entries = <SettingsSearchEntry>[
      SettingsSearchEntry(
        id: 'theme_settings',
        title: l10n.settingsThemeTitle,
        subtitle: l10n.settingsThemeSubtitle(
          AppThemeL10n.currentThemeTitle(l10n, themeProvider),
          AppThemeL10n.currentThemeSubtitle(l10n, themeProvider),
        ),
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.settingsThemeKeywords),
        onSelect: () =>
            _openSettingsDestination(context, SettingsDestinationRoutes.theme),
      ),
      SettingsSearchEntry(
        id: 'theme_custom_saved',
        title: l10n.settingsCustomThemeTitle,
        subtitle: l10n.settingsCustomThemeSubtitle,
        location: l10n.settingsLocationTheme,
        keywords: _keywords(l10n.settingsCustomThemeKeywords),
        onSelect: () =>
            _openSettingsDestination(context, SettingsDestinationRoutes.theme),
      ),
      SettingsSearchEntry(
        id: 'theme_custom_recipe',
        title: l10n.settingsCustomRecipeTitle,
        subtitle: l10n.settingsCustomRecipeSubtitle,
        location: l10n.settingsCustomRecipeLocation,
        keywords: _keywords(l10n.settingsCustomRecipeKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.themeCustomRecipe,
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_settings',
        title: l10n.settingsMpvTitle,
        subtitle: l10n.settingsMpvSubtitle,
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.settingsMpvKeywords),
        onSelect: () =>
            _openSettingsDestination(context, SettingsDestinationRoutes.mpv),
      ),
      if (parallelWindowSupported)
        SettingsSearchEntry(
          id: 'parallel_window_settings',
          title: l10n.settingsParallelWindowTitle,
          subtitle: parallelSummary,
          location: l10n.settingsLocationRoot,
          keywords: _keywords(l10n.settingsParallelWindowKeywords),
          onSelect: () => _openSettingsDestination(
            context,
            SettingsDestinationRoutes.parallelWindow,
          ),
        ),
      SettingsSearchEntry(
        id: 'download_management',
        title: l10n.settingsDownloadTitle,
        subtitle: l10n.settingsDownloadSubtitle,
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.settingsDownloadKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.downloads,
        ),
      ),
      SettingsSearchEntry(
        id: 'storage_management',
        title: l10n.settingsStorageTitle,
        subtitle: l10n.settingsStorageSubtitle,
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.settingsStorageKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.storage,
        ),
      ),
      SettingsSearchEntry(
        id: 'play_stats',
        title: l10n.settingsPlayStatsTitle,
        subtitle: l10n.settingsPlayStatsSubtitle,
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.settingsPlayStatsKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.playStats,
        ),
      ),
      SettingsSearchEntry(
        id: 'other_settings',
        title: l10n.settingsOtherTitle,
        subtitle: l10n.settingsOtherSubtitle,
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.settingsOtherKeywords),
        onSelect: () =>
            _openSettingsDestination(context, SettingsDestinationRoutes.other),
      ),
      SettingsSearchEntry(
        id: 'app_log',
        title: l10n.settingsLogTitle,
        subtitle: l10n.settingsLogSubtitle,
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.settingsLogKeywords),
        onSelect: () =>
            _openSettingsDestination(context, SettingsDestinationRoutes.logs),
      ),
      SettingsSearchEntry(
        id: 'bookmark_manager',
        title: l10n.settingsBookmarkTitle,
        subtitle: l10n.settingsBookmarkSubtitle,
        location: l10n.settingsLocationOther,
        keywords: _keywords(l10n.settingsBookmarkKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.bookmarks,
        ),
      ),
      SettingsSearchEntry(
        id: 'danmaku_settings',
        title: l10n.settingsDanmakuTitle,
        subtitle: l10n.settingsDanmakuSubtitle,
        location: l10n.settingsLocationOther,
        keywords: _keywords(l10n.settingsDanmakuKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.danmaku,
        ),
      ),
      SettingsSearchEntry(
        id: 'screenshot_settings',
        title: l10n.settingsScreenshotTitle,
        subtitle: l10n.settingsScreenshotSubtitle,
        location: l10n.settingsLocationOther,
        keywords: _keywords(l10n.settingsScreenshotKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.screenshot,
        ),
      ),
      SettingsSearchEntry(
        id: 'screenshot_include_subtitles',
        title: l10n.settingsScreenshotIncludeSubtitlesTitle,
        subtitle: l10n.settingsScreenshotIncludeSubtitlesSubtitle,
        location: l10n.settingsLocationScreenshot,
        keywords: _keywords(l10n.settingsScreenshotIncludeSubtitlesKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.screenshotRoute(
            target: ScreenshotSettingsScreen.targetIncludeSubtitles,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'screenshot_save_path',
        title: l10n.settingsScreenshotSavePathTitle,
        subtitle: l10n.settingsScreenshotSavePathSubtitle,
        location: l10n.settingsLocationScreenshot,
        keywords: _keywords(l10n.settingsScreenshotSavePathKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.screenshotRoute(
            target: ScreenshotSettingsScreen.targetSavePath,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'screenshot_custom_directory',
        title: l10n.settingsScreenshotCustomDirectoryTitle,
        subtitle: l10n.settingsScreenshotCustomDirectorySubtitle,
        location: l10n.settingsLocationScreenshot,
        keywords: _keywords(l10n.settingsScreenshotCustomDirectoryKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.screenshotRoute(
            target: ScreenshotSettingsScreen.targetCustomDirectory,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'screenshot_preview',
        title: l10n.settingsScreenshotPreviewTitle,
        subtitle: l10n.settingsScreenshotPreviewSubtitle,
        location: l10n.settingsLocationScreenshot,
        keywords: _keywords(l10n.settingsScreenshotPreviewKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.screenshotRoute(
            target: ScreenshotSettingsScreen.targetPreview,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_quick_mode',
        title: l10n.settingsMpvQuickModeTitle,
        subtitle: l10n.settingsMpvQuickModeSubtitle,
        location: l10n.settingsLocationMpv,
        keywords: _keywords(l10n.settingsMpvQuickModeKeywords),
        onSelect: () =>
            _openSettingsDestination(context, SettingsDestinationRoutes.mpv),
      ),
      SettingsSearchEntry(
        id: 'mpv_picture',
        title: l10n.settingsMpvPictureTitle,
        subtitle: l10n.settingsMpvPictureSubtitle,
        location: l10n.settingsLocationMpv,
        keywords: _keywords(l10n.settingsMpvPictureKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.mpvRoute(
            section: MpvPlayerSettingsScreen.sectionPicture,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_audio',
        title: l10n.settingsMpvAudioTitle,
        subtitle: l10n.settingsMpvAudioSubtitle,
        location: l10n.settingsLocationMpv,
        keywords: _keywords(l10n.settingsMpvAudioKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.mpvRoute(
            section: MpvPlayerSettingsScreen.sectionAudio,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_playback',
        title: l10n.settingsMpvPlaybackTitle,
        subtitle: l10n.settingsMpvPlaybackSubtitle,
        location: l10n.settingsLocationMpv,
        keywords: _keywords(l10n.settingsMpvPlaybackKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.mpvRoute(
            section: MpvPlayerSettingsScreen.sectionPlayback,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'mpv_compatibility',
        title: l10n.settingsMpvCompatibilityTitle,
        subtitle: l10n.settingsMpvCompatibilitySubtitle,
        location: l10n.settingsLocationMpv,
        keywords: _keywords(l10n.settingsMpvCompatibilityKeywords),
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.mpvRoute(
            section: MpvPlayerSettingsScreen.sectionCompatibility,
          ),
        ),
      ),
    ];

    for (final definition in MpvSettingsL10n.definitions(l10n)) {
      entries.add(
        SettingsSearchEntry(
          id: 'mpv:${definition.key}',
          title: definition.title,
          subtitle: definition.description,
          location: l10n.settingsLocationMpvWithSection(
            _mpvLocationLabel(l10n, definition.key),
          ),
          keywords: <String>[
            'mpv',
            definition.shortTitle,
            definition.key,
            _mpvLocationLabel(l10n, definition.key),
          ],
          onSelect: () => _openSettingsDestination(
            context,
            SettingsDestinationRoutes.mpvRoute(settingKey: definition.key),
          ),
        ),
      );
    }

    return entries;
  }

  List<String> _keywords(String value) {
    return value
        .split('|')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  String _mpvLocationLabel(AppLocalizations l10n, String key) {
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
    if (pictureKeys.contains(key)) return l10n.settingsMpvPictureSection;
    if (audioKeys.contains(key)) return l10n.settingsMpvAudioSection;
    if (playbackKeys.contains(key)) return l10n.settingsMpvPlaybackSection;
    if (key == MpvSettingsCatalog.compatibilityKey) {
      return l10n.settingsMpvCompatibilitySection;
    }
    return l10n.settingsMpvTitle;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final localeProvider = context.watch<AppLocaleProvider>();
    final themeProvider = context.watch<AppThemeProvider>();
    final parallelSettings = context.watch<ParallelWindowSettingsProvider>();
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720;
    final titleSize = AdaptiveText.roleSize(
      compact ? 19 : 21,
      role: AdaptiveFontRole.title,
    );

    return FutureBuilder<bool>(
      future: EmbeddedDetailLauncher.isParallelWindowSupported(),
      builder: (context, snapshot) {
        final parallelWindowSupported = snapshot.data ?? false;
        final parallelSummary = parallelSettings.enabled
            ? (parallelSettings.primaryOnLeft
                  ? l10n.settingsParallelSummaryEnabledLeft
                  : l10n.settingsParallelSummaryEnabledRight)
            : l10n.settingsParallelSummaryDisabled;

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
              l10n.settingsTitle,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: titleSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: <Widget>[
              IconButton(
                onPressed: () => _openSettingsSearch(
                  context,
                  themeProvider,
                  parallelSummary,
                  parallelWindowSupported,
                ),
                icon: const Icon(Icons.search_rounded),
                tooltip: l10n.settingsSearchTooltip,
              ),
            ],
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  colors.backgroundElevated,
                  colors.backgroundBase,
                ],
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
                            _SettingsGroupCard(
                              children: <Widget>[
                                _SettingsEntryTile(
                                  icon: Icons.palette_outlined,
                                  title: l10n.settingsThemeTitle,
                                  subtitle: l10n.settingsThemeSubtitle(
                                    AppThemeL10n.currentThemeTitle(
                                      l10n,
                                      themeProvider,
                                    ),
                                    AppThemeL10n.currentThemeSubtitle(
                                      l10n,
                                      themeProvider,
                                    ),
                                  ),
                                  onTap: () {
                                    unawaited(
                                      _openSettingsDestination(
                                        context,
                                        SettingsDestinationRoutes.theme,
                                      ),
                                    );
                                  },
                                ),
                                const _SettingsGroupDivider(),
                                _SettingsEntryTile(
                                  icon: Icons.language_rounded,
                                  title: l10n.settingsLanguageTitle,
                                  subtitle:
                                      localeProvider.mode == AppLocaleMode.zhCN
                                      ? l10n.settingsLanguageSubtitleZhCN
                                      : l10n.settingsLanguageSubtitleSystem,
                                  onTap: () {
                                    unawaited(_openLanguageSheet(context));
                                  },
                                ),
                                const _SettingsGroupDivider(),
                                _SettingsEntryTile(
                                  icon: Icons.video_settings_rounded,
                                  title: l10n.settingsMpvTitle,
                                  subtitle: l10n.settingsMpvSubtitle,
                                  onTap: () {
                                    unawaited(
                                      _openSettingsDestination(
                                        context,
                                        SettingsDestinationRoutes.mpv,
                                      ),
                                    );
                                  },
                                ),
                                if (parallelWindowSupported) ...<Widget>[
                                  const _SettingsGroupDivider(),
                                  _SettingsEntryTile(
                                    icon: Icons.splitscreen_outlined,
                                    title: l10n.settingsParallelWindowTitle,
                                    subtitle: parallelSummary,
                                    onTap: () {
                                      unawaited(
                                        _openSettingsDestination(
                                          context,
                                          SettingsDestinationRoutes
                                              .parallelWindow,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                const _SettingsGroupDivider(),
                                _SettingsEntryTile(
                                  icon: Icons.storage_rounded,
                                  title: l10n.settingsStorageTitle,
                                  subtitle: l10n.settingsStorageSubtitle,
                                  onTap: () {
                                    unawaited(
                                      _openSettingsDestination(
                                        context,
                                        SettingsDestinationRoutes.storage,
                                      ),
                                    );
                                  },
                                ),
                                const _SettingsGroupDivider(),
                                _SettingsEntryTile(
                                  icon: Icons.download_rounded,
                                  title: l10n.settingsDownloadTitle,
                                  subtitle: l10n.settingsDownloadSubtitle,
                                  onTap: () {
                                    unawaited(
                                      _openSettingsDestination(
                                        context,
                                        SettingsDestinationRoutes.downloads,
                                      ),
                                    );
                                  },
                                ),
                                const _SettingsGroupDivider(),
                                _SettingsEntryTile(
                                  icon: Icons.bar_chart_rounded,
                                  title: l10n.settingsPlayStatsTitle,
                                  subtitle: l10n.settingsPlayStatsSubtitle,
                                  onTap: () {
                                    unawaited(
                                      _openSettingsDestination(
                                        context,
                                        SettingsDestinationRoutes.playStats,
                                      ),
                                    );
                                  },
                                ),
                                const _SettingsGroupDivider(),
                                _SettingsEntryTile(
                                  icon: Icons.more_horiz_rounded,
                                  title: l10n.settingsOtherTitle,
                                  subtitle: l10n.settingsOtherSubtitle,
                                  onTap: () {
                                    unawaited(
                                      _openSettingsDestination(
                                        context,
                                        SettingsDestinationRoutes.other,
                                      ),
                                    );
                                  },
                                ),
                                const _SettingsGroupDivider(),
                                _SettingsEntryTile(
                                  icon: Icons.receipt_long_outlined,
                                  title: l10n.settingsLogTitle,
                                  subtitle: l10n.settingsLogSubtitle,
                                  onTap: () {
                                    unawaited(
                                      _openSettingsDestination(
                                        context,
                                        SettingsDestinationRoutes.logs,
                                      ),
                                    );
                                  },
                                ),
                              ],
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
      },
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  final AppLocaleMode mode;
  final AppLocaleMode groupValue;
  final String title;
  final String subtitle;
  final VoidCallback onSelected;

  const _LanguageOptionTile({
    required this.mode,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = mode == groupValue;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onSelected,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected ? colors.accent : colors.textMuted,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: AdaptiveText.roleSize(15.5),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: AdaptiveText.roleSize(13),
        ),
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
