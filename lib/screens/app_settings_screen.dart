import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../desktop/desktop.dart';
import '../l10n/generated/app_localizations.dart';
import '../playback/settings/mpv_settings_l10n.dart';
import '../playback/settings/mpv_settings_store.dart';
import '../providers/app_locale_provider.dart';
import '../providers/app_theme_provider.dart';
import '../providers/nas_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../providers/startup_preferences_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/fn_connect_web_session_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_l10n.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/main_navigation_metrics.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/app_top_tip.dart';
import 'mpv_player_settings_screen.dart';
import 'screenshot_settings_screen.dart';
import 'settings_search_screen.dart';
import 'settings_destination_routes.dart';

class AppSettingsScreen extends StatelessWidget {
  final bool secondaryHost;

  const AppSettingsScreen({super.key, this.secondaryHost = false});

  Future<void> _setStartupPosterHome(
    BuildContext context,
    StartupPreferencesProvider preferences,
    bool value,
  ) async {
    try {
      await preferences.setOpenPosterHomeOnStartup(value);
    } catch (error, stackTrace) {
      await AppErrorReporter.report(
        error,
        action: 'save startup poster home preference',
        source: 'app_settings_screen',
        stackTrace: stackTrace,
        fallbackKind: AppExceptionKind.transient,
      );
      if (!context.mounted) return;
      AppTopTip().show(
        context,
        message: AppLocalizations.of(context).commonOperationFailedRetryLater,
        color: context.appColors.danger,
      );
    }
  }

