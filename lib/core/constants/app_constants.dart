import 'package:flutter/material.dart';

abstract class AppConstants {
  // App Information
  static const String appName = 'BrickChat';           // Light theme name
  static const String appNameDark = "BrickChat";          // Dark theme name
  static const String appCaption = 'Powered by Databricks AI';  // Light theme caption
  static const String appCaptionDark = 'Powered by Databricks AI'; // Dark theme caption
  static const String appVersion = '1.0.0';

  // App Description
  static const String appPurpose = 'Chat interface for Databricks agents';
  static const String appTarget = 'Agents running on Databricks platform';

  // Animation Durations
  static const Duration fastAnimation = Duration(milliseconds: 150);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration slowAnimation = Duration(milliseconds: 500);

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacing2xl = 48.0;
  static const double spacing3xl = 64.0;

  // Border Radius
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;

  // Breakpoints
  static const double mobileBreakpoint = 768;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1920;

  // Chat Constants
  static const int maxMessageLength = 2000;
  static const Duration typingIndicatorDelay = Duration(milliseconds: 500);
  static const Duration messageStatusUpdateDelay = Duration(seconds: 2);

  // File Upload
  static const int maxFileSizeMB = 10;
  static const List<String> supportedImageTypes = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
  ];

  static const List<String> supportedFileTypes = [
    'pdf',
    'doc',
    'docx',
    'txt',
    'md',
    'zip',
    'rar',
  ];

  // Theme Keys
  static const String themeKey = 'app_theme';
  static const String lightTheme = 'light';
  static const String darkTheme = 'dark';
  static const String systemTheme = 'system';

  // Message Types
  static const String messageTypeText = 'text';
  static const String messageTypeImage = 'image';
  static const String messageTypeFile = 'file';
  static const String messageTypeSystem = 'system';

  // User Status
  static const String statusOnline = 'online';
  static const String statusAway = 'away';
  static const String statusOffline = 'offline';

  // Error Messages
  static const String errorGeneric = 'Something went wrong. Please try again.';
  static const String errorNetwork = 'Network error. Please check your connection.';
  static const String errorFileSize = 'File size exceeds the maximum limit.';
  static const String errorFileType = 'File type not supported.';
  static const String errorMessageEmpty = 'Message cannot be empty.';
  static const String errorMessageTooLong = 'Message is too long.';

  // UI Dimensions
  static const double sidebarWidth = 280.0;
  static const double profileSectionHeight = 100.0;
  static const double avatarRadius = 16.0;
  static const double profileIconSize = 30.0;
  static const double actionButtonSize = 20.0;
  static const double buttonIconSize = 12.0;
  static const double snackBarIconSize = 14.0;
  static const double speechMicrophoneSize = 80.0;
  static const double speechMicrophoneIconSize = 36.0;
  static const double speechWaveExpansion = 40.0;
  static const double speechMinTextHeight = 72.0;
  static const double speechMaxTextHeight = 96.0;

  // Alpha Values
  static const double sidebarBackgroundAlpha = 0.7;
  static const double sidebarRingAlpha = 0.37;
  static const double sidebarPrimaryAlpha = 0.1;
  static const double sidebarPrimarySecondaryAlpha = 0.05;
  static const double sidebarShadowAlpha = 0.28;
  static const double surfaceAlpha = 0.95;
  static const double inputAlpha = 0.1;
  static const double accentAlpha = 0.85;
  static const double buttonActiveAlpha = 0.2;
  static const double buttonBorderAlpha = 0.3;
  static const double glowPrimaryAlpha = 0.8;
  static const double glowSecondaryAlpha = 0.6;
  static const double glowTertiaryAlpha = 0.7;
  static const double glowQuaternaryAlpha = 0.5;

  // Animation Durations
  static const Duration themeTransitionDuration = Duration(milliseconds: 300);
  static const Duration snackBarDuration = Duration(milliseconds: 1200);
  static const Duration snackBarShortDuration = Duration(milliseconds: 1000);
  static const Duration speechInitDelay = Duration(milliseconds: 300);
  static const Duration speechListenDuration = Duration(seconds: 120);
  static const Duration speechPauseDuration = Duration(seconds: 3);
  static const Duration speechPulseAnimation = Duration(milliseconds: 1000);
  static const Duration speechWaveAnimation = Duration(milliseconds: 2000);
  static const Duration speechGlowAnimation = Duration(milliseconds: 1500);
  static const Duration speechGlowSlowAnimation = Duration(milliseconds: 2500);
  static const Duration speechScaleAnimation = Duration(milliseconds: 200);
  static const Duration animatedTextSpeed = Duration(milliseconds: 100);
  static const Duration animatedTextSlowSpeed = Duration(milliseconds: 80);
  static const Duration animatedTextPause = Duration(milliseconds: 1500);
  static const Duration glowAnimationDuration = Duration(milliseconds: 2000);

  // Text Limits
  static const int messagePreviewLimit = 50;
  static const int maxRecentMessages = 10;
  static const int animatedTextRepeatCount = 1;

  // Sidebar Item Positioning
  static const double sidebarItemLeftPadding = 30.0;

  // Glow Effects
  static const double glowBorderSize = 2.0;
  static const double glowSizeFocused = 8.0;
  static const double glowSizeUnfocused = 4.0;
  static const double speechGlowSizeListening = 12.0;
  static const double speechGlowSizeIdle = 6.0;
  static const double speechWaveBorderWidth = 2.0;

  // Scale Factors
  static const double speechScaleBegin = 1.0;
  static const double speechScaleEnd = 1.05;
  static const double speechPulseScale = 0.1;
  static const double speechWaveAlphaFactor = 0.3;
  static const double snackBarWidthFactor = 0.25;

  // Padding and Margins
  static const EdgeInsets profilePadding = EdgeInsets.all(20.0);
  static const EdgeInsets sidebarMargin = EdgeInsets.all(10.0);
  static const EdgeInsets sidebarItemPadding = EdgeInsets.only(left: 30.0);
  static const EdgeInsets speechContainerPadding = EdgeInsets.all(16.0);
  static const EdgeInsets speechTextPadding = EdgeInsets.all(12.0);
  static const EdgeInsets buttonPadding = EdgeInsets.all(4.0);
  static const EdgeInsets textFieldPadding = EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0);
  static const EdgeInsets messageMarginBottom = EdgeInsets.only(bottom: 4.0);
  static const EdgeInsets timestampPadding = EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0);

  // Border Radius Values
  static const double sidebarRadius = 20.0;
  static const double sidebarItemRadius = 10.0;
  static const double speechRadius = 16.0;
  static const double speechTextRadius = 8.0;
  static const double snackBarRadius = 20.0;
  static const double buttonRadius = 4.0;
  static const double messageRadius = 8.0;

  // Font Sizes
  static const double profileNameFontSize = 16.0;
  static const double profileStatusFontSize = 12.0;
  static const double sidebarFontSize = 13.0;
  static const double timestampFontSize = 10.0;
  static const double snackBarFontSize = 12.0;
  static const double avatarFontSize = 12.0;

  // Stroke Widths
  static const double progressIndicatorStroke = 2.0;
  static const double borderWidth = 0.5;
  static const double buttonBorderWidth = 1.0;

  // Feedback Messages
  static const String feedbackThanks = 'Thanks';
  static const String feedbackNoted = 'Noted';
  static const String feedbackRemoved = 'Rating removed';
  static const String copyMessage = 'Copied!';
  static const String playingMessage = 'Playing...';

  // Time Display Thresholds
  static const int minutesThreshold = 0;
  static const int hoursThreshold = 0;
  static const int daysThreshold = 0;
}