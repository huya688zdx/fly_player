class ApiUrlHelper {
  ApiUrlHelper._();

  static String normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.replaceAll(RegExp(r'/+$'), '');
    if (normalized.contains('://')) return normalized;
    return 'http://$normalized';
  }

  static String originFromBaseUrl(String baseUrl) {
    final normalizedBase = normalizeBaseUrl(baseUrl);
    if (normalizedBase.isEmpty) return '';

    try {
      final uri = Uri.parse(normalizedBase);
      if (uri.host.isEmpty) return normalizedBase;
      return Uri(
        scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      ).toString().replaceAll(RegExp(r'/$'), '');
    } catch (_) {
      return normalizedBase;
    }
  }

  static String apiPath(String path) {
    if (path.startsWith('/')) return path;
    return '/$path';
  }

  static String apiUrl(String baseUrl, String path) {
    final normalizedBase = normalizeBaseUrl(baseUrl);
    if (normalizedBase.isEmpty) return '';
    return '$normalizedBase${apiPath(path)}';
  }

  static String streamUrl(String baseUrl, String mediaGuid) {
    final guid = mediaGuid.trim();
    if (guid.isEmpty) return '';
    final url = apiUrl(baseUrl, '/v/api/v1/media/range/$guid');
    if (url.isEmpty) return '';
    return url;
  }

  static List<String> imageCandidates(
    String baseUrl,
    String path, {
    int width = 900,
    bool preferDirectPath = false,
  }) {
    final raw = path.trim();
    if (raw.isEmpty) return const <String>[];
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return _absoluteImageCandidates(
        baseUrl,
        raw,
        width: width,
        preferDirectPath: preferDirectPath,
      );
    }

    final normalizedPath = raw.startsWith('/') ? raw : '/$raw';
    final normalizedBase = normalizeBaseUrl(baseUrl);
    final origin = originFromBaseUrl(baseUrl);
    const sysImgDirectPrefix = '/sys/img';

    final apiCandidates = <String>[
      '$origin/v/api/v1/sys/img$normalizedPath?w=$width',
      '$origin/v/api/v1/sys/img$normalizedPath',
    ];
    final directCandidates = <String>[
      '$normalizedBase$sysImgDirectPrefix$normalizedPath',
      '$normalizedBase/v$sysImgDirectPrefix$normalizedPath',
    ];

    return <String>{
      ...(preferDirectPath ? directCandidates : apiCandidates),
      ...(preferDirectPath ? apiCandidates : directCandidates),
    }.where((value) => value.trim().isNotEmpty).toList();
  }

  static List<String> personImageCandidates(
    String baseUrl,
    String path, {
    int width = 320,
  }) {
    return imageCandidates(
      baseUrl,
      path,
      width: width,
      preferDirectPath: false,
    );
  }

  static List<String> _absoluteImageCandidates(
    String baseUrl,
    String rawUrl, {
    required int width,
    required bool preferDirectPath,
  }) {
    try {
      final uri = Uri.parse(rawUrl);
      final absoluteOrigin = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      ).toString().replaceAll(RegExp(r'/$'), '');

      const sysImgPrefix = '/v/api/v1/sys/img';
      const sysImgDirectPrefix = '/sys/img';
      String? originalPath;
      if (uri.path.startsWith('$sysImgPrefix/')) {
        originalPath = uri.path.substring(sysImgPrefix.length);
      }

      final normalizedBase = normalizeBaseUrl(baseUrl);
      final baseOrigin = originFromBaseUrl(baseUrl);
      final sameOrigin =
          normalizedBase.isNotEmpty &&
          baseOrigin.isNotEmpty &&
          baseOrigin == absoluteOrigin;

      if (originalPath != null && originalPath.isNotEmpty) {
        final apiCandidates = <String>[
          '$absoluteOrigin$sysImgPrefix$originalPath?w=$width',
          '$absoluteOrigin$sysImgPrefix$originalPath',
        ];
        final directCandidates = <String>[
          '$absoluteOrigin$sysImgDirectPrefix$originalPath',
          '$absoluteOrigin/v$sysImgDirectPrefix$originalPath',
        ];
        return <String>{
          ...apiCandidates,
          rawUrl,
          ...directCandidates,
        }.where((value) => value.trim().isNotEmpty).toList();
      }

      if (sameOrigin && uri.path.isNotEmpty && uri.path != '/') {
        final normalizedPath = uri.path.startsWith('/')
            ? uri.path
            : '/${uri.path}';
        final apiCandidates = <String>[
          '$absoluteOrigin/v/api/v1/sys/img$normalizedPath?w=$width',
          '$absoluteOrigin/v/api/v1/sys/img$normalizedPath',
        ];
        final directCandidates = <String>[
          rawUrl,
          '$absoluteOrigin$sysImgDirectPrefix$normalizedPath',
          '$absoluteOrigin/v$sysImgDirectPrefix$normalizedPath',
        ];
        return <String>{
          ...apiCandidates,
          ...directCandidates,
        }.where((value) => value.trim().isNotEmpty).toList();
      }
    } catch (_) {}

    return <String>[rawUrl];
  }
}
