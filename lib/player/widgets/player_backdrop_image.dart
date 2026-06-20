import 'dart:io';

import 'package:flutter/material.dart';

import '../../utils/nas_image_headers.dart';

class PlayerArtworkImage extends StatefulWidget {
  final List<String> urls;
  final String token;
  final BoxFit fit;
  final Widget? fallback;
  final Alignment alignment;
  final FilterQuality filterQuality;

  const PlayerArtworkImage({
    super.key,
    required this.urls,
    required this.token,
    this.fit = BoxFit.cover,
    this.fallback,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  State<PlayerArtworkImage> createState() => _PlayerArtworkImageState();
}

class PlayerBackdropImage extends StatefulWidget {
  final List<String> urls;
  final String token;
  final BoxFit fit;
  final Widget? fallback;

  const PlayerBackdropImage({
    super.key,
    required this.urls,
    required this.token,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  @override
  State<PlayerBackdropImage> createState() => _PlayerBackdropImageState();
}

class _PlayerArtworkImageState extends State<PlayerArtworkImage> {
  int _urlIndex = 0;

  @override
  void didUpdateWidget(covariant PlayerArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls || oldWidget.token != widget.token) {
      _urlIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return widget.fallback ?? const ColoredBox(color: Color(0xFF050608));
    }
    final currentUrl = widget.urls[_urlIndex].trim();
    if (currentUrl.isEmpty) {
      return widget.fallback ?? const ColoredBox(color: Color(0xFF050608));
    }
    final currentFile = _resolveLocalFile(currentUrl);
    if (currentFile != null) {
      return Image.file(
        currentFile,
        fit: widget.fit,
        alignment: widget.alignment,
        filterQuality: widget.filterQuality,
        errorBuilder: (context, error, stackTrace) =>
            _buildErrorFallback(context),
      );
    }
    return Image.network(
      currentUrl,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      headers: _networkHeaders(currentUrl),
      errorBuilder: (context, error, stackTrace) =>
          _buildErrorFallback(context),
    );
  }

  Widget _buildErrorFallback(BuildContext context) {
    if (_urlIndex + 1 < widget.urls.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _urlIndex += 1);
      });
    }
    return widget.fallback ?? const ColoredBox(color: Color(0xFF050608));
  }

  Map<String, String>? _networkHeaders(String url) {
    final token = widget.token.trim();
    if (token.isEmpty) {
      return null;
    }
    return nasImageHeaders(token, url: url);
  }

  File? _resolveLocalFile(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl);
    if (parsed != null && parsed.scheme.toLowerCase() == 'file') {
      return File(parsed.toFilePath());
    }
    if (_looksLikeLocalPath(rawUrl)) {
      return File(rawUrl);
    }
    return null;
  }

  bool _looksLikeLocalPath(String value) {
    if (value.startsWith('/') || value.startsWith('\\')) {
      return true;
    }
    return value.length > 2 &&
        value[1] == ':' &&
        (value[2] == '\\' || value[2] == '/');
  }
}

class _PlayerBackdropImageState extends State<PlayerBackdropImage> {
  @override
  Widget build(BuildContext context) {
    return PlayerArtworkImage(
      urls: widget.urls,
      token: widget.token,
      fit: widget.fit,
      fallback: widget.fallback,
    );
  }
}
