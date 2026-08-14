import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';

Future<void> showAddToPlaylistDialog(
  BuildContext context, {
  required String videoId,
  required String songTitle,
}) {
  return showAddSongsToPlaylistDialog(
    context,
    songs: [
      {'videoId': videoId, 'title': songTitle},
    ],
  );
}

Future<void> showAddSongsToPlaylistDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> songs,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _AddToPlaylistDialog(songs: songs),
  );
}

class _AddToPlaylistDialog extends StatefulWidget {
  const _AddToPlaylistDialog({required this.songs});

  final List<Map<String, dynamic>> songs;

  @override
  State<_AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<_AddToPlaylistDialog> {
  late final Future<List<Map<String, dynamic>>> _playlistsFuture;
  final Set<String> _selectedIds = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _playlistsFuture = YoutubePlaylistService.fetchMyPlaylists();
  }

  Future<void> _submit(List<Map<String, dynamic>> playlists) async {
    final targets = playlists
        .where((p) => _selectedIds.contains(p['playlistId'] as String? ?? ''))
        .toList();
    if (targets.isEmpty) return;

    setState(() => _submitting = true);

    final failures = <String>[];
    for (final playlist in targets) {
      try {
        for (final song in widget.songs) {
          final videoId = song['videoId'] as String? ?? '';
          if (videoId.isEmpty) continue;
          await YoutubePlaylistService.addVideoToPlaylist(
            playlistId: playlist['playlistId'] as String,
            videoId: videoId,
          );
        }
      } catch (_) {
        failures.add((playlist['title'] as String?) ?? 'playlist');
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (failures.isEmpty) {
      final destination = targets.length == 1
          ? 'to ${targets.first['title']}'
          : 'to ${targets.length} playlists';
      AppFlushbar.success(
        context,
        widget.songs.length == 1
            ? 'Added $destination'
            : 'Added ${widget.songs.length} songs $destination',
      );
    } else if (failures.length == targets.length) {
      AppFlushbar.error(context, "Couldn't add to any playlist.");
    } else {
      AppFlushbar.error(context, 'Failed for: ${failures.join(', ')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      title: Text(
        'Add to playlist',
        style: TextStyle(color: colorScheme.onSurface),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.songs.length == 1
                  ? ((widget.songs.first['title'] as String?) ?? 'Song')
                  : '${widget.songs.length} songs selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _playlistsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return SizedBox(
                    height: 100,
                    child: Center(
                      child: Text(
                        "Couldn't load your playlists.",
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }

                final playlists = snapshot.data ?? const [];
                if (playlists.isEmpty) {
                  return SizedBox(
                    height: 100,
                    child: Center(
                      child: Text(
                        'No playlists yet. Create one first.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }

                return SizedBox(
                  height: 300,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final playlistId = playlist['playlistId'] as String? ?? '';
                      final selected = _selectedIds.contains(playlistId);

                      return CheckboxListTile(
                        value: selected,
                        onChanged: _submitting || playlistId.isEmpty
                            ? null
                            : (_) => setState(() {
                                if (!_selectedIds.remove(playlistId)) {
                                  _selectedIds.add(playlistId);
                                }
                              }),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          (playlist['title'] as String?) ?? 'Untitled playlist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                        subtitle: Text(
                          '${playlist['itemCount'] ?? 0} videos',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _playlistsFuture,
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? const [];
            return ElevatedButton(
              style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: (_submitting || _selectedIds.isEmpty)
                  ? null
                  : () => _submit(playlists),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _selectedIds.isEmpty
                          ? 'Select playlists'
                          : 'Add to ${_selectedIds.length}',
                    ),
            );
          },
        ),
      ],
    );
  }
}
