import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

@immutable
class EpisodeSelection {
  final String seasonGuid;
  final String itemId;

  const EpisodeSelection({required this.seasonGuid, required this.itemId});

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'seasonGuid': seasonGuid, 'itemId': itemId};
  }

  factory EpisodeSelection.fromMap(Map<String, dynamic> raw) {
    return EpisodeSelection(
      seasonGuid: (raw['seasonGuid'] ?? '').toString(),
      itemId: (raw['itemId'] ?? '').toString(),
    );
  }
}

// ---------------------------------------------------------------------------
// Bridge
// ---------------------------------------------------------------------------

class NativePanelBridge {
  NativePanelBridge._();

  static final MethodChannel _channel = const MethodChannel(
    'fly_player/native_panels',
  );

  /// Set to `false` to fall back to the Flutter implementation for all panels.
  static bool enabled = false;

  // -- Episode picker -------------------------------------------------------

  /// Shows the native episode picker panel and returns the user's selection.
  ///
  /// Returns `null` when the native panel is not available, causing callers
  /// to fall back to the Flutter implementation.
  static Future<EpisodeSelection?> showEpisodePicker({
    required String barrierTitle,
    required String seriesTitle,
    required Map<String, dynamic> initialSeasonData,
    required String initialSeasonGuid,
    required String initialMode,
    required int rangeSize,
    required String baseUrl,
    required String token,
    required List<Map<String, dynamic>> seasons,
  }) async {
    if (!enabled) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'showEpisodePicker',
        <String, dynamic>{
          'barrierTitle': barrierTitle,
          'seriesTitle': seriesTitle,
          'initialSeasonData': initialSeasonData,
          'initialSeasonGuid': initialSeasonGuid,
          'initialMode': initialMode,
          'rangeSize': rangeSize,
          'baseUrl': baseUrl,
          'token': token,
          'seasons': seasons,
        },
      );
      if (result == null) return null;
      return EpisodeSelection.fromMap(result);
    } on MissingPluginException {
      return null;
    }
  }

  // -- Playback settings drawer ---------------------------------------------

  /// Shows the native playback settings panel.
  ///
  /// Returns `true` if the settings were shown, `false` to fall back to the
  /// Flutter implementation.
  static Future<bool> showSettings({required String initialPageId}) async {
    if (!enabled) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'showSettings',
        <String, dynamic>{'initialPageId': initialPageId},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  // -- Quality sheet --------------------------------------------------------

  /// Shows the native quality selection sheet.
  ///
  /// Returns the selected quality id, or `null` to fall back to Flutter.
  static Future<String?> showQualitySheet({
    required String title,
    required String sectionLabel,
    required List<Map<String, dynamic>> items,
    required String selectedId,
  }) async {
    if (!enabled) return null;
    try {
      final result = await _channel
          .invokeMethod<String>('showQualitySheet', <String, dynamic>{
            'title': title,
            'sectionLabel': sectionLabel,
            'items': items,
            'selectedId': selectedId,
          });
      return result;
    } on MissingPluginException {
      return null;
    }
  }

  // -- Speed sheet ----------------------------------------------------------

  /// Shows the native playback speed selection sheet.
  ///
  /// Returns the selected speed, or `null` to fall back to Flutter.
  static Future<double?> showSpeedSheet({required double currentSpeed}) async {
    if (!enabled) return null;
    try {
      final result = await _channel.invokeMethod<double>(
        'showSpeedSheet',
        <String, dynamic>{'currentSpeed': currentSpeed},
      );
      return result;
    } on MissingPluginException {
      return null;
    }
  }

  // -- Audio track sheet ----------------------------------------------------

  /// Shows the native audio track selection sheet.
  ///
  /// Returns the selected track id, or `null` to fall back to Flutter.
  static Future<String?> showAudioTrackSheet({
    required List<Map<String, dynamic>> tracks,
    required String selectedTrackId,
    required bool serverManaged,
  }) async {
    if (!enabled) return null;
    try {
      final result = await _channel
          .invokeMethod<String>('showAudioTrackSheet', <String, dynamic>{
            'tracks': tracks,
            'selectedTrackId': selectedTrackId,
            'serverManaged': serverManaged,
          });
      return result;
    } on MissingPluginException {
      return null;
    }
  }

  // -- Subtitle track sheet -------------------------------------------------

  /// Shows the native subtitle track selection sheet.
  ///
  /// Returns the selected track id, or `null` to fall back to Flutter.
  static Future<String?> showSubtitleTrackSheet({
    required List<Map<String, dynamic>> tracks,
    required String selectedTrackId,
    required bool serverManaged,
  }) async {
    if (!enabled) return null;
    try {
      final result = await _channel
          .invokeMethod<String>('showSubtitleTrackSheet', <String, dynamic>{
            'tracks': tracks,
            'selectedTrackId': selectedTrackId,
            'serverManaged': serverManaged,
          });
      return result;
    } on MissingPluginException {
      return null;
    }
  }
}
