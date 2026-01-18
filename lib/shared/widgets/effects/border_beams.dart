import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:glowy_borders/glowy_borders.dart';
import '../../../core/theme/app_colors.dart';

/// Animated neon border effect widget for the "neon" animation style.
/// Creates a glowing, pulsing border effect using the brand colors.
class BorderBeams extends StatelessWidget {
  const BorderBeams({
    super.key,
    required this.child,
    this.borderRadius = 12.0,
    this.glowSize = 4.0,
    this.animationDuration = const Duration(milliseconds: 2000),
  });

  final Widget child;
  final double borderRadius;
  final double glowSize;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;
    final colorScheme = Theme.of(context).colorScheme;

    // Build gradient colors based on theme
    final gradientColors = isDark
        ? [
            colorScheme.primary.withValues(alpha: 0.8), // Databricks orange
            appColors.accent.withValues(alpha: 0.6), // Electric cyan
            colorScheme.primary.withValues(alpha: 0.4),
          ]
        : [
            colorScheme.primary.withValues(alpha: 0.5),
            appColors.accent.withValues(alpha: 0.3),
            colorScheme.primary.withValues(alpha: 0.2),
          ];

    return AnimatedGradientBorder(
      borderSize: glowSize,
      glowSize: glowSize,
      gradientColors: gradientColors,
      borderRadius: BorderRadius.circular(borderRadius),
      animationTime: animationDuration.inSeconds,
      child: child,
    );
  }
}

/// A background wrapper that adds subtle neon glow effects
class BorderBeamsBackground extends StatefulWidget {
  const BorderBeamsBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<BorderBeamsBackground> createState() => _BorderBeamsBackgroundState();
}

class _BorderBeamsBackgroundState extends State<BorderBeamsBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isDark) {
      // No background effects in light mode
      return widget.child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;

    return Stack(
      children: [
        widget.child,
        // Subtle corner glow effects
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: NeonGlowPainter(
                    primaryColor: colorScheme.primary,
                    accentColor: appColors.accent,
                    pulseValue: _pulseAnimation.value,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for subtle neon glow in corners
class NeonGlowPainter extends CustomPainter {
  final Color primaryColor;
  final Color accentColor;
  final double pulseValue;

  NeonGlowPainter({
    required this.primaryColor,
    required this.accentColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = 0.05 + (pulseValue * 0.03);

    // Top-right corner glow (primary/orange)
    final topRightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withValues(alpha: opacity),
          primaryColor.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width, 0),
          radius: size.width * 0.4,
        ),
      );
    canvas.drawCircle(
      Offset(size.width, 0),
      size.width * 0.4,
      topRightPaint,
    );

    // Bottom-left corner glow (accent/cyan)
    final bottomLeftPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor.withValues(alpha: opacity),
          accentColor.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(0, size.height),
          radius: size.width * 0.3,
        ),
      );
    canvas.drawCircle(
      Offset(0, size.height),
      size.width * 0.3,
      bottomLeftPaint,
    );
  }

  @override
  bool shouldRepaint(NeonGlowPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue;
  }
}

/// Wave ripple loading indicator for neon style
class WaveRippleLoader extends StatefulWidget {
  const WaveRippleLoader({
    super.key,
    this.size = 40.0,
    this.strokeWidth = 2.0,
  });

  final double size;
  final double strokeWidth;

  @override
  State<WaveRippleLoader> createState() => _WaveRippleLoaderState();
}

class _WaveRippleLoaderState extends State<WaveRippleLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: WaveRipplePainter(
              progress: _controller.value,
              primaryColor: colorScheme.primary,
              accentColor: isDark ? appColors.accent : colorScheme.primary,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class WaveRipplePainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color accentColor;
  final double strokeWidth;

  WaveRipplePainter({
    required this.progress,
    required this.primaryColor,
    required this.accentColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Draw multiple expanding rings
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i * 0.33) % 1.0;
      final radius = maxRadius * ringProgress;
      final opacity = (1.0 - ringProgress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = (i % 2 == 0 ? primaryColor : accentColor)
            .withValues(alpha: opacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(WaveRipplePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Interactive particle burst effect for neon style
class CoolModeParticles extends StatefulWidget {
  const CoolModeParticles({
    super.key,
    required this.child,
    this.onTap,
    this.particleCount = 12,
  });

  final Widget child;
  final VoidCallback? onTap;
  final int particleCount;

  @override
  State<CoolModeParticles> createState() => _CoolModeParticlesState();
}

class _CoolModeParticlesState extends State<CoolModeParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _particles.clear();
            _tapPosition = null;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(TapDownDetails details) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;
    final random = math.Random();

    _tapPosition = details.localPosition;
    _particles.clear();

    final colors = [
      colorScheme.primary,
      appColors.accent,
      colorScheme.primary.withValues(alpha: 0.7),
      appColors.accent.withValues(alpha: 0.7),
    ];

    for (int i = 0; i < widget.particleCount; i++) {
      final angle = (i / widget.particleCount) * 2 * math.pi;
      final speed = 50 + random.nextDouble() * 50;
      _particles.add(_Particle(
        x: _tapPosition!.dx,
        y: _tapPosition!.dy,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        color: colors[i % colors.length],
        size: 3 + random.nextDouble() * 3,
      ));
    }

    _controller.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTap,
      child: Stack(
        children: [
          widget.child,
          if (_tapPosition != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ParticlePainter(
                        particles: _particles,
                        progress: _controller.value,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Particle {
  double x;
  double y;
  final double vx;
  final double vy;
  final Color color;
  final double size;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlePainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final x = particle.x + particle.vx * progress;
      final y = particle.y + particle.vy * progress;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final currentSize = particle.size * (1.0 - progress * 0.5);

      final paint = Paint()
        ..color = particle.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), currentSize, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
