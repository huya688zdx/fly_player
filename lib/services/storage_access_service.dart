import 'package:flutter/services.dart';

/// 表示通过系统授权访问的目录节点。
class ScopedBrowserDirectory {
  final String id;
  final String name;

  /// 根据目录标识与显示名称构造对象。
  const ScopedBrowserDirectory({required this.id, required this.name});

  /// 从平台层映射恢复目录节点。
  factory ScopedBrowserDirectory.fromMap(Map<Object?, Object?> raw) {
    return ScopedBrowserDirectory(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
    );
  }
}

/// 表示授权目录中的单个文件或子目录条目。
class ScopedBrowserEntry {
  final String id;
  final String name;
  final bool isDirectory;
  final int sizeBytes;

  /// 根据条目元数据构造对象。
  const ScopedBrowserEntry({
    required this.id,
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
  });

  /// 从平台层映射恢复目录条目。
  factory ScopedBrowserEntry.fromMap(Map<Object?, Object?> raw) {
    return ScopedBrowserEntry(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
      isDirectory: raw['isDirectory'] == true,
      sizeBytes: switch (raw['sizeBytes']) {
        final int value => value,
        final num value => value.toInt(),
        _ => 0,
      },
    );
  }
}

/// 表示一次授权目录浏览的返回结果。
class ScopedBrowserListing {
  final ScopedBrowserDirectory directory;
  final List<ScopedBrowserEntry> entries;

  /// 根据当前目录与其子项列表构造对象。
  const ScopedBrowserListing({required this.directory, required this.entries});

  /// 从平台层映射恢复目录列表结果。
  factory ScopedBrowserListing.fromMap(Map<Object?, Object?> raw) {
    final entryList = (raw['entries'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) => ScopedBrowserEntry.fromMap(item.cast<Object?, Object?>()),
        )
        .toList(growable: false);
    return ScopedBrowserListing(
      directory: ScopedBrowserDirectory.fromMap(
        (raw['directory'] as Map).cast<Object?, Object?>(),
      ),
      entries: entryList,
    );
  }
}

/// 表示本地文件选择器返回的文件选择结果。
class LocalBrowserFileSelection {
  final String identifier;
  final String displayName;

  /// 根据文件标识与展示名称构造对象。
  const LocalBrowserFileSelection({
    required this.identifier,
    required this.displayName,
  });
}

/// 描述截图自定义保存目录的当前状态。
class ScreenshotCustomDirectoryInfo {
  final String id;
  final String name;
  final String locationLabel;
  final bool available;

  /// 根据截图目录信息构造对象。
  const ScreenshotCustomDirectoryInfo({
    required this.id,
    required this.name,
    required this.locationLabel,
    required this.available,
  });

  /// 从平台层映射恢复截图目录信息。
  factory ScreenshotCustomDirectoryInfo.fromMap(Map<Object?, Object?> raw) {
    return ScreenshotCustomDirectoryInfo(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
      locationLabel: (raw['locationLabel'] ?? '').toString(),
      available: raw['available'] == true,
    );
  }
}

/// 表示图库中可管理的一张截图记录。
class ScreenshotLibraryItem {
  final String id;
  final String name;
  final String sourceKind;
  final String locationLabel;
  final String formatKind;
  final bool isHdr;
  final int sizeBytes;
  final DateTime modifiedAt;
  final bool isScoped;
  final String pathOrIdentifier;

  /// 根据截图元数据构造对象。
  const ScreenshotLibraryItem({
    required this.id,
    required this.name,
    required this.sourceKind,
    required this.locationLabel,
    required this.formatKind,
    required this.isHdr,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.isScoped,
    required this.pathOrIdentifier,
  });

  /// 从平台层映射恢复截图记录。
  factory ScreenshotLibraryItem.fromMap(Map<Object?, Object?> raw) {
    final modifiedAtMs = switch (raw['modifiedAtMs']) {
      final int value => value,
      final num value => value.toInt(),
      _ => 0,
    };
    return ScreenshotLibraryItem(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
      sourceKind: (raw['sourceKind'] ?? '').toString(),
      locationLabel: (raw['locationLabel'] ?? '').toString(),
      formatKind: (raw['formatKind'] ?? '').toString(),
      isHdr: raw['isHdr'] == true,
      sizeBytes: switch (raw['sizeBytes']) {
        final int value => value,
        final num value => value.toInt(),
        _ => 0,
      },
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(modifiedAtMs),
      isScoped: raw['isScoped'] == true,
      pathOrIdentifier: (raw['pathOrIdentifier'] ?? '').toString(),
    );
  }

  /// 转换为可传递给平台层的完整映射结构。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'sourceKind': sourceKind,
      'locationLabel': locationLabel,
      'formatKind': formatKind,
      'isHdr': isHdr,
      'sizeBytes': sizeBytes,
      'modifiedAtMs': modifiedAt.millisecondsSinceEpoch,
      'isScoped': isScoped,
      'pathOrIdentifier': pathOrIdentifier,
    };
  }

  /// 生成删除截图时所需的最小载荷。
  Map<String, String> toDeletePayload() {
    return <String, String>{
      'sourceKind': sourceKind,
      'pathOrIdentifier': pathOrIdentifier,
    };
  }
}

