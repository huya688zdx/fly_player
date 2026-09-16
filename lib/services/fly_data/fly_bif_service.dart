import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../playback/playback_source.dart';

import 'fly_data_service.dart';
import 'fly_oped.dart';
import 'fly_playback_service_client.dart';

/// Metadata copies and signed-URL renewal keep the same playback context.
/// An actual item/version/session replacement invalidates previews and leases.
class FlyBifPlaybackIdentity {
  FlyBifPlaybackIdentity(MpvMediaSource source) : _value = _identity(source);
  final (String, String, String, int) _value;
  static (String, String, String, int) _identity(MpvMediaSource source) =>
      (source.statsScope, source.itemGuid, source.mediaGuid, source.loadNonce);
  bool matches(MpvMediaSource source) => _value == _identity(source);
}

/// Immutable authorization snapshot. A late response cannot follow a new login,
/// binding, playback source, or native reverse-channel owner.
class FlyBifAccess {
  FlyBifAccess({
    required this.session,
    required this.source,
    required this.isCurrent,
  });
  final FlyDataSession session;
  final FlySourceRef source;
  final bool Function() isCurrent;

  static FlyBifAccess? capture({
    required String statsScope,
    required String itemGuid,
    required String mediaGuid,
    required bool Function() isCurrent,
  }) {
    try {
      final client = FlyPlaybackServiceClient.instance;
      final source = client.sourceRef(
        statsScope: statsScope,
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
      );
      final session = FlyDataService.instance.session;
      final epoch = client.epoch;
      if (source == null ||
          session == null ||
          session.serviceInstanceId.isEmpty) {
        return null;
      }
      return FlyBifAccess(
        session: session,
        source: source,
        isCurrent: () =>
            isCurrent() &&
            identical(session, FlyDataService.instance.session) &&
            epoch == client.epoch &&
            client
                    .sourceRef(
                      statsScope: statsScope,
                      itemGuid: itemGuid,
                      mediaGuid: mediaGuid,
                    )
                    ?.matches(source.toJson()) ==
                true,
      );
    } catch (_) {
      return null;
    }
  }
}

class FlyBifAsset {
  FlyBifAsset._(
    this.id,
    this.url,
    this.digest,
    this.bytes,
    this.frameCount,
    this.durationMs,
    this.fileRevision,
    this.coordinate,
  );
  final String id, url, digest, fileRevision, coordinate;
  final int bytes, frameCount, durationMs;
  static const maxBytes = 128 * 1024 * 1024;

  static FlyBifAsset? parse(Map<String, dynamic> data, FlySourceRef source) {
    final context = data['file_context'], asset = data['asset'];
    if (data['status'] != 'ready' ||
        context is! Map ||
        asset is! Map ||
        context['identity_state'] != 'verified' ||
        !source.matches(context['source_ref'])) {
      return null;
    }
    final id = asset['id'], url = asset['url'], digest = asset['sha256'];
    final bytes = asset['bytes'],
        count = asset['frame_count'],
        duration = context['duration_ms'];
    final file = context['file_revision_id'],
        coordinate = context['media_coordinate_id'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        url is! String ||
        digest is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest) ||
        file is! String ||
        file.isEmpty ||
        coordinate is! String ||
        coordinate.isEmpty ||
        bytes is! int ||
        bytes < 80 ||
        bytes > maxBytes ||
        count is! int ||
        count < 1 ||
        count > 200000 ||
        duration is! int ||
        duration <= 0 ||
        duration > 9007199254740991 ||
        asset['duration_ms'] != duration ||
        asset['coverage_start_ms'] != 0 ||
        asset['coverage_end_ms'] != duration ||
        asset['width'] is! int ||
        (asset['width'] as int) <= 0 ||
        (asset['width'] as int) > 4096 ||
        asset['height'] is! int ||
        (asset['height'] as int) <= 0 ||
        (asset['height'] as int) > 4096 ||
        asset['interval_ms'] is! int ||
        (asset['interval_ms'] as int) <= 0) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        !url.startsWith('/api/v1/bif/assets/') ||
        uri.path != '/api/v1/bif/assets/$id/content') {
      return null;
    }
    final expected = source.toJson()
      ..removeWhere((key, value) => value == null);
    final query = uri.queryParametersAll;
    if (query.length != expected.length ||
        expected.entries.any(
          (entry) =>
              query[entry.key]?.length != 1 ||
              query[entry.key]!.single != entry.value,
        )) {
      return null;
    }
    return FlyBifAsset._(
      id,
      url,
      digest.toLowerCase(),
      bytes,
      count,
      duration,
      file,
      coordinate,
    );
  }

  /// Validate the complete index before any platform parser receives the file.
  bool accepts(Uint8List value) {
    if (value.length != bytes ||
        sha256.convert(value).toString() != digest ||
        value.length < 80 ||
        !_magic.asMap().entries.every((e) => value[e.key] == e.value)) {
      return false;
    }
    final data = ByteData.sublistView(value);
    int u32(int offset) => data.getUint32(offset, Endian.little);
    if (u32(8) != 0 || u32(12) != frameCount) return false;
    final end = 64 + (frameCount + 1) * 8;
    if (end > value.length ||
        u32(64) != 0 ||
        u32(64 + frameCount * 8) != 0xffffffff) {
      return false;
    }
    final multiplier = u32(16) == 0 ? 1000 : u32(16);
    var previousOffset = end, previousTime = -1;
    for (var i = 0; i <= frameCount; i++) {
      final offset = u32(68 + i * 8);
      if (offset < previousOffset ||
          offset > value.length ||
          (i > 0 && offset == previousOffset)) {
        return false;
      }
      previousOffset = offset;
      if (i < frameCount) {
        final time = u32(64 + i * 8) * multiplier;
        if (time <= previousTime || time >= durationMs) return false;
        previousTime = time;
      }
    }
    return previousOffset == value.length;
  }

  static const _magic = [0x89, 0x42, 0x49, 0x46, 13, 10, 26, 10];
}

