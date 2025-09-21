import 'package:flutter/material.dart';

abstract class AppColors {
  // Databricks Brand Colors for Light Mode
  static const _lightBackground = Color(0xFFFBFBFB);
  static const _lightForeground = Color(0xFF1b3139); // Databricks navy
  static const _lightCard = Color(0xFFFFFFFF);
  static const _lightCardForeground = Color(0xFF1b3139);
  static const _lightPopover = Color(0xFFFFFFFF);
  static const _lightPopoverForeground = Color(0xFF1b3139);
  static const _lightPrimary = Color(0xFFff5f46); // Databricks orange-red
  static const _lightPrimaryForeground = Color(0xFFFFFFFF);
  static const _lightSecondary = Color(0xFF5a6f77); // Databricks muted gray-blue
  static const _lightSecondaryForeground = Color(0xFF1b3139);
  static const _lightMuted = Color(0xFFdce0e2); // Databricks light gray
  static const _lightMutedForeground = Color(0xFF5a6f77);
  static const _lightAccent = Color(0xFFeb1600); // Databricks deep red
  static const _lightAccentForeground = Color(0xFFFFFFFF);
  static const _lightDestructive = Color(0xFFbd2b26); // Databricks darker red
  static const _lightDestructiveForeground = Color(0xFFFFFFFF);
  static const _lightBorder = Color(0xFFdce0e2);
  static const _lightInput = Color(0xFFdce0e2);
  static const _lightRing = Color(0xFFff5f46);

  static const _lightMessageBubble = Color(0xFFdce0e2);
  static const _lightMessageBubbleOwn = Color(0xFFff5f46);
  static const _lightMessageText = Color(0xFF1b3139);
  static const _lightMessageTextOwn = Color(0xFFFFFFFF);
  static const _lightTypingIndicator = Color(0xFF5a6f77);
  static const _lightOnlineStatus = Color(0xFF10B981);
  static const _lightAwayStatus = Color(0xFFff5f46);
  static const _lightOfflineStatus = Color(0xFF5a6f77);

  static const _lightSidebar = Color(0xFFFBFBFB);
  static const _lightSidebarForeground = Color(0xFF1b3139);
  static const _lightSidebarPrimary = Color(0xFFff5f46);
  static const _lightSidebarPrimaryForeground = Color(0xFFFFFFFF);
  static const _lightSidebarAccent = Color(0xFFdce0e2);
  static const _lightSidebarAccentForeground = Color(0xFF1b3139);
  static const _lightSidebarBorder = Color(0xFFdce0e2);
  static const _lightSidebarRing = Color(0xFFff5f46);

  // Enhanced Dark Theme with Gradient-Ready Colors
  static const _darkBackground = Color(0xFF0F172A); // Darker for better gradient contrast
  static const _darkForeground = Color(0xFFF8FAFC);
  static const _darkCard = Color(0xFF1E293B); // Slightly lighter for gradient layering
  static const _darkCardForeground = Color(0xFFF1F5F9);
  static const _darkPopover = Color(0xFF1E293B);
  static const _darkPopoverForeground = Color(0xFFF8FAFC);
  static const _darkPrimary = Color(0xFF6366F1); // Vibrant for gradients
  static const _darkPrimaryForeground = Color(0xFFFFFFFF);
  static const _darkSecondary = Color(0xFF10B981); // Emerald for gradients
  static const _darkSecondaryForeground = Color(0xFFFFFFFF);
  static const _darkMuted = Color(0xFF374151);
  static const _darkMutedForeground = Color(0xFFCBD5E1);
  static const _darkAccent = Color(0xFFF59E0B); // Amber for gradients
  static const _darkAccentForeground = Color(0xFF171717);
  static const _darkDestructive = Color(0xFFEF4444); // Red for gradients
  static const _darkDestructiveForeground = Color(0xFFFFFFFF);
  static const _darkBorder = Color(0xFF374151);
  static const _darkInput = Color(0xFF374151);
  static const _darkRing = Color(0xFF8B5CF6); // Purple for gradients

  static const _darkMessageBubble = Color(0xFF374151); // Base for gradient overlay
  static const _darkMessageBubbleOwn = Color(0xFF6366F1); // Primary for gradient
  static const _darkMessageText = Color(0xFFF1F5F9);
  static const _darkMessageTextOwn = Color(0xFFFFFFFF);
  static const _darkTypingIndicator = Color(0xFF94A3B8);
  static const _darkOnlineStatus = Color(0xFF10B981);
  static const _darkAwayStatus = Color(0xFFF59E0B);
  static const _darkOfflineStatus = Color(0xFF6B7280);

