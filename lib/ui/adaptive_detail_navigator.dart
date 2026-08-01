import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media_backend/media_image_ref.dart';
import '../models/media_library_item.dart';
import '../providers/nas_provider.dart';
import 'detail_artwork_resolver.dart';
import 'detail_hero_image.dart';
import 'detail_theme_prewarmer.dart';
import '../services/detail_route_payload_store.dart';
import '../services/embedded_detail_launcher.dart';
import '../pages/media_collection_detail_page.dart';
import '../pages/tv_season_detail_page.dart';
import '../screens/person_detail_screen.dart';
import '../screens/play_detail_screen.dart';
import 'app_transitions.dart';
import 'detail_presentation.dart';
import 'player_pane_host_scope.dart';
import '../utils/async_action_guard.dart';

class AdaptiveDetailRequest {
  final Route<dynamic> Function(DetailPresentation presentation) buildRoute;
  final Future<bool> Function()? tryOpenEmbedded;
  final String? localRouteName;
  final String? actionKey;

  /// 目标详情 hero 背景的 backdrop 路径（点击时已知则填）。用于整页详情 push 前预取大图
  /// （Phase 4.1）。为空则不预取。仅整页（非 pane）路径会用到（嵌入详情走独立引擎缓存不通）。
  /// 飞牛相对路径专用；完整直链后端走 [heroImageRefs]。
  final String? heroBackdropPath;

  /// 目标详情 hero 的中立图引用候选（按详情页背景展示优先级排列：背景图在前、海报兜底）。
  /// 完整直链（Emby 等自鉴权 URL）由导航层直接按背景组件同款缓存键预取（H-019/H-021），
  /// 与后端无关；为空或非直链时回退 [heroBackdropPath] 的飞牛管线。
  final List<MediaImageRef> heroImageRefs;

  /// 目标详情页 DynamicPageThemeScope 的 pageKey（各工厂按目标页的键规则填写）。
  /// 用于 push 前预热取色 scheme（[DetailThemePrewarmer]）；为空则跳过预热。
  final String themePageKey;

  const AdaptiveDetailRequest._({
    required this.buildRoute,
    this.tryOpenEmbedded,
    this.localRouteName,
    this.actionKey,
    this.heroBackdropPath,
    this.heroImageRefs = const <MediaImageRef>[],
    this.themePageKey = '',
  });

  static String _backdropFrom(Map<String, dynamic>? detail) {
    if (detail == null) return '';
    return (detail['backdrops'] ?? detail['backdrop'] ?? '').toString().trim();
  }

  factory AdaptiveDetailRequest.item({
    required String itemGuid,
    String seriesGuid = '',
    String? heroTag,
    Map<String, dynamic>? initialItemDetail,
    List<MediaImageRef> heroImageRefs = const <MediaImageRef>[],
  }) {
    return AdaptiveDetailRequest._(
      buildRoute: (presentation) => AppTransitions.leftToRightPageTurnRoute(
        PlayDetailScreen(
          itemGuid: itemGuid,
          seriesGuid: seriesGuid,
          heroTag: heroTag,
          initialItemDetail: initialItemDetail,
          presentation: presentation,
        ),
      ),
      tryOpenEmbedded: () => EmbeddedDetailLauncher.openItemDetail(
        itemGuid,
        seriesGuid: seriesGuid,
        initialItemDetail: initialItemDetail,
      ),
      localRouteName: DetailRoutePayloadStore.routeNameForItem(
        itemGuid: itemGuid,
        seriesGuid: seriesGuid,
        initialItemDetail: initialItemDetail,
      ),
      actionKey: 'item:${itemGuid.trim()}:${seriesGuid.trim()}',
      heroBackdropPath: _backdropFrom(initialItemDetail),
      heroImageRefs: heroImageRefs,
      // play_detail/tv_detail 的 DynamicPageThemeScope.pageKey 均为 itemGuid。
      themePageKey: itemGuid.trim(),
    );
  }

