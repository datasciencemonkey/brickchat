// lib/features/autonomous/presentation/widgets/autonomous_toggle.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/autonomous_provider.dart';
import '../../../../core/theme/app_colors.dart';

/// Autonomous mode toggle with infinity animation
class AutonomousToggle extends ConsumerStatefulWidget {
  const AutonomousToggle({super.key});

  @override
  ConsumerState<AutonomousToggle> createState() => _AutonomousToggleState();
}

/// Compact autonomous mode icon button for use inside TextField suffix
/// Uses dharma wheel (☸) icon with color change when enabled
class AutonomousIconButton extends ConsumerWidget {
  const AutonomousIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final isAvailable = ref.watch(autonomousModeAvailableProvider);
    final isEnabled = ref.watch(autonomousModeProvider);

    // Don't show if no agents are enabled
    if (!isAvailable) {
      return const SizedBox.shrink();
    }

    return IconButton(
      onPressed: () {
        ref.read(autonomousModeProvider.notifier).toggle();
      },
      tooltip: isEnabled ? 'Autonomous mode (on)' : 'Autonomous mode (off)',
      icon: Text(
        '\u2638', // Unicode dharma wheel ☸
        style: TextStyle(
          fontSize: 20,
          color: isEnabled
              ? theme.colorScheme.primary
              : appColors.mutedForeground,
        ),
      ),
    );
  }
}

class _AutonomousToggleState extends ConsumerState<AutonomousToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final isAvailable = ref.watch(autonomousModeAvailableProvider);
    final isEnabled = ref.watch(autonomousModeProvider);

    // Don't show if no agents are enabled
    if (!isAvailable) {
      return const SizedBox.shrink();
    }

    // Control animation based on state
    if (isEnabled && !_animationController.isAnimating) {
      _animationController.repeat();
    } else if (!isEnabled && _animationController.isAnimating) {
      _animationController.stop();
      _animationController.reset();
    }

    return GestureDetector(
      onTap: () {
        ref.read(autonomousModeProvider.notifier).toggle();

        // Show feedback
        if (!isEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Autonomous mode activated'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isEnabled
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : appColors.input.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEnabled
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : appColors.input.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Infinity symbol with animation
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: isEnabled ? _animationController.value * 0.5 : 0,
                  child: Text(
                    '\u221E', // Unicode infinity symbol
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isEnabled
                          ? theme.colorScheme.primary
                          : appColors.mutedForeground,
                    ),
                  ),
                )
                    .animate(target: isEnabled ? 1 : 0)
                    .scale(
                        begin: const Offset(1, 1), end: const Offset(1.1, 1.1))
                    .then()
                    .scale(
                        begin: const Offset(1.1, 1.1), end: const Offset(1, 1));
              },
            ),
            const SizedBox(width: 6),
            Text(
              'Autonomous',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isEnabled
                    ? theme.colorScheme.primary
                    : appColors.mutedForeground,
                fontWeight: isEnabled ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
