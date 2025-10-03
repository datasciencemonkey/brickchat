import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

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

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final parsedContent = _parseThinkTags(widget.messageText);

    // If no thinking content, just show regular markdown
    if (parsedContent.thinkingContent == null) {
      return MarkdownBody(
        data: parsedContent.mainContent,
        styleSheet: widget.styleSheet,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapsible reasoning section
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

        // Expanded thinking content
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
            ),
          ),
        ),

        // Main content (always visible)
        if (parsedContent.mainContent.isNotEmpty) ...[
          SizedBox(height: parsedContent.thinkingContent != null ? 12 : 0),
          MarkdownBody(
            data: parsedContent.mainContent,
            styleSheet: widget.styleSheet,
          ),
        ],
      ],
    );
  }

  /// Parses message text to extract <think> content and main content
  _ParsedContent _parseThinkTags(String text) {
    // Pattern to match <think>...</think> (with DOTALL equivalent)
    final thinkPattern = RegExp(
      r'<think>(.*?)</think>',
      multiLine: true,
      dotAll: true,
    );

    final match = thinkPattern.firstMatch(text);

    if (match == null) {
      return _ParsedContent(
        mainContent: text,
        thinkingContent: null,
      );
    }

    final thinkingContent = match.group(1)?.trim() ?? '';
    final mainContent = text.replaceFirst(thinkPattern, '').trim();

    return _ParsedContent(
      mainContent: mainContent,
      thinkingContent: thinkingContent.isNotEmpty ? thinkingContent : null,
    );
  }
}

class _ParsedContent {
  final String mainContent;
  final String? thinkingContent;

  _ParsedContent({
    required this.mainContent,
    this.thinkingContent,
  });
}
