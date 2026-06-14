import 'dart:io';

import '../api/feiniu_api.dart';
import '../providers/nas_provider.dart';

/// 原生壳封面离线预取。
///
/// 原生壳的封面（纯听模式背景/海报、MediaSession 通知封面）走网络 URL，断网即空白。
/// 启动原生壳前，Flutter 侧把封面下载为本地缓存文件并把路径塞进 loadArgs
/// (`posterLocalPath`)，原生侧优先取本地路径、网络路径仅作回退。
///
/// 对齐 [NativeDanmakuPrefetch] 的「Flutter 解析 → 落临时文件 → 路径随 Intent 给原生壳」
/// 模式；文件落 `Directory.systemTemp`（Android 上即 app cache 目录，原生同 app 可读）。
class NativeArtworkPrefetch {
  const NativeArtworkPrefetch._();

  /// 把 [posterPath] 对应封面缓存成本地文件，返回路径。已有有效缓存直接复用（断网也命中）。
  /// 失败返回 null（调用方不塞 posterLocalPath，原生回退网络 URL）。
  static Future<String?> resolveToFile(
    NasProvider nas,
    String posterPath,
  ) async {
    final raw = posterPath.trim();
    if (raw.isEmpty) return null;
    try {
      final safeKey = raw.hashCode.toUnsigned(32).toRadixString(16);
      final file = File(
        '${Directory.systemTemp.path}/native_artwork_$safeKey.img',
      );
      // 命中既有缓存：断网时这条路径让封面仍可显示，且省一次下载。
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
      final bytes = await FeiniuApi(nas).downloadImageBytes(raw);
      if (bytes == null || bytes.isEmpty) return null;
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
