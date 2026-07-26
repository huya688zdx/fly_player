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
      // 单集卡直点（无 seriesGuid，如首页「继续观看」）按约定最终解析成**系列
      // TV 详情**，但卡片级 initial 的 type='episode' 会被 _resolveMode 兜底成
      // movie——先渲染单集样式 PlayDetailPage（hero 加载出单集封面），_load 判型
      // 回包后整页翻转成 TvDetailPage（系列大图），产生"先显示单集封面再跳成
      // 系列大图"的错图闪。该场景 initial 不足以定型：走骨架等判型一次到位。
      if (_initialTypeOf(initial) == 'episode' &&
          widget.seriesGuid.trim().isEmpty) {
        unawaited(_load());
        return;
      }
      _itemDetail = initial;
      _mode = _resolveMode(initial);
      _loading = false;
      unawaited(_load(silent: true));
      return;
    }
    unawaited(_load());
  }

  String _initialTypeOf(Map<String, dynamic> detail) {
    final directType = (detail['type'] ?? '').toString().trim().toLowerCase();
    if (directType.isNotEmpty) return directType;
    final item = detail['item'];
    if (item is Map<String, dynamic>) {
      return (item['type'] ?? '').toString().trim().toLowerCase();
    }
    return '';
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    // 非飞牛后端(Emby):读中立 MediaDetail.type 判模式(剧集 → TvDetailPage 中立体,
    // 其余 → PlayDetailPage 中立体)。带 seriesGuid 的条目(选集)恒 movie,与飞牛 _resolveMode
    // 同口径。详情由目标页自行按 backend 重取,这里只判型(故 _itemDetail 留 null)。
    final backend = context.read<MediaBackendProvider>().backend;
    if (backend.capabilities.kind != MediaBackendKind.feiniu) {
      if (widget.seriesGuid.trim().isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _mode = DetailPageMode.movie;
          _itemDetail = null;
          _loading = false;
        });
        return;
      }
      try {
        final detail = await backend.getItemDetail(widget.itemGuid);
        if (!mounted) return;
        final type = detail.type.trim().toLowerCase();
        setState(() {
          // 合集（Emby BoxSet）走合集详情页；剧集走 TV 详情；其余（影片/单集）走影片详情。
          _mode = (type == 'series' || type == 'tv')
              ? DetailPageMode.tv
              : (type == 'boxset'
                    ? DetailPageMode.library
                    : DetailPageMode.movie);
          _itemDetail = null;
          _loading = false;
        });
      } catch (_) {
        // 判型失败不阻断:退 movie(PlayDetailPage 自行重取/报错)。
        if (!mounted) return;
        setState(() {
          _mode = DetailPageMode.movie;
          _itemDetail = null;
          _loading = false;
        });
      }
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
