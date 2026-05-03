/// 媒体列表分页查询参数。
///
/// 该对象对应后端 `/item/list` 接口的请求体，调用方仅需关注
/// 目录范围、分页信息以及附加筛选标签。
class ItemListRequest {
  /// 祖先目录 guid；为空时表示按全局条件查询。
  final String ancestorGuid;

  /// 页码，从 1 开始。
  final int page;

  /// 单页条目数。
  final int pageSize;

  /// 是否排除聚合视频项。
  final int excludeGroupedVideo;

  /// 排序字段。
  final String sortColumn;

  /// 排序方向。
  final String sortType;

  /// 类型标签筛选。
  final List<String> typeTags;

  /// 额外业务标签筛选。
  final Map<String, dynamic>? tags;

  const ItemListRequest({
    required this.ancestorGuid,
    this.page = 1,
    this.pageSize = 50,
    this.excludeGroupedVideo = 1,
    this.sortColumn = 'create_time',
    this.sortType = 'DESC',
    this.typeTags = const ['Movie', 'TV', 'Directory', 'Video'],
    this.tags,
  });

  /// 为某个祖先目录构造默认分页请求。
  factory ItemListRequest.forAncestor(
    String ancestorGuid, {
    int page = 1,
    int pageSize = 50,
  }) {
    return ItemListRequest(
      ancestorGuid: ancestorGuid,
      page: page,
      pageSize: pageSize,
    );
  }

  /// 转成后端接口需要的 JSON 结构。
  Map<String, dynamic> toJson() {
    final mergedTags = <String, dynamic>{'type': typeTags};
    if (tags != null) {
      mergedTags.addAll(tags!);
    }

    final payload = <String, dynamic>{
      'exclude_grouped_video': excludeGroupedVideo,
      'page': page,
      'page_size': pageSize,
      'sort_column': sortColumn,
      'sort_type': sortType,
      'tags': mergedTags,
    };
    if (ancestorGuid.trim().isNotEmpty) {
      payload['ancestor_guid'] = ancestorGuid;
    }
    return payload;
  }
}
