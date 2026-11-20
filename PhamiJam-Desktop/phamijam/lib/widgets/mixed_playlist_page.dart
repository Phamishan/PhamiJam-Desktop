import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:phamijam/components/add_to_playlist_dialog.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/edit_song_dialog.dart';
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/components/mixed_playlist_dialogs.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/providers/liked_songs_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:phamijam/services/mixed_playlist_service.dart';
import 'package:phamijam/services/playlist_cover_service.dart';
import 'package:phamijam/services/share_link_service.dart';
import 'package:phamijam/services/youtube_data_service.dart';
import 'package:phamijam/widgets/artist_line.dart';
import 'package:provider/provider.dart';
import 'package:phamijam/services/log_service.dart';

enum _MixedSort { custom, titleAz, artistAz, durationShort, durationLong }

extension on _MixedSort {
  String get label {
    switch (this) {
      case _MixedSort.custom:
        return 'Playlist order';
      case _MixedSort.titleAz:
        return 'Title (A–Z)';
      case _MixedSort.artistAz:
        return 'Artist (A–Z)';
      case _MixedSort.durationShort:
        return 'Duration (shortest first)';
      case _MixedSort.durationLong:
        return 'Duration (longest first)';
    }
  }
}

class MixedPlaylistPage extends StatefulWidget {
  const MixedPlaylistPage({super.key, required this.playlistId, this.onBack});

  final String playlistId;
  final VoidCallback? onBack;

  @override
  State<MixedPlaylistPage> createState() => _MixedPlaylistPageState();
}

class _MixedPlaylistPageState extends State<MixedPlaylistPage> {
  late final PlaybackModel _playback;
  StreamSubscription<Map<String, dynamic>?>? _subscription;
  StreamSubscription<Map<String, String>>? _coverSubscription;
  String? _customCoverUrl;
  bool _uploadingCover = false;
  Map<String, dynamic>? _playlist;
  bool _loading = true;
  bool _missing = false;
  int? _loadingIndex;
  final Map<String, bool> _localExists = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _MixedSort _sort = _MixedSort.custom;

  List<Map<String, dynamic>> get _tracks =>
      (_playlist?['tracks'] as List<Map<String, dynamic>>?) ?? const [];

