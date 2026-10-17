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

  test('子项列表按 50 条分页，全文件不再出现一次拉 500 条', () {
    // 50 对齐本项目其它列表口径（CategoryItemsScreen._pageSize、
    // ItemListRequest.pageSize 默认值都是 50）。
    // 注意必须带上分号：'..._pageSize = 50' 是 '..._pageSize = 500' 的子串，会漏判。
    expect(source, contains('int _pageSize = 50;'));
    expect(
      source,
      isNot(contains('int _pageSize = 500;')),
      reason: '页大小又退回 500 了',
    );
    expect(source, isNot(contains('page_size: 500')), reason: '仍有分支在一次拉 500 条');
    expect(source, isNot(contains('pageSize: 500')), reason: '仍有分支在一次拉 500 条');

    // 请求里的页码必须来自参数，不能写死。
    final payloadBuilder = source.substring(
      source.indexOf('Map<String, dynamic>? _buildItemListPayload('),
      source.indexOf('String _detailType('),
    );
    expect(payloadBuilder, contains("'page': page,"));
    expect(payloadBuilder, contains('pageSize: _pageSize,'));
  });

  test('中立（Emby 合集）分支同样分页，改小页大小不会截断', () {
    // Emby 的 queryChildItems 本身就分页（startIndex / limit + totalRecordCount），
    // 所以这里也能安全按 _pageSize 取，不需要留 500 的例外。
    expect(source, contains('_fetchNeutralItemPage'));
    expect(source, contains('page: page,'));
    expect(
      source,
      contains('Future<_CollectionItemsPage> _loadNeutralItems('),
      reason: '中立分支未接入分页结果结构',
    );
    // 续拉要覆盖两个后端。
    expect(source, contains('await _fetchNeutralItemPage('));
  });

  test('hasMore 依据服务器原始行数判定，而不是过滤后的可见条数', () {
    // _filterItems 会按 parent_guid 丢掉季 / 集等非顶层行；用过滤后的条数算会误判。
    expect(
      source,
      contains(
        '_hasMore = next.items.isNotEmpty && merged.length < next.total;',
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

  test('排序切换在请求之前就作废在途分页', () {
    // 代次自增若写在「新首页请求返回之后」，旧排序的第 N 页会在偏好写入 / 重取期间
    // 完成并通过代次校验，把旧排序的行追加进来；若重取随后失败，这些行会留在新排序下。
    final changeSort = source.substring(
      source.indexOf('Future<void> _changeSort('),
      source.indexOf('Future<void> _reloadItemsOnly('),
    );
    final seqInChangeSort = changeSort.indexOf('_itemLoadSeq++;');
    final firstAwait = changeSort.indexOf('await ');
    expect(seqInChangeSort, greaterThanOrEqualTo(0), reason: '排序切换未作废在途分页');
    expect(firstAwait, greaterThanOrEqualTo(0));
    expect(seqInChangeSort, lessThan(firstAwait), reason: '作废必须发生在首个 await 之前');

    final reload = source.substring(
      source.indexOf('Future<void> _reloadItemsOnly('),
    );
    expect(
      reload.indexOf('_itemLoadSeq++;'),
      lessThan(reload.indexOf('await ')),
      reason: '重取首页同样要在请求前作废',
    );
  });

  test('本地筛选后主动补页，避免匹配项到不了', () {
    // 筛选可能把已加载的这一页全部滤掉；此时内容短于视口、没有滚动事件，页脚也不显示，
    // 不主动补页的话后续页里的匹配项永远到不了。
    final filterApply = source.substring(
      source.indexOf('final resolutions = result['),
      source.indexOf('void _replaceItemLocally('),
    );
    expect(filterApply, contains('_autoFillPages = 0;'));
    expect(filterApply, contains('_scheduleAutoFill();'));
  });

  test('可见列表为空时自动补页不受页数上限约束', () {
    // mediadb 的前几页可能整页都是会被 _filterItems 丢掉的季目录：可见列表为空、内容
    // 短于视口没有滚动事件。若上限照样生效，页面会永远空着且无法触发续拉。
    expect(
      source,
      contains(
        'if (_items.isNotEmpty && _autoFillPages >= _maxAutoFillPages) return;',
      ),
    );
    expect(source, contains('if (_items.isNotEmpty) _autoFillPages++;'));
  });
}
