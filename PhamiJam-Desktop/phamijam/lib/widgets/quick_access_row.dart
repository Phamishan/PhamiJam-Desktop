import 'package:flutter/material.dart';
import 'package:phamijam/providers/playlist_pin_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:provider/provider.dart';

class QuickAccessRow extends StatelessWidget {
  const QuickAccessRow({
    super.key,
    required this.youtubePlaylists,
    required this.mixedPlaylists,
    required this.coverOverrides,
    required this.onOpenYoutube,
    required this.onOpenMixed,
  });

  final List<Map<String, dynamic>> youtubePlaylists;
  final List<Map<String, dynamic>> mixedPlaylists;
  final Map<String, String> coverOverrides;
  final void Function(Map<String, dynamic> playlist) onOpenYoutube;
  final void Function(String id) onOpenMixed;

  _Entry? _youtubeEntry(Map<String, dynamic> p) {
    final id = (p['playlistId'] as String?) ?? '';
    if (id.isEmpty) return null;
    return _Entry(
      title: (p['title'] as String?) ?? 'Untitled playlist',
      subtitle: 'YouTube playlist',
      coverUrl: (p['thumbnailUrl'] as String?) ?? '',
      onTap: () => onOpenYoutube(p),
    );
  }

  _Entry _mixedEntry(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final tracks = ((p['tracks'] as List?) ?? const []).whereType<Map>();
    final custom = coverOverrides['mixed-$id'];
    final cover = (custom != null && custom.isNotEmpty)
        ? custom
        : tracks
              .map((t) => (t['thumbnailUrl'] as String?) ?? '')
              .firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final count = tracks.length;
    return _Entry(
      title: (p['title'] as String?) ?? 'Untitled playlist',
      subtitle: 'PhamiJam · $count ${count == 1 ? 'song' : 'songs'}',
      coverUrl: cover,
      onTap: () => onOpenMixed(id),
      mixed: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pins = context.watch<PlaylistPinProvider>();
    final settings = context.watch<SettingsProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    final youtubeById = {
      for (final p in youtubePlaylists)
        if (!settings.isPlaylistHidden((p['playlistId'] as String?) ?? ''))
          (p['playlistId'] as String? ?? ''): p,
    };
    final mixedById = {for (final p in mixedPlaylists) p['id'] as String: p};

    final pinned = <_Entry>[];
    for (final key in pins.pinnedOrder) {
      if (key.startsWith('mixed-')) {
        final p = mixedById[key.substring(6)];
        if (p != null) pinned.add(_mixedEntry(p));
      } else {
        final p = youtubeById[key];
        final entry = p == null ? null : _youtubeEntry(p);
        if (entry != null) pinned.add(entry);
      }
    }
    if (pinned.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in pinned.take(8))
              _QuickTile(entry: entry, colorScheme: colorScheme),
          ],
        ),
      ],
    );
  }
}

class _Entry {
  const _Entry({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
    this.mixed = false,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final VoidCallback onTap;
  final bool mixed;
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.entry, required this.colorScheme});

  final _Entry entry;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final fallbackIcon = entry.mixed
        ? Icons.library_music_rounded
        : Icons.playlist_play_rounded;
    return SizedBox(
      width: 250,
      height: 64,
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: entry.onTap,
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: entry.coverUrl.isEmpty
                    ? Container(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                        child: Icon(fallbackIcon, color: colorScheme.primary),
                      )
                    : Image.network(
                        entry.coverUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 128,
                        cacheHeight: 128,
                        errorBuilder: (_, _, _) => Container(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                          child: Icon(fallbackIcon, color: colorScheme.primary),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
