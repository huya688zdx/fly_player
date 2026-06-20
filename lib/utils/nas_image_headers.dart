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

bool usesFnConnectRelayCookie(String? rawUrl) {
  final trimmed = rawUrl?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  final host = uri?.host.trim().toLowerCase() ?? '';
  return host == 'fnos.net' || host.endsWith('.fnos.net');
}