  static const _darkSidebar = Color(0xFF171717);
  static const _darkSidebarForeground = Color(0xFFF8FAFC);
  static const _darkSidebarPrimary = Color(0xFFF1F5F9);
  static const _darkSidebarPrimaryForeground = Color(0xFF171717);
  static const _darkSidebarAccent = Color(0xFF334155);
  static const _darkSidebarAccentForeground = Color(0xFFF1F5F9);
  static const _darkSidebarBorder = Color(0xFF334155);
  static const _darkSidebarRing = Color(0xFF818CF8);

  static const List<Color> _lightChartColors = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFFBBF24),
    Color(0xFFEF4444),
    Color(0xFFA855F7),
  ];

  static const List<Color> _darkChartColors = [
    Color(0xFF818CF8),
    Color(0xFF34D399),
    Color(0xFFFCD34D),
    Color(0xFFF87171),
    Color(0xFFC084FC),
  ];

  static ColorScheme get lightColorScheme => const ColorScheme.light(
        brightness: Brightness.light,
        primary: _lightPrimary,
        onPrimary: _lightPrimaryForeground,
        secondary: _lightSecondary,
        onSecondary: _lightSecondaryForeground,
        error: _lightDestructive,
        onError: _lightDestructiveForeground,
        surface: _lightCard,
        onSurface: _lightCardForeground,
        surfaceContainerLowest: _lightBackground,
        outline: _lightBorder,
        shadow: Color(0x1A000000),
      );

  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: _darkPrimary,
        onPrimary: _darkPrimaryForeground,
        secondary: _darkSecondary,
        onSecondary: _darkSecondaryForeground,
        error: _darkDestructive,
        onError: _darkDestructiveForeground,
        surface: _darkCard,
        onSurface: _darkCardForeground,
        surfaceContainerLowest: _darkBackground,
        outline: _darkBorder,
        shadow: Color(0x33000000),
      );

  static AppColorsExtension get lightExtension => const AppColorsExtension(
        accent: _lightAccent,
        accentForeground: _lightAccentForeground,
        muted: _lightMuted,
        mutedForeground: _lightMutedForeground,
        popover: _lightPopover,
        popoverForeground: _lightPopoverForeground,
        input: _lightInput,
        ring: _lightRing,
        messageBubble: _lightMessageBubble,
        messageBubbleOwn: _lightMessageBubbleOwn,
        messageText: _lightMessageText,
        messageTextOwn: _lightMessageTextOwn,
        typingIndicator: _lightTypingIndicator,
        onlineStatus: _lightOnlineStatus,
        awayStatus: _lightAwayStatus,
        offlineStatus: _lightOfflineStatus,
        sidebar: _lightSidebar,
        sidebarForeground: _lightSidebarForeground,
        sidebarPrimary: _lightSidebarPrimary,
        sidebarPrimaryForeground: _lightSidebarPrimaryForeground,
        sidebarAccent: _lightSidebarAccent,
        sidebarAccentForeground: _lightSidebarAccentForeground,
        sidebarBorder: _lightSidebarBorder,
        sidebarRing: _lightSidebarRing,
        chartColors: _lightChartColors,
      );

  static AppColorsExtension get darkExtension => const AppColorsExtension(
        accent: _darkAccent,
        accentForeground: _darkAccentForeground,
        muted: _darkMuted,
        mutedForeground: _darkMutedForeground,
        popover: _darkPopover,
        popoverForeground: _darkPopoverForeground,
        input: _darkInput,
        ring: _darkRing,
        messageBubble: _darkMessageBubble,
        messageBubbleOwn: _darkMessageBubbleOwn,
        messageText: _darkMessageText,
        messageTextOwn: _darkMessageTextOwn,
        typingIndicator: _darkTypingIndicator,
        onlineStatus: _darkOnlineStatus,
        awayStatus: _darkAwayStatus,
        offlineStatus: _darkOfflineStatus,
        sidebar: _darkSidebar,
        sidebarForeground: _darkSidebarForeground,
        sidebarPrimary: _darkSidebarPrimary,
        sidebarPrimaryForeground: _darkSidebarPrimaryForeground,
        sidebarAccent: _darkSidebarAccent,
        sidebarAccentForeground: _darkSidebarAccentForeground,
        sidebarBorder: _darkSidebarBorder,
        sidebarRing: _darkSidebarRing,
        chartColors: _darkChartColors,
      );
}

