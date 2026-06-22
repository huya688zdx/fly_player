import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media_backend/detail/media_detail.dart';
import '../media_backend/media_item_card.dart';
import '../providers/media_backend_provider.dart';
import '../theme/app_theme.dart';
import '../ui/credit_person_presenter.dart';
import '../widgets/detail/credits_section.dart';
import '../widgets/detail/detail_description_section.dart';
import '../widgets/detail/detail_tag_chip.dart';
import '../widgets/detail/immersive_detail_background.dart';

/// 后端中立的详情展示屏——**首光阶段(只读展示)**。
///
/// 由 [MediaListScreen] 在非飞牛后端态(当前为 Emby)按 `backend.capabilities.kind`
/// 路由到本屏(飞牛态仍走原 `play_detail_page`)。数据只走
/// [MediaBackend.getItemDetail] 返回的中立 [MediaDetail],复用现有详情展示组件渲染;
/// 不含播放接线——播放入口为占位提示,后续独立切片再做。
class MediaDetailScreen extends StatefulWidget {
  final String itemId;

  /// 列表已有的卡片快照,用于首屏占位(标题/海报/背景),详情到达即覆盖,避免白屏。
  final MediaItemCard? initialCard;
  final String? heroTag;

  const MediaDetailScreen({
    super.key,
    required this.itemId,
    this.initialCard,
    this.heroTag,
  });

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  MediaDetail? _detail;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    if ((offset - _scrollOffset).abs() < 0.5) return;
    setState(() => _scrollOffset = offset);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final detail = await backend.getItemDetail(widget.itemId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// 背景图候选:详情背景优先,退海报,再退列表卡片占位。
  List<String> get _backgroundUrls {
    final detail = _detail;
    final urls = <String>[];
    if (detail != null) {
      if (detail.backdropImage.isNotEmpty) urls.add(detail.backdropImage.url);
      if (detail.primaryImage.isNotEmpty) urls.add(detail.primaryImage.url);
    }
    final card = widget.initialCard;
    if (urls.isEmpty && card != null) {
      if (card.backdropImage.isNotEmpty) urls.add(card.backdropImage.url);
      if (card.primaryImage.isNotEmpty) urls.add(card.primaryImage.url);
    }
    return urls;
  }

  String get _title {
    final detail = _detail;
    if (detail != null && detail.title.trim().isNotEmpty) {
      return detail.title.trim();
    }
    return widget.initialCard?.displayTitle.trim() ?? '';
  }

  /// 元信息行:年份 · 时长 · 评分(空项跳过)。
  String get _metaLine {
    final detail = _detail;
    if (detail == null) return '';
    final parts = <String>[];
    final year = _yearOf(detail.releaseDate);
    if (year.isNotEmpty) parts.add(year);
    if (detail.runtimeMinutes > 0) parts.add('${detail.runtimeMinutes} 分钟');
    if (detail.rating.trim().isNotEmpty) parts.add('⭐ ${detail.rating.trim()}');
    return parts.join('  ·  ');
  }

  static String _yearOf(String releaseDate) {
    final value = releaseDate.trim();
    if (value.length >= 4) {
      final head = value.substring(0, 4);
      if (int.tryParse(head) != null) return head;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final screenHeight = MediaQuery.of(context).size.height;
    final posterHeight = screenHeight * 0.46;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ImmersiveDetailBackground(
            urls: _backgroundUrls,
            token: '', // Emby 图片自鉴权(URL 带 api_key),无需 NAS token
            scrollOffset: _scrollOffset,
            posterHeight: posterHeight,
            enableBottomFade: true,
          ),
          SafeArea(child: _buildBody(colors, posterHeight)),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 4,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: colors.textPrimary),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppThemeColors colors, double posterHeight) {
    if (_loading && _detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败', style: TextStyle(color: colors.textPrimary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final detail = _detail;
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      children: [
        SizedBox(height: posterHeight * 0.62),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(colors),
              if (detail != null) ...[
                const SizedBox(height: 16),
                _buildPlaceholderPlayButton(colors),
                if (_chips(detail).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _chips(
                      detail,
                    ).map((label) => DetailTagChip(label: label)).toList(),
                  ),
                ],
                if (detail.overview.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  DetailDescriptionSection(
                    text: detail.overview.trim(),
                    onMoreTap: () => _showOverview(detail.overview.trim()),
                  ),
                ],
                if (detail.people.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  CreditsSection(
                    title: '演职员',
                    token: '',
                    items: detail.people
                        .map(
                          (p) => CreditPersonItem(
                            personGuid: p.id,
                            name: CreditPersonPresenter.displayName(p),
                            subtitle: CreditPersonPresenter.displaySubTitle(p),
                            imageUrls: p.avatar.isNotEmpty
                                ? <String>[p.avatar.url]
                                : const <String>[],
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(AppThemeColors colors) {
    final detail = _detail;
    final logoUrl = detail?.logoImage.url ?? '';
    final title = _title;
    final logo = logoUrl.isNotEmpty
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96, maxWidth: 280),
            child: Image.network(
              logoUrl,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, __, ___) => _titleText(colors, title),
            ),
          )
        : _titleText(colors, title);
    return Align(alignment: Alignment.centerLeft, child: logo);
  }

  Widget _titleText(AppThemeColors colors, String title) {
    return Text(
      title,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 26,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildPlaceholderPlayButton(AppThemeColors colors) {
    final meta = _metaLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              meta,
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ),
        // 占位:本切片只做展示,播放为后续独立切片。能力门控,非 if(isEmby)。
        FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('播放功能即将到来'),
        ),
      ],
    );
  }

  List<String> _chips(MediaDetail detail) {
    return <String>[
      ...detail.genreLabels,
      ...detail.regionLabels,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  void _showOverview(String text) {
    final colors = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.backgroundElevated,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Text(
              text,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
