import 'package:flutter/services.dart';

enum PlayerAdjustmentType { brightness, volume }

class PlayerSystemSnapshot {
  final double brightness;
  final double volume;

  const PlayerSystemSnapshot({required this.brightness, required this.volume});
}

class PlayerSystemController {
  static const MethodChannel _channel = MethodChannel('fly_player/system');

  const PlayerSystemController();

  Future<PlayerSystemSnapshot> readSnapshot() async {
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>(
        'getPlaybackSystemState',
      );
      return PlayerSystemSnapshot(
        brightness: _normalizedValue(data?['brightness']),
        volume: _normalizedValue(data?['volume']),
      );
    } on PlatformException {
      return const PlayerSystemSnapshot(brightness: 0.5, volume: 0.5);
    } on MissingPluginException {
      return const PlayerSystemSnapshot(brightness: 0.5, volume: 0.5);
    }
  }

  Future<double> setBrightness(double value) async {
    return _setNormalizedValue('setPlaybackBrightness', value);
  }

  Future<double> setVolume(double value) async {
    return _setNormalizedValue('setPlaybackVolume', value);
  }

  Future<double> _setNormalizedValue(String method, double value) async {
    final normalized = _normalizedValue(value);
    try {
      final result = await _channel.invokeMethod<double>(
        method,
        <String, double>{'value': normalized},
      );
      return _normalizedValue(result ?? normalized);
    } on PlatformException {
      return normalized;
    } on MissingPluginException {
      return normalized;
    }
  }

  static double _normalizedValue(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.5;
    return value.clamp(0.0, 1.0);
  }
}
