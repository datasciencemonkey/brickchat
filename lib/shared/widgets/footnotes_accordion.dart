import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class FootnotesAccordion extends StatefulWidget {
  final List<Map<String, String>> footnotes;
  final MarkdownStyleSheet? styleSheet;

  const FootnotesAccordion({
    super.key,
    required this.footnotes,
    this.styleSheet,
  });

  @override
  State<FootnotesAccordion> createState() => _FootnotesAccordionState();
}

class _FootnotesAccordionState extends State<FootnotesAccordion> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.footnotes.isEmpty) {
      return const SizedBox.shrink();
    }

    final appColors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: appColors.input.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        color: appColors.muted.withValues(alpha: 0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: appColors.mutedForeground,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Footnotes (${widget.footnotes.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: appColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (_isExpanded) ...[
            Divider(
              color: appColors.input.withValues(alpha: 0.2),
              height: 1,
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.footnotes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final footnote = entry.value;
                  final number = footnote['number'] ?? '${index + 1}';
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index < widget.footnotes.length - 1 ? 12 : 0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Footnote number badge with anchor ID
                        Container(
                          key: ValueKey('footnote-$number'),
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: appColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: appColors.accent.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            number.toString(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: appColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Footnote content with markdown support
                        Expanded(
                          child: MarkdownBody(
                            data: footnote['content'] ?? '',
                            selectable: true,
                            styleSheet: widget.styleSheet ??
                                MarkdownStyleSheet(
                                  p: TextStyle(
                                    color: appColors.messageText,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                  a: TextStyle(
                                    color: appColors.accent,
                                    fontSize: 12,
                                    decoration: TextDecoration.underline,
                                  ),
                                  code: TextStyle(
                                    backgroundColor: appColors.muted.withValues(alpha: 0.3),
                                    color: appColors.messageText,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                  strong: TextStyle(
                                    color: appColors.messageText,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
