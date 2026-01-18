import 'package:flutter/material.dart';
import 'border_beams.dart';

/// Animation style presets available for theming
enum AnimationStyle { cosmic, neon, minimal, professional, playful }

/// Current active style from theme_config.json
/// Update this when applying a new theme configuration
const AnimationStyle activeStyle = AnimationStyle.neon;

/// Provides animation effects based on the active style
class EffectsProvider {
  /// Wraps a widget with the appropriate background effect
  static Widget wrapWithBackground(Widget child) {
    switch (activeStyle) {
      case AnimationStyle.neon:
        return BorderBeamsBackground(child: child);
      case AnimationStyle.cosmic:
      case AnimationStyle.professional:
      case AnimationStyle.playful:
      case AnimationStyle.minimal:
        return child;
    }
  }

  /// Returns the appropriate loading indicator widget
  static Widget getLoadingIndicator({double size = 40.0}) {
    switch (activeStyle) {
      case AnimationStyle.neon:
        return WaveRippleLoader(size: size);
      case AnimationStyle.cosmic:
      case AnimationStyle.professional:
      case AnimationStyle.playful:
      case AnimationStyle.minimal:
        return SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
    }
  }

  /// Wraps a widget with interactive effects (e.g., particle burst on tap)
  static Widget wrapWithInteractive(Widget child, {VoidCallback? onTap}) {
    switch (activeStyle) {
      case AnimationStyle.neon:
      case AnimationStyle.playful:
        return CoolModeParticles(onTap: onTap, child: child);
      case AnimationStyle.cosmic:
      case AnimationStyle.professional:
      case AnimationStyle.minimal:
        return GestureDetector(onTap: onTap, child: child);
    }
  }

  /// Creates a border decoration based on active style
  static Widget wrapWithBorder(
    Widget child, {
    double borderRadius = 12.0,
    double glowSize = 4.0,
  }) {
    switch (activeStyle) {
      case AnimationStyle.neon:
        return BorderBeams(
          borderRadius: borderRadius,
          glowSize: glowSize,
          child: child,
        );
      case AnimationStyle.cosmic:
      case AnimationStyle.professional:
      case AnimationStyle.playful:
      case AnimationStyle.minimal:
        return child;
    }
  }
}

/// Extension for easy access to effects in widget build methods
extension EffectsExtension on BuildContext {
  /// Wrap with background effect
  Widget withBackgroundEffect(Widget child) {
    return EffectsProvider.wrapWithBackground(child);
  }

  /// Get loading indicator
  Widget get loadingIndicator => EffectsProvider.getLoadingIndicator();

  /// Wrap with interactive effect
  Widget withInteractiveEffect(Widget child, {VoidCallback? onTap}) {
    return EffectsProvider.wrapWithInteractive(child, onTap: onTap);
  }

  /// Wrap with border effect
  Widget withBorderEffect(Widget child, {double borderRadius = 12.0}) {
    return EffectsProvider.wrapWithBorder(child, borderRadius: borderRadius);
  }
}
