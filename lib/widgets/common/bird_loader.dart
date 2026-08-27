import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show Gradient, PathMetric;

import 'package:flutter/material.dart';

/// 青鸟加载动效。
///
/// 灵感取自《利兹与青鸟》：一只燕子沿一条闭合曲线盘旋，在顶点悬停犹豫、
/// 振翅飞离，又沿同一条曲线无声归来 —— 循环处切线连续，零跳变。
///
/// 燕形为三个同构关键帧（控制点形变生成）的数值插值，扇翅频率跟随速度：
/// 悬停时高频浅颤，滑翔时舒展慢拍。残影按固定路径间距跟飞，透明度随速度
/// 淡入。颜色默认取 [ColorScheme.primary] 派生三档明度渐变，自动跟随
/// 动态取色；[BirdLoaderStyle.logo] 使用品牌青绿→蓝→紫原生渐变。
enum BirdLoaderStyle { theme, logo }

const _loopDuration = Duration(milliseconds: 7000);
const _birdVisualScale = 2.1;

class BirdLoader extends StatefulWidget {
  const BirdLoader({
    super.key,
    this.size = 96,
    this.style = BirdLoaderStyle.theme,
  });

  /// 正方形渲染区边长。
  final double size;
  final BirdLoaderStyle style;

  @override
  State<BirdLoader> createState() => _BirdLoaderState();
}

class _BirdLoaderState extends State<BirdLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _static = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _loopDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disabled) {
      if (_controller.isAnimating) _controller.stop();
      _static = true;
    } else {
      _static = false;
      if (!_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _BirdPalette.resolve(context, widget.style);
    Widget paint(double t) => CustomPaint(
      painter: _BirdPainter(
        t: t,
        palette: palette,
        assets: _BirdAssets.instance,
        showEchoes: widget.size >= 56,
        showGlow: widget.size >= 90,
      ),
    );
    return SizedBox.square(
      dimension: widget.size,
      child: _static
          ? paint(0.65)
          : AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => paint(_controller.value),
            ),
    );
  }
}

class _BirdPalette {
  const _BirdPalette(this.light, this.mid, this.deep);

  final Color light;
  final Color mid;
  final Color deep;

  static const _logo = _BirdPalette(
    Color(0xFF4AE8CF),
    Color(0xFF3FA9F5),
    Color(0xFF8B7CF6),
  );

  factory _BirdPalette.resolve(BuildContext context, BirdLoaderStyle style) {
    if (style == BirdLoaderStyle.logo) return _logo;
    return _BirdPalette.fromColor(Theme.of(context).colorScheme.primary);
  }

  /// 从单一主色派生「亮 / 主 / 深」三档渐变。
  factory _BirdPalette.fromColor(Color base) {
    final hsl = HSLColor.fromColor(base);
    return _BirdPalette(
      hsl.withLightness((hsl.lightness + 0.14).clamp(0.0, 1.0)).toColor(),
      base,
      hsl
          .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0))
          .withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0))
          .toColor(),
    );
  }
}

/// 仅燕形本体的迷你加载指示：无轨道、无残影，扇翅与 [BirdLoader]
/// 共享同一节奏。用于行内小尺寸等待位。
class BirdGlyph extends StatefulWidget {
  const BirdGlyph({super.key, this.size = 20, this.color});

  /// 正方形渲染区边长。
  final double size;

  /// 覆盖主题强调色（如按钮前景色场景）。
  final Color? color;

  @override
  State<BirdGlyph> createState() => _BirdGlyphState();
}

class _BirdGlyphState extends State<BirdGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _loopDuration,
  );
  bool _static = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disabled) {
      if (_controller.isAnimating) _controller.stop();
      _static = true;
    } else {
      _static = false;
      if (!_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _BirdPalette.fromColor(
      widget.color ?? Theme.of(context).colorScheme.primary,
    );
    Widget paint(double t) => SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _BirdGlyphPainter(t: t, palette: palette),
      ),
    );
    return _static
        ? paint(0.65)
        : AnimatedBuilder(
            animation: _controller,
            builder: (_, _) => paint(_controller.value),
          );
  }
}

