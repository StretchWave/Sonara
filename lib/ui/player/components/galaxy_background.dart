import 'dart:math';

import 'package:flutter/material.dart';

/// Animated interactive galaxy starfield overlay.
///
/// Renders a field of twinkling, slowly drifting stars with a soft nebula
/// glow. The field reacts to pointer movement: stars near the pointer get
/// gently pushed away and glow brighter while touched.
///
/// Uses a raw [Listener] so it observes pointer positions without
/// participating in the gesture arena (dragging the player panel still
/// works while the stars react).
class GalaxyOverlay extends StatefulWidget {
  const GalaxyOverlay({super.key, this.opacity = 0.85});

  /// Overall opacity of the starfield.
  final double opacity;

  @override
  State<GalaxyOverlay> createState() => _GalaxyOverlayState();
}

class _GalaxyOverlayState extends State<GalaxyOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_Star> _stars;
  final List<_Nebula> _nebulas = [];
  final Random _random = Random(42);
  Offset? _touchPoint;
  bool _touching = false;
  double? _releaseTime;
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _initNebulas();
    _initStars(const Size(400, 800));
  }

  void _initNebulas() {
    _nebulas.addAll([
      _Nebula(
        center: const Offset(0.2, 0.25),
        radius: 0.55,
        hue: 265,
        opacity: 0.05,
      ),
      _Nebula(
        center: const Offset(0.85, 0.7),
        radius: 0.5,
        hue: 200,
        opacity: 0.05,
      ),
      _Nebula(
        center: const Offset(0.55, 0.9),
        radius: 0.45,
        hue: 320,
        opacity: 0.04,
      ),
    ]);
  }

  void _initStars(Size size) {
    final count =
        ((size.width * size.height) / 9500).round().clamp(45, 150).toInt();
    _stars = List.generate(count, (i) {
      return _Star(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        radius: 0.4 + _random.nextDouble() * 1.6,
        baseOpacity: 0.25 + _random.nextDouble() * 0.7,
        twinkleSpeed: 0.6 + _random.nextDouble() * 2.2,
        phase: _random.nextDouble() * 2 * pi,
        driftDx: (_random.nextDouble() - 0.5) * 0.004,
        driftDy: (_random.nextDouble() - 0.5) * 0.004,
        hue: 190 + _random.nextDouble() * 140,
      );
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _touchPoint = event.localPosition;
      _touching = true;
      _releaseTime = null;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    setState(() {
      _touchPoint = event.localPosition;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    setState(() {
      _touching = false;
      _touchPoint = event.localPosition;
      _releaseTime = _controller.value;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) => setState(() {
        _touching = false;
        _touchPoint = null;
      }),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (_lastSize != size && size.width > 0 && size.height > 0) {
            _lastSize = size;
            if (_stars.length !=
                ((size.width * size.height) / 9500).round().clamp(45, 150)) {
              _initStars(size);
            }
          }
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: size,
                painter: _GalaxyPainter(
                  stars: _stars,
                  nebulas: _nebulas,
                  time: _controller.value,
                  touchPoint: _touchPoint,
                  touching: _touching,
                  releaseTime: _releaseTime,
                  opacity: widget.opacity,
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void didUpdateWidget(covariant GalaxyOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opacity != widget.opacity) {
      setState(() {});
    }
  }
}

class _Star {
  final double x;
  final double y;
  final double radius;
  final double baseOpacity;
  final double twinkleSpeed;
  final double phase;
  final double driftDx;
  final double driftDy;
  final double hue;

  _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.baseOpacity,
    required this.twinkleSpeed,
    required this.phase,
    required this.driftDx,
    required this.driftDy,
    required this.hue,
  });
}

class _Nebula {
  final Offset center;
  final double radius;
  final double hue;
  final double opacity;

  _Nebula({
    required this.center,
    required this.radius,
    required this.hue,
    required this.opacity,
  });
}

class _GalaxyPainter extends CustomPainter {
  final List<_Star> stars;
  final List<_Nebula> nebulas;
  final double time;
  final Offset? touchPoint;
  final bool touching;
  final double? releaseTime;
  final double opacity;

  static const double _touchRadius = 130;

  _GalaxyPainter({
    required this.stars,
    required this.nebulas,
    required this.time,
    required this.touchPoint,
    required this.touching,
    required this.releaseTime,
    required this.opacity,
  });

  /// Touch strength: 1 while touching, fading to 0 over ~0.6s after release.
  double get _touchStrength {
    if (touching) return 1;
    final release = releaseTime;
    if (release == null) return 0;
    final elapsed = (time - release) % 1.0;
    if (elapsed > 0.6) return 0;
    return 1 - elapsed / 0.6;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Soft nebula gradients
    for (final nebula in nebulas) {
      final center = Offset(
        nebula.center.dx * size.width,
        nebula.center.dy * size.height,
      );
      final radius = nebula.radius * size.shortestSide;
      final color = HSVColor.fromAHSV(nebula.opacity, nebula.hue, 0.55, 1.0)
          .toColor();
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    // Stars
    final basePos = Offset(
      touchPoint?.dx ?? -1e4,
      touchPoint?.dy ?? -1e4,
    );
    for (final star in stars) {
      final px = ((star.x + star.driftDx * time * 8) % 1.0).clamp(0.0, 1.0) *
          size.width;
      final py = ((star.y + star.driftDy * time * 8) % 1.0).clamp(0.0, 1.0) *
          size.height;
      final position = Offset(px, py);

      // Twinkle
      final twinkle =
          0.55 + 0.45 * sin(star.phase + time * star.twinkleSpeed * 2 * pi);

      // Touch reaction: push away + glow
      final dist = (position - basePos).distance;
      final inTouch = dist < _touchRadius;
      final touchStrength = _touchStrength;
      var glowFactor = 0.0;
      var push = Offset.zero;
      if (inTouch && touchStrength > 0.01) {
        final falloff = 1 - dist / _touchRadius;
        glowFactor = falloff * touchStrength;
        if (dist > 1) {
          push = (position - basePos) / dist * falloff * 14 * touchStrength;
        }
      }

      final starPos = position + push;
      final alpha = (star.baseOpacity * twinkle + glowFactor * 0.8)
          .clamp(0.0, 1.0)
          .toDouble();

      final color = HSVColor.fromAHSV(1, star.hue, 0.35, 1).toColor();
      final starPaint = Paint()
        ..color = color.withValues(alpha: alpha * opacity);

      final radius = star.radius * (1 + glowFactor * 1.6);
      canvas.drawCircle(starPos, radius, starPaint);

      // Glow halo for bright stars / touched stars
      if (radius > 1.1) {
        final haloPaint = Paint()
          ..color = color.withValues(
              alpha: (alpha * 0.35 * (1 + glowFactor * 2)).clamp(0.0, 0.6));
        canvas.drawCircle(starPos, radius * 2.6, haloPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.touchPoint != touchPoint ||
        oldDelegate.touching != touching ||
        oldDelegate.releaseTime != releaseTime ||
        oldDelegate.opacity != opacity;
  }
}
