import 'package:flutter/services.dart';

import '../controllers/play_detail_data_loader.dart';
import '../models/play_info.dart';
import '../player/models/player_host_launch_args.dart';
import '../services/play_stats/play_stats.dart';

class PlayerHostBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/player_host');

  const PlayerHostBridge._();

  static Future<PlayerHostLaunchArgs?> consumeInitialPlayerArgs() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
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
      return await _channel.invokeMethod<bool>(
            'finishPlayerActivity',
            <String, Object?>{'result': result.toMap()},
          ) ??
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
    PlayInfoData? initialPlayInfo,
    PlayStartSource startSource = PlayStartSource.manual,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(
            'switchPlayerLayoutMode',
            <String, Object?>{
              'title': title,
              'source': source,
              'initialPlayInfo': initialPlayInfo?.toJson(),
              'startSource': PlayStatsSqlMapper.startSourceToText(startSource),
              'targetMode': targetMode,
              'result': result.toMap(),
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isSystemMultiWindowActive() async {
    try {
      return await _channel.invokeMethod<bool>('isSystemMultiWindowActive') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isPictureInPictureSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isPictureInPictureSupported') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> enterPictureInPicture() async {
    try {
      return await _channel.invokeMethod<bool>('enterPictureInPicture') ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
