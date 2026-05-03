class ApiUrlHelper {
  ApiUrlHelper._();

  static const String _apiImagePrefix = '/v/api/v1/sys/img';
  static const String _directImagePrefix = '/sys/img';
  static const String _vImagePrefix = '/v/sys/img';

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

  static String streamUrl(
    String baseUrl,
    String mediaGuid, {
    int? directLinkQualityIndex,
  }) {
    final guid = mediaGuid.trim();
    if (guid.isEmpty) return '';
    final origin = normalizeBaseUrl(baseUrl);
    if (origin.isEmpty) return '';
    final uri = Uri.parse('$origin/v/api/v1/media/range/$guid');
    if (directLinkQualityIndex == null) {
      return uri.toString();
    }
    return uri
        .replace(
          queryParameters: <String, String>{
            'direct_link_quality_index': directLinkQualityIndex.toString(),
          },
        )
        .toString();
  }

  static List<String> imageCandidates(
    String baseUrl,
    String path, {
    int width = 900,
    bool preferDirectPath = false,
  }) {
    final raw = path.trim();
    if (raw.isEmpty) return const <String>[];
    final uri = Uri.tryParse(raw);
    if (uri?.scheme == 'file') {
      return <String>[raw];
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return _absoluteImageCandidates(
        baseUrl,
        raw,
        width: width,
        preferDirectPath: preferDirectPath,
      );
    }

    final origin = originFromBaseUrl(baseUrl);
    if (origin.isEmpty) return const <String>[];
    final imagePath = _extractImagePath(raw) ?? _ensureLeadingSlash(raw);
    return _buildImageCandidates(
      origin: origin,
      imagePath: imagePath,
      width: width,
      preferDirectPath: preferDirectPath,
    );
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
      final originalPath = _extractImagePath(uri.path);

      final normalizedBase = normalizeBaseUrl(baseUrl);
      final baseOrigin = originFromBaseUrl(baseUrl);
      final sameOrigin =
          normalizedBase.isNotEmpty &&
          baseOrigin.isNotEmpty &&
          baseOrigin == absoluteOrigin;

      if (originalPath != null && originalPath.isNotEmpty) {
        return <String>{
          rawUrl,
          ..._buildImageCandidates(
            origin: absoluteOrigin,
            imagePath: originalPath,
            width: width,
            preferDirectPath: preferDirectPath,
          ),
        }.where((value) => value.trim().isNotEmpty).toList();
      }

      if (sameOrigin && uri.path.isNotEmpty && uri.path != '/') {
        return <String>{
          rawUrl,
          ..._buildImageCandidates(
            origin: absoluteOrigin,
            imagePath: _ensureLeadingSlash(uri.path),
            width: width,
            preferDirectPath: preferDirectPath,
          ),
        }.where((value) => value.trim().isNotEmpty).toList();
      }
    } catch (_) {}

    return <String>[rawUrl];
  }

  static List<String> _buildImageCandidates({
    required String origin,
    required String imagePath,
    required int width,
    required bool preferDirectPath,
  }) {
    // Current FN media deployments serve poster assets from the API prefix;
    // legacy /v/sys/img and /sys/img paths may resolve to HTML shells or 404s.
    final apiCandidates = preferDirectPath
        ? <String>[
            '$origin$_apiImagePrefix$imagePath',
            '$origin$_apiImagePrefix$imagePath?w=$width',
          ]
        : <String>[
            '$origin$_apiImagePrefix$imagePath?w=$width',
            '$origin$_apiImagePrefix$imagePath',
          ];
    return apiCandidates
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList();
  }

  static String? _extractImagePath(String rawPath) {
    final normalized = _ensureLeadingSlash(rawPath.trim());
    if (normalized.isEmpty || normalized == '/') return null;
    for (final prefix in <String>[
      _apiImagePrefix,
      _vImagePrefix,
      _directImagePrefix,
    ]) {
      if (normalized == prefix) {
        return '/';
      }
      if (normalized.startsWith('$prefix/')) {
        return normalized.substring(prefix.length);
      }
    }
    return null;
  }

  static String _ensureLeadingSlash(String value) {
    if (value.isEmpty) return '';
    return value.startsWith('/') ? value : '/$value';
  }
}
