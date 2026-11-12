import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/mixed_playlist_dialogs.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:phamijam/services/mixed_playlist_service.dart';
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
  static const String _youtubePrefix = 'yt:';
  static const String _mixedPrefix = 'mixed:';

  List<Map<String, dynamic>> _youtubePlaylists = [];
  List<Map<String, dynamic>> _mixedPlaylists = [];
  bool _loading = true;
  bool _youtubeFailed = false;
  bool _mixedFailed = false;
  final Set<String> _selectedKeys = {};
  bool _submitting = false;

  bool get _canUseYoutube => widget.songs.every((song) {
    final videoId = (song['videoId'] as String?) ?? '';
    return videoId.isNotEmpty && !videoId.startsWith(driveTrackIdPrefix);
  });

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final youtubeFuture = _canUseYoutube
        ? YoutubePlaylistService.fetchMyPlaylists()
        : Future.value(<Map<String, dynamic>>[]);
    final mixedFuture = MixedPlaylistService.fetchAll();

    var youtube = <Map<String, dynamic>>[];
    var mixed = <Map<String, dynamic>>[];
    var youtubeFailed = false;
    var mixedFailed = false;
    try {
      youtube = await youtubeFuture;
    } catch (_) {
      youtubeFailed = true;
    }
    try {
      mixed = await mixedFuture;
    } catch (_) {
      mixedFailed = true;
    }
    if (!mounted) return;
    setState(() {
      _youtubePlaylists = youtube;
      _mixedPlaylists = mixed;
      _youtubeFailed = youtubeFailed;
      _mixedFailed = mixedFailed;
      _loading = false;
    });
  }

  Future<void> _createMixedPlaylist() async {
    final name = await showMixedPlaylistNameDialog(context);
    if (name == null || !mounted) return;
    try {
      final id = await MixedPlaylistService.create(name);
      final mixed = await MixedPlaylistService.fetchAll();
      if (!mounted) return;
      setState(() {
        _mixedPlaylists = mixed;
        _selectedKeys.add('$_mixedPrefix$id');
      });
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't create playlist: $error");
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedKeys.isEmpty) return;
    setState(() => _submitting = true);

    final failures = <String>[];
    var targetCount = 0;
    String? lastTitle;

    for (final playlist in _youtubePlaylists) {
      final id = (playlist['playlistId'] as String?) ?? '';
      if (!_selectedKeys.contains('$_youtubePrefix$id')) continue;
      targetCount++;
      lastTitle = (playlist['title'] as String?) ?? 'playlist';
      try {
        for (final song in widget.songs) {
          final videoId = song['videoId'] as String? ?? '';
          if (videoId.isEmpty) continue;
          await YoutubePlaylistService.addVideoToPlaylist(
            playlistId: id,
            videoId: videoId,
          );
        }
      } catch (_) {
        failures.add(lastTitle);
      }
    }

    final tracks = widget.songs
        .map(MixedPlaylistService.trackFromSong)
        .toList();
    for (final playlist in _mixedPlaylists) {
      final id = (playlist['id'] as String?) ?? '';
      if (!_selectedKeys.contains('$_mixedPrefix$id')) continue;
      targetCount++;
      lastTitle = (playlist['title'] as String?) ?? 'playlist';
      try {
        await MixedPlaylistService.addTracks(id, tracks);
      } catch (_) {
        failures.add(lastTitle);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (failures.isEmpty) {
      final destination = targetCount == 1
          ? 'to $lastTitle'
          : 'to $targetCount playlists';
      AppFlushbar.success(
        context,
        widget.songs.length == 1
            ? 'Added $destination'
            : 'Added ${widget.songs.length} songs $destination',
      );
    } else if (failures.length == targetCount) {
      AppFlushbar.error(context, "Couldn't add to any playlist.");
    } else {
      AppFlushbar.error(context, 'Failed for: ${failures.join(', ')}');
    }
  }

  Widget _sectionHeader(String text, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _playlistTile({
    required String key,
    required bool enabled,
    required String title,
    required String subtitle,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    return CheckboxListTile(
      value: _selectedKeys.contains(key),
      onChanged: _submitting || !enabled
          ? null
          : (_) => setState(() {
              if (!_selectedKeys.remove(key)) _selectedKeys.add(key);
            }),
      controlAffinity: ListTileControlAffinity.leading,
      secondary: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colorScheme.onSurface),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    return ListView(
      shrinkWrap: true,
      children: [
        if (_canUseYoutube) ...[
          _sectionHeader('YOUTUBE PLAYLISTS', colorScheme),
          if (_youtubeFailed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                "Couldn't load your YouTube playlists.",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else if (_youtubePlaylists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No YouTube playlists yet.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final playlist in _youtubePlaylists)
              _playlistTile(
                key: '$_youtubePrefix${playlist['playlistId'] ?? ''}',
                enabled: ((playlist['playlistId'] as String?) ?? '').isNotEmpty,
                title: (playlist['title'] as String?) ?? 'Untitled playlist',
                subtitle: '${playlist['itemCount'] ?? 0} videos',
                icon: Icons.playlist_play_rounded,
                colorScheme: colorScheme,
              ),
        ],
        _sectionHeader('PHAMIJAM PLAYLISTS', colorScheme),
        if (_mixedFailed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "Couldn't load your PhamiJam playlists.",
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final playlist in _mixedPlaylists)
            _playlistTile(
              key: '$_mixedPrefix${playlist['id']}',
              enabled: true,
              title: (playlist['title'] as String?) ?? 'Untitled playlist',
              subtitle: '${(playlist['tracks'] as List?)?.length ?? 0} songs',
              icon: Icons.library_music_rounded,
              colorScheme: colorScheme,
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _submitting ? null : _createMixedPlaylist,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New mixed playlist'),
          ),
        ),
      ],
    );
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
                  ? (((widget.songs.first['title'] ??
                                widget.songs.first['songName'])
                            as String?) ??
                        'Song')
                  : '${widget.songs.length} songs selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (!_canUseYoutube)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Drive and local songs can only be added to PhamiJam '
                  'playlists.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (_loading)
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              SizedBox(height: 320, child: _buildList(colorScheme)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
          onPressed: (_submitting || _selectedKeys.isEmpty) ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _selectedKeys.isEmpty
                      ? 'Select playlists'
                      : 'Add to ${_selectedKeys.length}',
                ),
        ),
      ],
    );
  }
}
