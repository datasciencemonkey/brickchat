abstract class AppConstants {
  // App Information
  static const String appName = 'BrickChat';
  static const String appVersion = '1.0.0';

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
}