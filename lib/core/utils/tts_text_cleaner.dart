/// Utility class for cleaning text before sending to TTS
class TtsTextCleaner {
  /// Clean text for TTS by removing think tags and special markdown characters
  static String cleanForTts(String text) {
    String cleaned = text;

    // 1. Remove <think>...</think> tags and their content
    cleaned = _removeThinkTags(cleaned);

    // 2. Remove footnote references (superscript numbers like ¹²³⁴⁵⁶⁷⁸⁹⁰)
    cleaned = _removeFootnoteReferences(cleaned);

    // 3. Remove references section (everything after ": Policy Number:")
    cleaned = _removeReferences(cleaned);

    // 4. Remove markdown formatting
    cleaned = _removeMarkdownFormatting(cleaned);

    // 5. Clean up special characters
    cleaned = _cleanSpecialCharacters(cleaned);

    // 6. Normalize whitespace
    cleaned = _normalizeWhitespace(cleaned);

    return cleaned.trim();
  }

  /// Remove <think>...</think> tags and their content
  static String _removeThinkTags(String text) {
    final thinkPattern = RegExp(
      r'<think>.*?</think>',
      multiLine: true,
      dotAll: true,
    );
    return text.replaceAll(thinkPattern, '');
  }

  /// Remove footnote references (entire link patterns with superscript numbers)
  static String _removeFootnoteReferences(String text) {
    // Remove markdown-style footnote links like [¹](#footnote-1), [²](#footnote-2), etc.
    // This pattern matches [superscript](#footnote-number)
    // print(text);
    String cleaned = text.replaceAll(
      RegExp(r'\[[⁰¹²³⁴⁵⁶⁷⁸⁹]+\]\(#footnote-\d+\)'),
      ''
    );

    // Also remove any remaining standalone superscript characters
    cleaned = cleaned.replaceAll(RegExp(r'[⁰¹²³⁴⁵⁶⁷⁸⁹]+'), '');

    // Remove common footnote patterns like [1], [2], etc.
    cleaned = cleaned.replaceAll(RegExp(r'\[\d+\]'), '');

    // Remove footnote patterns with superscript-like notation (e.g., ^1, ^2)
    cleaned = cleaned.replaceAll(RegExp(r'\^\d+'), '');

    // Remove any markdown links that might be footnote references
    // Pattern: [any text](#footnote-any)
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]\(#footnote-[^\)]*\)'), '');

    return cleaned;
  }

  /// Remove references section (everything after newline + ": Policy Number:")
  /// This ensures we don't accidentally remove colons in normal sentences
  static String _removeReferences(String text) {
    final referencePattern = RegExp(
      r'\n*:\s*Policy Number:.*$',
      multiLine: true,
      dotAll: true,
    );
    return text.replaceAll(referencePattern, '');
  }

  /// Remove markdown formatting but keep the text content
  static String _removeMarkdownFormatting(String text) {
    String cleaned = text;

    // Remove headers (# ## ###)
    cleaned = cleaned.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

    // Remove bold (**text** or __text__)
    cleaned = cleaned.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');
    cleaned = cleaned.replaceAll(RegExp(r'__(.+?)__'), r'$1');

    // Remove italic (*text* or _text_)
    cleaned = cleaned.replaceAll(RegExp(r'\*(.+?)\*'), r'$1');
    cleaned = cleaned.replaceAll(RegExp(r'_(.+?)_'), r'$1');

    // Remove inline code (`text`)
    cleaned = cleaned.replaceAll(RegExp(r'`([^`]+?)`'), r'$1');

    // Remove code blocks (```...```)
    cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), '');

    // Remove links but keep text [text](url)
    cleaned = cleaned.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1');

    // Remove images ![alt](url)
    cleaned = cleaned.replaceAll(RegExp(r'!\[([^\]]*)\]\([^\)]+\)'), r'$1');

    // Remove horizontal rules (---, ___, ***)
    cleaned = cleaned.replaceAll(RegExp(r'^[\-_\*]{3,}$', multiLine: true), '');

    // Remove blockquotes (> text)
    cleaned = cleaned.replaceAll(RegExp(r'^>\s+', multiLine: true), '');

    // Remove list markers (-, *, +, 1.)
    cleaned = cleaned.replaceAll(RegExp(r'^[\s]*[-\*\+]\s+', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^[\s]*\d+\.\s+', multiLine: true), '');

    return cleaned;
  }

  /// Clean special characters that don't read well in TTS
  static String _cleanSpecialCharacters(String text) {
    String cleaned = text;

    // Remove HTML tags
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '');

    // Replace common symbols with spoken equivalents
    cleaned = cleaned.replaceAll('&', ' and ');
    cleaned = cleaned.replaceAll('@', ' at ');
    cleaned = cleaned.replaceAll('#', ' number ');
    cleaned = cleaned.replaceAll('%', ' percent ');
    cleaned = cleaned.replaceAll('+', ' plus ');
    cleaned = cleaned.replaceAll('=', ' equals ');

    // Remove other special characters that don't read well
    // Keep: letters, digits, whitespace, periods, commas, question marks, exclamation marks, hyphens, apostrophes, quotes
    cleaned = cleaned.replaceAll(RegExp(r'[^\w\s.,!?\-\"]'), ' ');

    return cleaned;
  }

  /// Normalize whitespace (multiple spaces, tabs, newlines)
  static String _normalizeWhitespace(String text) {
    String cleaned = text;

    // Replace multiple newlines with a period and space (for natural pauses)
    cleaned = cleaned.replaceAll(RegExp(r'\n\n+'), '. ');

    // Replace single newlines with space
    cleaned = cleaned.replaceAll(RegExp(r'\n'), ' ');

    // Replace tabs with space
    cleaned = cleaned.replaceAll('\t', ' ');

    // Replace multiple spaces with single space
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned;
  }
}
