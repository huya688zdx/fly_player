import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_library_item.dart';
import '../providers/nas_provider.dart';
import 'detail_hero_image.dart';
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
  final String? heroBackdropPath;

  const AdaptiveDetailRequest._({
    required this.buildRoute,
    this.tryOpenEmbedded,
    this.localRouteName,
    this.actionKey,
    this.heroBackdropPath,
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
    );
  }

  factory AdaptiveDetailRequest.library({
    required String itemGuid,
    String? heroTag,
    Map<String, dynamic>? initialItemDetail,
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

  static void _maybePrecacheHero(
    BuildContext context,
    AdaptiveDetailRequest request,
    DetailPresentation presentation,
  ) {
    if (presentation == DetailPresentation.pane) return;
    if (!context.mounted) return;
    final backdrop = request.heroBackdropPath?.trim() ?? '';
    if (backdrop.isEmpty) return;
    final nas = context.read<NasProvider>();
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return;
    final provider = DetailHeroImage.fullPagePrecacheProvider(
      baseUrl: nas.baseUrl,
      backdropPath: backdrop,
      token: nas.token,
      screenWidth: mq.size.width,
      devicePixelRatio: mq.devicePixelRatio,
    );
    if (provider == null) return;
    // 用根 context 预取，避免被 push 后 route 切换打断；错误（404/网络）静默忽略。
    precacheImage(provider, context).catchError((_) {});
  }
}
