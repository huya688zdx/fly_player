import 'package:flutter/material.dart';

class PlayerBackdropImage extends StatefulWidget {
  final List<String> urls;
  final String token;

  const PlayerBackdropImage({
    super.key,
    required this.urls,
    required this.token,
  });

  @override
  State<PlayerBackdropImage> createState() => _PlayerBackdropImageState();
}

class _PlayerBackdropImageState extends State<PlayerBackdropImage> {
  int _urlIndex = 0;

  @override
  void didUpdateWidget(covariant PlayerBackdropImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls || oldWidget.token != widget.token) {
      _urlIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty || widget.token.trim().isEmpty) {
      return const ColoredBox(color: Color(0xFF050608));
    }
    return Image.network(
      widget.urls[_urlIndex],
      fit: BoxFit.cover,
      headers: <String, String>{
        'Authorization': widget.token,
        'Trim-MC-token': widget.token,
      },
      errorBuilder: (context, error, stackTrace) {
        if (_urlIndex + 1 < widget.urls.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _urlIndex += 1);
          });
        }
        return const ColoredBox(color: Color(0xFF050608));
      },
    );
  }
}
