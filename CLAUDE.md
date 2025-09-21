# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter chat application called "brickchat" designed for web and desktop platforms. The project implements Clean Architecture with feature-based modules and uses the flutter_chat_ui package for a minimalistic, professional, and futuristic design aesthetic.

## Common Commands

### Development
- `flutter run -d chrome` - Run on web browser (Chrome)
- `flutter run -d windows` - Run on Windows desktop
- `flutter run -d macos` - Run on macOS desktop
- `flutter run -d linux` - Run on Linux desktop
- `flutter hot-reload` - Hot reload during development (press 'r' in terminal)
- `flutter hot-restart` - Hot restart (press 'R' in terminal)

### Build
- `flutter build web` - Build for web deployment
- `flutter build windows` - Build Windows desktop app
- `flutter build macos` - Build macOS desktop app
- `flutter build linux` - Build Linux desktop app

### Dependencies and Analysis
- `flutter pub get` - Install dependencies
- `flutter pub upgrade` - Upgrade dependencies
- `flutter analyze` - Run static analysis
- `flutter doctor` - Check Flutter installation and dependencies
- `dart run build_runner build` - Generate code for Riverpod providers and JSON serialization

### Testing
- `flutter test` - Run all tests
- `flutter test test/widget_test.dart` - Run specific test file

## Architecture and Design

### Current Implementation
The project follows Clean Architecture with implemented:

```
lib/
├── core/                           # Core functionality
│   ├── constants/app_constants.dart # App constants and configuration
│   ├── theme/                      # Complete theme system
│   │   ├── app_theme.dart         # Main theme configuration
│   │   ├── theme_provider.dart    # Riverpod theme state management
│   │   ├── app_colors.dart        # Color scheme definitions
│   │   ├── app_typography.dart    # Typography system
│   │   └── gradients.dart         # Gradient definitions
│   └── utils/responsive.dart       # Responsive design utilities
├── features/                       # Feature-based modules
│   └── chat/                       # Chat functionality
│       └── presentation/
│           └── chat_home_page.dart # Main chat interface
├── shared/                         # Shared components
│   ├── widgets/                    # Reusable UI components
│   │   ├── theme_toggle.dart      # Theme switching widget
│   │   └── responsive_layout.dart # Responsive layout wrapper
│   └── models/user.dart           # Shared data models
└── main.dart                      # App entry point with Riverpod setup
```

### State Management Strategy
- **Primary**: Riverpod for dependency injection and state management (implemented)
- **Theme Management**: StateNotifierProvider with SharedPreferences persistence
- **Service Locator**: GetIt configured for dependency injection
- **Repository Pattern**: Planned for data sources

### Key Dependencies (Implemented)
- `flutter_chat_core: ^2.0.7` - Core chat functionality
- `flutter_chat_ui: ^2.0.7` - Chat UI components
- `flutter_riverpod: ^2.4.9` - State management
- `riverpod_annotation: ^2.3.3` - Code generation for providers
- `get_it: ^7.6.4` - Service locator/dependency injection
- `shared_preferences: ^2.2.2` - Local data persistence
- `sidebarx: ^0.17.1` - Sidebar navigation component
- `google_fonts: ^6.1.0` - Typography system
- `flutter_animate: ^4.3.0` - Animation framework

## Design System

### Theme Architecture (Implemented)
- **Dual Theme Support**: Light and dark themes with system integration
- **Theme Persistence**: SharedPreferences with automatic loading
- **Custom Color Extensions**: Professional blue-based color scheme with extensions
- **Typography**: Inter font family with consistent scale
- **Material 3**: Full Material 3 design system implementation

### Theme Provider Usage
```dart
// Access theme state
final themeMode = ref.watch(themeProvider);
final isDark = ref.watch(isDarkModeProvider);

// Theme actions
ref.read(themeProvider.notifier).toggleTheme();
ref.read(themeProvider.notifier).setThemeMode(AppThemeMode.dark);

// Extension methods
ref.themeNotifier.toggleTheme();
bool isDark = ref.isDarkMode;
```

### Platform Support
- **Target Platforms**: Web (modern browsers), Desktop (Windows/macOS/Linux)
- **Web Rendering**: CanvasKit for optimal performance
- **Responsive Design**: Breakpoint-based layouts with responsive utilities

## Development Guidelines

### Code Organization
- Follow feature-based organization over file-type grouping
- Use Riverpod providers for state management
- Implement proper theme integration using extension methods
- Use responsive utilities for layout adaptation

### Theme Development
- All UI components inherit from centralized theme system
- Use AppColors extensions for consistent color usage
- Implement custom theme-aware widgets using Consumer/ConsumerWidget
- Theme switching includes smooth 300ms transitions

### Performance Considerations
- Theme state is cached and persisted automatically
- Responsive breakpoints optimize layouts per device
- Virtual scrolling planned for chat message lists
- Proper disposal of providers and controllers

## Testing Strategy

### Current Test Structure
- `test/widget_test.dart` - Basic app smoke test with Riverpod integration
- Tests verify app initialization and basic UI rendering
- Theme switching and provider state testing needed

### Testing Focus Areas
- Theme persistence and state management
- Riverpod provider behavior
- Responsive layout across breakpoints
- Cross-platform functionality

## Project Configuration

### Flutter Configuration
- **Flutter Version**: 3.8.1+ (specified in pubspec.yaml)
- **Dart Version**: 3.8.1+
- **Platforms**: Web, Windows, macOS, Linux, iOS, Android
- **Analysis**: flutter_lints ^5.0.0 for code quality
- **Code Generation**: build_runner for Riverpod and JSON serialization

### State Management Setup
The app uses ProviderScope at the root level with:
- ThemeNotifier for theme state management
- Automatic theme persistence and loading
- System theme detection and following
- Extension methods for convenient access

## Implementation Status

### Completed Features
- ✅ Complete theme system (light/dark/system)
- ✅ Riverpod state management setup
- ✅ Material 3 design system
- ✅ Theme persistence with SharedPreferences
- ✅ Responsive design utilities
- ✅ Basic chat home page structure
- ✅ Typography and color system

### Planned Features
- 🔲 Full chat functionality implementation
- 🔲 User authentication system
- 🔲 Message persistence and synchronization
- 🔲 File attachment support
- 🔲 Real-time messaging integration

## Important Notes

- This project is actively implementing chat functionality beyond the template stage
- The frontend_specifications.md contains comprehensive design requirements
- Always use the existing theme system for new UI components
- Follow the established Riverpod patterns for state management
- Maintain responsive design principles for all new features