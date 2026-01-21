// lib/features/autonomous/widgets/agent_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/autonomous_provider.dart';
import '../services/autonomous_service.dart';

/// A reusable card widget to display agent information in the admin UI.
/// Includes enable/disable toggle and router metadata editing functionality.
class AgentCard extends ConsumerStatefulWidget {
  final AutonomousAgent agent;

  const AgentCard({
    super.key,
    required this.agent,
  });

  @override
  ConsumerState<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends ConsumerState<AgentCard> {
  bool _isUpdating = false;
  bool _isMetadataExpanded = false;
  bool _isSavingMetadata = false;
  late TextEditingController _metadataController;
  String? _originalMetadata;

  @override
  void initState() {
    super.initState();
    _metadataController = TextEditingController(
      text: widget.agent.routerMetadata ?? '',
    );
    _originalMetadata = widget.agent.routerMetadata ?? '';
  }

  @override
  void didUpdateWidget(AgentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agent.routerMetadata != widget.agent.routerMetadata) {
      _metadataController.text = widget.agent.routerMetadata ?? '';
      _originalMetadata = widget.agent.routerMetadata ?? '';
    }
  }

  @override
  void dispose() {
    _metadataController.dispose();
    super.dispose();
  }

  bool get _hasMetadataChanged => _metadataController.text != _originalMetadata;

  /// Returns the appropriate color for the agent's status
  Color _getStatusColor(BuildContext context) {
    final appColors = context.appColors;
    switch (widget.agent.status) {
      case 'enabled':
        return appColors.onlineStatus;
      case 'disabled':
        return appColors.offlineStatus;
      case 'new':
        return appColors.awayStatus;
      default:
        return appColors.mutedForeground;
    }
  }

  /// Returns the display text for the agent's status
  String _getStatusText() {
    switch (widget.agent.status) {
      case 'enabled':
        return 'Enabled';
      case 'disabled':
        return 'Disabled';
      case 'new':
        return 'New';
      default:
        return 'Unknown';
    }
  }

  /// Handles toggling the agent's enabled/disabled status
  Future<void> _toggleStatus() async {
    if (_isUpdating) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      final newStatus = widget.agent.isEnabled ? 'disabled' : 'enabled';
      final updatedAgent = await AutonomousService.updateAgent(
        widget.agent.agentId,
        status: newStatus,
      );

      if (updatedAgent != null) {
        // Update the agent in the provider - Riverpod handles state propagation
        ref.read(allAgentsProvider.notifier).updateAgent(updatedAgent);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Agent ${updatedAgent.name} ${newStatus == 'enabled' ? 'enabled' : 'disabled'}',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update agent: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  /// Saves the router metadata
  Future<void> _saveRouterMetadata() async {
    if (_isSavingMetadata || !_hasMetadataChanged) return;

    setState(() {
      _isSavingMetadata = true;
    });

    try {
      final updatedAgent = await AutonomousService.updateAgent(
        widget.agent.agentId,
        routerMetadata: _metadataController.text,
      );

      if (updatedAgent != null) {
        // Update the agent in the provider - Riverpod handles state propagation
        ref.read(allAgentsProvider.notifier).updateAgent(updatedAgent);
        _originalMetadata = _metadataController.text;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Router metadata saved'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save metadata: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingMetadata = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: appColors.input.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with name and status badge
            Row(
              children: [
                // Agent icon with metadata indicator
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.smart_toy_outlined,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    // Metadata indicator badge
                    if (widget.agent.hasRouterMetadata)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: appColors.onlineStatus,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                // Agent name and status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.agent.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Status chip
                      _buildStatusChip(context),
                    ],
                  ),
                ),
                // Toggle switch
                _buildToggle(context),
              ],
            ),
            // Description
            if (widget.agent.description != null &&
                widget.agent.description!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                widget.agent.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: appColors.mutedForeground,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // Endpoint URL (truncated)
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.link,
                  size: 14,
                  color: appColors.mutedForeground,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.agent.endpointUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appColors.mutedForeground,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // Router Metadata section
            const SizedBox(height: 12),
            _buildRouterMetadataSection(context, theme, appColors),
          ],
        ),
      ),
    );
  }

  /// Builds the expandable router metadata section
  Widget _buildRouterMetadataSection(
    BuildContext context,
    ThemeData theme,
    AppColorsExtension appColors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with expand/collapse
        InkWell(
          onTap: () {
            setState(() {
              _isMetadataExpanded = !_isMetadataExpanded;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: widget.agent.hasRouterMetadata
                      ? theme.colorScheme.primary
                      : appColors.mutedForeground,
                ),
                const SizedBox(width: 6),
                Text(
                  'Router Metadata',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: widget.agent.hasRouterMetadata
                        ? theme.colorScheme.primary
                        : appColors.mutedForeground,
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message:
                      'Describe this agent\'s capabilities to help the router make intelligent routing decisions',
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: appColors.mutedForeground.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: _isMetadataExpanded ? 0.5 : 0,
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: appColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expandable content
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _metadataController,
                  maxLines: 4,
                  minLines: 2,
                  style: theme.textTheme.bodySmall,
                  decoration: InputDecoration(
                    hintText:
                        'Describe this agent\'s capabilities, use cases, and expertise...',
                    hintStyle: theme.textTheme.bodySmall?.copyWith(
                      color: appColors.mutedForeground.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: appColors.muted.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: appColors.input.withValues(alpha: 0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  onChanged: (_) {
                    // Trigger rebuild to update save button state
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                // Save button
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: _hasMetadataChanged ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton.icon(
                      onPressed: _hasMetadataChanged && !_isSavingMetadata
                          ? _saveRouterMetadata
                          : null,
                      icon: _isSavingMetadata
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 16),
                      label: Text(_isSavingMetadata ? 'Saving...' : 'Save'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _isMetadataExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  /// Builds the status chip with appropriate color
  Widget _buildStatusChip(BuildContext context) {
    final statusColor = _getStatusColor(context);
    final statusText = _getStatusText();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the enable/disable toggle switch
  Widget _buildToggle(BuildContext context) {
    final theme = Theme.of(context);

    // For 'new' status, show switch in off position but allow enabling
    final isOn = widget.agent.isEnabled;

    return Stack(
      alignment: Alignment.center,
      children: [
        Switch(
          value: isOn,
          onChanged: _isUpdating ? null : (_) => _toggleStatus(),
          activeTrackColor: theme.colorScheme.primary,
        ),
        if (_isUpdating)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}
