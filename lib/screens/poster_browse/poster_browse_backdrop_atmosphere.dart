import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 竖屏「大屏浏览」背景氛围层（全出血裁切的配套处理）。
///
/// 背景图改为 BoxFit.cover 铺满整屏后，任意比例的海报/横图都不再露黑；
/// 这三层负责压暗、晕影与颗粒：顶部渐变保住状态栏与信息区可读性，
/// 晕影与颗粒把小图放大后的模糊感读作“氛围”，而不是劣化。
/// 仅手机竖屏布局挂载，横屏/大屏布局保持原有左重渐变处理。
class PosterBrowseBackdropTopScrim extends StatelessWidget {
  const PosterBrowseBackdropTopScrim({super.key});

  static const double _fadeExtent = 0.18;

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x9106080E),
            Color(0x0006080E),
            Color(0x0006080E),
          ],
          stops: <double>[0.0, _fadeExtent, 1.0],
        ),
      ),
    );
  }
}

class PosterBrowseBackdropVignette extends StatelessWidget {
  const PosterBrowseBackdropVignette({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.1),
          radius: 1.25,
          colors: <Color>[Color(0x0006080E), Color(0x5706080E)],
          stops: <double>[0.64, 1.0],
        ),
      ),
    );
  }
}

class PosterBrowseBackdropGrain extends StatefulWidget {
  const PosterBrowseBackdropGrain({super.key, this.opacity = 0.05});

  /// 颗粒强度（0~1），对应噪点纹理的整体透明度。
  final double opacity;

  @override
  State<PosterBrowseBackdropGrain> createState() =>
      _PosterBrowseBackdropGrainState();
}

class _PosterBrowseBackdropGrainState extends State<PosterBrowseBackdropGrain> {
  // 全进程共享一张细颗粒噪声纹理；静态内容首帧后不再重绘。
  static const int _textureSize = 128;
  static ui.Image? _texture;
  static Future<ui.Image>? _textureLoad;

  @override
  void initState() {
    super.initState();
    _ensureTexture().whenComplete(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  static Future<ui.Image> _ensureTexture() {
    final cached = _texture;
    if (cached != null) {
      return SynchronousFuture<ui.Image>(cached);
    }
    return _textureLoad ??= _generateTexture();
  }

  static Future<ui.Image> _generateTexture() {
    // 固定种子：每次启动颗粒分布一致，避免闪变。
    final rng = math.Random(20260828);
    final bytes = Uint8List(_textureSize * _textureSize * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      final v = rng.nextInt(256);
      bytes[i] = v;
      bytes[i + 1] = v;
      bytes[i + 2] = v;
      bytes[i + 3] = 255;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      _textureSize,
      _textureSize,
      ui.PixelFormat.rgba8888,
      (image) {
        _texture = image;
        completer.complete(image);
      },
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final texture = _texture;
    if (texture == null) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GrainPainter(
            texture: texture,
            opacity: widget.opacity.clamp(0.0, 1.0),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.texture, required this.opacity});

  final ui.Image texture;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      texture.width.toDouble(),
      texture.height.toDouble(),
    );
    // modulate 白色：只缩放纹理的 alpha，不改变噪点明暗。
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..colorFilter = ColorFilter.mode(
        Color.fromRGBO(255, 255, 255, opacity),
        BlendMode.modulate,
      );
    final tileSize = texture.width.toDouble();
    for (var y = 0.0; y < size.height; y += tileSize) {
      for (var x = 0.0; x < size.width; x += tileSize) {
        canvas.drawImageRect(
          texture,
          src,
          Rect.fromLTWH(x, y, tileSize, tileSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) {
    return texture != oldDelegate.texture || opacity != oldDelegate.opacity;
  }
}
