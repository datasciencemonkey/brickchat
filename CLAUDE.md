# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**BrickChat** is a Flutter web/desktop chat application with a Python FastAPI backend that connects to Databricks serving endpoints. The project implements Clean Architecture with feature-based modules and uses the flutter_chat_ui package for a minimalistic, professional, and futuristic design aesthetic.

### Backend Architecture & API Integration

#### Databricks Configuration
The backend connects to Databricks serving endpoints using OpenAI-compatible API format:
- **API Pattern**: OpenAI chat completions with streaming support
- **Model**: ``
- **Base URL**: ``
- **Authentication**: Personal access token via environment variables

#### Backend Server Details
- **Framework**: Python FastAPI
- **Port**: 8000
- **Health Check**: `GET /health`
- **Chat Endpoint**: `POST /api/chat/send` (streaming SSE response)
- **Auth Endpoint**: `GET /api/auth/me` (debug endpoint for user identity)
- **Static Files**: Serves Flutter WASM build from `../build/web`
- **CORS**: Enabled for development

#### On-Behalf-Of Authentication (Databricks Apps)
When deployed to Databricks Apps, user authentication is handled automatically via forwarded headers:
- **X-Forwarded-Email**: User's email address
- **X-Forwarded-Preferred-Username**: Username
- **X-Forwarded-User**: User identifier
- **X-Real-Ip**: User's IP address
- **X-Forwarded-Access-Token**: User's access token for downstream API calls

The `auth.py` module provides:
- `UserContext` class: Encapsulates user identity (user_id, email, username)
- `get_current_user()` dependency: Extracts user context from headers, falls back to `dev_user` for local development

**IMPORTANT: User token is for identification only, not for API calls.**
The user's forwarded access token should NOT be used for Databricks API calls. All API calls (model inference, etc.) use the app's `DATABRICKS_TOKEN`. The user context is only for:
- Identifying who is making the request (for logging, thread ownership, etc.)
- Storing user-specific data (chat threads, preferences)

**Usage in routers:**
```python
from auth import get_current_user, UserContext

@router.post("/endpoint")
async def my_endpoint(user: UserContext = Depends(get_current_user)):
    # Access user identity for logging/tracking
    print(f"User: {user.user_id}, Email: {user.email}")

    # Use DATABRICKS_TOKEN (app's service principal) for all API calls
    client = OpenAI(api_key=DATABRICKS_TOKEN, base_url=DATABRICKS_BASE_URL)
```

#### Critical Implementation Pattern
The chat endpoint uses the **Responses API** (not `chat.completions`), which supports agent-style interactions with citations/annotations:

```python
from openai import OpenAI

# Client initialization for Databricks
client = OpenAI(
    api_key=DATABRICKS_TOKEN,
    base_url=DATABRICKS_BASE_URL
)

# Responses API call (for agent endpoints with citations)
response = client.responses.create(
    model=DATABRICKS_MODEL,
    input=input_array,  # List of {"role": "user/assistant", "content": "..."}
    stream=True
)
```

**Note:** The TTS router uses `chat.completions.create()` for simple text generation, but the main chat endpoint uses `responses.create()` for richer output including annotations and citations.

## Common Commands

### Development

#### Full Stack Development
1. **Backend**: `uv run python app.py` (runs on port 8000)
2. **Frontend Build**: `flutter build web --wasm`
3. **Access**: `http://localhost:8000` (backend serves Flutter app)

#### Flutter Development (when developing UI only)
- `flutter run -d chrome` - Run on web browser (Chrome)
- `flutter run -d windows` - Run on Windows desktop
- `flutter run -d macos` - Run on macOS desktop
- `flutter run -d linux` - Run on Linux desktop
- `flutter hot-reload` - Hot reload during development (press 'r' in terminal)
- `flutter hot-restart` - Hot restart (press 'R' in terminal)

### Build
- `flutter build web --wasm` - Build for web deployment (WASM compatible)
- `flutter build windows` - Build Windows desktop app
- `flutter build macos` - Build macOS desktop app
- `flutter build linux` - Build Linux desktop app

