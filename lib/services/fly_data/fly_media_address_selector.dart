import 'fly_media_identity.dart';

/// Test adapters must honor [timeout] and cancel their own pending IO.
typedef FlyMediaAddressVerifier =
    Future<void> Function({
      required String address,
      required String kind,
      required String expectedId,
      required Duration timeout,
    });

/// Select only from a fresh authorized set before a caller applies credentials.
/// No address or credential is persisted here. An explicit choice never falls
/// back, while an authorized preferred address is tried before stable priority.
Future<String> selectFlyMediaAddress({
  required List<Map<String, dynamic>> addresses,
  required String kind,
  required String expectedId,
  String? preferredAddress,
  String? explicitAddress,
  bool preferFnRelay = false,
  FlyMediaAddressVerifier? verify,
}) async {
  if (expectedId.trim().isEmpty) {
    throw StateError('媒体服务器尚无可验证身份，请重新授权。');
  }
  if (addresses.length > 16 || !{'feiniu', 'emby', 'jellyfin'}.contains(kind)) {
    throw StateError('媒体地址配置不可用，请刷新授权后重试。');
  }
  final candidates = <_AddressCandidate>[];
  for (var index = 0; index < addresses.length; index++) {
    final entry = addresses[index];
    if (!{'client_lan', 'client_remote', 'vpn'}.contains(entry['purpose'])) {
      continue;
    }
    final url = _safeBaseUrl(entry['base_url']);
    final priority = entry['priority'] ?? 0;
    if (url == null || priority is! int || priority < 0 || priority > 1000) {
      continue;
    }
    candidates.add(_AddressCandidate(url, priority, index));
  }
  candidates.sort((a, b) {
    final order = a.priority.compareTo(b.priority);
    return order != 0 ? order : a.index.compareTo(b.index);
  });
  final allowed = <String>{};
  final ordered = <String>[];
  for (final candidate in candidates) {
    if (allowed.add(candidate.url)) ordered.add(candidate.url);
  }
  if (explicitAddress != null) {
    final explicit = _safeBaseUrl(explicitAddress);
    if (explicit == null || !allowed.contains(explicit)) {
      throw StateError('指定媒体地址已不在当前授权中，请重新选择。');
    }
    ordered
      ..clear()
      ..add(explicit);
  } else {
    if (ordered.isEmpty) {
      throw StateError('尚未登记客户端连接地址，请让管理员添加局域网、HTTPS 或 VPN 媒体地址。');
    }
    final preferred = _safeBaseUrl(preferredAddress);
    if (preferred != null && ordered.remove(preferred)) {
      ordered.insert(0, preferred);
    }
    // FN 账号优先使用管理员明确登记的 FN 媒体入口，不由账号域名推测地址。
    if (preferFnRelay) {
      final relay = ordered.where((address) {
        final uri = Uri.parse(address);
        return uri.scheme == 'https' && uri.host.endsWith('.fnos.net');
      }).toList();
      ordered
        ..removeWhere(relay.contains)
        ..insertAll(0, relay);
    }
  }
  final probe = verify ?? verifyFlyMediaAddress;
  final clock = Stopwatch()..start();
  const totalBudget = Duration(seconds: 12);
  const perProbe = Duration(seconds: 3);
  for (final address in ordered) {
    final remaining = totalBudget - clock.elapsed;
    if (remaining <= Duration.zero) break;
    try {
      // The verifier enforces a total deadline and cancels/closes actual IO;
      // Future.timeout alone would leave the previous candidate running.
      await probe(
        address: address,
        kind: kind,
        expectedId: expectedId,
        timeout: remaining < perProbe ? remaining : perProbe,
      );
      return address;
    } catch (_) {
      // Do not include remote response text, credentials or addresses in errors.
      if (explicitAddress != null) break;
    }
  }
  throw StateError(
    explicitAddress != null
        ? '无法验证指定媒体地址，请检查网络或重新选择。'
        : '暂时无法连接已授权的媒体地址，请检查网络或手动选择地址。',
  );
}

String? _safeBaseUrl(Object? value) {
  if (value is! String || value.isEmpty || value.length > 2048) return null;
  if (RegExp(r'[\x00-\x20\\?#]').hasMatch(value) ||
      RegExp(r'/(?:\.|\.\.)(?:/|$)').hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.authority.contains('%') ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.pathSegments.any((part) => part == '.' || part == '..')) {
    return null;
  }
  return uri
      .replace(host: uri.host.toLowerCase())
      .toString()
      .replaceAll(RegExp(r'/+$'), '');
}

class _AddressCandidate {
  const _AddressCandidate(this.url, this.priority, this.index);
  final String url;
  final int priority;
  final int index;
}
