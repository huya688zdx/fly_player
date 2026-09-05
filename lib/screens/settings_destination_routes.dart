import 'package:flutter/material.dart';

import 'app_log_screen.dart';
import 'bookmark_manager_screen.dart';
import 'danmaku_settings_screen.dart';
import 'download_list_screen.dart';
import 'mpv_player_settings_screen.dart';
import 'parallel_window_settings_screen.dart';
import 'play_stats_report_screen.dart';
import 'screenshot_settings_screen.dart';
import 'storage_management_screen.dart';
import 'theme_custom_recipe_screen.dart';
import 'theme_settings_screen.dart';

class SettingsDestinationRoutes {
  static const String home = '/screen/settings';
  static const String theme = '/screen/settings/theme';
  static const String themeCustomRecipe =
      '/screen/settings/theme/custom-recipe';
  static const String mpv = '/screen/settings/mpv';
  static const String parallelWindow = '/screen/settings/parallel-window';
  static const String downloads = '/screen/settings/downloads';
  static const String storage = '/screen/settings/storage';
  static const String playStats = '/screen/settings/play-stats';
  static const String other = '/screen/settings/other';
  static const String logs = '/screen/settings/logs';
  static const String bookmarks = '/screen/settings/bookmarks';
  static const String danmaku = '/screen/settings/danmaku';
  static const String screenshot = '/screen/settings/screenshot';

  const SettingsDestinationRoutes._();

  static String mpvRoute({String? section, String? settingKey}) {
    final queryParameters = <String, String>{
      if (section?.trim().isNotEmpty == true) 'section': section!.trim(),
      if (settingKey?.trim().isNotEmpty == true)
        'settingKey': settingKey!.trim(),
    };
    return Uri(path: mpv, queryParameters: queryParameters).toString();
  }

  static String screenshotRoute({String? target}) {
    final queryParameters = <String, String>{
      if (target?.trim().isNotEmpty == true) 'target': target!.trim(),
    };
    return Uri(path: screenshot, queryParameters: queryParameters).toString();
  }

  static List<String>? buildNavigationStack(String routeName) {
    final normalizedRoute = routeName.trim();
    if (normalizedRoute.isEmpty) return null;
    final uri = Uri.tryParse(normalizedRoute);
    if (uri == null) return null;

    switch (uri.path) {
      case home:
        return const <String>[home];
      case theme:
        return const <String>[home, theme];
      case themeCustomRecipe:
        return const <String>[home, theme, themeCustomRecipe];
      case mpv:
        final section = _normalizedQueryValue(uri, 'section');
        final settingKey = _normalizedQueryValue(uri, 'settingKey');
        final stack = <String>[home, mpv];
        final mpvSectionRoute = _mpvSectionRoute(
          section: section,
          settingKey: settingKey,
        );
        if (mpvSectionRoute != null) {
          stack.add(mpvSectionRoute);
        }
        stack.add(normalizedRoute);
        return _dedupeSequential(stack);
      case parallelWindow:
        return const <String>[home, parallelWindow];
      case downloads:
        return const <String>[home, downloads];
      case storage:
        return const <String>[home, storage];
      case playStats:
        return const <String>[home, playStats];
      case other:
        return const <String>[home, other];
      case logs:
        return const <String>[home, logs];
      case bookmarks:
        return const <String>[home, other, bookmarks];
      case danmaku:
        return const <String>[home, other, danmaku];
      case screenshot:
        final target = _normalizedQueryValue(uri, 'target');
        final stack = <String>[home, other, screenshot];
        if (target != null) {
          stack.add(screenshotRoute(target: target));
        }
        return _dedupeSequential(stack);
    }
    return null;
  }

  static Widget? buildRoute(String routeName, {Key? key}) {
    final normalizedRoute = routeName.trim();
    if (normalizedRoute.isEmpty) return null;
    final uri = Uri.tryParse(normalizedRoute);
    if (uri == null) return null;

    switch (uri.path) {
      case theme:
        return ThemeSettingsScreen(key: key);
      case themeCustomRecipe:
        return ThemeCustomRecipeScreen(key: key);
      case mpv:
        final section = _normalizedQueryValue(uri, 'section');
        final settingKey = _normalizedQueryValue(uri, 'settingKey');
        return MpvPlayerSettingsScreen(
          key: key,
          initialSection: section,
          initialSettingKey: settingKey,
        );
      case parallelWindow:
        return ParallelWindowSettingsScreen(key: key);
      case downloads:
        return DownloadListScreen(
          key: key,
          initialTab: DownloadListTabX.fromRouteValue(
            uri.queryParameters['tab'] ?? '',
          ),
        );
      case storage:
        return StorageManagementScreen(key: key);
      case playStats:
        return PlayStatsReportScreen(key: key);
      case other:
        return OtherSettingsScreen(key: key);
      case logs:
        return AppLogScreen(key: key);
      case bookmarks:
        return BookmarkManagerScreen(key: key);
      case danmaku:
        return DanmakuSettingsScreen(key: key);
      case screenshot:
        final target = _normalizedQueryValue(uri, 'target');
        return ScreenshotSettingsScreen(key: key, initialTarget: target);
    }
    return null;
  }

  static String? _normalizedQueryValue(Uri uri, String key) {
    final value = uri.queryParameters[key]?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String? _mpvSectionRoute({String? section, String? settingKey}) {
    final normalizedSection = section?.trim();
    if (normalizedSection?.isNotEmpty == true) {
      return mpvRoute(section: normalizedSection);
    }
    final derivedSection = _mpvSectionForSettingKey(settingKey);
    if (derivedSection == null) return null;
    return mpvRoute(section: derivedSection);
  }

  static String? _mpvSectionForSettingKey(String? settingKey) {
    final normalized = settingKey?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    switch (normalized) {
      case 'deband':
      case 'sharpen':
      case 'denoise':
      case 'deinterlace':
      case 'scale_profile':
      case 'hdr_mode':
      case 'frame_interpolation':
        return MpvPlayerSettingsScreen.sectionPicture;
      case 'volume_gain':
      case 'audio_high_fidelity':
      case 'dynamic_range':
      case 'audio_eq':
      case 'audio_limiter':
      case 'audio_bass_boost':
      case 'audio_voice_enhance':
      case 'channel_mix':
        return MpvPlayerSettingsScreen.sectionAudio;
      case 'video_sync':
      case 'cache_profile':
      case 'cache_size_mb':
        return MpvPlayerSettingsScreen.sectionPlayback;
      case 'compatibility_profile':
        return MpvPlayerSettingsScreen.sectionCompatibility;
    }
    return null;
  }

  static List<String> _dedupeSequential(List<String> routes) {
    final normalized = <String>[];
    for (final route in routes) {
      final trimmed = route.trim();
      if (trimmed.isEmpty) continue;
      if (normalized.isNotEmpty && normalized.last == trimmed) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }
}
