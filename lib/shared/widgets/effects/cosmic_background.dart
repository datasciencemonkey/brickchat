import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/gradients.dart';
import '../particles_widget.dart';

/// Cosmic background effect widget for the "cosmic" animation style.
/// Creates an animated starfield using ParticlesWidget with theme-aware colors.
class CosmicBackground extends StatelessWidget {
  const CosmicBackground({
    super.key,
    required this.child,
    this.starQuantity = 120,
    this.starSize = 2.5,
  });

  final Widget child;
  final int starQuantity;
  final double starSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;

    // Use theme-aware star color
    // In dark mode: use muted foreground for subtle starlight effect
    // In light mode: no stars displayed
    final starColor = isDark
        ? appColors.mutedForeground.withValues(alpha: 0.9)
        : appColors.mutedForeground;

    return GradientContainer(
      gradient: isDark
          ? AppGradients.darkBackgroundGradient
          : AppGradients.lightBackgroundGradient,
      child: Stack(
        children: [
          // Starfield effect (only in dark mode)
          if (isDark)
            Positioned.fill(
              child: ParticlesWidget(
                quantity: starQuantity,
                ease: 80,
                color: starColor,
                staticity: 50,
                size: starSize,
              ),
            ),
          // Content on top
          child,
        ],
      ),
    );
  }
}