#### WASM Build Requirements
- **Critical**: Uses `dart:js_interop` instead of `dart:html`
- **File Handling**: Uses `file_selector` instead of `file_picker` for WASM compatibility
- **Clipboard Access**: Custom JS interop implementation
- **Serving**: Backend serves Flutter app at root `/` on port 8000

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
│   ├── services/                   # Backend communication services
│   │   └── fastapi_service.dart   # Databricks API integration
│   ├── theme/                      # Complete theme system
│   │   ├── app_theme.dart         # Main theme configuration
│   │   ├── theme_provider.dart    # Riverpod theme state management
│   │   ├── app_colors.dart        # Color scheme definitions
│   │   ├── app_typography.dart    # Typography system
│   │   └── gradients.dart         # Gradient definitions
│   └── utils/responsive.dart       # Responsive design utilities
├── features/                       # Feature-based modules
│   ├── chat/                       # Chat functionality
│   │   └── presentation/
│   │       └── chat_home_page.dart # Main chat interface with streaming
│   └── settings/                   # Settings functionality
│       ├── presentation/
│       │   └── settings_page.dart  # Settings interface
│       └── providers/
│           └── settings_provider.dart # Stream toggle settings
├── shared/                         # Shared components
│   ├── widgets/                    # Reusable UI components
│   │   ├── theme_toggle.dart      # Theme switching widget
│   │   ├── responsive_layout.dart # Responsive layout wrapper
│   │   └── speech_to_text_widget.dart # Voice input with animations
│   └── models/user.dart           # Shared data models
└── main.dart                      # App entry point with Riverpod setup
```

### State Management Strategy
- **Primary**: Riverpod for dependency injection and state management (implemented)
- **Theme Management**: StateNotifierProvider with SharedPreferences persistence
- **Settings Management**: StreamResultsNotifier for user preferences
- **Service Locator**: GetIt configured for dependency injection
- **Repository Pattern**: Planned for data sources

### Key Dependencies (Implemented)

#### Core Chat & State Management
- `flutter_chat_core: ^2.0.7` - Core chat functionality
- `flutter_chat_ui: ^2.0.7` - Chat UI components
- `flutter_riverpod: ^2.4.9` - State management
- `riverpod_annotation: ^2.3.3` - Code generation for providers
- `get_it: ^7.6.4` - Service locator/dependency injection
- `shared_preferences: ^2.2.2` - Local data persistence

#### UI & Effects
- `sidebarx: ^0.17.1` - Sidebar navigation component
- `google_fonts: ^6.1.0` - Typography system (DM Sans)
- `flutter_animate: ^4.3.0` - Animation framework
- `animated_text_kit: ^4.2.2` - Text animations for typing indicators
- `loading_animation_widget: ^1.2.1` - Loading animations
- `glowy_borders: ^1.0.2` - Animated gradient borders
- `cached_network_image: ^3.3.0` - Image handling

#### WASM Compatible Dependencies
- `file_selector: ^1.0.3` - File handling (WASM compatible, NOT file_picker)
- `http: ^1.1.2` - HTTP client for API communication
- `speech_to_text: ^7.0.0` - Voice input functionality
- `permission_handler: ^11.1.0` - Permissions management

#### Backend Communication
- **FastAPI Service**: Custom service layer for Databricks API integration
- **Streaming Support**: Server-Sent Events (SSE) for real-time chat responses
- **OpenAI Format**: Uses OpenAI-compatible API calls to Databricks endpoints

## Design System

### Theme Architecture (Implemented)
- **Dual Theme Support**: Light and dark themes with system integration
- **Theme Persistence**: SharedPreferences with automatic loading
- **Custom Color Extensions**: Professional Databricks-inspired color scheme
  - Light: Cream/beige background (`#F9F7F5`) with Databricks orange-red accents
  - Dark: Enhanced gradient-ready colors with vibrant accent support
- **Typography**: DM Sans font family with consistent scale (changed from Inter)
- **Material 3**: Full Material 3 design system implementation
- **Theme-Aware Assets**: Logo switching between light/dark modes
- **Transition Effects**: Smooth 300ms theme transitions

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
- **Primary Target**: Web (modern browsers with WASM support)
- **Secondary Targets**: Desktop (Windows/macOS/Linux)
- **Web Rendering**: WASM build with `dart:js_interop` for modern performance
- **Responsive Design**: Breakpoint-based layouts with responsive utilities
- **Backend Integration**: FastAPI server serves Flutter app at `http://localhost:8000`
- **Browser Requirements**: Modern browsers supporting WASM and microphone permissions

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

#### Backend Testing
- **Health Check**: `curl http://localhost:8000/health`
- **Chat API**: Test streaming endpoints with proper conversation history
- **Integration Testing**: Full stack testing via `http://localhost:8000`

