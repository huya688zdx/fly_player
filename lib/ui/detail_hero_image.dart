import 'package:flutter/material.dart';

import '../utils/api_url_helper.dart';
import '../utils/nas_image_headers.dart';

/// 详情页 hero 背景图的统一构造口（URL / cacheWidth / ImageProvider）。
///
/// 用途：列表点击 → push 详情前 `precacheImage` 预取 hero，使首屏大图在转场期间就开始
/// decode/raster，落地时少一个 ~90ms 的冷光栅尖峰（见 docs 性能计划 §5.1）。
///
/// 关键：预取要命中详情页内 `ImmersiveDetailBackground` 的 `Image.network(cacheWidth)`
/// 缓存条目，构造的 ImageProvider 必须与之**逐字段一致**——`Image.network(url, headers,
/// cacheWidth)` 内部即 `ResizeImage(NetworkImage(url, scale:1.0, headers), width:cacheWidth)`
/// （NetworkImage 相等只看 url+scale，headers 不参与；ResizeImage 相等看 provider+width+
/// height(null)+policy(exact 默认)+allowUpscaling(false 默认)）。本 helper 集中这套算法，
/// 避免与背景组件里的公式漂移。
///
/// 注意：仅对**同引擎整页详情**有效（手机/整页）。平板嵌入详情走独立 Flutter 引擎、独立
/// ImageCache，主引擎预取进不到副引擎缓存——那条路径由低清占位（lowResUrls）兜底。
class DetailHeroImage {
  const DetailHeroImage._();

  /// 整页（非分屏 pane）hero 的服务端请求宽度，与各详情页一致：非 pane 恒为 1200。
  static const int fullPageServerWidth = 1200;

  /// 与 `ImmersiveDetailBackground._BackgroundImage` 内一致的 cacheWidth：
  /// `(targetWidth * dpr.clamp(1,1.6)).round().clamp(560,1440)`。
  static int cacheWidthFor({
    required double targetWidth,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio.clamp(1.0, 1.6);
    return (targetWidth * dpr).round().clamp(560, 1440);
  }

  /// 构造与背景组件缓存键一致的 ImageProvider；url/token 为空则返回 null。
  static ImageProvider? provider({
    required String url,
    required String token,
    required int cacheWidth,
  }) {
    if (url.trim().isEmpty || token.trim().isEmpty) return null;
    return ResizeImage(
      NetworkImage(url, headers: nasImageHeaders(token, url: url)),
      width: cacheWidth,
    );
  }

  /// 整页详情 hero 的预取 provider：综合 baseUrl/backdropPath/token + 屏宽/dpr 给出可直接
  /// `precacheImage` 的 provider。backdrop 为空、URL 解析失败或无 token 则返回 null（跳过）。
  static ImageProvider? fullPagePrecacheProvider({
    required String baseUrl,
    required String backdropPath,
    required String token,
    required double screenWidth,
    required double devicePixelRatio,
  }) {
    if (backdropPath.trim().isEmpty || token.trim().isEmpty) return null;
    final urls = ApiUrlHelper.imageCandidates(
      baseUrl,
      backdropPath,
      width: fullPageServerWidth,
    );
    if (urls.isEmpty) return null;
    return provider(
      url: urls.first,
      token: token,
      cacheWidth: cacheWidthFor(
        targetWidth: screenWidth,
        devicePixelRatio: devicePixelRatio,
      ),
    );
  }
}
