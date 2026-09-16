import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/item_playback_launcher.dart';
import '../media_backend/detail/media_detail.dart';
import '../media_backend/detail/media_source_version.dart';
import '../providers/media_backend_provider.dart';
import '../theme/app_theme.dart';
import '../ui/detail_presentation.dart';
import '../utils/app_exception.dart';
import '../widgets/common/app_ambient_page.dart';
import '../widgets/common/app_error_state.dart';

/// 直播只提供频道、线路和播放入口，不加载点播的文件与演职员信息。
class LiveChannelScreen extends StatefulWidget {
  const LiveChannelScreen({
    super.key,
    required this.itemId,
    this.presentation = DetailPresentation.page,
  });

  final String itemId;
  final DetailPresentation presentation;

  @override
  State<LiveChannelScreen> createState() => _LiveChannelScreenState();
}

class _LiveChannelScreenState extends State<LiveChannelScreen> {
  MediaDetail? _detail;
  List<MediaSourceVersion> _lines = const [];
  String? _lineId;
  AppException? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final backend = context.read<MediaBackendProvider>().backend;
    try {
      final detail = await backend.getItemDetail(widget.itemId);
      final lines = await backend.getItemSourceVersions(
        widget.itemId,
        isLive: true,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _lines = lines;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = AppException.from(error, action: '加载直播频道'));
      }
    }
  }

  Future<void> _play() async {
    setState(() => _busy = true);
    try {
      await const ItemPlaybackLauncher().open(
        context,
        itemGuid: widget.itemId,
        fallbackTitle: _detail?.title ?? '直播',
        qualityMediaGuid: _lineId,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = AppException.from(error, action: '播放直播'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _favorite() async {
    final detail = _detail;
    if (detail == null) return;
    setState(() => _busy = true);
    try {
      final favorite = await context
          .read<MediaBackendProvider>()
          .backend
          .setItemFavorite(widget.itemId, favorite: !detail.favorite);
      if (mounted) {
        setState(() => _detail = detail.copyWith(favorite: favorite));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = AppException.from(error, action: '收藏直播频道'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final colors = context.appColors;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: widget.presentation == DetailPresentation.pane
            ? null
            : AppBar(title: const Text('直播频道')),
        body: SafeArea(
          child: _error != null
              ? AppErrorState(error: _error!, onRetry: _load)
              : detail == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(24),
                      children: [
                        Icon(
                          Icons.live_tv_rounded,
                          size: 64,
                          color: colors.accent,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          detail.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (detail.overview.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(detail.overview, textAlign: TextAlign.center),
                        ],
                        const SizedBox(height: 24),
                        if (_lines.length > 1)
                          DropdownButtonFormField<String>(
                            initialValue: _lineId,
                            decoration: const InputDecoration(
                              labelText: '直播线路',
                            ),
                            hint: const Text('服务器默认线路'),
                            isExpanded: true,
                            items: [
                              for (var i = 0; i < _lines.length; i++)
                                DropdownMenuItem(
                                  value: _lines[i].id,
                                  child: Text(
                                    _lines[i].label.isEmpty
                                        ? '线路 ${i + 1}'
                                        : _lines[i].label,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _lineId = value),
                          ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _play,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(_busy ? '正在处理…' : '播放直播'),
                        ),
                        if (context
                            .read<MediaBackendProvider>()
                            .backend
                            .capabilities
                            .supportsFavorite)
                          TextButton.icon(
                            onPressed: _busy ? null : _favorite,
                            icon: Icon(
                              detail.favorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                            ),
                            label: Text(detail.favorite ? '取消收藏' : '收藏频道'),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
