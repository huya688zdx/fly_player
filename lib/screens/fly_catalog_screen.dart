import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fly_data/fly_account_controller.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../theme/app_theme.dart';
import '../widgets/common/app_ambient_page.dart';
import '../widgets/common/bird_loader.dart';
import '../models/media_library_item.dart';
import '../desktop/desktop_hover_region.dart';
import 'fly_account_screen.dart';
import 'dart:typed_data';

part 'fly_catalog_widgets.dart';

String _kindLabel(Object? kind) =>
    const {
      'movie': '电影',
      'series': '剧集',
      'season': '季',
      'episode': '集',
    }[kind] ??
    '媒体';
String _completenessLabel(Object? value) =>
    const {'confirmed': '目录已完整扫描', 'partial': '显示上次目录，待更新'}[value] ?? '待扫描';

class FlyCatalogScreen extends StatefulWidget {
  const FlyCatalogScreen({super.key});
  @override
  State<FlyCatalogScreen> createState() => _FlyCatalogScreenState();
}

class _FlyCatalogScreenState extends State<FlyCatalogScreen> {
  final search = TextEditingController();
  List<Map<String, dynamic>> items = [];
  String? cursor, message;
  String _account = '', _binding = '';
  Object? _session;
  String _kind = '', _opening = '';
  int? total;
  bool loading = false;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.watch<FlyAccountController>();
    if (_account != account.accountKey ||
        _binding != account.activeBindingId ||
        !identical(_session, account.session)) {
      _account = account.accountKey;
      _binding = account.activeBindingId;
      _session = account.session;
      generation++;
      items = [];
      cursor = null;
      total = null;
      message = null;
      final scheduledGeneration = generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            generation == scheduledGeneration &&
            account.session != null) {
          _load();
        }
      });
    }
  }

  Future<void> _load({bool more = false}) async {
    final run = ++generation;
    final account = context.read<FlyAccountController>();
    final binding = account.activeBindingId;
    final session = account.session;
    final accountKey = account.accountKey;
    setState(() {
      loading = true;
      message = null;
      if (!more) {
        items = [];
        cursor = null;
      }
    });
    try {
      final result = await account.service.request(
        '/media',
        query: {
          'binding_id': binding,
          'q': search.text.trim(),
          'limit': 40,
          if (_kind.isNotEmpty) 'kind': _kind,
          if (more && cursor != null) 'cursor': cursor,
        },
      );
      if (!mounted ||
          run != generation ||
          binding != account.activeBindingId ||
          accountKey != account.accountKey ||
          !identical(session, account.session)) {
        return;
      }
      setState(() {
        items.addAll(
          (result['items'] as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        cursor = result['next_cursor'] as String?;
        total = (result['total'] as num?)?.toInt();
      });
    } catch (error) {
      if (mounted &&
          run == generation &&
          accountKey == account.accountKey &&
          identical(session, account.session)) {
        setState(() => message = FlyAccountController.safeMessage(error));
      }
    } finally {
      if (mounted && run == generation) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildCatalog(context);

  void _setKind(String kind) {
    setState(() => _kind = kind);
    _load();
  }

  void _showInfo(Map<String, dynamic> item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FlyCatalogDetailScreen(
          mediaId: item['id'] as String,
          accountKey: _account,
        ),
      ),
    );
  }

  Future<void> _openItem(Map<String, dynamic> item) async {
    if (_opening.isNotEmpty) return;
    setState(() => _opening = item['id'] as String);
    try {
      await openFlyCatalogItem(context, item, expectedAccountKey: _account);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FlyAccountController.safeMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = '');
    }
  }
}

/// Routes catalog identities to the original media detail pages.
Future<void> openFlyCatalogItem(
  BuildContext context,
  Map<String, dynamic> item, {
  required String expectedAccountKey,
}) async {
  final account = context.read<FlyAccountController>();
  final session = account.session;
  final binding = item['binding_id'];
  bool current() =>
      context.mounted &&
      session != null &&
      identical(session, account.session) &&
      account.accountKey == expectedAccountKey &&
      account.activeBindingId == binding;
  if (!current()) throw StateError('媒体来源已改变，请返回重新选择节目。');
  final remoteId = (item['remote_item_id'] as String? ?? '').trim();
  if (remoteId.isEmpty) throw StateError('节目暂未关联到媒体来源，请刷新同步信息。');
  Future<Map<String, dynamic>> loadParent(String id) async {
    if (!current()) throw StateError('账号或媒体来源已改变。');
    final parent = await account.service.request(
      '/media/${Uri.encodeComponent(id)}',
    );
    if (!current() || parent['binding_id'] != binding) {
      throw StateError('账号或媒体来源已改变。');
    }
    return parent;
  }

  var request = AdaptiveDetailRequest.item(itemGuid: remoteId);
  if (item['kind'] == 'season' || item['kind'] == 'episode') {
    final parentId = item['parent_id'] as String?;
    if (parentId != null && parentId.isNotEmpty) {
      var parent = await loadParent(parentId);
      if (item['kind'] == 'season') {
        request = AdaptiveDetailRequest.season(
          parentGuid: parent['remote_item_id'] as String,
          seriesTitle: parent['title'] as String? ?? '',
          backdropPath: '',
          seasonItem: MediaLibraryItem.fromJson({
            'guid': remoteId,
            'title': item['title'],
            'type': 'Season',
            'season_number': item['season_number'],
          }),
        );
      } else {
        if (parent['kind'] == 'season' && parent['parent_id'] is String) {
          parent = await loadParent(parent['parent_id'] as String);
        }
        if (parent['kind'] == 'series') {
          request = AdaptiveDetailRequest.item(
            itemGuid: remoteId,
            seriesGuid: parent['remote_item_id'] as String,
          );
        }
      }
    }
  }
  if (!context.mounted || !current()) return;
  await AdaptiveDetailNavigator.open(context, request, isCurrent: current);
}

