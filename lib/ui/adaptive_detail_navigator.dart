import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/media_library_item.dart';
import '../services/embedded_detail_launcher.dart';
import '../pages/media_collection_detail_page.dart';
import '../pages/tv_season_detail_page.dart';
import '../screens/person_detail_screen.dart';
import '../screens/play_detail_screen.dart';
import 'app_transitions.dart';
import 'detail_presentation.dart';
import 'player_pane_host_scope.dart';

class AdaptiveDetailRequest {
  final Route<dynamic> Function(DetailPresentation presentation) buildRoute;
  final Future<bool> Function()? tryOpenEmbedded;
  final String? localRouteName;

  const AdaptiveDetailRequest._({
    required this.buildRoute,
    this.tryOpenEmbedded,
    this.localRouteName,
  });

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
      localRouteName: Uri(
        path: '/detail/item',
        queryParameters: <String, String>{
          'itemGuid': itemGuid.trim(),
          if (seriesGuid.trim().isNotEmpty) 'seriesGuid': seriesGuid.trim(),
          if (initialItemDetail != null)
            'initialItemDetail': jsonEncode(initialItemDetail),
        },
      ).toString(),
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
      localRouteName: Uri(
        path: '/detail/season',
        queryParameters: <String, String>{
          'parentGuid': parentGuid.trim(),
          'seriesTitle': seriesTitle.trim(),
          'backdropPath': backdropPath.trim(),
          'seasonItem': jsonEncode(seasonItem.toJson()),
        },
      ).toString(),
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
    return navigator.push<T>(request.buildRoute(presentation) as Route<T>);
  }
}
