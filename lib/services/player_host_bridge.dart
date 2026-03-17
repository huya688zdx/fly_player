import 'package:flutter/services.dart';

import '../controllers/play_detail_data_loader.dart';
import '../player/models/player_host_launch_args.dart';

class PlayerHostBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/player_host');

  const PlayerHostBridge._();

  static Future<PlayerHostLaunchArgs?> consumeInitialPlayerArgs() async {
    try {
      final result =
          await _channel.invokeMapMethod<Object?, Object?>(
            'consumeInitialPlayerArgs',
          );
      if (result == null) return null;
      return PlayerHostLaunchArgs.fromPlatformMap(result);
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> finishPlayerActivity(
    PlayDetailPlayerReturnData result,
  ) async {
    try {
      return await _channel.invokeMethod<bool>('finishPlayerActivity', <String, Object?>{
            'result': result.toMap(),
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> switchPlayerLayoutMode({
    required String title,
    required Map<String, Object?> source,
    required String targetMode,
    required PlayDetailPlayerReturnData result,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('switchPlayerLayoutMode', <String, Object?>{
            'title': title,
            'source': source,
            'targetMode': targetMode,
            'result': result.toMap(),
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
