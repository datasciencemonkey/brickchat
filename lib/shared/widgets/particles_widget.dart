import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A starfield effect widget that displays animated stars like a night sky
/// Features twinkling stars of varying sizes and brightness
class ParticlesWidget extends StatefulWidget {
  const ParticlesWidget({
    super.key,
    this.quantity = 50,
    this.ease = 80,
    required this.color,
    this.staticity = 50,
    this.size = 0.4,
    this.vx = 0,
    this.vy = 0,
  });

  final int quantity;
  final int ease;
  final Color color;
  final int staticity;
  final double size;
  final double vx;
  final double vy;

  @override
  State<ParticlesWidget> createState() => _ParticlesWidgetState();
}

class _ParticlesWidgetState extends State<ParticlesWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Star> _stars = [];
  Offset _mousePosition = Offset.zero;
  Size _canvasSize = Size.zero;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateStars);
    _controller.repeat();
  }

  @override
  void didUpdateWidget(ParticlesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _initStars();
    }
  }

  void _initStars() {
    _stars.clear();
    final random = math.Random();

    for (int i = 0; i < widget.quantity; i++) {
      // Create variety of star sizes - mostly small, some medium, few large
      final sizeCategory = random.nextDouble();
      double starSize;
      if (sizeCategory < 0.6) {
        // 60% small stars
        starSize = widget.size * (0.3 + random.nextDouble() * 0.4);
      } else if (sizeCategory < 0.9) {
        // 30% medium stars
        starSize = widget.size * (0.7 + random.nextDouble() * 0.5);
      } else {
        // 10% large bright stars
        starSize = widget.size * (1.2 + random.nextDouble() * 0.8);
      }

      _stars.add(Star(
        x: random.nextDouble() * _canvasSize.width,
        y: random.nextDouble() * _canvasSize.height,
        size: starSize,
        twinkleSpeed: 0.5 + random.nextDouble() * 2.0,
        twinklePhase: random.nextDouble() * math.pi * 2,
        baseOpacity: 0.4 + random.nextDouble() * 0.5,
        isLargeStar: sizeCategory >= 0.9,
      ));
    }
  }

  void _updateStars() {
    _time += 0.016; // ~60fps

    for (var star in _stars) {
      // Very slow drift for stars (almost stationary like real stars)
      star.x += star.dx * 0.1 + widget.vx * 0.05;
      star.y += star.dy * 0.1 + widget.vy * 0.05;

      // Twinkling effect using sine wave
      final twinkle = math.sin(_time * star.twinkleSpeed + star.twinklePhase);
      star.opacity = star.baseOpacity + twinkle * 0.3;
      star.opacity = star.opacity.clamp(0.1, 1.0);

      // Mouse interaction - stars glow brighter near cursor
      final dx = _mousePosition.dx - star.x;
      final dy = _mousePosition.dy - star.y;
      final distance = math.sqrt(dx * dx + dy * dy);

      if (distance < 150) {
        final glow = (150 - distance) / 150;
        star.opacity = (star.opacity + glow * 0.4).clamp(0.0, 1.0);
        star.glowIntensity = glow;
      } else {
        star.glowIntensity *= 0.95;
      }

      // Boundary wrap-around (stars reappear on opposite side)
      if (star.x < -10) star.x = _canvasSize.width + 10;
      if (star.x > _canvasSize.width + 10) star.x = -10;
      if (star.y < -10) star.y = _canvasSize.height + 10;
      if (star.y > _canvasSize.height + 10) star.y = -10;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        _mousePosition = event.localPosition;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_canvasSize != constraints.biggest) {
            _canvasSize = constraints.biggest;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _initStars();
            });
          }
          return CustomPaint(
            size: _canvasSize,
            painter: StarfieldPainter(
              stars: _stars,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class Star {
  double x;
  double y;
  final double size;
  double opacity;
  final double baseOpacity;
  final double twinkleSpeed;
  final double twinklePhase;
  final bool isLargeStar;
  double glowIntensity = 0;
  double dx = (math.Random().nextDouble() - 0.5) * 0.2;
  double dy = (math.Random().nextDouble() - 0.5) * 0.2;

  Star({
    required this.x,
    required this.y,
    required this.size,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.baseOpacity,
    required this.isLargeStar,
  }) : opacity = baseOpacity;
}

class StarfieldPainter extends CustomPainter {
  final List<Star> stars;
  final Color color;

  StarfieldPainter({
    required this.stars,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var star in stars) {
      final center = Offset(star.x, star.y);

      // Draw glow for larger stars or when mouse is near
      if (star.isLargeStar || star.glowIntensity > 0.1) {
        final glowRadius = star.size * 4 * (1 + star.glowIntensity);
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: star.opacity * 0.4),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
        canvas.drawCircle(center, glowRadius, glowPaint);
      }

      // Draw star core
      final corePaint = Paint()
        ..color = Color.lerp(color, Colors.white, 0.7)!
            .withValues(alpha: star.opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, star.size, corePaint);

      // Draw 4-point star sparkle for large stars
      if (star.isLargeStar) {
        final sparklePaint = Paint()
          ..color = Colors.white.withValues(alpha: star.opacity * 0.6)
          ..strokeWidth = star.size * 0.3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final sparkleLength = star.size * 3;

        // Horizontal line
        canvas.drawLine(
          Offset(star.x - sparkleLength, star.y),
          Offset(star.x + sparkleLength, star.y),
          sparklePaint,
        );
        // Vertical line
        canvas.drawLine(
          Offset(star.x, star.y - sparkleLength),
          Offset(star.x, star.y + sparkleLength),
          sparklePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(StarfieldPainter oldDelegate) => true;
}
