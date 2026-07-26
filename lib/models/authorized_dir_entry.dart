class AuthorizedDirEntry {
  final String path;
  final String uname;
  final int storageType;

  const AuthorizedDirEntry({
    required this.path,
    required this.uname,
    required this.storageType,
  });

  factory AuthorizedDirEntry.fromJson(Map<String, dynamic> json) {
    return AuthorizedDirEntry(
      path: (json['path'] ?? '').toString(),
      uname: (json['uname'] ?? '').toString(),
      storageType: json['storageType'] is int
          ? json['storageType'] as int
          : int.tryParse('${json['storageType']}') ?? 0,
    );
  }
}