class FlyCatalogDetailScreen extends StatefulWidget {
  const FlyCatalogDetailScreen({
    super.key,
    required this.mediaId,
    required this.accountKey,
  });
  final String mediaId, accountKey;
  @override
  State<FlyCatalogDetailScreen> createState() => _FlyCatalogDetailScreenState();
}

class _FlyCatalogDetailScreenState extends State<FlyCatalogDetailScreen> {
  Map<String, dynamic>? media;
  String? message;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final account = context.read<FlyAccountController>();
      final session = account.session;
      final result = await account.service.request('/media/${widget.mediaId}');
      if (mounted &&
          widget.accountKey == account.accountKey &&
          identical(session, account.session)) {
        setState(() => media = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => message = FlyAccountController.safeMessage(error));
      }
    }
  }

  Future<void> _open() async {
    final account = context.read<FlyAccountController>();
    if (widget.accountKey != account.accountKey) return;
    setState(() => busy = true);
    try {
      await openFlyCatalogItem(
        context,
        media!,
        expectedAccountKey: widget.accountKey,
      );
    } catch (error) {
      if (mounted) {
        setState(() => message = FlyAccountController.safeMessage(error));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    if (account.accountKey != widget.accountKey) {
      return const Scaffold(body: Center(child: Text('账号已改变，请返回目录。')));
    }
    final item = media;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          title: const Text('同步信息'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (item == null && message == null)
              const LinearProgressIndicator(),
            if (message != null) Text(message!),
            if (item != null) ...[
              if (item['poster_url'] != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 180,
                    height: 250,
                    child: FlyCatalogPoster(mediaId: widget.mediaId),
                  ),
                ),
              Text(
                item['title'] as String? ?? '',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${_kindLabel(item['kind'])} · ${item['year'] ?? '年份未知'} · 评分 ${item['rating'] ?? '未知'}',
              ),
              Text((item['genres'] as List? ?? []).join(' / ')),
              const SizedBox(height: 16),
              Text(item['overview'] as String? ?? ''),
              const SizedBox(height: 16),
              Text(
                '目录完整性：${_completenessLabel(item['catalog_completeness'])} · 来源数：${item['source_count'] ?? 1}',
              ),
              if ([
                'movie',
                'episode',
                'series',
                'season',
              ].contains(item['kind']))
                FilledButton.icon(
                  onPressed: busy ? null : _open,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('打开节目详情'),
                ),
              for (final person in item['people'] as List? ?? [])
                Text(
                  '${person['name']} · ${person['role'] ?? person['type'] ?? ''}',
                ),
              if ((item['external_ids'] as Map? ?? {}).isNotEmpty)
                Text('外部标识：${item['external_ids']}'),
              for (final source in item['sources'] as List? ?? [])
                Card(
                  child: ListTile(
                    title: Text(
                      '${source['server_name']} · ${source['title']}',
                    ),
                    subtitle: Text(
                      '状态：${source['status']}\n${(source['versions'] as List? ?? []).map((v) => '${v['label'] ?? ''} ${v['resolution'] ?? ''} ${v['video_codec'] ?? ''}').join('\n')}',
                    ),
                  ),
                ),
              for (final child in item['children'] as List? ?? [])
                Card(
                  child: ListTile(
                    title: Text(child['title'] as String? ?? ''),
                    subtitle: Text(
                      '${_kindLabel(child['kind'])} · 季 ${child['season_number'] ?? '-'} / 集 ${child['episode_number'] ?? '-'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => FlyCatalogDetailScreen(
                          mediaId: child['id'] as String,
                          accountKey: widget.accountKey,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class FlyCatalogPoster extends StatefulWidget {
  const FlyCatalogPoster({super.key, required this.mediaId});
  final String mediaId;
  @override
  State<FlyCatalogPoster> createState() => _FlyCatalogPosterState();
}

class _FlyCatalogPosterState extends State<FlyCatalogPoster> {
  Future<Uint8List>? bytes;
  String account = '';
  Object? session;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.watch<FlyAccountController>();
    if (bytes == null ||
        account != controller.accountKey ||
        !identical(session, controller.session)) {
      account = controller.accountKey;
      session = controller.session;
      bytes = controller.service.imageBytes(widget.mediaId);
    }
  }

  @override
  void didUpdateWidget(covariant FlyCatalogPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId) {
      bytes = context.read<FlyAccountController>().service.imageBytes(
        widget.mediaId,
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    key: ValueKey((account, session, widget.mediaId)),
    future: bytes,
    builder: (context, snapshot) =>
        snapshot.connectionState == ConnectionState.done && snapshot.hasData
        ? Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined),
          )
        : const Icon(Icons.image_outlined),
  );
}
