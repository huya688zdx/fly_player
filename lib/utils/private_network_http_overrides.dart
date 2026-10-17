import 'dart:io';

class PrivateNetworkHttpOverrides extends HttpOverrides {
  static final Set<String> _knownNasHosts = {};

  /// Register a NAS hostname so images served from it also bypass certificate
  /// verification (the API Dio client does this per-host, but [Image.network]
  /// uses the global [HttpOverrides]).
  static void registerNasHost(String host) {
    final trimmed = host.trim().toLowerCase();
    if (trimmed.isNotEmpty) {
      _knownNasHosts.add(trimmed);
    }
  }

  /// 每个 host 的最大并发连接数。
  ///
  /// dart:io 默认**不限**并发，而 Flutter 的 `NetworkImage` 共用一个 static HttpClient——
  /// 海报网格一次滚入几十上百张图时会同时开出同样多的连接，把 NAS 的按需缩图服务打满，
  /// 表现为大量海报卡在占位图（实测 424 部电影时约一半）。这里按浏览器惯例限到 6：
  /// 超出部分由 dart:io 排队，不会失败，只是排队等待。
  ///
  /// 注意这是**每个 HttpClient 实例**的上限：dio 的 IOHttpClientAdapter 各自持有独立
  /// 实例，所以图片被限流不会拖慢 API 请求。
  static const int _maxConnectionsPerHost = 6;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.maxConnectionsPerHost = _maxConnectionsPerHost;
    client.badCertificateCallback = (cert, host, port) {
      return allowsBadCertificateForHost(host);
    };
    return client;
  }

  static bool allowsBadCertificateForHost(String host) {
    final normalized = host.trim().toLowerCase();
    // 已登记 NAS 也可能是公网 IP，必须先匹配，再判断私网地址。
    if (_knownNasHosts.contains(normalized)) {
      return true;
    }
    final address = InternetAddress.tryParse(normalized);
    if (address != null) {
      return _isPrivateAddress(address);
    }
    if (normalized == 'localhost') {
      return true;
    }
    return false;
  }

  static bool _isPrivateAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) {
      return true;
    }
    final raw = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && raw.length == 4) {
      final first = raw[0];
      final second = raw[1];
      return first == 10 ||
          (first == 100 && second >= 64 && second <= 127) ||
          (first == 172 && second >= 16 && second <= 31) ||
          (first == 192 && second == 168);
    }
    if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
      final first = raw[0];
      return (first & 0xfe) == 0xfc;
    }
    return false;
  }
}
