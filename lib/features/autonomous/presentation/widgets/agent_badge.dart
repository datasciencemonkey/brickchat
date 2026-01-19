// lib/features/autonomous/presentation/widgets/agent_badge.dart

import 'package:flutter/material.dart';
import '../../providers/autonomous_provider.dart';
import '../../../../core/theme/app_colors.dart';

/// Badge showing which agent handled a message in autonomous mode
class AgentBadge extends StatefulWidget {
  final RoutingInfo routingInfo;
  final bool initiallyExpanded;

  const AgentBadge({
    super.key,
    required this.routingInfo,
    this.initiallyExpanded = false,
  });

  @override
  State<AgentBadge> createState() => _AgentBadgeState();
}

class _AgentBadgeState extends State<AgentBadge> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final agent = widget.routingInfo.agent;

    return GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: _isExpanded ? 12 : 8,
          vertical: _isExpanded ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(_isExpanded ? 12 : 16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact view: just agent name
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  agent.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ],
            ),

            // Expanded view: routing reason and details
            if (_isExpanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why this agent?',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: appColors.mutedForeground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.routingInfo.reason,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (agent.description != null && agent.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'About',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: appColors.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        agent.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appColors.mutedForeground,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
