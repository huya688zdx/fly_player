import 'dart:async';

import 'package:flutter/material.dart';
import '../services/fly_data/fly_data_service.dart';
import '../services/fly_data/fly_oped.dart';
import '../services/fly_data/fly_playback_service_client.dart';
import '../services/play_stats/play_stats_service.dart';

typedef FlyAssistantRequest =
    Future<Map<String, dynamic>> Function(
      String path, {
      Object? body,
      Map<String, dynamic>? query,
    });

class FlyAssistantAction extends StatelessWidget {
  const FlyAssistantAction({
    super.key,
    required this.itemGuid,
    this.mediaGuid = '',
  });
  final String itemGuid, mediaGuid;
  @override
  Widget build(BuildContext context) {
    FlySourceRef? source;
    try {
      source = FlyPlaybackServiceClient.instance.sourceRef(
        statsScope: PlayStatsService.instance.currentScope,
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (source == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        onPressed: () => showFlyAssistant(context, source: source),
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('资料助手 · 当前节目'),
      ),
    );
  }
}

Future<void> showFlyAssistant(
  BuildContext context, {
  String? mediaId,
  FlySourceRef? source,
}) {
  final session = FlyDataService.instance.session;
  final epoch = FlyPlaybackServiceClient.instance.epoch;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: FlyAssistantPanel(
        mediaId: mediaId,
        source: source,
        isCurrent: () =>
            session != null &&
            identical(session, FlyDataService.instance.session) &&
            epoch == FlyPlaybackServiceClient.instance.epoch,
      ),
    ),
  );
}

/// Contextual, read-only assistant. All text is rendered as text; results never
/// launch player commands, publish segments, or execute model-supplied markup.
class FlyAssistantPanel extends StatefulWidget {
  const FlyAssistantPanel({
    super.key,
    this.mediaId,
    this.source,
    this.request,
    required this.isCurrent,
  });
  final String? mediaId;
  final FlySourceRef? source;
  final FlyAssistantRequest? request;
  final bool Function() isCurrent;
  @override
  State<FlyAssistantPanel> createState() => _FlyAssistantPanelState();
}