  factory AdaptiveDetailRequest.person({
    required String personGuid,
    String initialName = '',
    Map<String, dynamic> initialLocaleMap = const <String, dynamic>{},
  }) {
    return AdaptiveDetailRequest._(
      buildRoute: (presentation) => AppTransitions.leftToRightPageTurnRoute(
        PersonDetailScreen(
          personGuid: personGuid,
          initialName: initialName,
          initialLocaleMap: initialLocaleMap,
          presentation: presentation,
        ),
      ),
      tryOpenEmbedded: () => EmbeddedDetailLauncher.openPersonDetail(
        personGuid: personGuid,
        initialName: initialName,
      ),
      localRouteName: Uri(
        path: '/detail/person',
        queryParameters: <String, String>{
          'personGuid': personGuid.trim(),
          if (initialName.trim().isNotEmpty) 'initialName': initialName.trim(),
        },
      ).toString(),
      actionKey: 'person:${personGuid.trim()}',
      // person_detail_screen 的 DynamicPageThemeScope.pageKey 为 personGuid。
      themePageKey: personGuid.trim(),
    );
  }

  factory AdaptiveDetailRequest.season({
    required String parentGuid,
    required String seriesTitle,
    required String backdropPath,
    required MediaLibraryItem seasonItem,
    List<MediaLibraryItem>? initialSeasonItems,
  }) {
    return AdaptiveDetailRequest._(
      buildRoute: (presentation) => AppTransitions.leftToRightPageTurnRoute(
        TvSeasonDetailPage(
          parentGuid: parentGuid,
          seriesTitle: seriesTitle,
          backdropPath: backdropPath,
          seasonItem: seasonItem,
          initialSeasonItems: initialSeasonItems,
          presentation: presentation,
        ),
      ),
      tryOpenEmbedded: () => EmbeddedDetailLauncher.openSeasonDetail(
        parentGuid: parentGuid,
        seriesTitle: seriesTitle,
        backdropPath: backdropPath,
        seasonItem: seasonItem,
      ),
      localRouteName: DetailRoutePayloadStore.routeNameForSeason(
        parentGuid: parentGuid,
        seriesTitle: seriesTitle,
        backdropPath: backdropPath,
        seasonItem: seasonItem.toJson(),
      ),
      actionKey: 'season:${parentGuid.trim()}:${seasonItem.guid.trim()}',
      heroBackdropPath: backdropPath.trim(),
      // 对齐 tv_season_detail_page._seasonDynamicThemeKey 的键规则。
      themePageKey: parentGuid.trim().isNotEmpty
          ? 'tv-season-series:${parentGuid.trim()}'
          : '',
    );
  }

  factory AdaptiveDetailRequest.library({
    required String itemGuid,
    String? heroTag,
    Map<String, dynamic>? initialItemDetail,
    List<MediaImageRef> heroImageRefs = const <MediaImageRef>[],
  }) {
    return AdaptiveDetailRequest._(
      buildRoute: (presentation) => AppTransitions.leftToRightPageTurnRoute(
        MediaCollectionDetailPage(
          itemGuid: itemGuid,
          heroTag: heroTag,
          initialItemDetail: initialItemDetail,
          presentation: presentation,
        ),
      ),
      tryOpenEmbedded: () => EmbeddedDetailLauncher.openItemDetail(itemGuid),
      localRouteName: Uri(
        path: '/detail/item',
        queryParameters: <String, String>{'itemGuid': itemGuid.trim()},
      ).toString(),
      actionKey: 'item:${itemGuid.trim()}:',
      heroBackdropPath: _backdropFrom(initialItemDetail),
      heroImageRefs: heroImageRefs,
      // media_collection_detail_page 的 DynamicPageThemeScope.pageKey 为 itemGuid。
      themePageKey: itemGuid.trim(),
    );
  }
}

class AdaptiveDetailNavigator {
  const AdaptiveDetailNavigator._();

  static Future<T?> open<T>(
    BuildContext context,
    AdaptiveDetailRequest request, {
    DetailPresentation presentation = DetailPresentation.page,
  }) async {
    final routeName = request.localRouteName?.trim() ?? '';
    final guardKey = request.actionKey?.trim().isNotEmpty == true
        ? request.actionKey!.trim()
        : routeName;
    if (guardKey.isNotEmpty) {
      return AsyncActionGuard.run<T?>(
        'adaptive_detail:${presentation.name}:$guardKey',
        settleDuration: const Duration(milliseconds: 450),
        action: () =>
            _openInternal<T>(context, request, presentation: presentation),
      );
    }
    return _openInternal<T>(context, request, presentation: presentation);
  }

