import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/player/services/player_runtime_preferences_store.dart';

PlayerRuntimePreferencesStore _buildStore() {
  return const PlayerRuntimePreferencesStore(
    autoPlayPrefKey: 'player_auto_play_enabled',
    autoRotatePrefKey: 'player_auto_rotate_enabled',
    extremePlaybackPrefKey: 'player_extreme_playback_enabled',
    performanceOverlayPrefKey: 'player_performance_overlay_enabled',
    fpsOverlayPrefKey: 'player_fps_overlay_enabled',
    performanceOverlayOffsetXPrefKey: 'player_performance_overlay_offset_x',
    performanceOverlayOffsetYPrefKey: 'player_performance_overlay_offset_y',
    decoderModePrefKey: 'player_decoder_mode',
    displayAspectRatioPrefKey: 'player_display_aspect_ratio',
    introOutroEnabledPrefKey: 'player_intro_outro_enabled',
    introOutroSourceModePrefKey: 'player_intro_outro_source_mode',
    introOutroChapterModePrefKey: 'player_intro_outro_chapter_mode',
    introOutroIntroMaxPrefKey: 'player_intro_outro_intro_max_seconds',
    introOutroOutroMaxPrefKey: 'player_intro_outro_outro_max_seconds',
    mpvSettingPrefPrefix: 'player_mpv_setting_',
    decoderModeHardware: 'hardware',
    decoderModeSoftware: 'software',
    displayAspectRatioFit: 'fit',
    supportedDisplayAspectRatioModes: <String>{
      'fit',
      'fill',
      '4:3',
      '16:9',
      '21:9',
    },
    introOutroSourceModeOff: 'off',
    supportedIntroOutroSourceModes: <String>{'off', 'official', 'chapter'},
    chapterSkipModeAuto: 'auto',
    supportedChapterSkipModes: <String>{'auto', 'manual'},
    defaultMpvSettings: <String, String>{
      'deband': 'off',
      'cache_profile': 'default',
    },
    defaultPerformanceOverlayOffset: Offset(12, 56),
    introDurationMinSeconds: 60,
    introDurationMaxSeconds: 240,
    outroDurationMinSeconds: 60,
    outroDurationMaxSeconds: 240,
  );
}

void main() {
  group('PlayerRuntimePreferencesStore', () {
    test('loads and normalizes persisted runtime preferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'player_auto_play_enabled': false,
        'player_auto_rotate_enabled': false,
        'player_extreme_playback_enabled': true,
        'player_performance_overlay_enabled': true,
        'player_fps_overlay_enabled': false,
        'player_decoder_mode': 'invalid',
        'player_display_aspect_ratio': '16:9',
        'player_intro_outro_enabled': true,
        'player_intro_outro_source_mode': 'chapter',
        'player_intro_outro_chapter_mode': 'invalid',
        'player_intro_outro_intro_max_seconds': 999,
        'player_intro_outro_outro_max_seconds': 10,
        'player_mpv_setting_deband': 'on',
        'player_performance_overlay_offset_x': 24.0,
        'player_performance_overlay_offset_y': 72.0,
      });

      final preferences = await _buildStore().load();

      expect(preferences.autoPlayEnabled, isFalse);
      expect(preferences.autoRotateEnabled, isFalse);
      expect(preferences.extremePlaybackEnabled, isTrue);
      expect(preferences.performanceOverlayEnabled, isTrue);
      expect(preferences.fpsOverlayEnabled, isFalse);
      expect(preferences.decoderMode, 'hardware');
      expect(preferences.displayAspectRatioMode, '16:9');
      expect(preferences.introOutroEnabled, isTrue);
      expect(preferences.introOutroSourceMode, 'chapter');
      expect(preferences.chapterSkipMode, 'auto');
      expect(preferences.introDurationSeconds, 240);
      expect(preferences.outroDurationSeconds, 60);
      expect(preferences.mpvSettings['deband'], 'on');
      expect(preferences.mpvSettings['cache_profile'], 'default');
      expect(preferences.performanceOverlayOffset, const Offset(24, 72));
    });

    test('falls back to defaults when optional values are missing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'player_intro_outro_enabled': false,
        'player_intro_outro_source_mode': 'official',
      });

      final preferences = await _buildStore().load();

      expect(preferences.autoPlayEnabled, isTrue);
      expect(preferences.autoRotateEnabled, isTrue);
      expect(preferences.decoderMode, 'hardware');
      expect(preferences.displayAspectRatioMode, 'fit');
      expect(preferences.introOutroEnabled, isFalse);
      expect(preferences.introOutroSourceMode, 'off');
      expect(preferences.performanceOverlayOffset, const Offset(12, 56));
    });
  });
}