  Future<void> _openSettingsDestination(
    BuildContext context,
    String routeName,
  ) async {
    if (DesktopEnvironment.isDesktopPlatform) {
      // 桌面端：设置区内双栏（网格 | 子页列），条目在右侧子页列打开，
      // 分组网格与左侧应用侧栏均保持可见。
      final area = _DesktopSettingsAreaScope.maybeOf(context);
      if (area != null) {
        area.openDestination(routeName);
        return;
      }
      // 窄桌面窗口（未启用设置区双栏）回落整页导航。
      unawaited(Navigator.of(context).pushNamed(routeName));
      return;
    }
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
              color: sheetContext.appModalBackgroundColor,
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

  Future<void> _resetFnConnectWebLoginState(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.fnConnectReloginTitle,
      content: l10n.fnConnectReloginContent,
      cancelText: l10n.commonCancel,
      confirmText: l10n.fnConnectReloginConfirm,
      confirmColor: context.appColors.warning,
    );
    if (!context.mounted || !confirmed) return;

    try {
      await FnConnectWebSessionService.clearLoginState();
      if (!context.mounted) return;
      AppTopTip().show(
        context,
        message: l10n.fnConnectReloginSuccess,
        color: context.appColors.accent,
      );
      await context.read<NasProvider>().logout();
    } catch (error, stackTrace) {
      await AppErrorReporter.report(
        error,
        action: 'clear fn connect web login state',
        source: 'app_settings_screen',
        stackTrace: stackTrace,
        fallbackKind: AppExceptionKind.transient,
      );
      if (!context.mounted) return;
      AppTopTip().show(
        context,
        message: l10n.fnConnectReloginFailure,
        color: context.appColors.danger,
      );
    }
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
        id: 'startup_poster_home',
        title: l10n.settingsStartupPosterHomeTitle,
        subtitle: l10n.settingsStartupPosterHomeSubtitle,
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.settingsStartupPosterHomeKeywords),
        onSelect: () async {},
      ),
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
        id: 'fn_connect_relogin',
        title: l10n.fnConnectReloginTitle,
        subtitle: l10n.fnConnectReloginSubtitle,
        location: l10n.settingsLocationRoot,
        keywords: _keywords(l10n.fnConnectReloginKeywords),
        onSelect: () => _resetFnConnectWebLoginState(context),
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

  // ---------------------------------------------------------------------------
  // 设置首页条目（单栏列表与桌面双栏右栏共用，行为必须保持一致）。
  // ---------------------------------------------------------------------------

  Widget _themeEntryTile(
    BuildContext context,
    AppLocalizations l10n,
    AppThemeProvider themeProvider,
  ) {
    return _SettingsEntryTile(
      icon: Icons.palette_outlined,
      title: l10n.settingsThemeTitle,
      subtitle: l10n.settingsThemeSubtitle(
        AppThemeL10n.currentThemeTitle(l10n, themeProvider),
        AppThemeL10n.currentThemeSubtitle(l10n, themeProvider),
      ),
      onTap: () {
        unawaited(
          _openSettingsDestination(context, SettingsDestinationRoutes.theme),
        );
      },
    );
  }

  Widget _languageEntryTile(
    BuildContext context,
    AppLocalizations l10n,
    AppLocaleProvider localeProvider,
  ) {
    return _SettingsEntryTile(
      icon: Icons.language_rounded,
      title: l10n.settingsLanguageTitle,
      subtitle: localeProvider.mode == AppLocaleMode.zhCN
          ? l10n.settingsLanguageSubtitleZhCN
          : l10n.settingsLanguageSubtitleSystem,
      onTap: () {
        unawaited(_openLanguageSheet(context));
      },
    );
  }

  Widget _startupPosterHomeEntryTile(
    BuildContext context,
    AppLocalizations l10n,
    StartupPreferencesProvider startupPreferences,
  ) {
    return _SettingsSwitchTile(
      icon: Icons.slideshow_rounded,
      title: l10n.settingsStartupPosterHomeTitle,
      subtitle: l10n.settingsStartupPosterHomeSubtitle,
      value: startupPreferences.openPosterHomeOnStartup,
      onChanged: startupPreferences.isReady
          ? (value) => unawaited(
              _setStartupPosterHome(context, startupPreferences, value),
            )
          : null,
    );
  }

  Widget _mpvEntryTile(BuildContext context, AppLocalizations l10n) {
    return _SettingsEntryTile(
      icon: Icons.video_settings_rounded,
      title: l10n.settingsMpvTitle,
      subtitle: l10n.settingsMpvSubtitle,
      onTap: () {
        unawaited(
          _openSettingsDestination(context, SettingsDestinationRoutes.mpv),
        );
      },
    );
  }

  Widget _parallelWindowEntryTile(
    BuildContext context,
    AppLocalizations l10n,
    String parallelSummary,
  ) {
    return _SettingsEntryTile(
      icon: Icons.splitscreen_outlined,
      title: l10n.settingsParallelWindowTitle,
      subtitle: parallelSummary,
      onTap: () {
        unawaited(
          _openSettingsDestination(
            context,
            SettingsDestinationRoutes.parallelWindow,
          ),
        );
      },
    );
  }

  Widget _storageEntryTile(BuildContext context, AppLocalizations l10n) {
    return _SettingsEntryTile(
      icon: Icons.storage_rounded,
      title: l10n.settingsStorageTitle,
      subtitle: l10n.settingsStorageSubtitle,
      onTap: () {
        unawaited(
          _openSettingsDestination(context, SettingsDestinationRoutes.storage),
        );
      },
    );
  }

  Widget _downloadsEntryTile(BuildContext context, AppLocalizations l10n) {
    return _SettingsEntryTile(
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
    );
  }

  Widget _playStatsEntryTile(BuildContext context, AppLocalizations l10n) {
    return _SettingsEntryTile(
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
    );
  }

  Widget _otherEntryTile(BuildContext context, AppLocalizations l10n) {
    return _SettingsEntryTile(
      icon: Icons.more_horiz_rounded,
      title: l10n.settingsOtherTitle,
      subtitle: l10n.settingsOtherSubtitle,
      onTap: () {
        unawaited(
          _openSettingsDestination(context, SettingsDestinationRoutes.other),
        );
      },
    );
  }

  Widget _logsEntryTile(BuildContext context, AppLocalizations l10n) {
    return _SettingsEntryTile(
      icon: Icons.receipt_long_outlined,
      title: l10n.settingsLogTitle,
      subtitle: l10n.settingsLogSubtitle,
      onTap: () {
        unawaited(
          _openSettingsDestination(context, SettingsDestinationRoutes.logs),
        );
      },
    );
  }

  Widget _fnConnectReloginEntryTile(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return _SettingsEntryTile(
      icon: Icons.cloud_sync_outlined,
      title: l10n.fnConnectReloginTitle,
      subtitle: l10n.fnConnectReloginShortSubtitle,
      onTap: () {
        unawaited(_resetFnConnectWebLoginState(context));
      },
    );
  }

  /// 桌面端设置分组定义：条目指向与移动端单栏列表一致，
  /// 行组件为桌面紧凑样式（行尾当前值预览）。
  List<_SettingsSection> _buildDesktopSettingsSections(
    BuildContext context, {
    required AppLocalizations l10n,
    required AppLocaleProvider localeProvider,
    required AppThemeProvider themeProvider,
    required StartupPreferencesProvider startupPreferences,
    required bool parallelWindowSupported,
    required String parallelSummary,
  }) {
    final languageValue = localeProvider.mode == AppLocaleMode.zhCN
        ? l10n.settingsLanguageSubtitleZhCN
        : l10n.settingsLanguageSubtitleSystem;
    return <_SettingsSection>[
      // 通用：语言 / 启动直达 / FN Connect 重登。
      _SettingsSection(
        id: 'general',
        icon: Icons.tune_rounded,
        title: l10n.settingsSectionGeneral,
        rows: <_DesktopRowData>[
          _DesktopRowData(
            icon: Icons.language_rounded,
            title: l10n.settingsLanguageTitle,
            subtitle: languageValue,
            value: languageValue,
            onTap: () => unawaited(_openLanguageSheet(context)),
          ),
          _DesktopRowData(
            icon: Icons.slideshow_rounded,
            title: l10n.settingsStartupPosterHomeTitle,
            subtitle: l10n.settingsStartupPosterHomeSubtitle,
            switchValue: startupPreferences.openPosterHomeOnStartup,
            onSwitch: startupPreferences.isReady
                ? (value) => unawaited(
                    _setStartupPosterHome(context, startupPreferences, value),
                  )
                : null,
            switchKey: 'startup_poster_home_switch',
          ),
          _DesktopRowData(
            icon: Icons.cloud_sync_outlined,
            title: l10n.fnConnectReloginTitle,
            subtitle: l10n.fnConnectReloginShortSubtitle,
            onTap: () => unawaited(_resetFnConnectWebLoginState(context)),
          ),
        ],
      ),
      // 外观与播放：主题 / MPV / 分屏窗口。
      _SettingsSection(
        id: 'playback',
        icon: Icons.video_settings_rounded,
        title: l10n.settingsSectionPlayback,
        rows: <_DesktopRowData>[
          _DesktopRowData(
            icon: Icons.palette_outlined,
            title: l10n.settingsThemeTitle,
            subtitle: l10n.settingsThemeSubtitle(
              AppThemeL10n.currentThemeTitle(l10n, themeProvider),
              AppThemeL10n.currentThemeSubtitle(l10n, themeProvider),
            ),
            value: AppThemeL10n.currentThemeTitle(l10n, themeProvider),
            valueActive: true,
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.theme,
            ),
          ),
          _DesktopRowData(
            icon: Icons.video_settings_rounded,
            title: l10n.settingsMpvTitle,
            subtitle: l10n.settingsMpvSubtitle,
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.mpv,
            ),
          ),
          if (parallelWindowSupported)
            _DesktopRowData(
              icon: Icons.splitscreen_outlined,
              title: l10n.settingsParallelWindowTitle,
              subtitle: parallelSummary,
              onTap: () => _openSettingsDestination(
                context,
                SettingsDestinationRoutes.parallelWindow,
              ),
            ),
        ],
      ),
      // 数据与下载：储存 / 下载 / 播放统计。
      _SettingsSection(
        id: 'data',
        icon: Icons.storage_rounded,
        title: l10n.settingsSectionData,
        rows: <_DesktopRowData>[
          _DesktopRowData(
            icon: Icons.storage_rounded,
            title: l10n.settingsStorageTitle,
            subtitle: l10n.settingsStorageSubtitle,
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.storage,
            ),
          ),
          _DesktopRowData(
            icon: Icons.download_rounded,
            title: l10n.settingsDownloadTitle,
            subtitle: l10n.settingsDownloadSubtitle,
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.downloads,
            ),
          ),
          _DesktopRowData(
            icon: Icons.bar_chart_rounded,
            title: l10n.settingsPlayStatsTitle,
            subtitle: l10n.settingsPlayStatsSubtitle,
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.playStats,
            ),
          ),
        ],
      ),
      // 系统：其他 / 日志。
      _SettingsSection(
        id: 'system',
        icon: Icons.more_horiz_rounded,
        title: l10n.settingsSectionSystem,
        rows: <_DesktopRowData>[
          _DesktopRowData(
            icon: Icons.more_horiz_rounded,
            title: l10n.settingsOtherTitle,
            subtitle: l10n.settingsOtherSubtitle,
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.other,
            ),
          ),
          _DesktopRowData(
            icon: Icons.receipt_long_outlined,
            title: l10n.settingsLogTitle,
            subtitle: l10n.settingsLogSubtitle,
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.logs,
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final localeProvider = context.watch<AppLocaleProvider>();
    final themeProvider = context.watch<AppThemeProvider>();
    final parallelSettings = context.watch<ParallelWindowSettingsProvider>();
    final startupPreferences = context.watch<StartupPreferencesProvider>();
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720;
    final titleSize = AdaptiveText.roleSize(
      compact ? 19 : 21,
      role: AdaptiveFontRole.title,
    );

    return FutureBuilder<bool>(
      future: EmbeddedDetailLauncher.isParallelWindowSupported(),
      builder: (context, snapshot) {
        // 桌面端分屏由本壳层实现（设置开关 ↔ DesktopSplitController），
        // 不依赖 Android 宿主通道应答，「分屏窗口」入口常驻。
        final parallelWindowSupported =
            snapshot.data == true || DesktopEnvironment.isDesktopPlatform;
        final parallelSummary = parallelSettings.enabled
            ? (parallelSettings.primaryOnLeft
                  ? l10n.settingsParallelSummaryEnabledLeft
                  : l10n.settingsParallelSummaryEnabledRight)
            : l10n.settingsParallelSummaryDisabled;

        if (DesktopEnvironment.isDesktopPlatform &&
            !secondaryHost &&
            media.size.width >= DesktopBreakpoints.sidebarMinWidth) {
          // 桌面端：设置区自带 AppBar 与内部导航（分组卡片网格首页），
          // 子页在该 Navigator 内推入，只替换内容区、保留左侧应用侧栏。
          return _DesktopSettingsArea(
            key: const ValueKey<String>('desktop_settings_area'),
            bottomInset: MainNavigationMetrics.contentBottomInset(
              media.viewPadding.bottom,
            ),
            buildSections: (context) => _buildDesktopSettingsSections(
              context,
              l10n: AppLocalizations.of(context),
              localeProvider: context.watch<AppLocaleProvider>(),
              themeProvider: context.watch<AppThemeProvider>(),
              startupPreferences: context.watch<StartupPreferencesProvider>(),
              parallelWindowSupported: parallelWindowSupported,
              parallelSummary: parallelSummary,
            ),
            onOpenSearch: (context) => _openSettingsSearch(
              context,
              context.watch<AppThemeProvider>(),
              parallelSummary,
              parallelWindowSupported,
            ),
          );
        }

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
                  // 单栏设置列表：桌面宽视口由 maxWidth 收窄居中，
                  // 移动端 / 嵌入 pane 等窄视口同构，行为保持一致。
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
                        // 主窗口下内容延伸到悬浮导航条后方，需预留底栏高度；
                        // 分屏副窗没有底栏，维持原有留白。
                        secondaryHost
                            ? (compact ? 24 : 32)
                            : MainNavigationMetrics.contentBottomInset(
                                media.viewPadding.bottom,
                              ),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxContentWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _SettingsGroupCard(
                              children: <Widget>[
                                _themeEntryTile(context, l10n, themeProvider),
                                const _SettingsGroupDivider(),
                                _languageEntryTile(
                                  context,
                                  l10n,
                                  localeProvider,
                                ),
                                const _SettingsGroupDivider(),
                                _startupPosterHomeEntryTile(
                                  context,
                                  l10n,
                                  startupPreferences,
                                ),
                                const _SettingsGroupDivider(),
                                _mpvEntryTile(context, l10n),
                                if (parallelWindowSupported) ...<Widget>[
                                  const _SettingsGroupDivider(),
                                  _parallelWindowEntryTile(
                                    context,
                                    l10n,
                                    parallelSummary,
                                  ),
                                ],
                                const _SettingsGroupDivider(),
                                _storageEntryTile(context, l10n),
                                const _SettingsGroupDivider(),
                                _downloadsEntryTile(context, l10n),
                                const _SettingsGroupDivider(),
                                _playStatsEntryTile(context, l10n),
                                const _SettingsGroupDivider(),
                                _otherEntryTile(context, l10n),
                                const _SettingsGroupDivider(),
                                _logsEntryTile(context, l10n),
                                const _SettingsGroupDivider(),
                                _fnConnectReloginEntryTile(context, l10n),
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

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
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
            const SizedBox(width: 12),
            Switch.adaptive(
              key: const ValueKey<String>('startup_poster_home_switch'),
              value: value,
              onChanged: onChanged,
              // 显式取 AppThemeColors，跟随主题预设与动态取色。
              activeThumbColor: context.appColors.selection,
              activeTrackColor: context.appColors.selection.withValues(
                alpha: 0.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 桌面端设置行数据：紧凑行的静态描述，行组件按此渲染并支持搜索过滤。
class _DesktopRowData {
  final IconData icon;
  final String title;
  final String subtitle;

  /// 行尾等宽字体的当前值预览（如「跟随系统」「午夜」）。
  final String? value;

  /// 值是否高亮为强调色（如「已连接」「进行中」）。
  final bool valueActive;

  /// 整行点击动作；为 null 时行尾不显示 chevron。
  final VoidCallback? onTap;

  /// 非空时行尾渲染为开关（覆盖 value / chevron）。
  final bool? switchValue;
  final ValueChanged<bool>? onSwitch;

  /// 开关的测试语义键（可选）。
  final String? switchKey;

  const _DesktopRowData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.valueActive = false,
    this.onTap,
    this.switchValue,
    this.onSwitch,
    this.switchKey,
  });

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return title.toLowerCase().contains(normalized) ||
        subtitle.toLowerCase().contains(normalized);
  }
}

/// 桌面端设置分组：标题 + 图标 + 一组紧凑行。
class _SettingsSection {
  final String id;
  final IconData icon;
  final String title;
  final List<_DesktopRowData> rows;

  const _SettingsSection({
    required this.id,
    required this.icon,
    required this.title,
    required this.rows,
  });

  /// 按关键字过滤行；无匹配行时返回 null（整组隐藏）。
  _SettingsSection? filtered(String query) {
    final visible = rows.where((row) => row.matches(query)).toList();
    if (visible.isEmpty) return null;
    return _SettingsSection(id: id, icon: icon, title: title, rows: visible);
  }
}

/// 桌面端设置区：左栏分组卡片网格（二级）+ 右栏子页列（三级）。
/// 右栏由内部 Navigator 承载设置子页，滑入/滑出不替换网格、
/// 也不影响左侧应用侧栏；手机 / 平板不进入此分支。
class _DesktopSettingsArea extends StatefulWidget {
  final double bottomInset;
  final List<_SettingsSection> Function(BuildContext) buildSections;
  final void Function(BuildContext) onOpenSearch;

  const _DesktopSettingsArea({
    super.key,
    required this.bottomInset,
    required this.buildSections,
    required this.onOpenSearch,
  });

  @override
  State<_DesktopSettingsArea> createState() => _DesktopSettingsAreaState();
}

class _DesktopSettingsAreaState extends State<_DesktopSettingsArea> {
  static const double _subMinWidth = 430;
  static const double _subMaxWidth = 800;

  final GlobalKey<NavigatorState> _subNavKey = GlobalKey<NavigatorState>();

  /// 右栏当前栈顶路由名；'/' 表示未打开任何子页。
  String? _topRoute;

  bool get _subOpen => _topRoute != null && _topRoute != '/';

  void openDestination(String routeName) {
    if (_topRoute == routeName) return;
    _subNavKey.currentState?.pushNamed(routeName);
  }

  void openSearch() {
    final nav = _subNavKey.currentState;
    if (nav == null) return;
    widget.onOpenSearch(nav.context);
  }

  void _handleStackChanged(String? topRoute) {
    if (_topRoute == topRoute) return;
    // 初始 '/' 路由在首次 build 中同步 push，需延迟到帧末再 setState。
    final phase = SchedulerBinding.instance.schedulerPhase;
    void apply() {
      if (!mounted || _topRoute == topRoute) return;
      setState(() => _topRoute = topRoute);
    }

    if (phase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  Route<dynamic> _blankRoute(RouteSettings settings) {
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, __) =>
          Container(color: context.appColors.backgroundBase),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    if (name == '/' || name == SettingsDestinationRoutes.home) {
      return _blankRoute(settings);
    }
    final destination = SettingsDestinationRoutes.buildRoute(name);
    if (destination == null) {
      return _blankRoute(settings);
    }
    return AppTransitions.leftToRightPageTurnRoute<void>(
      _DesktopSettingsSubPage(child: destination),
      settings: settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _DesktopSettingsAreaScope(
      state: this,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final openWidth = math
              .max(constraints.maxWidth * 0.45, _subMinWidth)
              .clamp(0.0, _subMaxWidth)
              .toDouble();
          final subWidth = _subOpen ? openWidth : 0.0;
          return Row(
            key: const ValueKey<String>('desktop_settings_two_pane_row'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _DesktopSettingsGrid(
                  sections: widget.buildSections(context),
                  bottomInset: widget.bottomInset,
                ),
              ),
              // 右栏：设置子页列（三级），开启时以 1px 竖线与网格分隔。
              // 动画期间子页按目标宽度布局（OverflowBox），仅滑入/滑出裁剪，
              // 避免中间帧内容被压缩重排。
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: subWidth,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: _subOpen
                          ? colors.borderSubtle
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: openWidth,
                    maxWidth: openWidth,
                    child: KeyedSubtree(
                      key: const ValueKey<String>('desktop_settings_navigator'),
                      child: Navigator(
                        key: _subNavKey,
                        initialRoute: '/',
                        observers: <NavigatorObserver>[
                          _SettingsAreaNavObserver(_handleStackChanged),
                        ],
                        onGenerateRoute: _onGenerateRoute,
                        onUnknownRoute: _onGenerateRoute,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 设置区内部导航栈观察：同步右栏开合状态（栈顶离开 '/' 即视为打开）。
class _SettingsAreaNavObserver extends NavigatorObserver {
  final ValueChanged<String?> onTopRouteChanged;

  _SettingsAreaNavObserver(this.onTopRouteChanged);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onTopRouteChanged(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onTopRouteChanged(previousRoute?.settings.name ?? '/');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onTopRouteChanged(newRoute?.settings.name);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onTopRouteChanged(previousRoute?.settings.name ?? '/');
  }
}

/// 设置区能力作用域：条目 / 搜索入口经此打开右栏子页，
/// 不感知 Navigator 层级。
class _DesktopSettingsAreaScope extends InheritedWidget {
  final _DesktopSettingsAreaState state;

  const _DesktopSettingsAreaScope({required this.state, required super.child});

  static _DesktopSettingsAreaState? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DesktopSettingsAreaScope>()
        ?.state;
  }

  @override
  bool updateShouldNotify(_DesktopSettingsAreaScope oldWidget) => false;
}

/// 设置区首页（设计稿「放映控制台」）：页头标题 + 即时过滤搜索框，
/// 分组卡片网格（宽视口双列，窄视口单列），行尾当前值预览。
class _DesktopSettingsGrid extends StatefulWidget {
  final List<_SettingsSection> sections;
  final double bottomInset;

  static const double _gridMaxWidth = 1128;
  static const double _twoColumnMinWidth = 1000;

  const _DesktopSettingsGrid({
    required this.sections,
    required this.bottomInset,
  });

  @override
  State<_DesktopSettingsGrid> createState() => _DesktopSettingsGridState();
}

class _DesktopSettingsGridState extends State<_DesktopSettingsGrid> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  int get _totalRows =>
      widget.sections.fold<int>(0, (sum, section) => sum + section.rows.length);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final visibleSections = widget.sections
        .map((section) => section.filtered(_query))
        .whereType<_SettingsSection>()
        .toList();
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: _DesktopSettingsAtmosphere(
        child: SafeArea(
          top: false,
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () =>
                  _searchFocus.requestFocus(),
            },
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(40, 26, 40, widget.bottomInset + 28),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _DesktopSettingsGrid._gridMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildHeader(context, l10n),
                      const SizedBox(height: 26),
                      if (visibleSections.isEmpty)
                        _DesktopSearchEmptyHint(
                          text: l10n.settingsDesktopSearchEmpty,
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns =
                                constraints.maxWidth >=
                                _DesktopSettingsGrid._twoColumnMinWidth;
                            final leftSections = <_SettingsSection>[];
                            final rightSections = <_SettingsSection>[];
                            for (var i = 0; i < visibleSections.length; i++) {
                              (i.isEven ? leftSections : rightSections).add(
                                visibleSections[i],
                              );
                            }
                            final Widget content = twoColumns
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Expanded(
                                        child: _buildSectionColumn(
                                          context,
                                          leftSections,
                                        ),
                                      ),
                                      const SizedBox(width: 28),
                                      Expanded(
                                        child: _buildSectionColumn(
                                          context,
                                          rightSections,
                                        ),
                                      ),
                                    ],
                                  )
                                : _buildSectionColumn(context, visibleSections);
                            return content;
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    l10n.settingsTitle,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(
                        24,
                        role: AdaptiveFontRole.title,
                      ),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 标题后的强调色短划：放映光束的品牌记号。
                  Container(
                    width: 26,
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(
                        colors: <Color>[
                          colors.selection,
                          colors.selection.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${l10n.settingsDesktopSummary(widget.sections.length, _totalRows)}　'
                '${l10n.settingsDesktopSummaryHint}',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: AdaptiveText.roleSize(12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        _buildSearchField(context, l10n),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context, AppLocalizations l10n) {
    final colors = context.appColors;
    final hasQuery = _query.trim().isNotEmpty;
    return Container(
      width: 292,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, size: 15, color: colors.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: (value) => setState(() => _query = value),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: AdaptiveText.roleSize(13),
              ),
              cursorColor: colors.selection,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: l10n.settingsSearchHint,
                hintStyle: TextStyle(
                  color: colors.textMuted,
                  fontSize: AdaptiveText.roleSize(13),
                ),
              ),
            ),
          ),
          if (hasQuery)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: colors.textMuted,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Text(
                'Ctrl K',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: AdaptiveText.roleSize(10),
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionColumn(
    BuildContext context,
    List<_SettingsSection> list,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < list.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 26),
          _DesktopReveal(
            delay: Duration(milliseconds: 50 * i),
            child: _buildSection(context, list[i]),
          ),
        ],
      ],
    );
  }

  Widget _buildSection(BuildContext context, _SettingsSection section) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.selectionSoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Icon(section.icon, size: 13, color: colors.selection),
              ),
              const SizedBox(width: 9),
              Text(
                section.title,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(13),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                '${section.rows.length}',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: AdaptiveText.roleSize(10.5),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        // 分组卡片：发丝边框 + 微弱顶亮渐变；行间分割线避开图标栏。
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[colors.surfaceSubtle, colors.surface],
            ),
            border: Border.all(color: colors.borderSubtle),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              for (var i = 0; i < section.rows.length; i++) ...<Widget>[
                if (i > 0) const _DesktopGroupDivider(),
                _DesktopSettingsRow(data: section.rows[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 分组入场动画：按序号错峰上浮淡入。
class _DesktopReveal extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _DesktopReveal({required this.delay, required this.child});

  @override
  State<_DesktopReveal> createState() => _DesktopRevealState();
}

class _DesktopRevealState extends State<_DesktopReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 14, end: _visible ? 0 : 14),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, offset, child) =>
            Transform.translate(offset: Offset(0, offset), child: child),
        child: widget.child,
      ),
    );
  }
}

/// 桌面紧凑设置行：34px 图标位 + 标题/描述 + 行尾当前值或开关。
/// 悬停时图标「点亮」为强调色，chevron 右移。
class _DesktopSettingsRow extends StatelessWidget {
  final _DesktopRowData data;

  const _DesktopSettingsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return DesktopHoverRegion(
      onTap: data.onTap,
      builder: (context, hovering) {
        final colors = context.appColors;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          color: hovering ? colors.surfaceSubtle : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              // 图标位：悬停点亮为强调色。
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: hovering ? colors.selectionSoft : colors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: hovering ? colors.selection : colors.borderSubtle,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  data.icon,
                  size: 16,
                  color: hovering ? colors.selection : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: AdaptiveText.roleSize(13.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (data.switchValue != null)
                Switch.adaptive(
                  key: data.switchKey == null
                      ? null
                      : ValueKey<String>(data.switchKey!),
                  value: data.switchValue!,
                  onChanged: data.onSwitch,
                  // 显式取 AppThemeColors，跟随主题预设与动态取色。
                  activeThumbColor: colors.selection,
                  activeTrackColor: colors.selection.withValues(alpha: 0.45),
                )
              else ...<Widget>[
                if (data.value != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      data.value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: data.valueActive
                            ? colors.selection
                            : colors.textMuted,
                        fontSize: AdaptiveText.roleSize(12),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                if (data.onTap != null) const SizedBox(width: 10),
                if (data.onTap != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    transform: Matrix4.translationValues(
                      hovering ? 3 : 0,
                      0,
                      0,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: hovering ? colors.textSecondary : colors.textMuted,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 桌面分组行分割线：左端避开图标栏，与设计稿的发丝线对齐。
class _DesktopGroupDivider extends StatelessWidget {
  const _DesktopGroupDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(left: 64, right: 16),
      height: 1,
      color: colors.borderSubtle,
    );
  }
}

/// 搜索无结果提示。
class _DesktopSearchEmptyHint extends StatelessWidget {
  final String text;

  const _DesktopSearchEmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Center(
        child: Column(
          children: <Widget>[
            Icon(Icons.search_off_rounded, size: 34, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(
              text,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: AdaptiveText.roleSize(13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置子页容器：桌面端统一外观 —— 基底底色 + 氛围光晕叠加在内容上方，
/// 内容宽度收敛居中；子页自身仍是完整 Scaffold（头部由
/// buildSecondaryHostAppBar 的桌面变体统一）。
class _DesktopSettingsSubPage extends StatelessWidget {
  final Widget child;

  const _DesktopSettingsSubPage({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.backgroundBase,
      child: _DesktopSettingsAtmosphere(
        overlay: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 桌面设置区氛围：右上「放映光束」+ 左下环境反光。
/// 颜色一律取自 [context.appColors] 的 selection 色，
/// 主题预设与动态取色切换时同步变化。
class _DesktopSettingsAtmosphere extends StatelessWidget {
  final Widget child;

  /// true：光晕叠加在内容上方（子页内容自带不透明背景时使用）。
  final bool overlay;

  const _DesktopSettingsAtmosphere({required this.child, this.overlay = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final beamAlpha = overlay ? 0.06 : 0.10;
    final beam = Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.9, -1.15),
              radius: 1.4,
              colors: <Color>[
                colors.selection.withValues(alpha: beamAlpha),
                colors.selection.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
    final floor = Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.05, 1.15),
              radius: 1.2,
              colors: <Color>[
                colors.selection.withValues(alpha: beamAlpha / 2),
                colors.selection.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
    if (overlay) {
      return Stack(
        children: <Widget>[
          Positioned.fill(child: child),
          beam,
          floor,
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
        ),
      ),
      child: Stack(
        children: <Widget>[
          beam,
          floor,
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
