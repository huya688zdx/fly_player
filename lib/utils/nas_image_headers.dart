Map<String, String> nasImageHeaders(String token, {String? url}) {
  final trimmedToken = token.trim();
  if (trimmedToken.isEmpty) {
    return const <String, String>{};
  }
  final headers = <String, String>{
    'Authorization': trimmedToken,
    'Trim-MC-token': trimmedToken,
  };
  if (usesFnConnectRelayCookie(url)) {
    headers['Cookie'] = 'mode=relay';
  }
  return headers;
}

/// 合并 entry-token 到既有 Cookie 串：去重旧 `entry-token=` 后追加，供 Emby HTTP 拦截器与
/// 播放 headers 共用（语义与 `EmbyApi` 内私有版一致）。`*.fnos.net` 中转域名的 Emby 播放直链
/// 必须带 `Cookie: entry-token=<值>` 过云端 FN Connect 边缘闸。
String mergeEntryTokenCookie(String cookie, String token) {
  final entries = cookie
      .split(';')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .where((entry) => !entry.toLowerCase().startsWith('entry-token='))
      .toList();
  entries.add('entry-token=$token');
  return entries.join('; ');
}

bool usesFnConnectRelayCookie(String? rawUrl) {
  final trimmed = rawUrl?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  final host = uri?.host.trim().toLowerCase() ?? '';
  return host == 'fnos.net' || host.endsWith('.fnos.net');
}
