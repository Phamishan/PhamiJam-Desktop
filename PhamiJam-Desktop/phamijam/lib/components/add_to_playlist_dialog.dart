import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/mixed_playlist_dialogs.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:phamijam/services/mixed_playlist_service.dart';
import 'package:phamijam/services/youtube_data_service.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';
import 'package:provider/provider.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/recent_playlists_prefs.dart';

Future<bool?> showAddToPlaylistDialog(
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

Future<bool?> showAddSongsToPlaylistDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> songs,
  String? excludeYoutubePlaylistId,
  String? excludeMixedPlaylistId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _AddToPlaylistDialog(
      songs: songs,
      excludeYoutubePlaylistId: excludeYoutubePlaylistId,
      excludeMixedPlaylistId: excludeMixedPlaylistId,
    ),
  );
}

class _AddToPlaylistDialog extends StatefulWidget {
  const _AddToPlaylistDialog({
    required this.songs,
    this.excludeYoutubePlaylistId,
    this.excludeMixedPlaylistId,
  });

  final List<Map<String, dynamic>> songs;
  final String? excludeYoutubePlaylistId;
  final String? excludeMixedPlaylistId;

  @override
  State<_AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

enum _PickerFilter { all, youtube, phamijam }

enum _DuplicateChoice { skip, addAnyway }

class _AddToPlaylistDialogState extends State<_AddToPlaylistDialog> {
  String _query = '';
  _PickerFilter _filter = _PickerFilter.all;
  List<String> _recentKeys = const [];
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
    RecentPlaylistsPrefs.load().then((keys) {
      if (mounted) setState(() => _recentKeys = keys);
    });
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
    } catch (error) {
      Log.w('library', 'load failed', error);
      youtubeFailed = true;
    }
    try {
      mixed = await mixedFuture;
    } catch (error) {
      Log.w('library', 'load failed', error);
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
      Log.e('library', 'create mixed playlist failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't create playlist: $error");
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fillMissingDetails(
    List<Map<String, dynamic>> songs,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (final original in songs) {
      final song = Map<String, dynamic>.from(original);
      final videoId = (song['videoId'] as String?) ?? '';
      final isYoutube =
          videoId.isNotEmpty &&
          !videoId.startsWith(driveTrackIdPrefix) &&
          ((song['path'] as String?) ?? '').isEmpty;
      if (isYoutube) {
        final hasArtist =
            ((song['artist'] ?? song['artistName']) as String?)?.isNotEmpty ??
            false;
        final hasThumb = ((song['thumbnailUrl'] as String?) ?? '').isNotEmpty;
        if (!hasArtist || !hasThumb) {
          try {
            final info = await YoutubeDataService.fetchVideoById(videoId);
            if (info != null) {
              if (!hasArtist) {
                song['artist'] = info['artist'];
                song['artistId'] =
                    (song['artistId'] as String?)?.isNotEmpty == true
                    ? song['artistId']
                    : info['artistId'];
              }
              if (!hasThumb) song['thumbnailUrl'] = info['thumbnailUrl'];
            }
          } catch (error) {
            Log.w('library', 'looking up song details failed', error);
          }
        }
        if (((song['thumbnailUrl'] as String?) ?? '').isEmpty) {
          song['thumbnailUrl'] =
              'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        }
        final knownSeconds = (song['durationSeconds'] as int?) ?? 0;
        final knownMs = (song['durationMs'] as int?) ?? 0;
        if (knownSeconds <= 0 && knownMs <= 0) {
          try {
            final seconds =
                await YoutubePlaylistService.fetchVideoDurationSeconds(videoId);
            if (seconds > 0) song['durationSeconds'] = seconds;
          } catch (error) {
            Log.w('library', 'looking up song length failed', error);
          }
        }
      }
      result.add(song);
    }
    return result;
  }

  Future<Map<String, Set<String>>> _findDuplicates() async {
    final duplicates = <String, Set<String>>{};

    final wantedVideoIds = widget.songs
        .map((s) => (s['videoId'] as String?) ?? '')
        .where((id) => id.isNotEmpty && !id.startsWith(driveTrackIdPrefix))
        .toSet();
    for (final playlist in _youtubePlaylists) {
      final id = (playlist['playlistId'] as String?) ?? '';
      if (!_selectedKeys.contains('$_youtubePrefix$id')) continue;
      try {
        final present = (await YoutubePlaylistService.fetchPlaylistItemIds(
          id,
        )).keys.toSet();
        final dup = wantedVideoIds.intersection(present);
        if (dup.isNotEmpty) duplicates['$_youtubePrefix$id'] = dup;
      } catch (error) {
        Log.w('library', 'checking for duplicates failed', error);
      }
    }

    final wantedKeys = widget.songs
        .map(
          (s) => MixedPlaylistService.trackKey(
            MixedPlaylistService.trackFromSong(s),
          ),
        )
        .toSet();
    for (final playlist in _mixedPlaylists) {
      final id = (playlist['id'] as String?) ?? '';
      if (!_selectedKeys.contains('$_mixedPrefix$id')) continue;
      final present = ((playlist['tracks'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (t) => MixedPlaylistService.trackKey(Map<String, dynamic>.from(t)),
          )
          .toSet();
      final dup = wantedKeys.intersection(present);
      if (dup.isNotEmpty) duplicates['$_mixedPrefix$id'] = dup;
    }
    return duplicates;
  }

  Future<_DuplicateChoice?> _askAboutDuplicates(
    Map<String, Set<String>> duplicates,
  ) {
    final names = <String>[];
    for (final playlist in _youtubePlaylists) {
      if (duplicates.containsKey('$_youtubePrefix${playlist['playlistId']}')) {
        names.add('"${playlist['title']}"');
      }
    }
    for (final playlist in _mixedPlaylists) {
      if (duplicates.containsKey('$_mixedPrefix${playlist['id']}')) {
        names.add('"${playlist['title']}"');
      }
    }
    final single = widget.songs.length == 1;
    final songTitle =
        ((widget.songs.first['title'] ?? widget.songs.first['songName'])
            as String?) ??
        'This song';
    final message = single
        ? '"$songTitle" is already in ${names.join(', ')}.'
        : 'Some of these songs are already in ${names.join(', ')}.';
    return showDialog<_DuplicateChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Already in the playlist'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DuplicateChoice.skip),
            child: Text(single ? "Don't add" : 'Skip duplicates'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DuplicateChoice.addAnyway),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedKeys.isEmpty) return;
    setState(() => _submitting = true);

    final duplicates = await _findDuplicates();
    var skipDuplicates = false;
    if (duplicates.isNotEmpty) {
      if (!mounted) return;
      final choice = await _askAboutDuplicates(duplicates);
      if (!mounted) return;
      if (choice == null) {
        setState(() => _submitting = false);
        return;
      }
      skipDuplicates = choice == _DuplicateChoice.skip;
    }

    final failures = <String>[];
    var targetCount = 0;
    var addedAnything = false;
    String? lastTitle;

    for (final playlist in _youtubePlaylists) {
      final id = (playlist['playlistId'] as String?) ?? '';
      final key = '$_youtubePrefix$id';
      if (!_selectedKeys.contains(key)) continue;
      targetCount++;
      lastTitle = (playlist['title'] as String?) ?? 'playlist';
      final already = duplicates[key] ?? const <String>{};
      try {
        for (final song in widget.songs) {
          final videoId = song['videoId'] as String? ?? '';
          if (videoId.isEmpty) continue;
          if (skipDuplicates && already.contains(videoId)) continue;
          await YoutubePlaylistService.addVideoToPlaylist(
            playlistId: id,
            videoId: videoId,
          );
          addedAnything = true;
        }
      } catch (error) {
        Log.w('library', 'submit failed', error);
        failures.add(lastTitle);
      }
    }

    final wantsMixed = _selectedKeys.any((k) => k.startsWith(_mixedPrefix));
    final enriched = wantsMixed
        ? await _fillMissingDetails(widget.songs)
        : widget.songs;
    final tracks = enriched.map(MixedPlaylistService.trackFromSong).toList();
    for (final playlist in _mixedPlaylists) {
      final id = (playlist['id'] as String?) ?? '';
      final key = '$_mixedPrefix$id';
      if (!_selectedKeys.contains(key)) continue;
      targetCount++;
      lastTitle = (playlist['title'] as String?) ?? 'playlist';
      final already = duplicates[key] ?? const <String>{};
      final toAdd = skipDuplicates
          ? tracks
                .where(
                  (t) => !already.contains(MixedPlaylistService.trackKey(t)),
                )
                .toList()
          : tracks;
      if (toAdd.isEmpty) continue;
      try {
        await MixedPlaylistService.addTracks(
          id,
          toAdd,
          allowDuplicates: !skipDuplicates,
        );
        addedAnything = true;
      } catch (error) {
        Log.w('library', 'submit failed', error);
        failures.add(lastTitle);
      }
    }

    if (failures.isEmpty) {
      unawaited(RecentPlaylistsPrefs.record(_selectedKeys.toList()));
    }
    if (!mounted) return;
    Navigator.of(context).pop(addedAnything);

    if (failures.isEmpty && !addedAnything) {
      AppFlushbar.info(context, 'Nothing added - already in the playlist.');
    } else if (failures.isEmpty) {
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

  Widget _youtubeTile(Map<String, dynamic> playlist, ColorScheme colorScheme) {
    return _playlistTile(
      key: '$_youtubePrefix${playlist['playlistId'] ?? ''}',
      enabled: ((playlist['playlistId'] as String?) ?? '').isNotEmpty,
      title: (playlist['title'] as String?) ?? 'Untitled playlist',
      subtitle: '${playlist['itemCount'] ?? 0} videos',
      icon: Icons.playlist_play_rounded,
      colorScheme: colorScheme,
    );
  }

  Widget _mixedTile(Map<String, dynamic> playlist, ColorScheme colorScheme) {
    return _playlistTile(
      key: '$_mixedPrefix${playlist['id']}',
      enabled: true,
      title: (playlist['title'] as String?) ?? 'Untitled playlist',
      subtitle: '${(playlist['tracks'] as List?)?.length ?? 0} songs',
      icon: Icons.library_music_rounded,
      colorScheme: colorScheme,
    );
  }

  Widget _buildFilters(ColorScheme colorScheme) {
    final total =
        (_canUseYoutube ? _youtubePlaylists.length : 0) +
        _mixedPlaylists.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total >= 6)
            TextField(
              onChanged: (value) => setState(() => _query = value),
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search playlists',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: colorScheme.onSurface.withValues(alpha: 0.12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          if (_canUseYoutube &&
              _youtubePlaylists.isNotEmpty &&
              _mixedPlaylists.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final entry in const {
                    _PickerFilter.all: 'All',
                    _PickerFilter.youtube: 'YouTube',
                    _PickerFilter.phamijam: 'PhamiJam',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _filter == entry.key,
                      onSelected: (_) => setState(() => _filter = entry.key),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    final settings = context.watch<SettingsProvider>();
    final query = _query.trim().toLowerCase();
    bool matches(Map<String, dynamic> p) =>
        query.isEmpty ||
        ((p['title'] as String?) ?? '').toLowerCase().contains(query);

    final youtubePlaylists = _youtubePlaylists
        .where(
          (p) =>
              !settings.isPlaylistHidden((p['playlistId'] as String?) ?? '') &&
              p['playlistId'] != widget.excludeYoutubePlaylistId &&
              matches(p),
        )
        .toList();
    final mixedPlaylists = _mixedPlaylists
        .where(
          (p) =>
              !settings.isPlaylistHidden((p['id'] as String?) ?? '') &&
              p['id'] != widget.excludeMixedPlaylistId &&
              matches(p),
        )
        .toList();

    final showYoutube =
        _canUseYoutube &&
        (_filter == _PickerFilter.all || _filter == _PickerFilter.youtube);
    final showMixed =
        _filter == _PickerFilter.all || _filter == _PickerFilter.phamijam;

    final recentWidgets = <Widget>[];
    final recentKeys = <String>{};
    if (query.isEmpty && _filter == _PickerFilter.all) {
      for (final key in _recentKeys) {
        if (recentWidgets.length >= 3) break;
        if (key.startsWith(_youtubePrefix) && _canUseYoutube) {
          final id = key.substring(_youtubePrefix.length);
          for (final p in youtubePlaylists) {
            if (p['playlistId'] == id) {
              recentWidgets.add(_youtubeTile(p, colorScheme));
              recentKeys.add(key);
              break;
            }
          }
        } else if (key.startsWith(_mixedPrefix)) {
          final id = key.substring(_mixedPrefix.length);
          for (final p in mixedPlaylists) {
            if (p['id'] == id) {
              recentWidgets.add(_mixedTile(p, colorScheme));
              recentKeys.add(key);
              break;
            }
          }
        }
      }
    }

    return ListView(
      shrinkWrap: true,
      children: [
        if (recentWidgets.isNotEmpty) ...[
          _sectionHeader('RECENT', colorScheme),
          ...recentWidgets,
        ],
        if (showYoutube) ...[
          _sectionHeader('YOUTUBE PLAYLISTS', colorScheme),
          if (_youtubeFailed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                "Couldn't load your YouTube playlists.",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else if (youtubePlaylists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                query.isEmpty
                    ? 'No YouTube playlists yet.'
                    : 'No YouTube playlists match.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final playlist in youtubePlaylists)
              if (!recentKeys.contains(
                '$_youtubePrefix${playlist['playlistId']}',
              ))
                _youtubeTile(playlist, colorScheme),
        ],
        if (showMixed) ...[
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
            for (final playlist in mixedPlaylists)
              if (!recentKeys.contains('$_mixedPrefix${playlist['id']}'))
                _mixedTile(playlist, colorScheme),
        ],
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
              SizedBox(
                height: 340,
                child: Column(
                  children: [
                    _buildFilters(colorScheme),
                    Expanded(child: _buildList(colorScheme)),
                  ],
                ),
              ),
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