@immutable
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  const AppColorsExtension({
    required this.accent,
    required this.accentForeground,
    required this.muted,
    required this.mutedForeground,
    required this.popover,
    required this.popoverForeground,
    required this.input,
    required this.ring,
    required this.messageBubble,
    required this.messageBubbleOwn,
    required this.messageText,
    required this.messageTextOwn,
    required this.typingIndicator,
    required this.onlineStatus,
    required this.awayStatus,
    required this.offlineStatus,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
    required this.sidebarBorder,
    required this.sidebarRing,
    required this.chartColors,
  });

  final Color accent;
  final Color accentForeground;
  final Color muted;
  final Color mutedForeground;
  final Color popover;
  final Color popoverForeground;
  final Color input;
  final Color ring;
  final Color messageBubble;
  final Color messageBubbleOwn;
  final Color messageText;
  final Color messageTextOwn;
  final Color typingIndicator;
  final Color onlineStatus;
  final Color awayStatus;
  final Color offlineStatus;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarPrimary;
  final Color sidebarPrimaryForeground;
  final Color sidebarAccent;
  final Color sidebarAccentForeground;
  final Color sidebarBorder;
  final Color sidebarRing;
  final List<Color> chartColors;

  @override
  AppColorsExtension copyWith({
    Color? accent,
    Color? accentForeground,
    Color? muted,
    Color? mutedForeground,
    Color? popover,
    Color? popoverForeground,
    Color? input,
    Color? ring,
    Color? messageBubble,
    Color? messageBubbleOwn,
    Color? messageText,
    Color? messageTextOwn,
    Color? typingIndicator,
    Color? onlineStatus,
    Color? awayStatus,
    Color? offlineStatus,
    Color? sidebar,
    Color? sidebarForeground,
    Color? sidebarPrimary,
    Color? sidebarPrimaryForeground,
    Color? sidebarAccent,
    Color? sidebarAccentForeground,
    Color? sidebarBorder,
    Color? sidebarRing,
    List<Color>? chartColors,
  }) {
    return AppColorsExtension(
      accent: accent ?? this.accent,
      accentForeground: accentForeground ?? this.accentForeground,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      popover: popover ?? this.popover,
      popoverForeground: popoverForeground ?? this.popoverForeground,
      input: input ?? this.input,
      ring: ring ?? this.ring,
      messageBubble: messageBubble ?? this.messageBubble,
      messageBubbleOwn: messageBubbleOwn ?? this.messageBubbleOwn,
      messageText: messageText ?? this.messageText,
      messageTextOwn: messageTextOwn ?? this.messageTextOwn,
      typingIndicator: typingIndicator ?? this.typingIndicator,
      onlineStatus: onlineStatus ?? this.onlineStatus,
      awayStatus: awayStatus ?? this.awayStatus,
      offlineStatus: offlineStatus ?? this.offlineStatus,
      sidebar: sidebar ?? this.sidebar,
      sidebarForeground: sidebarForeground ?? this.sidebarForeground,
      sidebarPrimary: sidebarPrimary ?? this.sidebarPrimary,
      sidebarPrimaryForeground: sidebarPrimaryForeground ?? this.sidebarPrimaryForeground,
      sidebarAccent: sidebarAccent ?? this.sidebarAccent,
      sidebarAccentForeground: sidebarAccentForeground ?? this.sidebarAccentForeground,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      sidebarRing: sidebarRing ?? this.sidebarRing,
      chartColors: chartColors ?? this.chartColors,
    );
  }

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) {
      return this;
    }
    return AppColorsExtension(
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(accentForeground, other.accentForeground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      popover: Color.lerp(popover, other.popover, t)!,
      popoverForeground: Color.lerp(popoverForeground, other.popoverForeground, t)!,
      input: Color.lerp(input, other.input, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
      messageBubble: Color.lerp(messageBubble, other.messageBubble, t)!,
      messageBubbleOwn: Color.lerp(messageBubbleOwn, other.messageBubbleOwn, t)!,
      messageText: Color.lerp(messageText, other.messageText, t)!,
      messageTextOwn: Color.lerp(messageTextOwn, other.messageTextOwn, t)!,
      typingIndicator: Color.lerp(typingIndicator, other.typingIndicator, t)!,
      onlineStatus: Color.lerp(onlineStatus, other.onlineStatus, t)!,
      awayStatus: Color.lerp(awayStatus, other.awayStatus, t)!,
      offlineStatus: Color.lerp(offlineStatus, other.offlineStatus, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarForeground: Color.lerp(sidebarForeground, other.sidebarForeground, t)!,
      sidebarPrimary: Color.lerp(sidebarPrimary, other.sidebarPrimary, t)!,
      sidebarPrimaryForeground: Color.lerp(sidebarPrimaryForeground, other.sidebarPrimaryForeground, t)!,
      sidebarAccent: Color.lerp(sidebarAccent, other.sidebarAccent, t)!,
      sidebarAccentForeground: Color.lerp(sidebarAccentForeground, other.sidebarAccentForeground, t)!,
      sidebarBorder: Color.lerp(sidebarBorder, other.sidebarBorder, t)!,
      sidebarRing: Color.lerp(sidebarRing, other.sidebarRing, t)!,
      chartColors: chartColors,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColorsExtension get appColors => Theme.of(this).extension<AppColorsExtension>()!;
}