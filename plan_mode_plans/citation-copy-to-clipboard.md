# Plan: Add Copy-to-Clipboard for Source Citation Badges

## Summary
Make the numbered citation badges (1, 2, 3) in the `SourcesAccordion` widget tappable to copy the source URL to clipboard.

## File Modified
- [lib/shared/widgets/footnotes_accordion.dart](../lib/shared/widgets/footnotes_accordion.dart)

## Changes Made

### 1. Added imports
```dart
import 'dart:js_interop';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
```

### 2. Added JS interop function for web clipboard
```dart
@JS('navigator.clipboard.writeText')
external JSPromise<JSAny?> _writeTextToClipboard(String text);
```

### 3. Added clipboard helper method in `_SourcesAccordionState`
```dart
Future<void> _copyUrlToClipboard(String url) async {
  try {
    if (kIsWeb) {
      await _writeTextToClipboard(url).toDart;
    } else {
      await Clipboard.setData(ClipboardData(text: url));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Source URL copied!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    await Clipboard.setData(ClipboardData(text: url));
  }
}
```

### 4. Wrapped citation badge with GestureDetector
```dart
GestureDetector(
  onTap: url.isNotEmpty ? () => _copyUrlToClipboard(url) : null,
  child: MouseRegion(
    cursor: url.isNotEmpty ? SystemMouseCursors.click : SystemMouseCursors.basic,
    child: Container(/* existing styling */),
  ),
),
```

## Behavior
- Tap on numbered badge (1, 2, 3) → copies URL to clipboard
- Shows snackbar: "Source URL copied!"
- Pointer cursor on hover (web)
- No action if citation has no URL
