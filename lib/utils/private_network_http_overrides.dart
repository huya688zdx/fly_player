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

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) {
      return allowsBadCertificateForHost(host);
    };
    return client;
  }

  static bool allowsBadCertificateForHost(String host) {
    final normalized = host.trim().toLowerCase();
    final address = InternetAddress.tryParse(normalized);
    if (address != null) {
      return _isPrivateAddress(address);
    }
    if (normalized == 'localhost') {
      return true;
    }
    if (_knownNasHosts.contains(normalized)) {
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