  static Future<T?> _openInternal<T>(
    BuildContext context,
    AdaptiveDetailRequest request, {
    required DetailPresentation presentation,
  }) async {
    final navigator = Navigator.of(context);
    // push/pane 打开前预热目标页取色 scheme + 提前应用全局运行时主题：seed 命中
    // 缓存时详情首帧免冷跑 HCT，且转场里新旧两页已是目标配色（不再"进页后整页
    // 配色晚一步跳变"）。必须 await：push 同步置起转场计数，其后的主题发布会被
    // 转场收口推迟。内部为微任务级等待，无可感延迟。
    if (request.themePageKey.isNotEmpty) {
      await DetailThemePrewarmer.warmUp(
        context,
        pageKey: request.themePageKey,
        imageUrl: _firstDirectHeroUrl(request),
      );
      if (!context.mounted) return null;
    }
    final paneHost = PlayerPaneHostScope.maybeOf(context);
    final localRouteName = request.localRouteName;
    if (presentation == DetailPresentation.pane &&
        paneHost != null &&
        localRouteName != null &&
        localRouteName.trim().isNotEmpty) {
      await paneHost.openRoute(localRouteName);
      return null;
    }
    final tryOpenEmbedded = request.tryOpenEmbedded;
    if (presentation == DetailPresentation.pane &&
        tryOpenEmbedded != null &&
        await tryOpenEmbedded()) {
      return null;
    }
    // Phase 4.1：整页详情（非 pane）push 前预取 hero 大图，让 decode/raster 抢在转场期间起步，
    // 落地少一个冷光栅尖峰。fire-and-forget、错误吞掉，绝不阻塞导航。嵌入(pane)路径不预取
    // （副引擎独立 ImageCache，主引擎预取无效，由低清占位兜底）。
    if (context.mounted) {
      _maybePrecacheHero(context, request, presentation);
    }
    return navigator.push<T>(request.buildRoute(presentation) as Route<T>);
  }

  /// 首个完整直链 hero 引用的 URL（无则空串）。同时是取色 seed 图缓存的回退查询键。
  static String _firstDirectHeroUrl(AdaptiveDetailRequest request) {
    for (final ref in request.heroImageRefs) {
      final url = ref.url.trim();
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
      }
    }
    return '';
  }

  static void _maybePrecacheHero(
    BuildContext context,
    AdaptiveDetailRequest request,
    DetailPresentation presentation,
  ) {
    if (presentation == DetailPresentation.pane) return;
    if (!context.mounted) return;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return;
    // 中立直链引用（Emby 等自鉴权 URL）优先：URL 自带凭据与尺寸参数，直接按
    // 背景组件同款缓存键预取，不依赖 NAS token（H-019/H-021）。只预取首个直链
    // 候选——它就是详情 hero 实际展示位；后续候选是失败兜底，不值得预热流量。
    // 图请求统一经 DetailArtworkResolver 产出（直链透传 ref 自带 header/自鉴权
    // 标志；飞牛 backdrop 相对路径拼候选 + NAS header），预取口不再自持鉴权分支。
    final nas = context.read<NasProvider>();
    final directUrl = _firstDirectHeroUrl(request);
    final resolver = DetailArtworkResolver(
      baseUrl: directUrl.isEmpty ? nas.baseUrl : '',
      token: directUrl.isEmpty ? nas.token : '',
      accessCode: directUrl.isEmpty ? nas.accessCode : '',
    );
    final MediaImageRequest heroImages;
    if (directUrl.isNotEmpty) {
      final ref = request.heroImageRefs.firstWhere(
        (ref) => ref.url.trim() == directUrl,
      );
      heroImages = resolver.resolveRef(ref);
    } else {
      final backdrop = request.heroBackdropPath?.trim() ?? '';
      if (backdrop.isEmpty) return;
      heroImages = resolver.resolvePath(
        backdrop,
        width: DetailHeroImage.fullPageServerWidth,
      );
    }
    final provider = DetailHeroImage.precacheProvider(
      images: heroImages,
      screenWidth: mq.size.width,
      devicePixelRatio: mq.devicePixelRatio,
    );
    if (provider == null) return;
    // 用根 context 预取，避免被 push 后 route 切换打断；错误（404/网络）静默忽略。
    precacheImage(provider, context).catchError((_) {});
  }
}
