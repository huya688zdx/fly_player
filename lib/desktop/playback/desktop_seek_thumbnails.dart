import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../models/stream_track_data.dart';

/// 与安卓一致的 BIF 时间索引：取目标时间之前的最后一帧。
class _BifIndex {
  _BifIndex(this.bytes, this.times, this.offsets);

  final Uint8List bytes;
  final List<int> times;
  final List<int> offsets;

  static _BifIndex? parse(Uint8List bytes) {
    const magic = [0x89, 0x42, 0x49, 0x46, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length < 80 || !listEquals(bytes.sublist(0, 8), magic)) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    int uint32(int offset) => data.getUint32(offset, Endian.little);
    final count = uint32(12);
    final indexEnd = 64 + (count + 1) * 8;
    if (count == 0 || count > 200000 || indexEnd > bytes.length) return null;
    final multiplier = uint32(16) == 0 ? 1000 : uint32(16);
    final times = <int>[];
    final offsets = <int>[];
    var previousOffset = indexEnd;
    for (var i = 0; i <= count; i++) {
      final offset = uint32(64 + i * 8 + 4);
      if (offset < previousOffset || offset > bytes.length) return null;
      offsets.add(offset);
      previousOffset = offset;
      if (i < count) {
        final time = uint32(64 + i * 8) * multiplier;
        if (times.isNotEmpty && time < times.last) return null;
        times.add(time);
      }
    }
    return _BifIndex(bytes, times, offsets);
  }

  int frameAt(int positionMs) {
    var low = 0;
    var high = times.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (times[mid] <= positionMs) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}

/// 当前播放源的预览数据；后台装载 BIF，未就绪或失败时使用章节图。
class DesktopSeekThumbnails extends ChangeNotifier {
  String _bifUrl = '';
  Map<String, String> _headers = const {};
  List<MpvSeekThumbnail> _chapters = const [];
  _BifIndex? _bif;
  HttpClient? _client;
  int _generation = 0;
  final _frames = <int, MemoryImage>{};

  int get generation => _generation;

  Future<void> prepare({
    required String bifUrl,
    required List<MpvSeekThumbnail> chapters,
    required Map<String, String> headers,
  }) {
    _chapters = chapters;
    if (_bifUrl == bifUrl && mapEquals(_headers, headers)) {
      return Future.value();
    }
    _bifUrl = bifUrl;
    _headers = Map.of(headers);
    _generation++;
    _client?.close(force: true);
    _client = null;
    _bif = null;
    _frames.clear();
    return bifUrl.isEmpty ? Future.value() : _load(_generation);
  }

  NetworkImage? chapterAt(int positionMs) {
    if (_chapters.isEmpty) return null;
    var chosen = _chapters.first;
    for (final chapter in _chapters) {
      if (chapter.positionMs > positionMs) break;
      chosen = chapter;
    }
    return NetworkImage(chosen.url, headers: _headers);
  }

  ImageProvider? imageAt(int positionMs) {
    final bif = _bif;
    if (bif == null) return chapterAt(positionMs);
    final index = bif.frameAt(positionMs);
    // 复用同一帧的 ImageProvider，让来回移动命中 Flutter 的解码缓存。
    final image =
        _frames.remove(index) ??
        MemoryImage(
          bif.bytes.sublist(bif.offsets[index], bif.offsets[index + 1]),
        );
    _frames[index] = image;
    if (_frames.length > 24) _frames.remove(_frames.keys.first);
    return image;
  }

  Future<void> _load(int generation) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _client = client;
    try {
      final bytes = await _download(
        client,
        Uri.parse(_bifUrl),
        _headers,
      ).timeout(const Duration(seconds: 60));
      if (generation != _generation || bytes == null) return;
      _bif = _BifIndex.parse(bytes);
      if (_bif != null) notifyListeners();
    } catch (_) {
      // 未生成 BIF、网络或索引错误只影响预览，不打断播放、不反复请求。
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }

  Future<Uint8List?> _download(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    const maxBytes = 128 * 1024 * 1024;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      headers.forEach((name, value) => request.headers.set(name, value));
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) return null;
        final next = uri.resolve(location);
        // 与安卓一致：鉴权请求只跟随同源跳转。
        if (next.origin != uri.origin) return null;
        await response.drain<void>();
        uri = next;
        continue;
      }
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > maxBytes) {
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxBytes) return null;
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }
    return null;
  }

  @override
  void dispose() {
    _generation++;
    _client?.close(force: true);
    _bif = null;
    _frames.clear();
    super.dispose();
  }
}
