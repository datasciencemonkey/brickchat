import 'package:flutter/material.dart';

abstract class AppGradients {
  // Light Mode Gradients - Professional & Elegant
  static const lightBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFFFF), // Pure white
      Color(0xFFFAFAFA), // Very light gray
      Color(0xFFF5F5F5), // Subtle gray
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const lightPrimaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF7355), // Bright coral
      Color(0xFFFF5F46), // Databricks orange-red
      Color(0xFFFF4B37), // Deep coral
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const lightSecondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6A8291), // Light muted blue
      Color(0xFF5a6f77), // Databricks muted gray-blue
      Color(0xFF4A5F67), // Deep muted blue
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const lightCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFFFF), // Pure white
      Color(0xFFFCFCFC), // Almost white
      Color(0xFFFAFAFA), // Very light gray
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const lightSidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFAFAFA), // Light gray
      Color(0xFFFFFFFF), // White
      Color(0xFFFAFAFA), // Light gray
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // Databricks Neon Theme Gradients - Orange primary, cyan accent
  static const darkPrimaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF7355), // Bright orange
      Color(0xFFFF5F46), // Databricks orange
      Color(0xFFE54B32), // Deep orange
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkSecondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF243B4D), // Light slate
      Color(0xFF1B2A3D), // Deep slate
      Color(0xFF12202D), // Darker slate
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF00E5FF), // Bright cyan
      Color(0xFF00D4FF), // Electric cyan
      Color(0xFF00B8E6), // Deep cyan
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0D1117), // Deep slate
      Color(0xFF161B22), // Lighter slate
      Color(0xFF0D1117), // Deep slate
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF161B22), // Slate card
      Color(0xFF1B2A3D), // Deep slate
      Color(0xFF21262D), // Lighter slate
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkSidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF010409), // Deepest black
      Color(0xFF0D1117), // Deep slate
      Color(0xFF010409), // Deepest black
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const darkMessageBubbleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF3D1810), // Deep orange base
      Color(0xFF4A1E14), // Lighter orange
    ],
    stops: [0.0, 1.0],
  );

  static const darkMessageBubbleOtherGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1B2A3D), // Deep slate
      Color(0xFF243B4D), // Lighter slate
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

  // Button gradients - Databricks Neon
  static const primaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF7355), // Bright orange
      Color(0xFFFF5F46), // Databricks orange
    ],
  );

  static const secondaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF00E5FF), // Bright cyan
      Color(0xFF00D4FF), // Electric cyan
    ],
  );

  static const dangerButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF4444), // Bright red
      Color(0xFFDC2626), // Deep red
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