import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../providers/settings_provider.dart';
import '../../autonomous/providers/autonomous_provider.dart';
import '../../autonomous/services/autonomous_service.dart';
import '../../autonomous/widgets/agent_card.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    try {
      final agents = await AutonomousService.getAllAgents();
      if (mounted) {
        ref.read(allAgentsProvider.notifier).setAgents(agents);
      }
    } catch (e) {
      // Silently fail - agents list will be empty
      debugPrint('Failed to load agents: $e');
    }
  }

  Future<void> _discoverAgents() async {
    if (_isDiscovering) return;

    setState(() {
      _isDiscovering = true;
    });

    try {
      final result = await AutonomousService.discoverAgents();

      if (mounted) {
        if (result['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Discovery failed: ${result['error']}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        } else {
          final discovered = result['discovered'] ?? 0;
          final updated = result['updated'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Discovered $discovered new agent(s), updated $updated existing'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Refresh the agents list
          await _loadAgents();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Discovery error: $e'),
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
                  const SizedBox(height: 16),
                  _buildEagerModeToggle(),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Keyboard Shortcuts Section
            _buildModernCard(
              context,
              icon: Icons.keyboard_outlined,
              title: 'Keyboard Shortcuts',
              subtitle: 'Configure keyboard shortcuts',
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildVoiceShortcutDropdown(),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Text-to-Speech Settings Section
            _buildModernCard(
              context,
              icon: Icons.volume_up_outlined,
              title: 'Text-to-Speech',
              subtitle: 'Configure voice output settings',
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildTtsProviderDropdown(),
                  const SizedBox(height: 16),
                  _buildTtsVoiceDropdown(),
                  const SizedBox(height: 16),
                  _buildTtsSaveToVolumeToggle(),
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

            const SizedBox(height: 20),

            // Autonomous Agents Section
            _buildAutonomousAgentsSection(),
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
          activeTrackColor: theme.colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildEagerModeToggle() {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final eagerMode = ref.eagerMode;
    final streamResults = ref.streamResults;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Eager mode',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                eagerMode
                    ? streamResults
                        ? 'Automatically play TTS as response streams'
                        : 'Automatically play TTS after response completes'
                    : 'Manually trigger TTS playback',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch(
          value: eagerMode,
          onChanged: (value) {
            ref.eagerModeNotifier.setEagerMode(value);
          },
          activeTrackColor: theme.colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildTtsProviderDropdown() {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final currentProvider = ref.ttsProvider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TTS Provider',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: appColors.input.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: currentProvider,
            isExpanded: true,
            underline: const SizedBox(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            items: TtsProvider.values.map((provider) {
              return DropdownMenuItem<String>(
                value: provider.value,
                child: Text(provider.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                ref.ttsProviderNotifier.setProvider(value);
                // Reset voice to default when changing provider
                if (value == TtsProvider.replicate.value) {
                  ref.ttsVoiceNotifier.setVoice('af_nicole');
                } else {
                  ref.ttsVoiceNotifier.setVoice('aura-2-thalia-en');
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTtsVoiceDropdown() {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final currentProvider = ref.ttsProvider;
    final currentVoice = ref.ttsVoice;

    // Get voices based on selected provider
    final voices = currentProvider == TtsProvider.replicate.value
        ? ReplicateVoices.voices
        : DeepgramVoices.voices;

    // Ensure current voice is valid for the selected provider
    final validVoice = voices.contains(currentVoice)
        ? currentVoice
        : voices.first;

    if (validVoice != currentVoice) {
      // Update to valid voice if current is invalid
      Future.microtask(() => ref.ttsVoiceNotifier.setVoice(validVoice));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Voice',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: appColors.input.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: validVoice,
            isExpanded: true,
            underline: const SizedBox(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            items: voices.map((voice) {
              final displayName = currentProvider == TtsProvider.replicate.value
                  ? ReplicateVoices.getDisplayName(voice)
                  : DeepgramVoices.getDisplayName(voice);

              return DropdownMenuItem<String>(
                value: voice,
                child: Text(displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                ref.ttsVoiceNotifier.setVoice(value);
              }
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          currentProvider == TtsProvider.replicate.value
              ? 'Replicate voices powered by Kokoro-82M'
              : 'Deepgram Aura voices',
          style: theme.textTheme.bodySmall?.copyWith(
            color: appColors.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildTtsSaveToVolumeToggle() {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final saveToVolume = ref.ttsSaveToVolume;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cache TTS audio',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                saveToVolume
                    ? 'Audio cached to cloud for faster playback'
                    : 'Audio generated fresh each time',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch(
          value: saveToVolume,
          onChanged: (value) {
            ref.ttsSaveToVolumeNotifier.setSaveToVolume(value);
          },
          activeTrackColor: theme.colorScheme.primary,
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

  Widget _buildVoiceShortcutDropdown() {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final currentShortcut = ref.voiceShortcut;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Voice Input Shortcut',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: appColors.input.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<VoiceShortcut>(
            value: currentShortcut,
            isExpanded: true,
            underline: const SizedBox(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            items: VoiceShortcut.values.map((shortcut) {
              return DropdownMenuItem<VoiceShortcut>(
                value: shortcut,
                child: Text(shortcut.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                ref.voiceShortcutNotifier.setShortcut(value);
              }
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Toggle voice input mode with this keyboard shortcut',
          style: theme.textTheme.bodySmall?.copyWith(
            color: appColors.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildAutonomousAgentsSection() {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final agents = ref.watch(allAgentsProvider);

    return _buildModernCard(
      context,
      icon: Icons.smart_toy_outlined,
      title: 'Autonomous Agents',
      subtitle: 'Manage AI agents for autonomous routing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Discover Agents Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDiscovering ? null : _discoverAgents,
              icon: _isDiscovering
                  ? SizedBox(
                      width: 16,
                      height: 16,
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
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Agents List
          if (agents.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              width: double.infinity,
              child: Column(
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 48,
                    color: appColors.mutedForeground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No agents discovered yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: appColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Click "Discover Agents" to find available agents',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appColors.mutedForeground.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${agents.length} agent(s) found',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 12),
                ...agents.map(
                  (agent) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AgentCard(
                      agent: agent,
                      onUpdated: _loadAgents,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}