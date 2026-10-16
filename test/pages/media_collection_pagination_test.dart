import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `MediaCollectionDetailPage` 合集 / 媒体库子项列表的分页契约。
///
/// 背景：原实现首页固定 `page:1, page_size:500` 且没有下一页。实测 `item/list` 约
/// 1.1–1.5 KB/条 → 单响应可达 ~600 KB，在 `_dio` 的 10s receiveTimeout 下容易整页
/// 失败（用户反馈的「媒体库加载不出来」），且第 501 条起静默不可达。改为分页续拉。
void main() {
  final source = File(
    'lib/pages/media_collection_detail_page.dart',
  ).readAsStringSync();

  test('子项列表按 100 条分页，不再一次拉 500 条', () {
    expect(source, contains('static const int _pageSize = 100'));

    // 只约束飞牛的取数口径。中立（Emby 合集）分支的 _loadNeutralItems 仍是单次
    // 500 条：它没有分页，单纯调小页大小会截断数据，留待单独改造。
    final payloadBuilder = source.substring(
      source.indexOf('Map<String, dynamic>? _buildItemListPayload('),
      source.indexOf('String _detailType('),
    );
    expect(payloadBuilder, isNot(contains('500')), reason: '飞牛取数分支仍在一次拉 500 条');
    // 请求里的页码必须来自参数，不能写死。
    expect(payloadBuilder, contains("'page': page,"));
    expect(payloadBuilder, contains('pageSize: _pageSize,'));
  });

  test('hasMore 依据服务器原始行数判定，而不是过滤后的可见条数', () {
    // _filterItems 会按 parent_guid 丢掉季 / 集等非顶层行；用过滤后的条数算会误判。
    expect(
      source,
      contains(
        '_hasMore = page.items.isNotEmpty && merged.length < page.total;',
      ),
    );
    expect(source, contains('List<MediaLibraryItem> _rawItems'));
  });

  test('目录分支不锁类型——直接子项可能是季 / 集', () {
    // 实测：Directory 就是「Season 01」，其下是 Episode。锁成
    // Movie/TV/Directory/Video 会把这些子项滤掉，页面直接空掉。
    expect(source, contains("'tags': const <String, dynamic>{},"));
    expect(source, contains("'parent_guid': parentGuid,"));
  });

  test('媒体库分支的类型锁保留 Directory——部分库顶层就是目录', () {
    expect(
      source,
      contains("'type': <String>['Movie', 'TV', 'Directory', 'Video'],"),
    );
  });

  test('滚动续拉：注册监听、代次防串页、可重试', () {
    expect(source, contains('_scrollController.addListener(_onScroll)'));
    expect(
      source,
      contains('_scrollController.removeListener(_onScroll)'),
      reason: 'dispose 未解绑滚动监听',
    );
    expect(source, contains('Future<void> _loadMoreItems() async'));
    // 换排序 / 换筛选后旧排序的后续页必须作废。
    expect(source, contains('_itemLoadSeq'));
    expect(source, contains('if (!mounted || seq != _itemLoadSeq) return;'));
    // 续拉失败要留在页脚可重试，且不自动重试刷屏。
    expect(source, contains('_loadMoreError'));
    expect(source, contains('commonRefreshRetry'));
  });

  test('视口未填满时自动补页，且有页数上限', () {
    expect(source, contains('static const int _maxAutoFillPages = 3;'));
    expect(source, contains('_scheduleAutoFill();'));
    expect(source, contains('_autoFillPages = 0;'));
  });
}
