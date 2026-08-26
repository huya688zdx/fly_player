import 'package:flutter/material.dart';

import '../media_backend/media_image_request.dart';

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
/// 鉴权中立（H-019/H-021 收口）：只消费 [MediaImageRequest]（URL 候选 + header +
/// 自鉴权标志），不感知 NAS token / Emby `api_key` 等后端私有语义；请求对象由
/// `DetailArtworkResolver` / `mediaImageRequestForUrls` 单一入口产出。
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

  /// 构造与背景组件缓存键一致的预取 provider：取请求首候选（即详情 hero 实际展示位）。
  /// 请求不可加载（无候选，或既无 header 鉴权也非自鉴权直链——与展示端回退底色同口径）
  /// 时返回 null（跳过预取）。headers 只影响预取请求本身，不参与 NetworkImage 缓存键。
  static ImageProvider? precacheProvider({
    required MediaImageRequest images,
    required double screenWidth,
    required double devicePixelRatio,
  }) {
    if (!images.canLoad) return null;
    final url = images.urls.first.trim();
    if (url.isEmpty) return null;
    return ResizeImage(
      NetworkImage(
        url,
        headers: images.headers.isEmpty ? null : images.headers,
      ),
      width: cacheWidthFor(
        targetWidth: screenWidth,
        devicePixelRatio: devicePixelRatio,
      ),
    );
  }
}
