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
      return _isPrivateHost(host);
    };
    return client;
  }

  bool _isPrivateHost(String host) {
    final normalized = host.trim();
    final address = InternetAddress.tryParse(normalized);
    if (address != null) {
      // Direct NAS access commonly uses self-signed certs on raw IP hosts.
      return true;
    }
    if (normalized == 'localhost') {
      return true;
    }
    if (_knownNasHosts.contains(normalized.toLowerCase())) {
      return true;
    }
    return false;
  }
}