### Testing Focus Areas
- Theme persistence and state management
- Riverpod provider behavior
- Responsive layout across breakpoints
- Cross-platform functionality

## Project Configuration

### Flutter Configuration
- **Flutter Version**: 3.8.1+ (specified in pubspec.yaml)
- **Dart Version**: 3.8.1+
- **Primary Platforms**: Web (WASM), Desktop (Windows/macOS/Linux)
- **Analysis**: flutter_lints ^5.0.0 for code quality
- **Code Generation**: build_runner for Riverpod and JSON serialization

### Backend Configuration
- **Python**: FastAPI with uvicorn server
- **Dependencies**: Managed via `uv` (as per user preferences)
- **Environment**: `.env` file for sensitive configuration
- **API Format**: OpenAI-compatible endpoints for Databricks integration
- **Streaming**: Server-Sent Events (SSE) for real-time responses
- **Authentication**: `databricks-sdk` for on-behalf-of user context and workspace client

### State Management Setup
The app uses ProviderScope at the root level with:
- ThemeNotifier for theme state management
- StreamResultsNotifier for user preference management
- Automatic theme persistence and loading
- System theme detection and following
- Extension methods for convenient access

## Implementation Status

### Completed Features
- ✅ Complete theme system (light/dark/system) with Databricks branding
- ✅ Riverpod state management setup
- ✅ Material 3 design system
- ✅ Theme persistence with SharedPreferences
- ✅ Responsive design utilities
- ✅ Full chat functionality with Databricks backend integration
- ✅ Typography and color system (DM Sans)
- ✅ WASM-compatible build system
- ✅ FastAPI backend with streaming support
- ✅ Speech-to-text functionality with animated UI
- ✅ Theme-aware logo system
- ✅ Multi-stage typing indicators with animations
- ✅ Settings page with stream toggle
- ✅ File selector integration (WASM compatible)
- ✅ Real-time conversation state management
- ✅ On-behalf-of authentication for Databricks Apps (web deployment)

### Planned Features
- 🔲 Message persistence and synchronization
- 🔲 Enhanced file attachment support
- 🔲 Multi-user chat rooms
- 🔲 Message search functionality
- 🔲 Export conversation history
- 🔲 Production deployment configuration

## Project Skills

Skills are Claude Code workflows that automate common tasks. Located in `skills/`.

### Available Skills

#### `/brand-theme` - Brand Theme Configuration
Guides deployment teams through Q&A to configure app branding without code changes.

**Collects:**
- Logo file paths (light/dark variants)
- Brand colors (hex, names, brand references, or descriptions)
- Animation style preset (cosmic, neon, minimal, professional, playful)

**Outputs:** `assets/config/theme_config.json`

**Usage:** Invoke with `/brand-theme` or ask to "configure branding" or "set up theme"

**Animation effects sourced from:** [flutterfx/flutterfx_widgets](https://github.com/flutterfx/flutterfx_widgets)

#### `/apply-theme` - Apply Theme from Configuration
Reads `theme_config.json` and updates Dart theme files.

**Updates:**
- `lib/core/theme/app_colors.dart` - Color constants and logo paths
- `lib/core/theme/gradients.dart` - Gradient variations from brand colors
- `lib/shared/widgets/effects/` - Animation effect widgets based on style

**Prerequisites:** Run `/brand-theme` first to generate `assets/config/theme_config.json`

**Usage:** Invoke with `/apply-theme` after generating a theme config

## Important Notes

### Critical Implementation Details
- **Conversation State**: NEVER modify conversation history logic in `app.py` - maintains proper context
- **API Integration**: Always use OpenAI format with Databricks endpoints
- **WASM Compatibility**: Use `dart:js_interop` instead of `dart:html`
- **File Operations**: Use `file_selector` package for cross-platform compatibility
- **Backend Dependency**: Frontend requires backend server running on port 8000

### Development Guidelines
- Always use the existing theme system for new UI components
- Follow the established Riverpod patterns for state management
- Maintain responsive design principles for all new features
- Use `uv` for all Python package management (as per user preferences)
- Test full stack via `http://localhost:8000`, not direct file access
- **Backend Development**: Always work in the `backend/` folder for backend dev efforts. Once work is done, port changes over to the `deployment/` folder
- **Plan Mode Plans**: Write all plan mode plans to the `plan_mode_plans/` folder

### Security Considerations
- Microphone permissions require HTTPS or localhost
- Databricks tokens stored in `.env` file
- CORS configured for development (restrict for production)
- File access handled via secure file_selector package

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.