import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';

/// Widget that displays message content with collapsible reasoning section
/// when <think> tags are detected
class CollapsibleReasoningWidget extends StatefulWidget {
  final String messageText;
  final MarkdownStyleSheet styleSheet;

  const CollapsibleReasoningWidget({
    super.key,
    required this.messageText,
    required this.styleSheet,
  });

  @override
  State<CollapsibleReasoningWidget> createState() => _CollapsibleReasoningWidgetState();
}

class _CollapsibleReasoningWidgetState extends State<CollapsibleReasoningWidget> {
  bool _isExpanded = false;
  bool _isReferencesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final parsedContent = _parseThinkTags(widget.messageText);

    // Process footnotes to convert them to superscript links
    final processedMainContent = _processFootnotes(parsedContent.mainContent);

    // If no thinking content, just show regular markdown
    if (parsedContent.thinkingContent == null) {
      return MarkdownBody(
        data: processedMainContent,
        styleSheet: widget.styleSheet,
        onTapLink: (text, href, title) {
          if (href != null) {
            _launchUrl(href);
          }
        },
        selectable: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapsible reasoning button at the top
        GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: appColors.muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: appColors.input.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology,
                  size: 16,
                  color: appColors.mutedForeground,
                ),
                const SizedBox(width: 8),
                Text(
                  'View reasoning process',
                  style: TextStyle(
                    color: appColors.mutedForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: appColors.mutedForeground,
                ),
              ],
            ),
          ),
        ),

        // Expanded thinking content (ONLY the <think> content is hidden)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _isExpanded
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: appColors.muted.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: appColors.input.withValues(alpha: 0.2),
              ),
            ),
            child: MarkdownBody(
              data: parsedContent.thinkingContent!,
              styleSheet: widget.styleSheet.copyWith(
                p: widget.styleSheet.p?.copyWith(
                  color: appColors.mutedForeground,
                  fontSize: 12,
                ),
              ),
              onTapLink: (text, href, title) {
                if (href != null) {
                  _launchUrl(href);
                }
              },
              selectable: true,
            ),
          ),
        ),

        // Main content (ALWAYS VISIBLE)
        if (parsedContent.mainContent.isNotEmpty) ...[
          const SizedBox(height: 12),
          MarkdownBody(
            data: processedMainContent,
            styleSheet: widget.styleSheet,
            onTapLink: (text, href, title) {
              if (href != null) {
                _launchUrl(href);
              }
            },
            selectable: true,
          ),
        ],

        // References accordion (if references exist)
        if (parsedContent.referencesContent != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                _isReferencesExpanded = !_isReferencesExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: appColors.muted.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: appColors.input.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.link,
                    size: 14,
                    color: appColors.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'View references',
                    style: TextStyle(
                      color: appColors.mutedForeground,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isReferencesExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: appColors.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isReferencesExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: appColors.muted.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: appColors.input.withValues(alpha: 0.15),
                ),
              ),
              child: MarkdownBody(
                data: parsedContent.referencesContent!,
                styleSheet: widget.styleSheet.copyWith(
                  p: widget.styleSheet.p?.copyWith(
                    color: appColors.mutedForeground,
                    fontSize: 11,
                  ),
                ),
                onTapLink: (text, href, title) {
                  if (href != null) {
                    _launchUrl(href);
                  }
                },
                selectable: true,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Process footnotes in markdown to convert them to simple numbered links
  String _processFootnotes(String text) {
    // Pattern to match footnote references in various formats
    // Matches patterns like:
    // <sup><a href="#footnote-1">1</a></sup>
    // <sup><a href="#footnote-2">2</a></sup>
    // Also matches simpler patterns if they exist
    final footnotePattern = RegExp(
      r'<sup>\s*<a\s+href="#footnote-(\d+)"[^>]*>\s*\d+\s*</a>\s*</sup>',
      multiLine: true,
    );

    // Replace all footnote patterns with simple numbered links
    String processed = text.replaceAllMapped(footnotePattern, (match) {
      final footnoteNumber = match.group(1) ?? '1';
      // Convert to simple numbered link format [¹]
      // Using Unicode superscript numbers for better display
      final superscriptNumber = _getSuperscriptNumber(footnoteNumber);
      return '[$superscriptNumber](#footnote-$footnoteNumber)';
    });

    return processed;
  }

  /// Convert regular number to Unicode superscript
  String _getSuperscriptNumber(String number) {
    const superscriptMap = {
      '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
      '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    };

    return number.split('').map((digit) =>
      superscriptMap[digit] ?? digit
    ).join();
  }

  /// Parses message text to extract <think> content, main content, and references
  _ParsedContent _parseThinkTags(String text) {
    // Pattern to match <think>...</think> (with DOTALL equivalent)
    final thinkPattern = RegExp(
      r'<think>(.*?)</think>',
      multiLine: true,
      dotAll: true,
    );

    final thinkMatch = thinkPattern.firstMatch(text);

    // Remove think tags first
    String processedText = text;
    String? thinkingContent;

    if (thinkMatch != null) {
      thinkingContent = thinkMatch.group(1)?.trim() ?? '';
      processedText = text.replaceFirst(thinkPattern, '').trim();
    }

    // Pattern to extract references section
    // Looks for end of sentence/paragraph followed by ": Policy Number:" to the end
    // This ensures we don't catch colons in the middle of normal sentences
    final referencePattern = RegExp(
      r'\n*:\s*Policy Number:.*$',
      multiLine: true,
      dotAll: true,
    );

    final refMatch = referencePattern.firstMatch(processedText);
    String mainContent = processedText;
    String? referencesContent;

    if (refMatch != null) {
      referencesContent = refMatch.group(1)?.trim() ?? '';
      mainContent = processedText.substring(0, refMatch.start).trim();
    }

    return _ParsedContent(
      mainContent: mainContent,
      thinkingContent: thinkingContent?.isNotEmpty == true ? thinkingContent : null,
      referencesContent: referencesContent?.isNotEmpty == true ? referencesContent : null,
    );
  }

  /// Launch URL in browser or handle footnote links
  Future<void> _launchUrl(String urlString) async {
    // Handle footnote links (e.g., #footnote-1)
    if (urlString.startsWith('#footnote-')) {
      // Find the footnote number from the URL
      final footnoteNumber = urlString.replaceFirst('#footnote-', '');

      // Show a tooltip with footnote number to indicate it was clicked
      // In a real implementation, this could expand the footnotes accordion
      // or scroll to the footnote section
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'See footnote $footnoteNumber in the Footnotes section below',
              style: const TextStyle(fontSize: 12),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            width: 280,
          ),
        );
      }
      return;
    }

    // Handle regular URLs
    try {
      final url = Uri.parse(urlString);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Handle invalid URLs
      debugPrint('Failed to launch URL: $urlString');
    }
  }
}

class _ParsedContent {
  final String mainContent;
  final String? thinkingContent;
  final String? referencesContent;

  _ParsedContent({
    required this.mainContent,
    this.thinkingContent,
    this.referencesContent,
  });
}
