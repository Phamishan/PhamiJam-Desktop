import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phamijam/components/manage_playlist_visibility_dialog.dart';
import 'package:phamijam/models/app_update_info.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/update_service.dart';
import 'package:phamijam/theme/app_theme.dart';
import 'package:provider/provider.dart';

enum _UpdateState { idle, checking, upToDate, available, downloading, installing, error }

const List<Color> _accentColorPresets = [
  Color(0xFFE53935),
  Color(0xFFF4511E),
  Color(0xFF43A047),
  Color(0xFF00897B),
  Color(0xFF1E88E5),
  Color(0xFF5E35B1),
  Color(0xFF8E24AA),
  Color(0xFFD81B60),
];

Color? _parseHexColor(String input) {
  var hex = input.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(value);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final String _settingsTitle = 'Settings';
  String _appVersion = '';
  _UpdateState _updateState = _UpdateState.idle;
  AppUpdateInfo? _pendingUpdate;
  double _downloadProgress = 0;
  String? _updateError;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = info.version);
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _updateState = _UpdateState.checking;
      _updateError = null;
    });
    try {
      final update = await UpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        if (update == null) {
          _updateState = _UpdateState.upToDate;
        } else {
          _pendingUpdate = update;
          _updateState = _UpdateState.available;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updateState = _UpdateState.error;
        _updateError = error.toString();
      });
    }
  }

  Future<void> _downloadAndInstallUpdate() async {
    final update = _pendingUpdate;
    if (update == null) return;
    setState(() {
      _updateState = _UpdateState.downloading;
      _downloadProgress = 0;
    });
    try {
      final installerPath = await UpdateService.downloadInstaller(
        update.downloadUrl,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _updateState = _UpdateState.installing);
      await UpdateService.runInstallerAndExit(installerPath);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updateState = _UpdateState.error;
        _updateError = error.toString();
      });
    }
  }

  Widget _buildAppearanceCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
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
          const SizedBox(height: 16),
          Text(
            'Accent color',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _buildAccentColorPicker(colorScheme),
        ],
      ),
    );
  }

  Widget _buildAccentColorSwatch({
    required Color displayColor,
    required bool selected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: displayColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colorScheme.onSurface : Colors.transparent,
            width: 2,
          ),
        ),
        child: icon != null
            ? Icon(icon, size: 16, color: Colors.white)
            : (selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    )
                  : null),
      ),
    );
  }

  Widget _buildAccentColorPicker(ColorScheme colorScheme) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final current = themeProvider.accentColor;
        final isCustom =
            current != null && !_accentColorPresets.contains(current);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildAccentColorSwatch(
              displayColor: kBrandGold,
              selected: current == null,
              onTap: () => themeProvider.setAccentColor(null),
              colorScheme: colorScheme,
            ),
            for (final preset in _accentColorPresets)
              _buildAccentColorSwatch(
                displayColor: preset,
                selected: current == preset,
                onTap: () => themeProvider.setAccentColor(preset),
                colorScheme: colorScheme,
              ),
            _buildAccentColorSwatch(
              displayColor: isCustom
                  ? current
                  : colorScheme.onSurface.withValues(alpha: 0.12),
              selected: isCustom,
              icon: isCustom ? null : Icons.colorize_rounded,
              onTap: () => _showCustomColorDialog(
                themeProvider,
                isCustom ? current : null,
              ),
              colorScheme: colorScheme,
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCustomColorDialog(
    ThemeProvider themeProvider,
    Color? initial,
  ) async {
    final controller = TextEditingController(
      text: initial != null
          ? '#${initial.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
          : '',
    );
    Color? preview = initial;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              title: const Text('Custom accent color'),
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: preview ?? colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Hex color',
                        hintText: '#DBA43A',
                      ),
                      onChanged: (value) {
                        setDialogState(() => preview = _parseHexColor(value));
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: preview == null
                      ? null
                      : () {
                          themeProvider.setAccentColor(preview);
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSearchEngineCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search & Artists',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose search results from YouTube Music or YouTube',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return SegmentedButton<SearchEngine>(
                segments: const [
                  ButtonSegment(
                    value: SearchEngine.youtubeMusic,
                    label: Text('YouTube Music'),
                    icon: Icon(Icons.music_note_rounded),
                  ),
                  ButtonSegment(
                    value: SearchEngine.youtube,
                    label: Text('YouTube'),
                    icon: Icon(Icons.smart_display_rounded),
                  ),
                ],
                selected: {settings.searchEngine},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    settings.setSearchEngine(selection.first),
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
            color: colorScheme.surfaceContainer,
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

  Widget _buildLibraryCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showManagePlaylistVisibilityDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.playlist_play_rounded, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Playlist Visibility',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose which playlists show on Home and Playlists',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colorScheme.onSurface),
            ],
          ),
        ),
      ),
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
            color: colorScheme.surfaceContainer,
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
                OutlinedButton.icon(
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
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatTrimTime(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmClearEditedSongs(EditedSongsProvider editedSongs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all edited songs?'),
        content: const Text(
          'This resets every trimmed song back to playing in full.',
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
      for (final trim in List.of(editedSongs.all)) {
        await editedSongs.removeTrim(trim.videoId);
      }
    }
  }

  Widget _buildEditedSongsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<EditedSongsProvider>(
      builder: (context, editedSongs, _) {
        final trims = List.of(editedSongs.all)
          ..sort((a, b) => a.title.compareTo(b.title));
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.content_cut_rounded, color: colorScheme.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edited Songs',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${trims.length} songs trimmed',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (trims.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final trim in trims)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trim.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: colorScheme.onSurface),
                              ),
                              Text(
                                '${_formatTrimTime(trim.startMs)} - '
                                '${_formatTrimTime(trim.endMs)}',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Reset',
                          onPressed: () => editedSongs.removeTrim(trim.videoId),
                          icon: Icon(
                            Icons.restart_alt_rounded,
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _confirmClearEditedSongs(editedSongs),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: colorScheme.error,
                  ),
                  label: const Text('Clear all edited songs'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error),
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
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    _appVersion.isEmpty ? 'Version...' : 'Version $_appVersion',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._buildUpdateSection(colorScheme),
        ],
      ),
    );
  }

  List<Widget> _buildUpdateSection(ColorScheme colorScheme) {
    switch (_updateState) {
      case _UpdateState.idle:
        return [
          OutlinedButton.icon(
            onPressed: _checkForUpdate,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Check for updates'),
          ),
        ];
      case _UpdateState.checking:
        return [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                'Checking for updates...',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ];
      case _UpdateState.upToDate:
        return [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                "You're up to date.",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ];
      case _UpdateState.available:
        final update = _pendingUpdate;
        return [
          Text(
            update != null
                ? 'Version ${update.latestVersion} is available.'
                : 'An update is available.',
            style: TextStyle(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _downloadAndInstallUpdate,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download & install'),
          ),
        ];
      case _UpdateState.downloading:
        return [
          Text(
            'Downloading update... ${(_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
            ),
          ),
        ];
      case _UpdateState.installing:
        return [
          Text(
            'Installing update — PhamiJam will restart shortly...',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ];
      case _UpdateState.error:
        return [
          Text(
            _updateError ?? 'Failed to check for updates.',
            style: TextStyle(color: colorScheme.error),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _checkForUpdate,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ];
    }
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
        _buildSearchEngineCard(),
        const SizedBox(height: 10),
        _buildPlayerCard(),
        const SizedBox(height: 10),
        _buildLibraryCard(),
        const SizedBox(height: 10),
        _buildStorageCard(),
        const SizedBox(height: 10),
        _buildEditedSongsCard(),
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
