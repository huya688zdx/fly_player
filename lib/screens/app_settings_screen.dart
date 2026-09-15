import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
import '../services/storage_access_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_l10n.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/main_navigation_metrics.dart';
import '../ui/player_pane_host_scope.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/app_ambient_page.dart';
import 'mpv_player_settings_screen.dart';
import 'screenshot_settings_screen.dart';
import 'settings_search_screen.dart';
import 'settings_destination_routes.dart';

/// 语言模式 → 设置行/搜索条目里展示的当前值（语言名本身不做翻译，用各自文字）。
String _languageModeValue(AppLocalizations l10n, AppLocaleMode mode) =>
    switch (mode) {
      AppLocaleMode.system => l10n.settingsLanguageSubtitleSystem,
      AppLocaleMode.zhCN => l10n.settingsLanguageSubtitleZhCN,
      AppLocaleMode.en => l10n.settingsLanguageSubtitleEn,
      AppLocaleMode.ja => l10n.settingsLanguageSubtitleJa,
    };

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
    // Account changes must stay in this engine so media and statistics share
    // the same live FlyAccountController after a binding switch.
    if (!DesktopEnvironment.isDesktopPlatform &&
        (routeName == SettingsDestinationRoutes.flyAccount ||
            routeName == SettingsDestinationRoutes.flyCatalog ||
            routeName == SettingsDestinationRoutes.flyData)) {
      unawaited(Navigator.of(context).pushNamed(routeName));
      return;
    }
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
    final entries = _buildSearchEntries(
      context,
      themeProvider,
      parallelSummary,
      parallelWindowSupported,
    );
    return Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        SettingsSearchScreen(entries: entries),
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
        id: 'language_settings',
        title: l10n.settingsLanguageTitle,
        subtitle: _languageModeValue(
          l10n,
          context.read<AppLocaleProvider>().mode,
        ),
        location: l10n.settingsLocationRoot,
        keywords: <String>[
          l10n.languageSystem,
          l10n.languageZhCN,
          l10n.languageEn,
          l10n.languageJa,
          'language',
        ],
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.language,
        ),
      ),
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
      if (DesktopEnvironment.isDesktopPlatform && DesktopEnvironment.isWindows)
        SettingsSearchEntry(
          id: 'external_player_settings',
          title: '外部播放器接入',
          subtitle: '使用 PotPlayer 播放并回报播放进度',
          location: l10n.settingsLocationRoot,
          keywords: const <String>['PotPlayer', '外部播放器', '字幕', '弹幕', '进度回报'],
          onSelect: () => _openSettingsDestination(
            context,
            SettingsDestinationRoutes.externalPlayer,
          ),
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
        id: 'fly_data_service',
        title: '账号与媒体来源',
        subtitle: '飞翔账号、飞牛与 Emby 连接',
        location: l10n.settingsLocationRoot,
        keywords: const ['NAS', '账号', '绑定', '飞牛', 'Emby', 'VPN'],
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.flyAccount,
        ),
      ),
      SettingsSearchEntry(
        id: 'fly_catalog',
        title: '已同步节目',
        subtitle: '节目海报与来源信息',
        location: l10n.settingsLocationRoot,
        keywords: const ['NAS', '节目', '番剧', '目录', '海报'],
        onSelect: () => _openSettingsDestination(
          context,
          SettingsDestinationRoutes.flyCatalog,
        ),
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
      if (MpvSettingsCatalog.isSettingAvailable(
        MpvSettingsCatalog.compatibilityKey,
      ))
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

    if (!StorageAccessService.supportsScreenshotLibrary) {
      entries.removeWhere((entry) => entry.id.startsWith('screenshot_'));
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

  /// 设置分组定义：全部形态共用（桌面双栏与手机/平板/窄窗单列网格
  /// 同构），行组件为紧凑样式（行尾当前值预览）。
  List<_SettingsSection> _buildDesktopSettingsSections(
    BuildContext context, {
    required AppLocalizations l10n,
    required AppLocaleProvider localeProvider,
    required AppThemeProvider themeProvider,
    required StartupPreferencesProvider startupPreferences,
    required bool parallelWindowSupported,
    required String parallelSummary,
  }) {
    final languageValue = _languageModeValue(l10n, localeProvider.mode);
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
            onTap: () => unawaited(
              _openSettingsDestination(
                context,
                SettingsDestinationRoutes.language,
              ),
            ),
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
          if (DesktopEnvironment.isDesktopPlatform &&
              DesktopEnvironment.isWindows)
            _DesktopRowData(
              icon: Icons.launch_rounded,
              title: '外部播放器接入',
              subtitle: '使用 PotPlayer 播放并回报播放进度',
              value: 'PotPlayer',
              onTap: () => _openSettingsDestination(
                context,
                SettingsDestinationRoutes.externalPlayer,
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
          _DesktopRowData(
            icon: Icons.cloud_sync_outlined,
            title: '账号与媒体来源',
            subtitle: '飞翔账号、飞牛与 Emby 连接',
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.flyAccount,
            ),
          ),
          _DesktopRowData(
            icon: Icons.video_library_outlined,
            title: '已同步节目',
            subtitle: '节目海报与来源信息',
            onTap: () => _openSettingsDestination(
              context,
              SettingsDestinationRoutes.flyCatalog,
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
    final l10n = AppLocalizations.of(context);
    final localeProvider = context.watch<AppLocaleProvider>();
    final themeProvider = context.watch<AppThemeProvider>();
    final parallelSettings = context.watch<ParallelWindowSettingsProvider>();
    final startupPreferences = context.watch<StartupPreferencesProvider>();
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720;

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

        if (DesktopEnvironment.isDesktopPlatform && !secondaryHost) {
          // 桌面端：设置区自带页头与内部导航（分组卡片网格首页），
          // 子页只替换设置内容区、保留左侧应用侧栏。子页形态跟随
          // 「并行窗口」开关：开 → 网格 | 右栏双栏；关 → 单屏铺满内容区。
          return _DesktopSettingsArea(
            key: const ValueKey<String>('desktop_settings_area'),
            bottomInset: MainNavigationMetrics.contentBottomInset(
              media.viewPadding.bottom,
            ),
            // 桌面壳已有副屏时不再嵌套第二套双栏。
            twoPane:
                parallelSettings.enabled &&
                PlayerPaneHostScope.maybeOf(context) == null,
            buildSections: (context) => _buildDesktopSettingsSections(
              context,
              l10n: AppLocalizations.of(context),
              localeProvider: context.watch<AppLocaleProvider>(),
              themeProvider: context.watch<AppThemeProvider>(),
              startupPreferences: context.watch<StartupPreferencesProvider>(),
              parallelWindowSupported: parallelWindowSupported,
              parallelSummary: parallelSummary,
            ),
            buildSearchEntries: (context) => _buildSearchEntries(
              context,
              // 事件回调里不得再 watch：复用 build 阶段已取好的 provider。
              themeProvider,
              parallelSummary,
              parallelWindowSupported,
            ),
          );
        }

        // 手机 / 平板 / 窄桌面窗 / 分屏副窗：与桌面设置区同构的分组卡片
        // 首页（窄视口自动单列），子页仍走整页导航，观感与桌面双栏一致。
        return _DesktopSettingsGrid(
          sections: _buildDesktopSettingsSections(
            context,
            l10n: l10n,
            localeProvider: localeProvider,
            themeProvider: themeProvider,
            startupPreferences: startupPreferences,
            parallelWindowSupported: parallelWindowSupported,
            parallelSummary: parallelSummary,
          ),
          bottomInset: secondaryHost
              ? (compact ? 24.0 : 32.0)
              : MainNavigationMetrics.contentBottomInset(
                  media.viewPadding.bottom,
                ).toDouble(),
          leading: secondaryHost
              ? IconButton(
                  onPressed: () {
                    EmbeddedDetailLauncher.closeHostOrPop(context);
                  },
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                )
              : null,
          buildSearchEntries: (context) => _buildSearchEntries(
            context,
            themeProvider,
            parallelSummary,
            parallelWindowSupported,
          ),
          onOpenFullSearch: () => _openSettingsSearch(
            context,
            themeProvider,
            parallelSummary,
            parallelWindowSupported,
          ),
        );
      },
    );
  }
}

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
}

/// 桌面端设置区：分组卡片网格首页 + 内部导航承载设置子页（三级），
/// 不替换内容区外的布局、也不影响左侧应用侧栏。
/// 子页形态跟随「并行窗口」开关：开且内容区够宽 → 网格 | 右栏双栏；
/// 关（或内容区不够宽）→ 单屏，子页整区铺开、返回即回网格。
class _DesktopSettingsArea extends StatefulWidget {
  final double bottomInset;
  final List<_SettingsSection> Function(BuildContext) buildSections;
  final List<SettingsSearchEntry> Function(BuildContext) buildSearchEntries;

  /// 「并行窗口」开关：true 时子页在右栏并排打开，false 时单屏铺满。
  final bool twoPane;

  const _DesktopSettingsArea({
    super.key,
    required this.bottomInset,
    required this.buildSections,
    required this.buildSearchEntries,
    required this.twoPane,
  });

  @override
  State<_DesktopSettingsArea> createState() => _DesktopSettingsAreaState();
}

class _DesktopSettingsAreaState extends State<_DesktopSettingsArea> {
  static const double _subMinWidth = 430;
  static const double _subMaxWidth = 800;

  /// 双栏的最低内容区宽度：低于此值即使并行开启也退单屏，
  /// 避免网格被压到不可读。
  static const double _twoPaneMinWidth = 900;

  final GlobalKey<NavigatorState> _subNavKey = GlobalKey<NavigatorState>();

  /// 单屏模式的内部导航键：与双栏右栏分开，避免形态切换时
  /// GlobalKey 复用把首页路由搬进隐形右栏。
  final GlobalKey<NavigatorState> _singlePaneNavKey =
      GlobalKey<NavigatorState>();

  /// 当前帧实际生效的形态（build 中同步），供打开子页时选键。
  bool _twoPaneActive = false;

  /// 右栏当前栈顶路由名；'/' 表示未打开任何子页。
  String? _topRoute;

  bool get _subOpen => _topRoute != null && _topRoute != '/';

  Future<void> openDestination(String routeName) async {
    final paneHost = PlayerPaneHostScope.maybeOf(context);
    if (paneHost != null && await paneHost.openRoute(routeName)) return;
    if (!mounted || _topRoute == routeName) return;
    (_twoPaneActive ? _subNavKey : _singlePaneNavKey).currentState?.pushNamed(
      routeName,
    );
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
      // 双栏模式 '/' 仅占位：透出壳层整窗晕染，与网格右缘无缝衔接。
      pageBuilder: (context, _, __) => const SizedBox.expand(),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    if (name == '/' || name == SettingsDestinationRoutes.home) {
      // 单屏模式：'/' 即分组卡片首页（经作用域取最新分组数据）；
      // 双栏模式网格在导航器外，'/' 只占位。
      if (!_twoPaneActive) {
        return PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => const _DesktopSettingsHomeView(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              AppTransitions.leftToRightPageTurnTransition(
                child,
                animation,
                secondaryAnimation,
                context,
              ),
        );
      }
      return _blankRoute(settings);
    }
    final destination = SettingsDestinationRoutes.buildRoute(name);
    if (destination == null) {
      return _blankRoute(settings);
    }
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => _DesktopSettingsSubPage(
        alignToGrid: !_twoPaneActive,
        child: destination,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          AppTransitions.leftToRightPageTurnTransition(
            child,
            animation,
            secondaryAnimation,
            context,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final content = _DesktopSettingsAreaScope(
      state: this,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 「并行窗口」关闭或内容区不够宽时退单屏：子页整区铺开，
          // 返回即回网格，应用侧栏始终保留。
          final twoPane =
              widget.twoPane && constraints.maxWidth >= _twoPaneMinWidth;
          _twoPaneActive = twoPane;
          if (!twoPane) {
            return KeyedSubtree(
              key: const ValueKey<String>('desktop_settings_navigator'),
              child: Navigator(
                key: _singlePaneNavKey,
                initialRoute: '/',
                observers: <NavigatorObserver>[
                  _SettingsAreaNavObserver(_handleStackChanged),
                ],
                onGenerateRoute: _onGenerateRoute,
                onUnknownRoute: _onGenerateRoute,
              ),
            );
          }
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
                  buildSearchEntries: widget.buildSearchEntries,
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
    return AppAmbientPage(
      shareBackground: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            final navigator =
                (_twoPaneActive ? _subNavKey : _singlePaneNavKey).currentState;
            unawaited(navigator?.maybePop());
          },
        },
        child: content,
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

/// 设置区首页（设计稿「放映控制台」）：页头标题 + 统一搜索入口，
/// 分组卡片网格（宽视口双列，窄视口单列），行尾当前值预览。
/// 桌面双栏与手机/平板/窄窗单列形态共用此首页。
class _DesktopSettingsGrid extends StatefulWidget {
  final List<_SettingsSection> sections;
  final double bottomInset;

  /// 分屏副窗等宿主的返回钮（主窗口首页为 null）。
  final Widget? leading;

  /// 完整设置搜索入口（跨子页深搜）；null 时不显示入口。
  final VoidCallback? onOpenFullSearch;
  final List<SettingsSearchEntry> Function(BuildContext)? buildSearchEntries;

  static const double _gridMaxWidth = 1128;
  static const double _twoColumnMinWidth = 1000;

  const _DesktopSettingsGrid({
    required this.sections,
    required this.bottomInset,
    this.leading,
    this.onOpenFullSearch,
    this.buildSearchEntries,
  });

  @override
  State<_DesktopSettingsGrid> createState() => _DesktopSettingsGridState();
}

class _DesktopSettingsGridState extends State<_DesktopSettingsGrid> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchOverlay = OverlayPortalController();
  List<SettingsSearchEntry> _searchEntries = const [];

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_handleSearchFocus);
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocus() {
    if (_searchFocus.hasFocus) _openSearch();
  }

  void _openSearch() {
    if (!DesktopEnvironment.isDesktopPlatform) {
      widget.onOpenFullSearch?.call();
      return;
    }
    if (!_searchOverlay.isShowing) {
      _searchEntries = widget.buildSearchEntries!(context);
      _searchOverlay.show();
    }
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchOverlay.hide();
    _searchFocus.unfocus();
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < 720;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () =>
                  _openSearch(),
              if (defaultTargetPlatform == TargetPlatform.macOS)
                const SingleActivator(
                  LogicalKeyboardKey.keyK,
                  meta: true,
                ): () =>
                    _openSearch(),
            },
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 40,
                26,
                compact ? 16 : 40,
                widget.bottomInset + 28,
              ),
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final twoColumns =
                              constraints.maxWidth >=
                              _DesktopSettingsGrid._twoColumnMinWidth;
                          final leftSections = <_SettingsSection>[];
                          final rightSections = <_SettingsSection>[];
                          for (var i = 0; i < widget.sections.length; i++) {
                            (i.isEven ? leftSections : rightSections).add(
                              widget.sections[i],
                            );
                          }
                          final Widget content = twoColumns
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              : _buildSectionColumn(context, widget.sections);
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
    final compact = MediaQuery.sizeOf(context).width < 720;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (widget.leading != null) ...<Widget>[
              widget.leading!,
              const SizedBox(width: 10),
            ],
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
      ],
    );
    final searchField = _buildSearchField(context, l10n);
    // 分屏切换宽度时只改变排列方向，保留搜索框及弹层的挂载关系。
    return Flex(
      direction: compact ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: <Widget>[
        Flexible(flex: compact ? 0 : 1, fit: FlexFit.tight, child: titleBlock),
        SizedBox(width: compact ? 0 : 24, height: compact ? 14 : 0),
        searchField,
      ],
    );
  }

  Widget _buildSearchField(BuildContext context, AppLocalizations l10n) {
    final colors = context.appColors;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final field = InkWell(
      key: const ValueKey<String>('settings_open_full_search'),
      autofocus: !DesktopEnvironment.isDesktopPlatform,
      onTap: _openSearch,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: compact ? double.infinity : 292,
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
              child: DesktopEnvironment.isDesktopPlatform
                  ? TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      groupId: _searchController,
                      onTap: _openSearch,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: AdaptiveText.roleSize(13),
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.settingsSearchHint,
                        hintStyle: TextStyle(
                          color: colors.textMuted,
                          fontSize: AdaptiveText.roleSize(13),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                  : Text(
                      l10n.settingsSearchHint,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: AdaptiveText.roleSize(13),
                      ),
                    ),
            ),
            if (!compact)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Text(
                  defaultTargetPlatform == TargetPlatform.macOS
                      ? '⌘ K'
                      : 'Ctrl K',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: AdaptiveText.roleSize(10),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (!DesktopEnvironment.isDesktopPlatform) return field;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _searchOverlay,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final width = math.min(520.0, info.overlaySize.width - 32);
        final left = (anchor.right - width).clamp(
          16.0,
          info.overlaySize.width - width - 16,
        );
        final top = anchor.bottom + 10;
        return Stack(
          children: <Widget>[
            Positioned(
              left: left,
              top: top,
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(
                    0.0,
                    math.min(480.0, info.overlaySize.height - top - 16),
                  ),
                ),
                child: TapRegion(
                  groupId: _searchController,
                  child: SettingsSearchScreen(
                    entries: _searchEntries,
                    asPanel: true,
                    controller: _searchController,
                    onClose: _closeSearch,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: TapRegion(
        groupId: _searchController,
        onTapOutside: (_) {
          if (_searchOverlay.isShowing) _closeSearch();
        },
        child: Focus(
          onKeyEvent: (_, event) {
            if (_searchOverlay.isShowing &&
                event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _closeSearch();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: field,
        ),
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
        // 设置分组透出氛围背景；行间分割线避开图标栏。
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                colors.surfaceSubtle.withValues(alpha: 0.22),
                colors.surface.withValues(alpha: 0.12),
              ],
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
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    _revealTimer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
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
        return Container(
          color: hovering
              ? colors.selection.withValues(alpha: 0.08)
              : Colors.transparent,
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

/// 单屏模式（并行窗口关闭）的设置首页路由页：经作用域取最新分组数据，
/// 与双栏模式的网格共用同一份数据源。
class _DesktopSettingsHomeView extends StatelessWidget {
  const _DesktopSettingsHomeView();

  @override
  Widget build(BuildContext context) {
    final area = _DesktopSettingsAreaScope.maybeOf(context);
    return _DesktopSettingsGrid(
      sections:
          area?.widget.buildSections(context) ?? const <_SettingsSection>[],
      bottomInset: area?.widget.bottomInset ?? 0,
      buildSearchEntries: area?.widget.buildSearchEntries,
    );
  }
}

/// 设置子页容器：统一栅格对齐与页边距；子页仍是完整 Scaffold
/// （复用设置区背景，头部由 buildSecondaryHostAppBar 统一）。
class _DesktopSettingsSubPage extends StatelessWidget {
  final Widget child;

  /// 单屏模式：与首页网格同页边距（40 / 窄窗 16）与上限（1128），
  /// 进出子页时左右边缘与首页卡片对齐；滚动条由 [_SubPageEdgeScrollbar]
  /// 画在窗口右缘。双栏右栏维持原 940 居中（视口=栏宽，无悬空问题）。
  final bool alignToGrid;

  const _DesktopSettingsSubPage({
    required this.child,
    this.alignToGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (!alignToGrid) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 940),
          child: child,
        ),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 720;
    // 视口与首页网格同宽，内建滚动条会悬空在内容盒边缘；
    // 屏蔽后由 _SubPageEdgeScrollbar 监听滚动指标、画在窗口右缘。
    return _SubPageEdgeScrollbar(
      color: colors.textMuted.withValues(alpha: 0.35),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _DesktopSettingsGrid._gridMaxWidth,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 窗口右缘滚动指示条：子页滚动视口与首页网格同宽（居中），
/// 内建滚动条会画在视口边缘而悬空；这里监听后代滚动通知，
/// 把指示条画在容器（窗口）最右缘，符合桌面端滚动条贴边的惯例。
class _SubPageEdgeScrollbar extends StatefulWidget {
  const _SubPageEdgeScrollbar({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  State<_SubPageEdgeScrollbar> createState() => _SubPageEdgeScrollbarState();
}

class _SubPageEdgeScrollbarState extends State<_SubPageEdgeScrollbar> {
  _ScrollbarMetricsSnapshot? _snapshot;

  bool _handleNotification(Notification notification) {
    final ScrollMetrics metrics;
    if (notification is ScrollMetricsNotification) {
      metrics = notification.metrics;
    } else if (notification is ScrollUpdateNotification) {
      metrics = notification.metrics;
    } else {
      return false;
    }
    // 只响应主纵向滚动；嵌套横向列表（如主题预设横排）不触发。
    if (metrics.axis != Axis.vertical) return false;
    final snapshot = _ScrollbarMetricsSnapshot.from(metrics);
    final old = _snapshot;
    if (old == null || !old.sameAs(snapshot)) {
      setState(() => _snapshot = snapshot);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(
      onNotification: _handleNotification,
      child: CustomPaint(
        foregroundPainter: _snapshot == null
            ? null
            : _EdgeScrollbarPainter(snapshot: _snapshot!, color: widget.color),
        child: widget.child,
      ),
    );
  }
}

/// 滚动指标快照：ScrollMetrics 由可变位置实现，留存数值而非引用。
class _ScrollbarMetricsSnapshot {
  const _ScrollbarMetricsSnapshot({
    required this.pixels,
    required this.minExtent,
    required this.maxExtent,
    required this.viewportDimension,
  });

  factory _ScrollbarMetricsSnapshot.from(ScrollMetrics metrics) {
    return _ScrollbarMetricsSnapshot(
      pixels: metrics.pixels,
      minExtent: metrics.minScrollExtent,
      maxExtent: metrics.maxScrollExtent,
      viewportDimension: metrics.viewportDimension,
    );
  }

  final double pixels;
  final double minExtent;
  final double maxExtent;
  final double viewportDimension;

  bool get scrollable => maxExtent > minExtent + 0.01;

  double get progress =>
      ((pixels - minExtent) / (maxExtent - minExtent)).clamp(0.0, 1.0);

  double get thumbRatio =>
      (viewportDimension / (viewportDimension + maxExtent - minExtent)).clamp(
        0.08,
        1.0,
      );

  bool sameAs(_ScrollbarMetricsSnapshot other) =>
      pixels == other.pixels &&
      minExtent == other.minExtent &&
      maxExtent == other.maxExtent &&
      viewportDimension == other.viewportDimension;
}

class _EdgeScrollbarPainter extends CustomPainter {
  const _EdgeScrollbarPainter({required this.snapshot, required this.color});

  final _ScrollbarMetricsSnapshot snapshot;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!snapshot.scrollable) return;
    const double marginY = 10;
    const double thumbWidth = 6;
    const double edgeInset = 4;
    final trackHeight = size.height - marginY * 2;
    if (trackHeight <= 0) return;
    final thumbHeight = trackHeight * snapshot.thumbRatio;
    final thumbTop = marginY + (trackHeight - thumbHeight) * snapshot.progress;
    final rect = Rect.fromLTWH(
      size.width - edgeInset - thumbWidth,
      thumbTop,
      thumbWidth,
      thumbHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_EdgeScrollbarPainter oldDelegate) =>
      !snapshot.sameAs(oldDelegate.snapshot) || color != oldDelegate.color;
}
