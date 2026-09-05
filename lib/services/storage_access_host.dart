import 'package:flutter/services.dart';

/// 截图与文件访问平台宿主接口：屏蔽 Android 原生通道与桌面端等价实现的差异。
///
/// Android 由 `FlutterHostActivity` 注册的 `fly_player/storage` 通道承载；
/// 桌面端（Windows/Linux/macOS）无该通道，任何直连调用都会抛
/// MissingPluginException（此前「其他」设置页首个加载调用即触发，页面永久
/// 卡在加载态），由 [DesktopStorageAccessHost] 提供语义等价的 Dart 实现。
/// 新增平台只需追加 `StorageAccessHost` 实现，业务层禁止直连通道。
/// 方法返回的载荷结构与 Android 端通道应答字段保持一致，领域映射
/// （`ScreenshotCustomDirectoryInfo.fromMap` 等）由 `StorageAccessService` 承担。
abstract interface class StorageAccessHost {
  /// 是否具备常规文件访问权限。
  Future<bool?> hasFileAccess();

  /// 请求常规文件访问权限。
  Future<bool?> requestFileAccess();

  /// 读取截图自定义保存目录配置，未设置时返回 null。
  Future<Map<Object?, Object?>?> getScreenshotCustomDirectory();

  /// 请求用户选择截图自定义保存目录，取消或不可用时返回 null。
  Future<Map<Object?, Object?>?> requestScreenshotCustomDirectory();

  /// 清除截图自定义保存目录配置。
  Future<bool?> clearScreenshotCustomDirectory();

  /// 列出截图库中的全部可管理截图。
  Future<List<Object?>?> listScreenshotLibrary();

  /// 读取指定截图文件的原始字节内容。
  Future<Uint8List?> readScreenshotFileBytes({
    required String sourceKind,
    required String pathOrIdentifier,
  });

  /// 批量删除截图库中的截图文件，返回载荷含 `deletedCount`。
  Future<Map<Object?, Object?>?> deleteScreenshotFiles(
    List<Map<String, String>> items,
  );
}

/// Android 通道宿主：透传 `fly_player/storage`，方法名与载荷字段
/// 与原先 `StorageAccessService` 直连通道完全一致。
class MethodChannelStorageAccessHost implements StorageAccessHost {
  const MethodChannelStorageAccessHost();

  static const MethodChannel _channel = MethodChannel('fly_player/storage');

  @override
  Future<bool?> hasFileAccess() => _channel.invokeMethod<bool>('hasFileAccess');

  @override
  Future<bool?> requestFileAccess() =>
      _channel.invokeMethod<bool>('requestFileAccess');

  @override
  Future<Map<Object?, Object?>?> getScreenshotCustomDirectory() => _channel
      .invokeMethod<Map<Object?, Object?>>('getScreenshotCustomDirectory');

  @override
  Future<Map<Object?, Object?>?> requestScreenshotCustomDirectory() => _channel
      .invokeMethod<Map<Object?, Object?>>('requestScreenshotCustomDirectory');

  @override
  Future<bool?> clearScreenshotCustomDirectory() =>
      _channel.invokeMethod<bool>('clearScreenshotCustomDirectory');

  @override
  Future<List<Object?>?> listScreenshotLibrary() =>
      _channel.invokeListMethod<Object?>('listScreenshotLibrary');

  @override
  Future<Uint8List?> readScreenshotFileBytes({
    required String sourceKind,
    required String pathOrIdentifier,
  }) => _channel.invokeMethod<Uint8List>('readScreenshotFileBytes', {
    'sourceKind': sourceKind,
    'pathOrIdentifier': pathOrIdentifier,
  });

  @override
  Future<Map<Object?, Object?>?> deleteScreenshotFiles(
    List<Map<String, String>> items,
  ) => _channel.invokeMethod<Map<Object?, Object?>>('deleteScreenshotFiles', {
    'items': items,
  });
}

/// 桌面端（Windows/Linux/macOS）存储宿主等价实现，纯 Dart，三平台通用。
///
/// 归零口径与桌面壳当前能力一一对应：
/// - 文件访问：桌面无运行时权限模型，应用即用户权限，恒为 true
///   （对齐 `DesktopStorageManagementHost`）；
/// - 截图库：截图持久化依赖 Android MediaStore/SAF，桌面截图走播放器内
///   「另存为」对话框（`desktop_playback_screen._captureScreenshot`），无入库
///   管线，故列表恒为空、读取恒为 null、删除恒为 0；
/// - 自定义保存目录：桌面截图不消费保存路径配置，目录授权保持「未设置」
///   语义（get/request → null、clear → true），桌面截图管线接入后再补齐
///   真实目录选择。
class DesktopStorageAccessHost implements StorageAccessHost {
  const DesktopStorageAccessHost();

  @override
  Future<bool?> hasFileAccess() async => true;

  @override
  Future<bool?> requestFileAccess() async => true;

  @override
  Future<Map<Object?, Object?>?> getScreenshotCustomDirectory() async => null;

  @override
  Future<Map<Object?, Object?>?> requestScreenshotCustomDirectory() async =>
      null;

  @override
  Future<bool?> clearScreenshotCustomDirectory() async => true;

  @override
  Future<List<Object?>?> listScreenshotLibrary() async => const <Object?>[];

  @override
  Future<Uint8List?> readScreenshotFileBytes({
    required String sourceKind,
    required String pathOrIdentifier,
  }) async => null;

  @override
  Future<Map<Object?, Object?>?> deleteScreenshotFiles(
    List<Map<String, String>> items,
  ) async => const <String, Object?>{'deletedCount': 0};
}
