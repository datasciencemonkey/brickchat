// lib/features/settings/presentation/autonomous_agents_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../autonomous/providers/autonomous_provider.dart';
import '../../autonomous/services/autonomous_service.dart';
import '../../autonomous/widgets/agent_card.dart';

/// Dedicated page for managing autonomous agents with search and filtering.
class AutonomousAgentsPage extends ConsumerStatefulWidget {
  const AutonomousAgentsPage({super.key});

  @override
  ConsumerState<AutonomousAgentsPage> createState() =>
      _AutonomousAgentsPageState();
}

class _AutonomousAgentsPageState extends ConsumerState<AutonomousAgentsPage> {
  bool _isDiscovering = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    try {
      final agents = await AutonomousService.getAllAgents();
      if (mounted) {
        ref.read(allAgentsProvider.notifier).setAgents(agents);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load agents: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _discoverAgents() async {
    if (_isDiscovering) return;

    setState(() {
      _isDiscovering = true;
    });

    try {
      final result = await AutonomousService.discoverAgents();

      if (result.containsKey('error')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Discovery failed: ${result['error']}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } else {
        final newAgents = result['new_agents'] ?? 0;
        final existingAgents = result['existing_agents'] ?? 0;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Discovered $newAgents new agent(s), updated $existingAgents existing',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        // Reload agents to get updated list
        await _loadAgents();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Discovery failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final allAgents = ref.watch(allAgentsProvider);
    final filteredAgents = ref.watch(filteredAgentsProvider);
    final showEnabledOnly = ref.watch(agentShowEnabledOnlyProvider);
    final searchQuery = ref.watch(agentSearchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Autonomy'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Discover button (at the top)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isDiscovering ? null : _discoverAgents,
                icon: _isDiscovering
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : const Icon(Icons.search, size: 18),
                label: Text(_isDiscovering ? 'Discovering...' : 'Discover Agents'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Search bar
            TextField(
              controller: _searchController,
              onChanged: (value) {
                ref.read(agentSearchQueryProvider.notifier).state = value;
              },
              decoration: InputDecoration(
                hintText: 'Search agents...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: appColors.mutedForeground.withValues(alpha: 0.6),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: appColors.mutedForeground,
                ),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: appColors.mutedForeground,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(agentSearchQueryProvider.notifier).state =
                              '';
                        },
                      )
                    : null,
                filled: true,
                fillColor: appColors.muted.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: appColors.input.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Filter row with checkbox
            Row(
              children: [
                // Show enabled only checkbox
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: showEnabledOnly,
                    onChanged: (value) {
                      ref.read(agentShowEnabledOnlyProvider.notifier).state =
                          value ?? false;
                    },
                    activeColor: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    ref.read(agentShowEnabledOnlyProvider.notifier).state =
                        !showEnabledOnly;
                  },
                  child: Text(
                    'Show enabled only',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const Spacer(),
                // Agent count
                Text(
                  '${filteredAgents.length} of ${allAgents.length} agent(s)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appColors.mutedForeground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Agent list
            Expanded(
              child: filteredAgents.isEmpty
                  ? _buildEmptyState(context, theme, appColors, allAgents.isEmpty)
                  : ListView.builder(
                      itemCount: filteredAgents.length,
                      itemBuilder: (context, index) {
                        final agent = filteredAgents[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AgentCard(
                            agent: agent,
                            // Removed onUpdated callback - state is already updated via Riverpod
                            // Calling _loadAgents() caused a race condition that affected other agents
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    AppColorsExtension appColors,
    bool noAgentsAtAll,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            noAgentsAtAll ? Icons.smart_toy_outlined : Icons.search_off,
            size: 64,
            color: appColors.mutedForeground.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            noAgentsAtAll ? 'No agents discovered yet' : 'No matching agents',
            style: theme.textTheme.titleMedium?.copyWith(
              color: appColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            noAgentsAtAll
                ? 'Click "Discover Agents" to find available agents'
                : 'Try adjusting your search or filters',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: appColors.mutedForeground.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