/// Only local verified paths leave this service. Fly credentials are never
/// supplied to media image clients, URLs, or playback loadArgs.
class FlyBifService {
  FlyBifService({
    Future<Directory> Function()? cacheDirectory,
    Future<Map<String, dynamic>> Function(FlyDataSession, FlySourceRef)?
    request,
    Future<Uint8List> Function(FlyDataSession, FlyBifAsset)? download,
  }) : _cacheDirectory =
           cacheDirectory ??
           (() async => Directory(
             p.join((await getApplicationCacheDirectory()).path, 'fly_bif'),
           )),
       _request = request ?? _resolve,
       _download = download ?? _fetch;
  static final instance = FlyBifService();
  final Future<Directory> Function() _cacheDirectory;
  final Future<Map<String, dynamic>> Function(FlyDataSession, FlySourceRef)
  _request;
  final Future<Uint8List> Function(FlyDataSession, FlyBifAsset) _download;

  Future<String?> resolve(FlyBifAccess access) async {
    File? temporary;
    try {
      if (!access.isCurrent()) return null;
      final data = await _request(access.session, access.source);
      if (!access.isCurrent()) return null;
      final asset = FlyBifAsset.parse(data, access.source);
      if (asset == null) return null;
      final directory = await _cacheDirectory();
      if (!access.isCurrent()) return null;
      await directory.create(recursive: true);
      final key = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                access.session.serviceInstanceId,
                access.session.userId,
                access.source.toJson(),
                asset.fileRevision,
                asset.coordinate,
                asset.id,
                asset.digest,
              ]),
            ),
          )
          .toString();
      final file = File(p.join(directory.path, '$key.bif'));
      if (await file.exists() &&
          await file.length() == asset.bytes &&
          await _valid(asset, await file.readAsBytes())) {
        return access.isCurrent() ? file.path : null;
      }
      if (!access.isCurrent()) return null;
      final bytes = await _download(access.session, asset);
      if (!access.isCurrent() ||
          !await _valid(asset, bytes) ||
          !access.isCurrent()) {
        return null;
      }
      temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await temporary.writeAsBytes(bytes, flush: true);
      if (!access.isCurrent()) return null;
      // Windows rename cannot replace an existing damaged cache entry.
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      temporary = null;
      await _trim(directory, file.path);
      return access.isCurrent() ? file.path : null;
    } catch (_) {
      return null;
    } finally {
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {
          /* best effort */
        }
      }
    }
  }

  static Future<Map<String, dynamic>> _resolve(
    FlyDataSession session,
    FlySourceRef source,
  ) async {
    final api = session.createApi(maxResponseBytes: 64 * 1024);
    try {
      return await api
          .post('/bif/resolve', {'source_ref': source.toJson()})
          .timeout(const Duration(seconds: 3));
    } finally {
      api.close();
    }
  }

  static Future<bool> _valid(FlyBifAsset asset, Uint8List bytes) =>
      Isolate.run(() => asset.accepts(bytes));

  static Future<Uint8List> _fetch(
    FlyDataSession session,
    FlyBifAsset asset,
  ) async {
    final api = session.createApi();
    try {
      return await api
          .bifBytes(asset.url, expectedBytes: asset.bytes)
          .timeout(const Duration(seconds: 60));
    } finally {
      api.close();
    }
  }

  static Future<void> _trim(Directory directory, String keep) async {
    final files = await directory
        .list()
        .where((f) => f is File && f.path.endsWith('.bif') && f.path != keep)
        .cast<File>()
        .toList();
    final dated = <(File, DateTime)>[];
    for (final file in files) {
      dated.add((file, await file.lastModified()));
    }
    dated.sort((a, b) => a.$2.compareTo(b.$2));
    for (final entry in dated.take(
      (dated.length - 15).clamp(0, dated.length),
    )) {
      await entry.$1.delete();
    }
  }
}
