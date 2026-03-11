import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../providers/nas_provider.dart';
import '../theme/detail_tokens.dart';
import '../utils/app_exception.dart';
import '../utils/media_locale_store.dart';
import '../widgets/common/app_error_state.dart';
import 'play_detail_page.dart';
import 'tv_detail_page.dart';

enum DetailPageMode { movie, tv }

class PlayDetailEntryPage extends StatefulWidget {
  final String itemGuid;
  final String? heroTag;
  final Map<String, dynamic>? initialItemDetail;

  const PlayDetailEntryPage({
    super.key,
    required this.itemGuid,
    this.heroTag,
    this.initialItemDetail,
  });

  @override
  State<PlayDetailEntryPage> createState() => _PlayDetailEntryPageState();
}

class _PlayDetailEntryPageState extends State<PlayDetailEntryPage> {
  bool _loading = true;
  AppException? _error;
  DetailPageMode _mode = DetailPageMode.movie;
  Map<String, dynamic>? _itemDetail;
  Map<String, dynamic> _localeMap = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    unawaited(_ensureLocaleMapLoaded());
    if (widget.initialItemDetail != null) {
      final initial = widget.initialItemDetail!;
      _itemDetail = initial;
      _mode = _resolveMode(initial);
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load(silent: true);
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _ensureLocaleMapLoaded() async {
    final provider = context.read<NasProvider>();
    final localeMap = await MediaLocaleStore.load(provider);
    if (!mounted || localeMap.isEmpty) return;
    setState(() {
      _localeMap = localeMap;
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
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
    final directType = (detail['type'] ?? '').toString().trim().toLowerCase();
    if (directType == 'tv') return DetailPageMode.tv;
    if (directType == 'movie') return DetailPageMode.movie;

    final item = detail['item'];
    if (item is Map<String, dynamic>) {
      final nestedType = (item['type'] ?? '').toString().trim().toLowerCase();
      if (nestedType == 'tv') return DetailPageMode.tv;
      if (nestedType == 'movie') return DetailPageMode.movie;
    }
    return DetailPageMode.movie;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: DetailTokens.pageBackground,
        body: SizedBox.shrink(),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: DetailTokens.pageBackground,
        appBar: AppBar(backgroundColor: DetailTokens.pageBackground),
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
      );
    }
    return PlayDetailPage(
      itemGuid: widget.itemGuid,
      heroTag: widget.heroTag,
      initialItemDetail: _itemDetail,
    );
  }
}