  String get _title => (_playlist?['title'] as String?) ?? 'Playlist';

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackModel>();
    _coverSubscription = PlaylistCoverService.watchAll().listen((overrides) {
      if (!mounted) return;
      setState(
        () => _customCoverUrl =
            overrides[MixedPlaylistService.coverKey(widget.playlistId)],
      );
    });
    _subscription = MixedPlaylistService.watchOne(widget.playlistId).listen(
      (playlist) {
        if (!mounted) return;
        if (playlist != null) {
          for (final track
              in playlist['tracks'] as List<Map<String, dynamic>>) {
            if (track['source'] == 'local') {
              final path = (track['path'] as String?) ?? '';
              _localExists[path] = path.isNotEmpty && File(path).existsSync();
            }
          }
        }
        setState(() {
          _playlist = playlist;
          _missing = playlist == null;
          _loading = false;
        });
        if (playlist != null) unawaited(_repairMissingDetails(playlist));
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _missing = true;
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _coverSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  final Set<String> _repairAttempted = {};

  Future<void> _repairMissingDetails(Map<String, dynamic> playlist) async {
    final tracks = (playlist['tracks'] as List<Map<String, dynamic>>);
    final missing = <String>[];
    for (final track in tracks) {
      if (_sourceOf(track) != 'youtube') continue;
      final videoId = (track['videoId'] as String?) ?? '';
      if (videoId.isEmpty || _repairAttempted.contains(videoId)) continue;
      final artist = (track['artist'] as String?) ?? '';
      final thumb = (track['thumbnailUrl'] as String?) ?? '';
      if (artist.isEmpty || thumb.isEmpty) missing.add(videoId);
    }
    if (missing.isEmpty) return;
    Log.i('library', 'repairing details for ${missing.length} songs');
    final details = <String, Map<String, dynamic>>{};
    for (final videoId in missing.take(25)) {
      _repairAttempted.add(videoId);
      try {
        final info = await YoutubeDataService.fetchVideoById(videoId);
        if (info != null) details[videoId] = info;
      } catch (error) {
        Log.w('library', 'could not look up details for a song', error);
      }
    }
    try {
      await MixedPlaylistService.repairMissingMetadata(
        widget.playlistId,
        details,
      );
    } catch (error) {
      Log.w('library', 'saving repaired song details failed', error);
    }
  }

  Future<void> _changeCover() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingCover = true);
    try {
      await PlaylistCoverService.upload(
        MixedPlaylistService.coverKey(widget.playlistId),
        File(picked.path),
      );
    } catch (error) {
      Log.e('library', 'change cover failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't update cover image: $error");
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _removeCover() async {
    setState(() => _uploadingCover = true);
    try {
      await PlaylistCoverService.remove(
        MixedPlaylistService.coverKey(widget.playlistId),
      );
    } catch (error) {
      Log.e('library', 'remove cover failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't remove cover image: $error");
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  static String _sourceOf(Map<String, dynamic> track) =>
      (track['source'] as String?) ?? 'youtube';

  static String _expectedPath(Map<String, dynamic> track) {
    switch (_sourceOf(track)) {
      case 'local':
        return (track['path'] as String?) ?? '';
      case 'drive':
        return (track['videoId'] as String?) ?? '';
      default:
        return 'yt:${track['videoId'] ?? ''}';
    }
  }

  bool _isPlayable(Map<String, dynamic> track) {
    if (_sourceOf(track) != 'local') return true;
    return _localExists[(track['path'] as String?) ?? ''] ?? false;
  }

  Map<String, dynamic> _queueItem(Map<String, dynamic> track) {
    final title = (track['title'] as String?) ?? '';
    final artist = (track['artist'] as String?) ?? '';
    final artistId = (track['artistId'] as String?) ?? '';
    final durationMs = (track['durationMs'] as int?) ?? 0;
    final item = <String, dynamic>{
      'title': title,
      'artist': artist,
      'songName': title,
      'artistName': artist,
      'artistId': artistId.isEmpty ? null : artistId,
      'thumbnailUrl': (track['thumbnailUrl'] as String?) ?? '',
      'durationSeconds': (durationMs / 1000).round(),
    };
    if (_sourceOf(track) == 'local') {
      item['path'] = (track['path'] as String?) ?? '';
      item['coverImageBytes'] = null;
    } else {
      item['videoId'] = (track['videoId'] as String?) ?? '';
    }
    return item;
  }

  Future<Uint8List?> _downloadImageBytes(String imageUrl) async {
    if (imageUrl.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (error) {
      Log.w('library', 'download image bytes failed', error);
    }
    return null;
  }

  Future<bool> _startPlayback(Map<String, dynamic> track) async {
    final playback = _playback;
    final title = (track['title'] as String?) ?? 'Unknown song';
    final artist = (track['artist'] as String?) ?? 'Unknown artist';
    final durationMs = (track['durationMs'] as int?) ?? 0;
    final duration = durationMs > 0
        ? Duration(milliseconds: durationMs)
        : Duration.zero;
    final videoId = (track['videoId'] as String?) ?? '';

    switch (_sourceOf(track)) {
      case 'local':
        final path = (track['path'] as String?) ?? '';
        if (path.isEmpty || !await File(path).exists()) {
          if (mounted) {
            AppFlushbar.error(context, '"$title" is not on this computer.');
          }
          return false;
        }
        await playback.switchToLocalEngine();
        playback.setDuration(Duration.zero);
        await player.setFilePath(path);
        await player.seek(Duration.zero);
        await player.play();
        playback.setArtist(artist);
        playback.setArtistId(null);
        playback.setSongName(title);
        playback.setCurrentSongPath(path);
        playback.setCoverImageBytes(null);
        playback.setDuration(duration);
        playback.setIsPlaying(true);
        playback.setIsMuted(false);
        return true;
      case 'drive':
        if (!videoId.startsWith(driveTrackIdPrefix)) return false;
        final fileId = videoId.substring(driveTrackIdPrefix.length);
        await playback.switchToLocalEngine();
        playback.setDuration(Duration.zero);
        final headers = await GoogleDriveService.streamHeaders(fileId);
        await player.setUrl(
          GoogleDriveService.streamUri(fileId).toString(),
          headers: headers,
        );
        await player.seek(Duration.zero);
        await player.play();
        playback.setArtist(artist);
        playback.setArtistId(null);
        playback.setSongName(title);
        playback.setCurrentSongPath(videoId);
        playback.setCoverImageBytes(null);
        playback.setDuration(duration);
        playback.setIsPlaying(true);
        playback.setIsMuted(false);
        return true;
      default:
        if (videoId.isEmpty) return false;
        final cover = await _downloadImageBytes(
          (track['thumbnailUrl'] as String?) ?? '',
        );
        final artistId = (track['artistId'] as String?) ?? '';
        playback.setSongName(title);
        playback.setArtist(artist);
        playback.setArtistId(artistId.isEmpty ? null : artistId);
        playback.setCurrentSongPath('yt:$videoId');
        playback.setCoverImageBytes(cover);
        playback.setDuration(duration);
        await playback.playYouTubeVideoById(videoId);
        await playback.applyVolume(playback.currentSliderValue);
        return true;
    }
  }

  Future<void> _playFrom(
    List<Map<String, dynamic>> tracks,
    int index, {
    required bool syncQueue,
  }) async {
    if (index < 0 || index >= tracks.length) return;
    if (syncQueue) setState(() => _loadingIndex = index);
    try {
      final started = await _startPlayback(tracks[index]);
      if (!started) return;

      if (syncQueue) {
        _playback.setPlaylistQueue(
          tracks.map(_queueItem).toList(),
          startIndex: index,
        );
        _playback.setQueueHandlers(
          playAtSourceIndex: (sourceIndex) async {
            if (sourceIndex < 0 || sourceIndex >= tracks.length) return;
            final ok = await _startPlayback(tracks[sourceIndex]);
            if (ok) _playback.markCurrentSourceIndex(sourceIndex);
          },
          prefetchQueueItem: (item) async {
            if (item is! Map<String, dynamic>) return;
            final videoId = (item['videoId'] as String?) ?? '';
            if (videoId.isEmpty || videoId.startsWith(driveTrackIdPrefix)) {
              return;
            }
            await _playback.prefetchYouTubeVideoById(videoId);
          },
        );
      } else {
        _playback.markCurrentSourceIndex(index);
      }
    } catch (error) {
      Log.e('library', 'play from failed', error);
      if (mounted) AppFlushbar.error(context, 'Failed to play: $error');
    } finally {
      if (syncQueue && mounted) setState(() => _loadingIndex = null);
    }
  }

  Future<void> _playTrack(int index) async {
    if (_loadingIndex != null) return;
    await _playFrom(
      List<Map<String, dynamic>>.from(_tracks),
      index,
      syncQueue: true,
    );
  }

  Future<void> _rename() async {
    final name = await showMixedPlaylistNameDialog(
      context,
      title: 'Rename playlist',
      initial: _title,
      actionLabel: 'Save',
    );
    if (name == null || name == _title) return;
    try {
      await MixedPlaylistService.rename(widget.playlistId, name);
    } catch (error) {
      Log.e('library', 'rename failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't rename playlist: $error");
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDeleteMixedPlaylist(context, _title);
    if (!confirmed) return;
    try {
      await MixedPlaylistService.delete(widget.playlistId);
      if (mounted) widget.onBack?.call();
    } catch (error) {
      Log.e('library', 'delete failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't delete playlist: $error");
      }
    }
  }

  Future<void> _removeTrack(int index) async {
    final title = (_tracks[index]['title'] as String?) ?? 'song';
    try {
      await MixedPlaylistService.removeTrackAt(widget.playlistId, index);
      if (mounted) AppFlushbar.success(context, 'Removed "$title"');
    } catch (error) {
      Log.e('library', 'remove track failed', error);
      if (mounted) AppFlushbar.error(context, "Couldn't remove song: $error");
    }
  }

  String _sourceLabel(Map<String, dynamic> track) {
    switch (_sourceOf(track)) {
      case 'local':
        return _isPlayable(track) ? 'This computer' : 'Not on this computer';
      case 'drive':
        return 'Google Drive';
      default:
        return 'YouTube';
    }
  }

  IconData _sourceIcon(Map<String, dynamic> track) {
    switch (_sourceOf(track)) {
      case 'local':
        return Icons.computer_rounded;
      case 'drive':
        return Icons.cloud_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  int _durationSecondsOf(Map<String, dynamic> track) =>
      (((track['durationMs'] as int?) ?? 0) / 1000).round();

  bool _isYoutube(Map<String, dynamic> track) =>
      _sourceOf(track) == 'youtube' &&
      ((track['videoId'] as String?) ?? '').isNotEmpty;

  Map<String, dynamic> _songMap(Map<String, dynamic> track) => {
    'videoId': (track['videoId'] as String?) ?? '',
    'path': (track['path'] as String?) ?? '',
    'title': (track['title'] as String?) ?? '',
    'artist': (track['artist'] as String?) ?? '',
    'artistId': (track['artistId'] as String?) ?? '',
    'thumbnailUrl': (track['thumbnailUrl'] as String?) ?? '',
    'durationSeconds': _durationSecondsOf(track),
  };

  List<MapEntry<int, Map<String, dynamic>>> get _visibleTracks {
    final tracks = _tracks;
    final query = _searchQuery.trim().toLowerCase();
    var entries = [
      for (var i = 0; i < tracks.length; i++) MapEntry(i, tracks[i]),
    ];
    if (query.isNotEmpty) {
      entries = entries.where((e) {
        final title = ((e.value['title'] as String?) ?? '').toLowerCase();
        final artist = ((e.value['artist'] as String?) ?? '').toLowerCase();
        return title.contains(query) || artist.contains(query);
      }).toList();
    }
    int byText(
      String key,
      MapEntry<int, Map<String, dynamic>> a,
      MapEntry<int, Map<String, dynamic>> b,
    ) => ((a.value[key] as String?) ?? '').toLowerCase().compareTo(
      ((b.value[key] as String?) ?? '').toLowerCase(),
    );
    switch (_sort) {
      case _MixedSort.custom:
        break;
      case _MixedSort.titleAz:
        entries.sort((a, b) => byText('title', a, b));
      case _MixedSort.artistAz:
        entries.sort((a, b) => byText('artist', a, b));
      case _MixedSort.durationShort:
        entries.sort(
          (a, b) => _durationSecondsOf(
            a.value,
          ).compareTo(_durationSecondsOf(b.value)),
        );
      case _MixedSort.durationLong:
        entries.sort(
          (a, b) => _durationSecondsOf(
            b.value,
          ).compareTo(_durationSecondsOf(a.value)),
        );
    }
    return entries;
  }

  Future<void> _playOrPause(bool isPlaying, bool isShuffled) async {
    if (isPlaying) {
      await _playback.togglePlayPause();
      return;
    }
    final tracks = List<Map<String, dynamic>>.from(_tracks);
    final playable = [
      for (var i = 0; i < tracks.length; i++)
        if (_isPlayable(tracks[i])) i,
    ];
    if (playable.isEmpty) return;
    final target = isShuffled
        ? playable[Random().nextInt(playable.length)]
        : playable.first;
    await _playFrom(tracks, target, syncQueue: true);
  }

  Widget _buildMenuButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasCover = _customCoverUrl != null && _customCoverUrl!.isNotEmpty;
    return PopupMenuButton<String>(
      enabled: !_uploadingCover,
      icon: _uploadingCover
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.edit_rounded, color: colorScheme.onSurface),
      onSelected: (value) {
        if (value == 'rename') {
          _rename();
        } else if (value == 'cover') {
          _changeCover();
        } else if (value == 'remove_cover') {
          _removeCover();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'cover', child: Text('Change cover image')),
        if (hasCover)
          const PopupMenuItem(
            value: 'remove_cover',
            child: Text('Remove cover image'),
          ),
      ],
    );
  }

  Widget _buildMetadataRow(List<Map<String, dynamic>> tracks) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalSeconds = tracks.fold<int>(
      0,
      (sum, t) => sum + _durationSecondsOf(t),
    );
    final style = TextStyle(color: colorScheme.onSurfaceVariant);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text('PhamiJam playlist', style: style),
        Text('${tracks.length} songs', style: style),
        Text(_formatDuration(totalSeconds), style: style),
      ],
    );
  }

  Widget _buildControlButtons(List<Map<String, dynamic>> tracks) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = context.select<PlaybackModel, (bool, bool, PlayerRepeatMode)>(
      (p) => (p.isPlaying, p.isShuffled, p.repeatMode),
    );
    final isPlaying = state.$1;
    final isShuffled = state.$2;
    final repeatMode = state.$3;

    return Row(
      children: [
        IconButton(
          onPressed: tracks.any(_isPlayable)
              ? () => _playOrPause(isPlaying, isShuffled)
              : null,
          icon: Icon(
            isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
            color: colorScheme.primary,
          ),
        ),
        IconButton(
          onPressed: _playback.toggleShuffle,
          icon: Icon(
            isShuffled ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
            color: colorScheme.primary,
          ),
        ),
        IconButton(
          onPressed: _playback.cycleRepeatMode,
          icon: Icon(switch (repeatMode) {
            PlayerRepeatMode.off => Icons.repeat_rounded,
            PlayerRepeatMode.all => Icons.repeat_on_rounded,
            PlayerRepeatMode.one => Icons.repeat_one_on_rounded,
          }, color: colorScheme.primary),
        ),
        if (tracks.any(_isYoutube)) _buildDownloadAllButton(tracks),
      ],
    );
  }

  Widget _buildDownloadAllButton(List<Map<String, dynamic>> tracks) {
    final colorScheme = Theme.of(context).colorScheme;
    final downloads = context.watch<DownloadsProvider>();
    final youtube = tracks.where(_isYoutube).toList();
    final ids = youtube.map((t) => t['videoId'] as String).toList();
    final allDownloaded = ids.every(downloads.isDownloaded);
    final anyDownloading = ids.any(downloads.isDownloading);

    if (anyDownloading) {
      return IconButton(
        onPressed: downloads.cancelAllDownloads,
        icon: SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              Icon(
                Icons.stop_rounded,
                size: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }
    return IconButton(
      onPressed: allDownloaded
          ? null
          : () => downloads.downloadTracks([
              for (final t in youtube)
                {
                  'videoId': t['videoId'],
                  'songName': t['title'],
                  'artistName': t['artist'],
                  'artistId': t['artistId'],
                  'durationSeconds': _durationSecondsOf(t),
                },
            ]),
      icon: Icon(
        allDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
        color: colorScheme.primary,
      ),
    );
  }

  Widget _buildSearchAndSort() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            style: TextStyle(color: colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Search songs...',
              hintStyle: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
              filled: true,
              fillColor: colorScheme.onSurface.withValues(alpha: 0.26),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_MixedSort>(
          initialValue: _sort,
          onSelected: (value) => setState(() => _sort = value),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          icon: Icon(
            _sort == _MixedSort.custom
                ? Icons.sort_rounded
                : Icons.filter_list_rounded,
            color: _sort == _MixedSort.custom
                ? colorScheme.onSurfaceVariant
                : colorScheme.primary,
          ),
          itemBuilder: (context) => [
            for (final option in _MixedSort.values)
              PopupMenuItem(
                value: option,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: option == _sort
                      ? Icon(Icons.check_rounded, color: colorScheme.primary)
                      : const SizedBox(width: 24),
                  title: Text(option.label),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    int sourceIndex,
    Map<String, dynamic> track,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final playable = _isPlayable(track);
    final isCurrent =
        context.select<PlaybackModel, String?>((p) => p.currentSongPath) ==
        _expectedPath(track);
    final title = (track['title'] as String?) ?? 'Unknown song';
    final artist = (track['artist'] as String?) ?? '';
    final videoId = (track['videoId'] as String?) ?? '';
    final isYoutube = _isYoutube(track);
    var thumbnailUrl = (track['thumbnailUrl'] as String?) ?? '';
    if (thumbnailUrl.isEmpty && isYoutube) {
      thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }
    final durationSeconds = _durationSecondsOf(track);
    final downloads = context.watch<DownloadsProvider>();
    final likedSongs = context.watch<LikedSongsProvider>();
    final isDownloaded = isYoutube && downloads.isDownloaded(videoId);
    final isDownloading = isYoutube && downloads.isDownloading(videoId);
    final isLiked = isYoutube && likedSongs.isLiked(videoId);

    final subtitleStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(color: colorScheme.onSurfaceVariant);

    return ContextMenuRegion<String>(
      contextMenu: ContextMenu(
        borderRadius: BorderRadius.circular(12),
        entries: [
          if (playable) ...[
            MenuItem<String>(
              value: 'play_next',
              icon: const Icon(Icons.playlist_play_rounded),
              label: const Text('Play next'),
            ),
            MenuItem<String>(
              value: 'add_to_queue',
              icon: const Icon(Icons.queue_music_rounded),
              label: const Text('Add to queue'),
            ),
          ],
          MenuItem<String>(
            value: 'add_to_playlist',
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text('Add to playlist'),
          ),
          if (isYoutube) ...[
            MenuItem<String>(
              value: isDownloaded ? 'remove_download' : 'download',
              icon: Icon(
                isDownloaded
                    ? Icons.download_done_rounded
                    : Icons.download_rounded,
              ),
              label: Text(isDownloaded ? 'Remove download' : 'Download'),
            ),
            MenuItem<String>(
              value: 'edit_trim',
              icon: const Icon(Icons.content_cut_rounded),
              label: const Text('Edit song'),
            ),
            MenuItem<String>(
              value: 'share',
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share'),
            ),
          ],
          MenuItem<String>(
            value: 'remove_from_playlist',
            icon: const Icon(Icons.playlist_remove_rounded),
            label: const Text('Remove from playlist'),
          ),
        ],
      ),
      onItemSelected: (value) {
        switch (value) {
          case 'play_next':
            _playback.addToQueue(_queueItem(track));
          case 'add_to_queue':
            _playback.appendToQueue(_queueItem(track));
          case 'add_to_playlist':
            showAddSongsToPlaylistDialog(context, songs: [_songMap(track)]);
          case 'download':
            downloads.download(
              videoId: videoId,
              songName: title,
              artistName: artist,
              artistId: (track['artistId'] as String?) ?? '',
              durationSeconds: durationSeconds,
            );
          case 'remove_download':
            downloads.remove(videoId);
          case 'edit_trim':
            showEditSongDialog(
              context,
              videoId: videoId,
              title: title,
              artist: artist,
              thumbnailUrl: thumbnailUrl,
              durationSeconds: durationSeconds,
            );
          case 'share':
            ShareLinkService.shareSong(context, videoId);
          case 'remove_from_playlist':
            _removeTrack(sourceIndex);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            enabled: playable,
            leading: thumbnailUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      thumbnailUrl,
                      width: 56,
                      height: 56,
                      cacheWidth: 112,
                      cacheHeight: 112,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        _sourceIcon(track),
                        color: colorScheme.onSurface,
                      ),
                    ),
                  )
                : SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(
                      _sourceIcon(track),
                      color: colorScheme.onSurface,
                    ),
                  ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurface),
            ),
            subtitle: isYoutube
                ? ArtistLine(
                    videoId: videoId,
                    artist: artist.isEmpty ? 'Unknown artist' : artist,
                    title: title,
                    style: subtitleStyle,
                  )
                : Text(
                    '${artist.isEmpty ? '' : '$artist · '}${_sourceLabel(track)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isYoutube)
                  IconButton(
                    onPressed: () => likedSongs.toggleLike(_songMap(track)),
                    icon: Icon(
                      isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: isLiked
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                    splashRadius: 18,
                  ),
                const SizedBox(width: 4),
                if (_loadingIndex == sourceIndex)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (isDownloading)
                  IconButton(
                    onPressed: () => downloads.cancelDownload(videoId),
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    icon: SizedBox(
                      width: 18,
                      height: 18,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const CircularProgressIndicator(strokeWidth: 2),
                          Icon(
                            Icons.stop_rounded,
                            size: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    _formatDuration(durationSeconds),
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
            onTap: playable ? () => _playTrack(sourceIndex) : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_missing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This playlist no longer exists.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            TextButton(onPressed: widget.onBack, child: const Text('Back')),
          ],
        ),
      );
    }

    final tracks = _tracks;
    final visible = _visibleTracks;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: colorScheme.onSurface,
                ),
              ),
              Expanded(
                child: Text(
                  _title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildMenuButton(),
              IconButton(
                onPressed: _delete,
                icon: Icon(Icons.delete_rounded, color: colorScheme.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMetadataRow(tracks),
          if (tracks.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildControlButtons(tracks),
            const SizedBox(height: 8),
            _buildSearchAndSort(),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: tracks.isEmpty
                ? Center(
                    child: Text(
                      'No songs yet. Add songs from a YouTube playlist, '
                      'Google Drive or Local Files using "Add to playlist".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : visible.isEmpty
                ? Center(
                    child: Text(
                      'No songs match your search.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => Builder(
                      builder: (context) => _buildRow(
                        context,
                        visible[index].key,
                        visible[index].value,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
