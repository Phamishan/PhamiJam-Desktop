import 'package:flutter/material.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final String _settingsTitle = 'Settings';

  Widget _buildAppearanceCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose how PhamiJam looks on this device.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.auto,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto_rounded),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_rounded),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_rounded),
                  ),
                ],
                selected: {themeProvider.mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    themeProvider.setMode(selection.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: colorScheme.onSurface.withValues(
                    alpha: 0.12,
                  ),
                  foregroundColor: colorScheme.onSurfaceVariant,
                  selectedBackgroundColor: colorScheme.primary,
                  selectedForegroundColor: colorScheme.onPrimary,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.playlist_remove_rounded, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggest removing skipped songs',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Get asked to remove a playlist song you've skipped "
                      'early several times',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: settings.suggestRemovingSkippedSongs,
                onChanged: settings.setSuggestRemovingSkippedSongs,
                activeThumbColor: colorScheme.onPrimary,
                inactiveThumbColor: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmClearDownloads(DownloadsProvider downloads) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all downloads?'),
        content: const Text(
          'This deletes every downloaded song from this device. '
          "This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await downloads.clearAll();
    }
  }

  Widget _buildStorageCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<DownloadsProvider>(
      builder: (context, downloads, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.download_done_rounded,
                    color: colorScheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Downloaded Songs',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${downloads.totalTracks} songs · '
                          '${formatDownloadSize(downloads.totalSizeBytes)}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (downloads.totalTracks > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmClearDownloads(downloads),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: colorScheme.error,
                    ),
                    label: const Text('Clear all downloads'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildVersionInfoCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_rounded, color: colorScheme.onSurface),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'About PhamiJam',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 1.0.2',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _settingsTitle,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildAppearanceCard(),
        const SizedBox(height: 10),
        _buildPlayerCard(),
        const SizedBox(height: 10),
        _buildStorageCard(),
        const SizedBox(height: 10),
        _buildVersionInfoCard(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(child: _buildSettingsContent()),
    );
  }
}