/// 封装文件访问、目录授权与截图库相关的平台桥接。
class StorageAccessService {
  static const MethodChannel _channel = MethodChannel('fly_player/storage');

  /// 判断应用当前是否具备常规文件访问权限。
  static Future<bool> hasFileAccess() async {
    final result = await _channel.invokeMethod<bool>('hasFileAccess');
    return result == true;
  }

  /// 请求系统授予常规文件访问权限。
  static Future<bool> requestFileAccess() async {
    final result = await _channel.invokeMethod<bool>('requestFileAccess');
    return result == true;
  }

  /// 打开系统文件访问权限设置页。
  static Future<bool> openFileAccessSettings() async {
    final result = await _channel.invokeMethod<bool>('openFileAccessSettings');
    return result == true;
  }

  /// 读取主存储根目录路径。
  static Future<String> primaryStorageRoot() async {
    final path = await _channel.invokeMethod<String>('getPrimaryStorageRoot');
    return (path ?? '/storage/emulated/0').trim();
  }

  /// 返回当前已授权的目录树根节点。
  static Future<ScopedBrowserDirectory?> getScopedTreeRoot() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getScopedTreeRoot',
    );
    if (raw == null || raw.isEmpty) return null;
    final directory = ScopedBrowserDirectory.fromMap(raw);
    if (directory.id.trim().isEmpty) return null;
    return directory;
  }

  /// 请求用户授予新的目录树访问权限。
  static Future<ScopedBrowserDirectory?> requestScopedTreeAccess() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'requestScopedTreeAccess',
    );
    if (raw == null || raw.isEmpty) return null;
    final directory = ScopedBrowserDirectory.fromMap(raw);
    if (directory.id.trim().isEmpty) return null;
    return directory;
  }

  /// 列出指定授权目录下的子目录与文件条目。
  static Future<ScopedBrowserListing?> listScopedTreeEntries({
    String? directoryId,
    List<String> allowedExtensions = const <String>[],
  }) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'listScopedTreeEntries',
      <String, Object?>{
        'directoryId': directoryId,
        'allowedExtensions': allowedExtensions,
      },
    );
    if (raw == null || raw.isEmpty) return null;
    return ScopedBrowserListing.fromMap(raw);
  }

  /// 读取授权目录中文件的原始字节内容。
  static Future<Uint8List?> readScopedFileBytes(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return null;
    return _channel.invokeMethod<Uint8List>(
      'readScopedFileBytes',
      <String, Object?>{'identifier': trimmed},
    );
  }

  /// 获取截图自定义保存目录的当前配置。
  static Future<ScreenshotCustomDirectoryInfo?>
  getScreenshotCustomDirectory() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getScreenshotCustomDirectory',
    );
    if (raw == null || raw.isEmpty) return null;
    return ScreenshotCustomDirectoryInfo.fromMap(raw);
  }

  /// 请求用户重新选择截图自定义保存目录。
  static Future<ScreenshotCustomDirectoryInfo?>
  requestScreenshotCustomDirectory() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'requestScreenshotCustomDirectory',
    );
    if (raw == null || raw.isEmpty) return null;
    return ScreenshotCustomDirectoryInfo.fromMap(raw);
  }

  /// 清除截图自定义保存目录配置。
  static Future<bool> clearScreenshotCustomDirectory() async {
    final result = await _channel.invokeMethod<bool>(
      'clearScreenshotCustomDirectory',
    );
    return result == true;
  }

  /// 列出截图库中的全部可管理截图。
  static Future<List<ScreenshotLibraryItem>> listScreenshotLibrary() async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'listScreenshotLibrary',
    );
    return (raw ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) =>
              ScreenshotLibraryItem.fromMap(item.cast<Object?, Object?>()),
        )
        .toList(growable: false);
  }

  /// 读取指定截图文件的原始字节内容。
  static Future<Uint8List?> readScreenshotFileBytes({
    required String sourceKind,
    required String pathOrIdentifier,
  }) async {
    final trimmedSource = sourceKind.trim();
    final trimmedPath = pathOrIdentifier.trim();
    if (trimmedSource.isEmpty || trimmedPath.isEmpty) return null;
    return _channel.invokeMethod<Uint8List>(
      'readScreenshotFileBytes',
      <String, Object?>{
        'sourceKind': trimmedSource,
        'pathOrIdentifier': trimmedPath,
      },
    );
  }

  /// 批量删除截图库中的截图文件，并返回实际删除数量。
  static Future<int> deleteScreenshotFiles(
    List<ScreenshotLibraryItem> items,
  ) async {
    if (items.isEmpty) return 0;
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'deleteScreenshotFiles',
      <String, Object?>{
        'items': items.map((item) => item.toDeletePayload()).toList(),
      },
    );
    if (raw == null || raw.isEmpty) return 0;
    return switch (raw['deletedCount']) {
      final int value => value,
      final num value => value.toInt(),
      _ => 0,
    };
  }

  /// 判断给定标识是否为授权目录体系下的逻辑标识。
  static bool isScopedIdentifier(String identifier) {
    final trimmed = identifier.trim();
    return trimmed.isNotEmpty && !trimmed.startsWith('/');
  }
}
