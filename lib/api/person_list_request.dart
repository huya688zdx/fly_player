/// 人员列表分页查询参数。
class PersonListRequest {
  /// 页码，从 1 开始。
  final int page;

  /// 单页条目数。
  final int pageSize;

  const PersonListRequest({this.page = 1, this.pageSize = 200});

  /// 转成后端接口需要的 JSON 结构。
  Map<String, dynamic> toJson() {
    return {'page': page, 'page_size': pageSize};
  }
}
