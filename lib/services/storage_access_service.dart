import 'package:flutter/services.dart';

class ScopedBrowserDirectory {
  final String id;
  final String name;

  const ScopedBrowserDirectory({required this.id, required this.name});

  factory ScopedBrowserDirectory.fromMap(Map<Object?, Object?> raw) {
    return ScopedBrowserDirectory(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
    );
  }
}

class ScopedBrowserEntry {
  final String id;
  final String name;
  final bool isDirectory;
  final int sizeBytes;

  const ScopedBrowserEntry({
    required this.id,
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
  });

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

class ScopedBrowserListing {
  final ScopedBrowserDirectory directory;
  final List<ScopedBrowserEntry> entries;

  const ScopedBrowserListing({required this.directory, required this.entries});

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

class LocalBrowserFileSelection {
  final String identifier;
  final String displayName;

  const LocalBrowserFileSelection({
    required this.identifier,
    required this.displayName,
  });
}

class ScreenshotCustomDirectoryInfo {
  final String id;
  final String name;
  final String locationLabel;
  final bool available;

  const ScreenshotCustomDirectoryInfo({
    required this.id,
    required this.name,
    required this.locationLabel,
    required this.available,
  });

  factory ScreenshotCustomDirectoryInfo.fromMap(Map<Object?, Object?> raw) {
    return ScreenshotCustomDirectoryInfo(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
      locationLabel: (raw['locationLabel'] ?? '').toString(),
      available: raw['available'] == true,
    );
  }
}

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

  Map<String, String> toDeletePayload() {
    return <String, String>{
      'sourceKind': sourceKind,
      'pathOrIdentifier': pathOrIdentifier,
    };
  }
}

class StorageAccessService {
  static const MethodChannel _channel = MethodChannel('fly_player/storage');

  static Future<bool> hasFileAccess() async {
    final result = await _channel.invokeMethod<bool>('hasFileAccess');
    return result == true;
  }

  static Future<bool> requestFileAccess() async {
    final result = await _channel.invokeMethod<bool>('requestFileAccess');
    return result == true;
  }

  static Future<bool> openFileAccessSettings() async {
    final result = await _channel.invokeMethod<bool>('openFileAccessSettings');
    return result == true;
  }

  static Future<String> primaryStorageRoot() async {
    final path = await _channel.invokeMethod<String>('getPrimaryStorageRoot');
    return (path ?? '/storage/emulated/0').trim();
  }

  static Future<ScopedBrowserDirectory?> getScopedTreeRoot() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getScopedTreeRoot',
    );
    if (raw == null || raw.isEmpty) return null;
    final directory = ScopedBrowserDirectory.fromMap(raw);
    if (directory.id.trim().isEmpty) return null;
    return directory;
  }

  static Future<ScopedBrowserDirectory?> requestScopedTreeAccess() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'requestScopedTreeAccess',
    );
    if (raw == null || raw.isEmpty) return null;
    final directory = ScopedBrowserDirectory.fromMap(raw);
    if (directory.id.trim().isEmpty) return null;
    return directory;
  }

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

  static Future<Uint8List?> readScopedFileBytes(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return null;
    return _channel.invokeMethod<Uint8List>(
      'readScopedFileBytes',
      <String, Object?>{'identifier': trimmed},
    );
  }

  static Future<ScreenshotCustomDirectoryInfo?>
  getScreenshotCustomDirectory() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getScreenshotCustomDirectory',
    );
    if (raw == null || raw.isEmpty) return null;
    return ScreenshotCustomDirectoryInfo.fromMap(raw);
  }

  static Future<ScreenshotCustomDirectoryInfo?>
  requestScreenshotCustomDirectory() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'requestScreenshotCustomDirectory',
    );
    if (raw == null || raw.isEmpty) return null;
    return ScreenshotCustomDirectoryInfo.fromMap(raw);
  }

  static Future<bool> clearScreenshotCustomDirectory() async {
    final result = await _channel.invokeMethod<bool>(
      'clearScreenshotCustomDirectory',
    );
    return result == true;
  }

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

  static bool isScopedIdentifier(String identifier) {
    final trimmed = identifier.trim();
    return trimmed.isNotEmpty && !trimmed.startsWith('/');
  }
}
