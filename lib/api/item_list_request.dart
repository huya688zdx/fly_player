class ItemListRequest {
  final String ancestorGuid;
  final int page;
  final int pageSize;
  final int excludeGroupedVideo;
  final String sortColumn;
  final String sortType;
  final List<String> typeTags;
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
