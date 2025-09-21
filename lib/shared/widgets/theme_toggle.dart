import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({
    super.key,
    this.showLabel = false,
    this.size = 24.0,
  });

  final bool showLabel;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final appColors = context.appColors;

    return showLabel
        ? _buildToggleWithLabel(context, themeMode, themeNotifier, appColors)
        : _buildToggleButton(context, themeMode, themeNotifier, appColors);
  }

  Widget _buildToggleButton(
    BuildContext context,
    AppThemeMode themeMode,
    ThemeNotifier themeNotifier,
    AppColorsExtension appColors,
  ) {
    return IconButton(
      onPressed: () => themeNotifier.toggleTheme(),
      icon: AnimatedSwitcher(
        duration: AppConstants.mediumAnimation,
        child: Icon(
          _getThemeIcon(themeMode),
          key: ValueKey(themeMode),
          size: size,
        ),
      ),
      tooltip: _getTooltipText(themeMode),
    );
  }

  Widget _buildToggleWithLabel(
    BuildContext context,
    AppThemeMode themeMode,
    ThemeNotifier themeNotifier,
    AppColorsExtension appColors,
  ) {
    return InkWell(
      onTap: () => _showThemeSelector(context, themeNotifier),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getThemeIcon(themeMode),
              size: size,
            ),
            const SizedBox(width: 8),
            Text(
              _getThemeLabel(themeMode),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: size,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getThemeIcon(AppThemeMode themeMode) {
    switch (themeMode) {
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
      case AppThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  String _getThemeLabel(AppThemeMode themeMode) {
    switch (themeMode) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.system:
        return 'System';
    }
  }

  String _getTooltipText(AppThemeMode themeMode) {
    switch (themeMode) {
      case AppThemeMode.light:
        return 'Switch to dark theme';
      case AppThemeMode.dark:
        return 'Switch to light theme';
      case AppThemeMode.system:
        return 'Switch to light theme';
    }
  }

  void _showThemeSelector(BuildContext context, ThemeNotifier themeNotifier) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _ThemeSelector(themeNotifier: themeNotifier),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.themeNotifier});

  final ThemeNotifier themeNotifier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Theme',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _ThemeOption(
            icon: Icons.light_mode,
            title: 'Light',
            subtitle: 'Light theme',
            onTap: () {
              themeNotifier.setThemeMode(AppThemeMode.light);
              Navigator.of(context).pop();
            },
          ),
          _ThemeOption(
            icon: Icons.dark_mode,
            title: 'Dark',
            subtitle: 'Dark theme',
            onTap: () {
              themeNotifier.setThemeMode(AppThemeMode.dark);
              Navigator.of(context).pop();
            },
          ),
          _ThemeOption(
            icon: Icons.brightness_auto,
            title: 'System',
            subtitle: 'Follow system theme',
            onTap: () {
              themeNotifier.setThemeMode(AppThemeMode.system);
              Navigator.of(context).pop();
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}