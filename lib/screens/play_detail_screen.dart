import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../media_backend/media_backend_kind.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../theme/app_theme.dart';
import '../ui/detail_presentation.dart';
import '../utils/app_exception.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/detail_loading_skeleton.dart';
import '../pages/media_collection_detail_page.dart';
import '../pages/play_detail_page.dart';
import '../pages/tv_detail_page.dart';

enum DetailPageMode { movie, tv, library }

class PlayDetailScreen extends StatefulWidget {
  final String itemGuid;
  final String seriesGuid;
  final String? heroTag;
  final Map<String, dynamic>? initialItemDetail;
  final DetailPresentation presentation;

  const PlayDetailScreen({
    super.key,
    required this.itemGuid,
    this.seriesGuid = '',
    this.heroTag,
    this.initialItemDetail,
    this.presentation = DetailPresentation.page,
  });

  @override
  State<PlayDetailScreen> createState() => _PlayDetailScreenState();
}

class _PlayDetailScreenState extends State<PlayDetailScreen> {
  bool _loading = true;
  AppException? _error;
  DetailPageMode _mode = DetailPageMode.movie;
  Map<String, dynamic>? _itemDetail;
  final Map<String, dynamic> _localeMap = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialItemDetail != null) {
      final initial = widget.initialItemDetail!;
      _itemDetail = initial;
      _mode = _resolveMode(initial);
      _loading = false;
      unawaited(_load(silent: true));
      return;
    }
    unawaited(_load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    // 非飞牛后端(Emby):不调飞牛 getItemDetail 判模式(会报权限错),直接走 movie 模式
    // → PlayDetailPage,由其按 backend 读中立 MediaDetail 渲染。TV/合集模式属后续切片。
    final backend = context.read<MediaBackendProvider>().backend;
    if (backend.capabilities.kind != MediaBackendKind.feiniu) {
      if (!mounted) return;
      setState(() {
        _mode = DetailPageMode.movie;
        _itemDetail = null;
        _loading = false;
      });
      return;
    }

    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final detail = await api.getItemDetail(widget.itemGuid);
      if (!mounted) return;
      setState(() {
        _itemDetail = detail;
        _mode = _resolveMode(detail);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'detail entry',
          fallbackKind: AppExceptionKind.transient,
        );
        _loading = false;
      });
    }
  }

  DetailPageMode _resolveMode(Map<String, dynamic> detail) {
    if (widget.seriesGuid.trim().isNotEmpty) {
      return DetailPageMode.movie;
    }
    final directType = (detail['type'] ?? '').toString().trim().toLowerCase();
    if (directType == 'tv') return DetailPageMode.tv;
    if (directType == 'mediadb' || directType == 'directory') {
      return DetailPageMode.library;
    }
    if (directType == 'movie') return DetailPageMode.movie;

    final item = detail['item'];
    if (item is Map<String, dynamic>) {
      final nestedType = (item['type'] ?? '').toString().trim().toLowerCase();
      if (nestedType == 'tv') return DetailPageMode.tv;
      if (nestedType == 'mediadb' || nestedType == 'directory') {
        return DetailPageMode.library;
      }
      if (nestedType == 'movie') return DetailPageMode.movie;
    }
    return DetailPageMode.movie;
  }

  bool get _isPane => widget.presentation == DetailPresentation.pane;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return DetailLoadingSkeleton(presentation: widget.presentation);
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: colors.backgroundBase,
        appBar: _isPane ? null : AppBar(backgroundColor: colors.backgroundBase),
        body: AppErrorState(
          error: _error!,
          localeMap: _localeMap,
          onRetry: _load,
        ),
      );
    }

    if (_mode == DetailPageMode.tv) {
      return TvDetailPage(
        itemGuid: widget.itemGuid,
        initialItemDetail: _itemDetail,
        heroTag: widget.heroTag,
        presentation: widget.presentation,
      );
    }

    if (_mode == DetailPageMode.library) {
      return MediaCollectionDetailPage(
        itemGuid: widget.itemGuid,
        initialItemDetail: _itemDetail,
        heroTag: widget.heroTag,
        presentation: widget.presentation,
      );
    }

    return PlayDetailPage(
      itemGuid: widget.itemGuid,
      seriesGuid: widget.seriesGuid,
      heroTag: widget.heroTag,
      initialItemDetail: _itemDetail,
      presentation: widget.presentation,
    );
  }
}
