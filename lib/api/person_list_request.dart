class PersonListRequest {
  final int page;
  final int pageSize;

  const PersonListRequest({this.page = 1, this.pageSize = 200});

  Map<String, dynamic> toJson() {
    return {'page': page, 'page_size': pageSize};
  }
}
