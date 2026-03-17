import 'package:flutter/material.dart';

import '../models/media_library_item.dart';
import '../services/embedded_detail_launcher.dart';
import '../pages/media_collection_detail_page.dart';
import '../pages/tv_season_detail_page.dart';
import '../screens/person_detail_screen.dart';
import '../screens/play_detail_screen.dart';
import 'app_transitions.dart';
import 'detail_presentation.dart';

class AdaptiveDetailRequest {
  final Route<dynamic> Function(DetailPresentation presentation) buildRoute;
  final Future<bool> Function()? tryOpenEmbedded;

  const AdaptiveDetailRequest._({
    required this.buildRoute,
    this.tryOpenEmbedded,
  });

  factory AdaptiveDetailRequest.item({
    required String itemGuid,
    String? heroTag,
    Map<String, dynamic>? initialItemDetail,
  }) {
    return AdaptiveDetailRequest._(
      buildRoute: (presentation) => AppTransitions.leftToRightPageTurnRoute(
        PlayDetailScreen(
          itemGuid: itemGuid,
          heroTag: heroTag,
          initialItemDetail: initialItemDetail,
          presentation: presentation,
        ),
      ),
      tryOpenEmbedded: () => EmbeddedDetailLauncher.openItemDetail(itemGuid),
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
    );
  }

  factory AdaptiveDetailRequest.season({
    required String parentGuid,
    required String seriesTitle,
    required String backdropPath,
    required MediaLibraryItem seasonItem,
  }) {
    return AdaptiveDetailRequest._(
      buildRoute: (presentation) => AppTransitions.leftToRightPageTurnRoute(
        TvSeasonDetailPage(
          parentGuid: parentGuid,
          seriesTitle: seriesTitle,
          backdropPath: backdropPath,
          seasonItem: seasonItem,
          presentation: presentation,
        ),
      ),
      tryOpenEmbedded: () => EmbeddedDetailLauncher.openSeasonDetail(
        parentGuid: parentGuid,
        seriesTitle: seriesTitle,
        backdropPath: backdropPath,
        seasonItem: seasonItem,
      ),
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
    );
  }
}

class AdaptiveDetailNavigator {
  const AdaptiveDetailNavigator._();

  static Future<T?> open<T>(
    BuildContext context,
    AdaptiveDetailRequest request,
    {DetailPresentation presentation = DetailPresentation.page}
  ) async {
    final navigator = Navigator.of(context);
    final tryOpenEmbedded = request.tryOpenEmbedded;
    if (presentation == DetailPresentation.pane &&
        tryOpenEmbedded != null &&
        await tryOpenEmbedded()) {
      return null;
    }
    return navigator.push<T>(
      request.buildRoute(presentation) as Route<T>,
    );
  }
}
