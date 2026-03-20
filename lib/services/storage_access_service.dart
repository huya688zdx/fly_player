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

  static bool isScopedIdentifier(String identifier) {
    final trimmed = identifier.trim();
    return trimmed.isNotEmpty && !trimmed.startsWith('/');
  }
}
