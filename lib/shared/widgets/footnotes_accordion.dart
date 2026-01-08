import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget to display source citations from the model response.
/// Citations contain title and URL linking to the source document.
class SourcesAccordion extends StatefulWidget {
  final List<Map<String, dynamic>> citations;

  const SourcesAccordion({
    super.key,
    required this.citations,
  });

  @override
  State<SourcesAccordion> createState() => _SourcesAccordionState();
}

class _SourcesAccordionState extends State<SourcesAccordion> {
  bool _isExpanded = false;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.citations.isEmpty) {
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
                  Icon(
                    Icons.link,
                    size: 14,
                    color: appColors.mutedForeground,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Sources (${widget.citations.length})',
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
                children: widget.citations.asMap().entries.map((entry) {
                  final index = entry.key;
                  final citation = entry.value;
                  final number = citation['id'] ?? '${index + 1}';
                  final title = citation['title'] ?? 'Source';
                  final url = citation['url'] ?? '';

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index < widget.citations.length - 1 ? 12 : 0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Citation number badge
                        Container(
                          key: ValueKey('citation-$number'),
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
                        // Citation content with clickable link
                        Expanded(
                          child: InkWell(
                            onTap: url.isNotEmpty ? () => _launchUrl(url) : null,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 14,
                                  color: appColors.accent,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: url.isNotEmpty ? appColors.accent : appColors.messageText,
                                      fontSize: 12,
                                      height: 1.4,
                                      decoration: url.isNotEmpty ? TextDecoration.underline : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ),
                                if (url.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.open_in_new,
                                    size: 12,
                                    color: appColors.accent,
                                  ),
                                ],
                              ],
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
