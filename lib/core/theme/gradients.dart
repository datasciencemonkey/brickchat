import 'package:flutter/material.dart';

abstract class AppGradients {
  // Dark theme gradients
  static const darkPrimaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF8B5CF6), // Purple
      Color(0xFF6366F1), // Indigo
      Color(0xFF3B82F6), // Blue
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkSecondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF059669), // Emerald
      Color(0xFF0891B2), // Cyan
      Color(0xFF0284C7), // Sky
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEF4444), // Red
      Color(0xFFF97316), // Orange
      Color(0xFFF59E0B), // Amber
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0F172A), // Slate 900
      Color(0xFF1E293B), // Slate 800
      Color(0xFF334155), // Slate 700
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1E293B), // Slate 800
      Color(0xFF334155), // Slate 700
      Color(0xFF475569), // Slate 600
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkSidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0F172A), // Dark slate
      Color(0xFF1E293B), // Medium slate
      Color(0xFF0F172A), // Dark slate
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkMessageBubbleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6366F1), // Indigo
      Color(0xFF8B5CF6), // Purple
    ],
    stops: [0.0, 1.0],
  );

  static const darkMessageBubbleOtherGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF374151), // Gray 700
      Color(0xFF4B5563), // Gray 600
    ],
    stops: [0.0, 1.0],
  );

  // Animated shimmer gradient for loading states
  static const shimmerGradient = LinearGradient(
    begin: Alignment(-1.0, -0.3),
    end: Alignment(1.0, 0.3),
    colors: [
      Color(0x00FFFFFF),
      Color(0x33FFFFFF),
      Color(0x00FFFFFF),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // Button gradients
  static const primaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6366F1), // Indigo
      Color(0xFF8B5CF6), // Purple
    ],
  );

  static const secondaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF10B981), // Emerald
      Color(0xFF059669), // Emerald dark
    ],
  );

  static const dangerButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEF4444), // Red
      Color(0xFFDC2626), // Red dark
    ],
  );
}

// Extension to easily apply gradients to containers
extension GradientExtension on Container {
  Container withGradient(Gradient gradient) {
    final boxDecoration = decoration as BoxDecoration?;
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: boxDecoration?.borderRadius,
        border: boxDecoration?.border,
        boxShadow: boxDecoration?.boxShadow,
      ),
      child: child,
    );
  }
}

// Helper widgets for gradient backgrounds
class GradientContainer extends StatelessWidget {
  final Widget child;
  final Gradient gradient;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GradientContainer({
    super.key,
    required this.child,
    required this.gradient,
    this.borderRadius,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}

class AnimatedGradientContainer extends StatefulWidget {
  final Widget child;
  final List<Gradient> gradients;
  final Duration duration;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AnimatedGradientContainer({
    super.key,
    required this.child,
    required this.gradients,
    this.duration = const Duration(seconds: 3),
    this.borderRadius,
    this.padding,
    this.margin,
  });

  @override
  State<AnimatedGradientContainer> createState() => _AnimatedGradientContainerState();
}

class _AnimatedGradientContainerState extends State<AnimatedGradientContainer>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _currentGradientIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _currentGradientIndex = (_currentGradientIndex + 1) % widget.gradients.length;
        });
        _controller.reset();
        _controller.forward();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final currentGradient = widget.gradients[_currentGradientIndex] as LinearGradient;
        final nextGradient = widget.gradients[(_currentGradientIndex + 1) % widget.gradients.length] as LinearGradient;

        return Container(
          padding: widget.padding,
          margin: widget.margin,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: currentGradient.begin,
              end: currentGradient.end,
              colors: currentGradient.colors.asMap().entries.map((entry) {
                final index = entry.key;
                final currentColor = entry.value;
                final nextColor = nextGradient.colors[index % nextGradient.colors.length];
                return Color.lerp(currentColor, nextColor, _animation.value)!;
              }).toList(),
              stops: currentGradient.stops,
            ),
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        );
      },
    );
  }
}