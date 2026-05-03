import 'package:flutter/services.dart';

import '../controllers/play_detail_data_loader.dart';
import '../models/play_info.dart';
import '../player/models/player_host_launch_args.dart';
import '../services/play_stats/play_stats.dart';

/// 封装播放器宿主 Activity 与 Flutter 间的桥接调用。
class PlayerHostBridge {
  static const MethodChannel _channel = MethodChannel('fly_player/player_host');

  const PlayerHostBridge._();

  /// 读取并消费宿主在播放器启动时注入的初始参数。
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

  /// 请求宿主结束播放器 Activity，并回传播放结果。
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

  /// 请求宿主在不同播放器布局模式之间切换。
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

  /// 将当前播放器启动状态同步回宿主侧。
  static Future<bool> syncPlayerLaunchState({
    required String title,
    required Map<String, Object?> source,
    PlayInfoData? initialPlayInfo,
    PlayStartSource startSource = PlayStartSource.manual,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(
            'syncPlayerLaunchState',
            <String, Object?>{
              'title': title,
              'source': source,
              'initialPlayInfo': initialPlayInfo?.toJson(),
              'startSource': PlayStatsSqlMapper.startSourceToText(startSource),
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// 查询当前系统级分屏或多窗口模式是否处于激活状态。
  static Future<bool> isSystemMultiWindowActive() async {
    try {
      return await _channel.invokeMethod<bool>('isSystemMultiWindowActive') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// 查询宿主环境是否支持画中画能力。
  static Future<bool> isPictureInPictureSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isPictureInPictureSupported') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// 请求宿主进入画中画模式。
  static Future<bool> enterPictureInPicture() async {
    try {
      return await _channel.invokeMethod<bool>('enterPictureInPicture') ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