class _BirdGlyphPainter extends CustomPainter {
  _BirdGlyphPainter({required this.t, required this.palette});

  final double t;
  final _BirdPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 46;
    final phase = _BirdAssets.instance.phaseOf(t);
    final blend = (math.sin(phase) * 17 / 18).clamp(-1.0, 1.0); // 与主加载器同幅度扇翅
    final bob = math.sin(phase * 0.875) * 1.2; // 单位：舞台坐标

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + bob * scale);
    canvas.rotate(blend * 0.055);
    canvas.scale(scale);
    // 注意：设置 shader 后 Paint.color 被忽略，透明度需烘进渐变色
    final shader = ui.Gradient.linear(
      const Offset(-18, -16),
      const Offset(10, 14),
      [palette.light, palette.mid, palette.deep],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawPath(_lerpBirdPath(blend), Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BirdGlyphPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.palette != palette;
}

/// 三帧同构路径的数值插值：blend ∈ [-1,1]，>0 向上拍帧、<0 向下拍帧。
Path _lerpBirdPath(double blend) {
  final target = blend >= 0 ? _frameUp : _frameDown;
  final f = blend.abs();
  const mid = _frameMid;
  var i = 0;

  Offset pair() {
    final o = Offset(
      mid[i] + (target[i] - mid[i]) * f,
      mid[i + 1] + (target[i + 1] - mid[i + 1]) * f,
    );
    i += 2;
    return o;
  }

  final first = pair();
  final path = Path()..moveTo(first.dx, first.dy);
  void cubic() {
    final a = pair();
    final b = pair();
    final c = pair();
    path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
  }

  void line() {
    final p = pair();
    path.lineTo(p.dx, p.dy);
  }

  // 帧结构：M + 8×C + L + 3×C + L + 2×C + Z（84 个数）
  cubic();
  cubic();
  cubic();
  cubic();
  cubic();
  cubic();
  cubic();
  cubic();
  line();
  cubic();
  cubic();
  cubic();
  line();
  cubic();
  cubic();
  path.close();
  assert(i == mid.length, 'bird frame data length mismatch: $i');
  return path;
}

/// 与帧无关的静态资源：飞行路径、相位积分表、虚线轨道。
class _BirdAssets {
  _BirdAssets._() {
    _flight = _buildFlightPath();
    metric = _flight.computeMetrics().first;
    _buildPhaseTable();
    _orbit = _buildOrbitDashes();
  }

  static final _BirdAssets instance = _BirdAssets._();

  static const _stageW = 520.0;
  static const _stageH = 340.0;

  late final Path _flight;
  late final ui.PathMetric metric;
  late final Path _orbit;
  late final Float32List _phaseTable;

  // ── 时间 → 弧长 映射（分段 smoothstep 关键帧）──
  // 关键帧 [t, s]：盘旋 | 悬停犹豫 | 冲出 | 场外巡航 | 归来
  static const _knots = <(double, double)>[
    (0.0, 0.0),
    (0.58, 0.185),
    (0.72, 0.215),
    (0.78, 0.30),
    (0.92, 0.90),
    (1.0, 1.0),
  ];

  static double _smoothstep(double x) => x * x * (3 - 2 * x);

  static double sOf(double t) {
    t = ((t % 1) + 1) % 1;
    for (var i = 1; i < _knots.length; i++) {
      if (t <= _knots[i].$1) {
        final (t0, s0) = _knots[i - 1];
        final (t1, s1) = _knots[i];
        return s0 + (s1 - s0) * _smoothstep((t - t0) / (t1 - t0));
      }
    }
    return 1;
  }

  static double _gauss(double x, double mu, double sig) =>
      math.exp(-math.pow(x - mu, 2) / (2 * sig * sig));

  static double _sstep(double x, double a, double b) =>
      _smoothstep(((x - a) / (b - a)).clamp(0.0, 1.0));

  // 扇翅相位是 freq 的时间积分（freq 随阶段变化），预积分成查找表。
  // 每步 1/120 圈，共 120 段 + 1 个端点。
  void _buildPhaseTable() {
    const steps = 120;
    const dt = 1 / steps;
    final table = Float32List(steps + 1);
    var phase = 0.0;
    for (var i = 0; i < steps; i++) {
      table[i] = phase;
      final t = i * dt;
      final s = sOf(t);
      final wHes = _gauss(s, 0.20, 0.03);
      final wEsc = _sstep(t, 0.74, 0.80) * (1 - _sstep(t, 0.93, 1));
      final freq = 2.2 + 3.4 * wHes - 1.1 * wEsc; // 圈/秒
      phase += math.pi * 2 * freq * dt * 7.0; // × 单圈 7 秒
    }
    table[steps] = phase;
    _phaseTable = table;
  }

  double phaseOf(double t) {
    const steps = 120;
    final x = (t.clamp(0.0, 1.0)) * steps;
    final i = x.floor();
    if (i >= steps) return _phaseTable[steps];
    final f = x - i;
    return _phaseTable[i] + (_phaseTable[i + 1] - _phaseTable[i]) * f;
  }

  Path _buildFlightPath() {
    // 闭合、接缝切线连续：轨道 → 顶部飞离 → 场外大回环 → 右侧俯冲归位。
    return Path()
      ..moveTo(380, 170)
      ..cubicTo(380, 214, 324, 248, 260, 248)
      ..cubicTo(196, 248, 140, 214, 140, 170)
      ..cubicTo(140, 126, 196, 92, 260, 92)
      ..cubicTo(320, 92, 368, 70, 402, 42)
      ..cubicTo(436, 14, 500, 2, 556, 18)
      ..cubicTo(640, 40, 668, 130, 650, 210)
      ..cubicTo(632, 292, 560, 350, 460, 362)
      ..cubicTo(360, 374, 200, 368, 100, 332)
      ..cubicTo(0, 296, -55, 226, -58, 146)
      ..cubicTo(-61, 66, -16, -6, 70, -34)
      ..cubicTo(190, -70, 400, -50, 470, 40)
      ..cubicTo(500, 95, 380, 90, 380, 170)
      ..close();
  }

  Path _buildOrbitDashes() {
    final ellipse = Path()
      ..addOval(
        Rect.fromCenter(
          center: const Offset(260, 170),
          width: 240,
          height: 156,
        ),
      );
    final metric = ellipse.computeMetrics().first;
    final total = metric.length;
    const dash = 1.2, gap = 7.0;
    final out = Path();
    var d = 0.0;
    while (d < total) {
      out.addPath(
        metric.extractPath(d, math.min(d + dash, total)),
        Offset.zero,
      );
      d += dash + gap;
    }
    return out;
  }
}

class _BirdPainter extends CustomPainter {
  _BirdPainter({
    required this.t,
    required this.palette,
    required _BirdAssets assets,
    required this.showEchoes,
    required this.showGlow,
  }) : _a = assets;

  final double t;
  final _BirdPalette palette;
  final _BirdAssets _a;
  final bool showEchoes;
  final bool showGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / _BirdAssets._stageW,
      size.height / _BirdAssets._stageH,
    );
    canvas.save();
    canvas.translate(
      (size.width - _BirdAssets._stageW * scale) / 2,
      (size.height - _BirdAssets._stageH * scale) / 2,
    );
    canvas.scale(scale);

    // 虚线轨道
    canvas.drawPath(
      _a._orbit,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = palette.mid.withValues(alpha: 0.07)
        ..strokeWidth = 1,
    );

    // 时间 → 弧长 与相位
    final s = _BirdAssets.sOf(t);
    final spd = () {
      var d = s - _BirdAssets.sOf(t - 0.016);
      if (d < -0.5) d += 1;
      if (d > 0.5) d -= 1;
      return (d.abs() / 0.012).clamp(0.0, 1.0);
    }();
    final phase = _a.phaseOf(t);
    final wHes = _BirdAssets._gauss(s, 0.20, 0.03);
    final wEsc =
        _BirdAssets._sstep(t, 0.74, 0.80) *
        (1 - _BirdAssets._sstep(t, 0.93, 1));
    final amp = 17.0 - 8 * wHes + 3 * wEsc;
    final blend = (math.sin(phase) * amp / 18).clamp(-1.0, 1.0);
    // 飞离渐远缩小 / 归来还原
    final k =
        1.0 -
        0.30 * _BirdAssets._sstep(t, 0.76, 0.84) +
        0.30 * _BirdAssets._sstep(t, 0.94, 1);

    final len = _a.metric.length;

    if (showEchoes) {
      _drawBird(
        canvas,
        _lag(s, len, 80),
        k,
        (math.sin(phase - 1.0) * amp / 18).clamp(-1.0, 1.0),
        0.06 * (0.1 + 0.9 * spd),
        glow: false,
      );
      _drawBird(
        canvas,
        _lag(s, len, 40),
        k,
        (math.sin(phase - 0.5) * amp / 18).clamp(-1.0, 1.0),
        0.14 * (0.1 + 0.9 * spd),
        glow: false,
      );
    }
    _drawBird(canvas, s, k, blend, 1.0, glow: showGlow);
    canvas.restore();
  }

  /// 固定路径间距回退（循环闭合，负距离回绕）。
  static double _lag(double s, double len, double units) {
    var x = s - units / len;
    if (x < 0) x += 1;
    return x;
  }

  void _drawBird(
    Canvas canvas,
    double s,
    double scale,
    double blend,
    double opacity, {
    required bool glow,
  }) {
    // 位置与切线（取切线采样点，含角度）
    final len = _a.metric.length;
    final d = (s.clamp(0.0, 1.0)) * len;
    final tan = _a.metric.getTangentForOffset(d.clamp(0.0, len));
    final pos = tan!.position;
    var ang = tan.angle + blend * 0.055;
    // 悬停颤振：沿法线的细微抖动（仅悬停段有权重）
    final w = _BirdAssets._gauss(s, 0.20, 0.012);
    final wob = math.sin(t * 7.0 * 21.0) * 1.5 * w;
    final nx = -math.sin(ang);
    final ny = math.cos(ang);

    canvas.save();
    canvas.translate(pos.dx + nx * wob, pos.dy + ny * wob);
    canvas.rotate(ang);
    canvas.scale(scale * _birdVisualScale);

    // 注意：设置了 shader 后 Paint.color 被忽略，透明度需烘进渐变色
    ui.Gradient shader(double alpha) => ui.Gradient.linear(
      const Offset(-18, -16),
      const Offset(10, 14),
      [
        palette.light.withValues(alpha: alpha),
        palette.mid.withValues(alpha: alpha),
        palette.deep.withValues(alpha: alpha),
      ],
      const [0.0, 0.55, 1.0],
    );

    if (glow) {
      canvas.drawPath(
        _lerpBirdPath(blend),
        Paint()
          ..shader = shader(0.4 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawPath(_lerpBirdPath(blend), Paint()..shader = shader(opacity));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BirdPainter oldDelegate) => oldDelegate.t != t;

  @override
  bool operator ==(Object other) =>
      other is _BirdPainter &&
      other.t == t &&
      other.palette == palette &&
      other.showEchoes == showEchoes &&
      other.showGlow == showGlow;

  @override
  int get hashCode => Object.hash(t, palette, showEchoes, showGlow);
}

// ── 燕形三帧数据（Openclipart #278011 CC0，控制点形变生成，同构：M+13C+2L+Z）──

const List<double> _frameDown = [
  -14.260,
  -2.754,
  -5.954,
  -0.477,
  1.126,
  -0.946,
  4.375,
  -3.607,
  7.842,
  -7.557,
  7.434,
  -14.012,
  6.784,
  -20.165,
  13.171,
  -16.855,
  14.526,
  -8.140,
  13.894,
  -3.122,
  13.809,
  -2.205,
  13.026,
  -1.439,
  12.785,
  -0.911,
  14.789,
  0.984,
  16.798,
  2.123,
  17.149,
  4.848,
  15.243,
  5.637,
  13.248,
  5.811,
  11.224,
  6.063,
  9.564,
  8.352,
  9.501,
  8.700,
  6.399,
  12.258,
  3.709,
  15.708,
  0.838,
  17.830,
  -2.811,
  20.000,
  -1.395,
  16.871,
  0.016,
  13.660,
  1.006,
  12.888,
  1.857,
  10.203,
  2.217,
  9.067,
  1.878,
  7.166,
  1.906,
  5.736,
  -3.621,
  2.120,
  -9.495,
  3.277,
  -15.510,
  2.023,
  -17.149,
  1.725,
  -13.133,
  2.235,
  -8.409,
  1.390,
  -5.854,
  1.135,
  -8.176,
  -0.575,
  -7.879,
  0.793,
  -14.260,
  -2.754,
];

const List<double> _frameMid = [
  -14.226,
  -3.032,
  -5.954,
  -0.477,
  1.136,
  -0.976,
  5.047,
  -4.008,
  9.423,
  -7.400,
  10.143,
  -13.828,
  10.571,
  -20.000,
  16.286,
  -15.631,
  16.107,
  -6.814,
  14.374,
  -2.466,
  14.093,
  -1.759,
  13.176,
  -1.196,
  12.869,
  -0.762,
  14.789,
  0.984,
  16.798,
  2.123,
  17.149,
  4.848,
  15.243,
  5.637,
  13.248,
  5.811,
  11.224,
  6.063,
  9.564,
  8.352,
  9.501,
  8.700,
  6.399,
  12.258,
  3.709,
  15.708,
  0.838,
  17.830,
  -2.811,
  20.000,
  -1.395,
  16.871,
  0.016,
  13.660,
  1.006,
  12.888,
  1.857,
  10.203,
  2.217,
  9.067,
  1.878,
  7.166,
  1.906,
  5.736,
  -3.621,
  2.120,
  -9.495,
  3.277,
  -15.510,
  2.023,
  -17.149,
  1.725,
  -13.133,
  2.235,
  -8.409,
  1.390,
  -5.854,
  1.135,
  -8.176,
  -0.575,
  -7.879,
  0.793,
  -14.226,
  -3.032,
];

const List<double> _frameUp = [
  -14.100,
  -3.403,
  -5.954,
  -0.477,
  1.156,
  -1.016,
  6.082,
  -4.361,
  11.540,
  -6.726,
  13.793,
  -12.789,
  15.702,
  -18.674,
  20.190,
  -13.052,
  17.883,
  -4.540,
  14.841,
  -1.430,
  14.352,
  -1.068,
  13.312,
  -0.820,
  12.939,
  -0.535,
  14.788,
  0.986,
  16.798,
  2.123,
  17.149,
  4.848,
  15.243,
  5.637,
  13.248,
  5.811,
  11.224,
  6.063,
  9.564,
  8.352,
  9.501,
  8.700,
  6.399,
  12.258,
  3.709,
  15.708,
  0.838,
  17.830,
  -2.811,
  20.000,
  -1.395,
  16.871,
  0.016,
  13.660,
  1.006,
  12.888,
  1.857,
  10.203,
  2.217,
  9.067,
  1.878,
  7.166,
  1.906,
  5.736,
  -3.621,
  2.120,
  -9.495,
  3.277,
  -15.510,
  2.023,
  -17.149,
  1.725,
  -13.133,
  2.235,
  -8.409,
  1.390,
  -5.854,
  1.135,
  -8.176,
  -0.575,
  -7.879,
  0.793,
  -14.100,
  -3.403,
];
