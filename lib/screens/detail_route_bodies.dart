import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/media_library_item.dart';
import '../pages/tv_season_detail_page.dart';
import '../services/detail_route_payload_store.dart';
import '../ui/detail_presentation.dart';
import '../utils/swallowed_error_logger.dart';
import '../widgets/detail/detail_loading_skeleton.dart';
import 'play_detail_screen.dart';

class DetailItemRouteBody extends StatefulWidget {
  final String itemGuid;
  final String seriesGuid;
  final Map<String, dynamic>? initialItemDetail;
  final String? payloadToken;
  final DetailPresentation presentation;

  const DetailItemRouteBody({
    super.key,
    required this.itemGuid,
    this.seriesGuid = '',
    this.initialItemDetail,
    this.payloadToken,
    this.presentation = DetailPresentation.page,
  });

  @override
  State<DetailItemRouteBody> createState() => _DetailItemRouteBodyState();
}

class _DetailItemRouteBodyState extends State<DetailItemRouteBody> {
  Future<Map<String, dynamic>?>? _payloadFuture;
  Map<String, dynamic>? _cachedPayload;

  @override
  void initState() {
    super.initState();
    final token = widget.payloadToken?.trim() ?? '';
    if (token.isNotEmpty) {
      _cachedPayload = DetailRoutePayloadStore.readCachedPayload(token);
      if (_cachedPayload == null) {
        _payloadFuture = DetailRoutePayloadStore.readPayload(token);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemGuid = widget.itemGuid.trim();
    if (itemGuid.isEmpty) {
      return _DetailRouteStatusScreen(
        message: AppLocalizations.of(context).routeErrorMissingDetail,
      );
    }
    final cachedPayload = _cachedPayload;
    if (cachedPayload != null) {
      final initialItemDetail =
          _asStringMap(cachedPayload['initialItemDetail']) ??
          widget.initialItemDetail;
      return _buildContent(initialItemDetail);
    }
    final payloadFuture = _payloadFuture;
    if (payloadFuture == null) {
      return _buildContent(widget.initialItemDetail);
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: payloadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return DetailLoadingSkeleton(presentation: widget.presentation);
        }
        if (snapshot.hasError) {
          unawaited(
            logSwallowedError(
              action: 'read detail route payload',
              id: widget.payloadToken,
              error: snapshot.error ?? StateError('unknown payload error'),
              stackTrace: snapshot.stackTrace,
              source: 'detail_route_bodies',
              details: 'route=item',
            ),
          );
        }
        final payload = snapshot.data;
        final initialItemDetail =
            _asStringMap(payload?['initialItemDetail']) ??
            widget.initialItemDetail;
        return _buildContent(initialItemDetail);
      },
    );
  }

  Widget _buildContent(Map<String, dynamic>? initialItemDetail) {
    return PlayDetailScreen(
      itemGuid: widget.itemGuid,
      seriesGuid: widget.seriesGuid,
      initialItemDetail: initialItemDetail,
      presentation: widget.presentation,
    );
  }
}

class DetailSeasonRouteBody extends StatefulWidget {
  final String parentGuid;
  final String seriesTitle;
  final String backdropPath;
  final MediaLibraryItem? seasonItem;
  final String? seasonGuid;
  final String? payloadToken;
  final DetailPresentation presentation;

  const DetailSeasonRouteBody({
    super.key,
    required this.parentGuid,
    required this.seriesTitle,
    required this.backdropPath,
    this.seasonItem,
    this.seasonGuid,
    this.payloadToken,
    this.presentation = DetailPresentation.page,
  });

  @override
  State<DetailSeasonRouteBody> createState() => _DetailSeasonRouteBodyState();
}

class _DetailSeasonRouteBodyState extends State<DetailSeasonRouteBody> {
  Future<Map<String, dynamic>?>? _payloadFuture;
  Map<String, dynamic>? _cachedPayload;

  @override
  void initState() {
    super.initState();
    final token = widget.payloadToken?.trim() ?? '';
    if (token.isNotEmpty) {
      _cachedPayload = DetailRoutePayloadStore.readCachedPayload(token);
      if (_cachedPayload == null) {
        _payloadFuture = DetailRoutePayloadStore.readPayload(token);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cachedPayload = _cachedPayload;
    if (cachedPayload != null) {
      final payloadSeasonItem = _asStringMap(cachedPayload['seasonItem']);
      final seasonItem = payloadSeasonItem == null
          ? widget.seasonItem
          : MediaLibraryItem.fromJson(payloadSeasonItem);
      return _buildContent(seasonItem);
    }
    final payloadFuture = _payloadFuture;
    if (payloadFuture == null) {
      return _buildContent(widget.seasonItem);
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: payloadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return DetailLoadingSkeleton(presentation: widget.presentation);
        }
        if (snapshot.hasError) {
          unawaited(
            logSwallowedError(
              action: 'read detail route payload',
              id: widget.payloadToken,
              error: snapshot.error ?? StateError('unknown payload error'),
              stackTrace: snapshot.stackTrace,
              source: 'detail_route_bodies',
              details: 'route=season',
            ),
          );
        }
        final payloadSeasonItem = _asStringMap(snapshot.data?['seasonItem']);
        final seasonItem = payloadSeasonItem == null
            ? widget.seasonItem
            : MediaLibraryItem.fromJson(payloadSeasonItem);
        return _buildContent(seasonItem);
      },
    );
  }

  Widget _buildContent(MediaLibraryItem? seasonItem) {
    final parentGuid = widget.parentGuid.trim();
    final resolvedSeasonItem =
        seasonItem ?? _seasonItemFromGuid(widget.seasonGuid?.trim() ?? '');
    if (parentGuid.isEmpty || resolvedSeasonItem == null) {
      return _DetailRouteStatusScreen(
        message: AppLocalizations.of(context).routeErrorMissingSeason,
      );
    }
    return TvSeasonDetailPage(
      parentGuid: parentGuid,
      seriesTitle: widget.seriesTitle,
      backdropPath: widget.backdropPath,
      seasonItem: resolvedSeasonItem,
      presentation: widget.presentation,
    );
  }

  MediaLibraryItem? _seasonItemFromGuid(String seasonGuid) {
    if (seasonGuid.isEmpty) {
      return null;
    }
    return MediaLibraryItem.fromJson(<String, dynamic>{'guid': seasonGuid});
  }
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return null;
}

class _DetailRouteStatusScreen extends StatelessWidget {
  final String message;

  const _DetailRouteStatusScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: Text(
          message,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 16),
        ),
      ),
    );
  }
}
