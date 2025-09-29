import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Chat Settings Section
            _buildModernCard(
              context,
              icon: Icons.chat_outlined,
              title: 'Chat Settings',
              subtitle: 'Configure chat behavior and preferences',
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildStreamToggle(),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // App Information Section
            _buildModernCard(
              context,
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'App information and purpose',
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildInfoItem('App Purpose', AppConstants.appPurpose),
                  _buildInfoItem('Designed for', AppConstants.appTarget),
                  _buildInfoItem('Features', 'Multi-backend AI support with voice interaction'),
                  _buildInfoItem('App Version', '1.0.0+1'),
                  _buildInfoItem('Built with', 'Flutter & Riverpod'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
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
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            child,
          ],
        ),
      ),
    );
  }


  Widget _buildStreamToggle() {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final streamResults = ref.streamResults;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stream results (experimental)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                streamResults
                    ? 'Responses appear word-by-word as they are generated'
                    : 'Complete responses appear all at once (faster)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch(
          value: streamResults,
          onChanged: (value) {
            ref.streamResultsNotifier.setStreamResults(value);
          },
          activeColor: theme.colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildInfoItem(String title, String value) {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: appColors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}