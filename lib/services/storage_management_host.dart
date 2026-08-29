import 'package:flutter/services.dart';

/// 储存管理平台宿主接口：屏蔽 Android 原生通道与桌面端等价实现的差异。
///
/// Android 由 `FlutterHostActivity` 注册的 `fly_player/storage` 通道承载；
/// 桌面端（Windows/Linux/macOS）无该通道，任何调用都会抛 MissingPluginException，
/// 由 [DesktopStorageManagementHost] 提供语义等价的 Dart 实现。新增平台只需追加
/// `StorageManagementHost` 实现，业务层禁止直连通道。方法返回的映射结构与
/// Android 端 `StorageManagementController` 的载荷字段保持一致。
abstract interface class StorageManagementHost {
  /// 原生侧统计：playbackCache{bytes,fileCount,completeCount,active}、
  /// danmakuAiCache{bytes,fileCount}、otherCache{bytes,fileCount}、
  /// screenshots{bytes,fileCount,restricted}、nativeSettingsBytes。
  Future<Map<Object?, Object?>?> getStorageOverview();

  /// 执行原生清理动作，action 取值与 Android 端 StorageManagementController
  /// 常量一致（clearPlaybackCache/clearDanmakuAiCache/clearOtherCache/
  /// clearScreenshots/clearParallelWindowSettings/clearScopedTreeAccess）。
  Future<Map<Object?, Object?>?> clearStorageAction(String action);

  /// 列出播放缓存记录（桌面端恒为空）。
  Future<List<Object?>?> listPlaybackCacheEntries();

  /// 按资源键批量清理播放缓存记录。
  Future<Map<Object?, Object?>?> clearPlaybackCacheEntries(
    List<String> resourceKeys,
  );

  /// 查询缓存媒体可否提升为下载文件。
  Future<Map<Object?, Object?>?> queryCachedDownloadable(
    Map<String, Object?> identity,
  );

  /// 将缓存媒体提升到目标存储位置。
  Future<Map<Object?, Object?>?> promoteCachedMedia(
    Map<String, Object?> arguments,
  );

  /// 是否具备常规文件访问权限（桌面端恒为 true）。
  Future<bool?> hasFileAccess();

  /// 请求常规文件访问权限（桌面端恒为 true）。
  Future<bool?> requestFileAccess();
}

/// 桌面端（Windows/Linux/macOS）储存宿主等价实现，纯 Dart，三平台通用。
///
/// 归零口径与桌面壳当前能力一一对应：
/// - 播放缓存：桌面播放内核未接入（`*playback_launcher` 有桌面守卫），无缓存会话；
/// - 弹幕 AI 缓存：Paddle Lite 遮挡分割是 Android 原生能力；
/// - 其他缓存：Android 对应 cacheDir/codeCacheDir/tmpdir，桌面端应用自有数据
///   全部位于 SharedPreferences/数据库/下载目录（已由 Dart 侧统计），共享系统
///   临时目录禁止批量清理，故恒为 0；
/// - 截图：截图库依赖 Android MediaStore/SAF，桌面无截图管线；
/// - 原生设置：parallel_window_settings / fly_player_scoped_tree 为 Android
///   原生 SharedPreferences，桌面端无对应存储。
/// 播放内核接入后，播放缓存统计在本类内补齐，`StorageManagementService` 不再改动。
class DesktopStorageManagementHost implements StorageManagementHost {
  const DesktopStorageManagementHost();

  @override
  Future<Map<Object?, Object?>> getStorageOverview() async {
    return const <String, Object?>{
      'playbackCache': <String, Object?>{
        'bytes': 0,
        'fileCount': 0,
        'completeCount': 0,
        'active': false,
      },
      'danmakuAiCache': <String, Object?>{'bytes': 0, 'fileCount': 0},
      'otherCache': <String, Object?>{'bytes': 0, 'fileCount': 0},
      'screenshots': <String, Object?>{
        'bytes': 0,
        'fileCount': 0,
        'restricted': false,
      },
      'nativeSettingsBytes': 0,
    };
  }

  @override
  Future<Map<Object?, Object?>> clearStorageAction(String action) async {
    switch (action) {
      case 'clearPlaybackCache':
      case 'clearDanmakuAiCache':
      case 'clearOtherCache':
      case 'clearParallelWindowSettings':
      case 'clearScopedTreeAccess':
        return const <String, Object?>{'success': true};
      case 'clearScreenshots':
        return const <String, Object?>{
          'success': true,
          'restricted': false,
          'deletedCount': 0,
        };
      default:
        return const <String, Object?>{
          'success': false,
          'code': 'unknown_action',
        };
    }
  }

  @override
  Future<List<Object?>> listPlaybackCacheEntries() async {
    return const <Object?>[];
  }

  @override
  Future<Map<Object?, Object?>> clearPlaybackCacheEntries(
    List<String> resourceKeys,
  ) async {
    return const <String, Object?>{'success': true, 'clearedCount': 0};
  }

  @override
  Future<Map<Object?, Object?>> queryCachedDownloadable(
    Map<String, Object?> identity,
  ) async {
    return const <String, Object?>{
      'found': false,
      'downloadable': false,
      'code': 'not_found',
      'resourceKey': '',
      'bytes': 0,
      'totalBytes': 0,
      'mimeType': '',
      'suggestedFileName': '',
      'title': '',
    };
  }

  @override
  Future<Map<Object?, Object?>> promoteCachedMedia(
    Map<String, Object?> arguments,
  ) async {
    return const <String, Object?>{'success': false, 'code': 'not_found'};
  }

  @override
  Future<bool> hasFileAccess() async {
    return true;
  }

  @override
  Future<bool> requestFileAccess() async {
    return true;
  }
}

/// Android 通道宿主：透传 `fly_player/storage`，行为与原先
/// `StorageManagementService` 直连通道完全一致。
class MethodChannelStorageManagementHost implements StorageManagementHost {
  const MethodChannelStorageManagementHost();

  static const MethodChannel _channel = MethodChannel('fly_player/storage');

  @override
  Future<Map<Object?, Object?>?> getStorageOverview() =>
      _channel.invokeMapMethod<Object?, Object?>('getStorageOverview');

  @override
  Future<Map<Object?, Object?>?> clearStorageAction(String action) =>
      _channel.invokeMapMethod<Object?, Object?>(
        'clearStorageAction',
        <String, Object?>{'action': action},
      );

  @override
  Future<List<Object?>?> listPlaybackCacheEntries() =>
      _channel.invokeListMethod<Object?>('listPlaybackCacheEntries');

  @override
  Future<Map<Object?, Object?>?> clearPlaybackCacheEntries(
    List<String> resourceKeys,
  ) => _channel.invokeMapMethod<Object?, Object?>(
    'clearPlaybackCacheEntries',
    <String, Object?>{'resourceKeys': resourceKeys},
  );

  @override
  Future<Map<Object?, Object?>?> queryCachedDownloadable(
    Map<String, Object?> identity,
  ) => _channel.invokeMapMethod<Object?, Object?>(
    'queryCachedDownloadable',
    identity,
  );

  @override
  Future<Map<Object?, Object?>?> promoteCachedMedia(
    Map<String, Object?> arguments,
  ) => _channel.invokeMapMethod<Object?, Object?>(
    'promoteCachedMedia',
    arguments,
  );

  @override
  Future<bool?> hasFileAccess() => _channel.invokeMethod<bool>('hasFileAccess');

  @override
  Future<bool?> requestFileAccess() =>
      _channel.invokeMethod<bool>('requestFileAccess');
}