class _FlyAssistantPanelState extends State<FlyAssistantPanel> {
  final _query = TextEditingController();
  Map<String, dynamic>? _context, _run;
  String? _error;
  bool _busy = false;
  Timer? _poll;
  int _generation = 0;
  Future<Map<String, dynamic>> _request(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      widget.request?.call(path, body: body, query: query) ??
      FlyDataService.instance.request(path, body: body, query: query);
  bool get _active =>
      _run != null &&
      [
        'queued',
        'running',
        'waiting_dependency',
        'waiting_idle',
        'planning',
      ].contains(_run!['status']);
  bool _current(int generation) =>
      mounted && generation == _generation && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      if (!widget.isCurrent()) throw StateError('scope_changed');
      final result = await _request(
        '/assistant/context',
        query: widget.mediaId != null ? {'media_id': widget.mediaId} : null,
        body: widget.mediaId == null && widget.source != null
            ? {'source_ref': widget.source!.toJson()}
            : null,
      );
      if (_current(generation)) setState(() => _context = result);
    } catch (_) {
      if (mounted) setState(() => _error = '资料助手暂不可用。检查飞翔登录、服务版本与连接后重试。');
    }
  }

  Future<void> _start() async {
    if (!widget.isCurrent()) {
      setState(() => _error = '账号或播放来源已改变，请关闭后重新打开。');
      return;
    }
    final media = _context?['media'];
    final id = media is Map ? media['id'] : widget.mediaId;
    if (_busy || _active || id is! String || _query.text.trim().isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _request(
        '/assistant/runs',
        body: {
          'media_id': id,
          if (_context?['source_ref'] != null)
            'source_ref': _context!['source_ref'],
          'query': _query.text.trim(),
          'idempotency_key': FlyPlaybackServiceClient.newId(),
        },
      );
      if (!_current(generation)) return;
      setState(() => _run = result);
      _schedulePoll(generation);
    } catch (_) {
      if (_current(generation)) {
        setState(() => _error = '任务未成功创建。模型或搜索未配置时，可继续普通播放与人工资料操作。');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _schedulePoll(int generation) {
    _poll?.cancel();
    if (!_active) return;
    _poll = Timer(const Duration(seconds: 2), () async {
      final id = _run?['id'];
      if (!_current(generation) || id is! String) return;
      try {
        final result = await _request(
          '/assistant/runs/${Uri.encodeComponent(id)}',
        );
        if (!_current(generation)) return;
        setState(() => _run = result);
        _schedulePoll(generation);
      } catch (_) {
        if (_current(generation)) {
          setState(() => _error = '连接已中断，任务可能仍在后台执行。可重试读取或在网页任务中心查看。');
        }
      }
    });
  }

  Future<void> _cancel() async {
    if (!widget.isCurrent() || _busy) return;
    final id = _run?['id'];
    if (id is! String) return;
    final generation = ++_generation;
    _poll?.cancel();
    setState(() => _busy = true);
    try {
      final result = await _request(
        '/assistant/runs/${Uri.encodeComponent(id)}/cancel',
        body: {},
      );
      if (_current(generation)) setState(() => _run = result);
    } catch (_) {
      if (_current(generation)) {
        setState(() => _error = '取消未确认，请到网页任务中心查看；已发出的供应商请求仍可能计费。');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = _context?['media'];
    final file = _context?['file_context'];
    final title = media is Map ? media['title']?.toString() ?? '' : '';
    final run = _run;
    final evidence = run?['evidence'] is List
        ? run!['evidence'] as List
        : const [];
    final candidates = run?['candidates'] is List
        ? run!['candidates'] as List
        : const [];
    final answer = (run?['answer'] ?? run?['text'] ?? run?['result'] ?? '')
        .toString();
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_outlined, color: colors.primary),
            const SizedBox(width: 10),
            Text('资料助手', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 12),
        if (_context == null && _error == null) const LinearProgressIndicator(),
        if (title.isNotEmpty)
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          file is Map && file['identity_state'] == 'verified'
              ? '已关联当前文件。候选经核验发布后才会用于跳过。'
              : '当前文件尚未核验。可查询资料与保存候选，暂不能发布跳过区间。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _query,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: '关于当前节目',
            hintText: '查找片头片尾资料，或询问目录中的信息',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _context == null || _busy || _active ? null : _start,
              icon: const Icon(Icons.search),
              label: const Text('查找资料'),
            ),
            if (_active)
              OutlinedButton(
                onPressed: _busy ? null : _cancel,
                child: const Text('取消任务'),
              ),
            if (_error != null)
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  if (_context == null) {
                    unawaited(_load());
                  } else {
                    _schedulePoll(_generation);
                  }
                },
                child: const Text('重试读取'),
              ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
        if (run != null) ...[
          const SizedBox(height: 18),
          Text(
            '任务：${_statusLabel(run['status'])}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (run['reason'] != null) SelectableText(run['reason'].toString()),
          if (answer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(answer),
            ),
          for (final item in evidence.whereType<Map>())
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['title'] ?? item['provider'] ?? '来源证据').toString(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (item['url'] != null)
                      SelectableText(item['url'].toString()),
                    if (item['excerpt'] != null)
                      Text(item['excerpt'].toString()),
                    if (item['retrieved_at'] != null)
                      Text(
                        '获取时间：${item['retrieved_at']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          for (final item in candidates.whereType<Map>())
            Card(
              child: ListTile(
                title: Text(
                  '${item['kind'] ?? '区间'} · ${item['start_ms'] ?? '?'}–${item['end_ms'] ?? '?'} ms',
                ),
                subtitle: const Text('资料候选，未视为当前文件已核验。请在网页工作区查看证据与发布。'),
              ),
            ),
          if (run['budget'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '本次预算与用量：${run['budget']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }

  String _statusLabel(Object? status) =>
      const {
        'queued': '排队中',
        'running': '处理中',
        'completed': '已完成',
        'partial': '已完成可用部分',
        'waiting_dependency': '等待所需能力',
        'awaiting_review': '待复核',
        'failed': '失败',
        'blocked': '缺少能力或配置',
        'cancelled': '已取消',
        'needs_review': '待复核',
      }[status] ??
      status?.toString() ??
      '待开始';
}
