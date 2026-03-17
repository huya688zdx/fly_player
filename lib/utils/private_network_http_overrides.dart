import 'dart:io';

class PrivateNetworkHttpOverrides extends HttpOverrides {
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
    return normalized == 'localhost';
  }
}
