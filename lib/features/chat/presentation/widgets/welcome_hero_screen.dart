import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_provider.dart';

class WelcomeHeroScreen extends ConsumerWidget {
  final VoidCallback onGetStarted;

  const WelcomeHeroScreen({
    super.key,
    required this.onGetStarted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.isDarkMode;
    final appColors = context.appColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hero logo/name animation
          Hero(
            tag: 'app_logo',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                isDark ? AppColors.darkLogo : AppColors.lightLogo,
                height: 120,
                fit: BoxFit.contain,
              ),
            )
                .animate()
                .fadeIn(duration: 800.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1.0, 1.0),
                  duration: 800.ms,
                  curve: Curves.easeOutBack,
                ),
          ),

          const SizedBox(height: AppConstants.spacingXl),

          // App name with animation
          Text(
            isDark ? AppConstants.appNameDark : AppConstants.appName,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: appColors.sidebarPrimary,
            ),
          )
              .animate()
              .fadeIn(delay: 400.ms, duration: 600.ms)
              .slideY(
                begin: 0.3,
                end: 0,
                duration: 600.ms,
                curve: Curves.easeOut,
              ),

          const SizedBox(height: AppConstants.spacingSm),

          // App caption with animation
          Text(
            isDark ? AppConstants.appCaptionDark : AppConstants.appCaption,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: appColors.mutedForeground,
            ),
          )
              .animate()
              .fadeIn(delay: 600.ms, duration: 600.ms)
              .slideY(
                begin: 0.3,
                end: 0,
                duration: 600.ms,
                curve: Curves.easeOut,
              ),

          const SizedBox(height: AppConstants.spacing3xl),

          // Inviting chat box with animation
          Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingXl,
            ),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(AppConstants.radiusXl),
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  gradient: isDark
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            appColors.messageBubble.withValues(alpha: 0.95),
                            appColors.messageBubble.withValues(alpha: 0.85),
                          ],
                        )
                      : null,
                  color: isDark ? null : appColors.popover,
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  border: Border.all(
                    color: appColors.accent.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: appColors.accent.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spacingXl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: appColors.accent,
                      ),
                      const SizedBox(height: AppConstants.spacingLg),
                      Text(
                        'Start a Conversation',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: appColors.messageText,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingMd),
                      Text(
                        'Ask me anything and let\'s explore together',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: appColors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingXl),
                      ElevatedButton(
                        onPressed: onGetStarted,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.accent,
                          foregroundColor: appColors.accentForeground,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.spacing2xl,
                            vertical: AppConstants.spacingMd,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                          ),
                          elevation: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Get Started',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: appColors.accentForeground,
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacingSm),
                            Icon(
                              Icons.arrow_forward,
                              color: appColors.accentForeground,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 800.ms, duration: 800.ms)
                .scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1.0, 1.0),
                  delay: 800.ms,
                  duration: 800.ms,
                  curve: Curves.easeOutBack,
                )
                .shimmer(
                  delay: 1600.ms,
                  duration: 2000.ms,
                  color: appColors.accent.withValues(alpha: 0.3),
                ),
          ),
        ],
      ),
    );
  }
}
