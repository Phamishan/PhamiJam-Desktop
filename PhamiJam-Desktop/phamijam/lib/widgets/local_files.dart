import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:provider/provider.dart';

class LocalFilesPage extends StatefulWidget {
  const LocalFilesPage({super.key});

  @override
  State<LocalFilesPage> createState() => _LocalFilesPageState();
}

class _LocalFilesPageState extends State<LocalFilesPage> {
  static bool _hasScannedOnce = false;
  static String? _selectedFolderPath;
  static String? _cachedFolderPath;
  static List<String> _cachedArtistNames = [];
  static List<String> _cachedSongNames = [];
  static List<String> _cachedSongPaths = [];
  static List<Uint8List?> _cachedCoverImages = [];
  static List<int> _cachedSongDurations = [];

  bool _didInitialDependencySetup = false;
  bool _isLoadingPlaylists = false;
  final String _localFilesTitle = 'Local Files';

  List<String> artistName = [];
  List<String> songName = [];
  List<String> songPaths = [];
  List<Uint8List?> coverImages = [];
  List<int> songDurations = [];
  int _currentSongIndex = -1;
  late final PlaybackModel _playback;

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildMetadataRow() {
    final songCountLabel = songName.length.toString();
    final totalDurationSeconds = songDurations.fold<int>(
      0,
      (sum, seconds) => sum + seconds,
    );
    final durationLabel = _formatDuration(totalDurationSeconds);

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(
          '$songCountLabel songs',
          style: const TextStyle(color: Colors.white70),
        ),
        Text(durationLabel, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialDependencySetup) return;
    _didInitialDependencySetup = true;

    if (_hasScannedOnce && _cachedFolderPath == _selectedFolderPath) {
      setState(() {
        artistName = List<String>.from(_cachedArtistNames);
        songName = List<String>.from(_cachedSongNames);
        songPaths = List<String>.from(_cachedSongPaths);
        coverImages = List<Uint8List?>.from(_cachedCoverImages);
        songDurations = List<int>.from(_cachedSongDurations);
      });
      return;
    }

    _scanFilesPressed(forceRescan: true);
  }

  Directory? _resolveMusicDirectory() {
    if (_selectedFolderPath != null && _selectedFolderPath!.isNotEmpty) {
      return Directory(_selectedFolderPath!);
    }

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        return Directory('$userProfile\\Music');
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return Directory('$home/Music');
      }
    }

    return null;
  }

  Uint8List? _pickPreferredCover(List<Picture> pictures) {
    if (pictures.isEmpty) return null;
    for (final picture in pictures) {
      if (picture.pictureType == PictureType.coverFront) {
        return picture.bytes;
      }
    }
    return pictures.first.bytes;
  }

  Future<void> _scanFilesPressed({bool forceRescan = false}) async {
    if (!forceRescan &&
        _hasScannedOnce &&
        _cachedFolderPath == _selectedFolderPath) {
      if (!mounted) return;
      setState(() {
        songName = List<String>.from(_cachedSongNames);
        artistName = List<String>.from(_cachedArtistNames);
        songPaths = List<String>.from(_cachedSongPaths);
        coverImages = List<Uint8List?>.from(_cachedCoverImages);
        songDurations = List<int>.from(_cachedSongDurations);
      });
      return;
    }

    final musicDir = _resolveMusicDirectory();

    if (!mounted) return;
    setState(() {
      _isLoadingPlaylists = true;
    });

    if (musicDir == null || !await musicDir.exists()) {
      if (!mounted) return;
      setState(() {
        songName = [];
        artistName = [];
        songPaths = [];
        coverImages = [];
        songDurations = [];
        _isLoadingPlaylists = false;
      });

      _cachedSongNames = [];
      _cachedArtistNames = [];
      _cachedSongPaths = [];
      _cachedCoverImages = [];
      _cachedSongDurations = [];
      _cachedFolderPath = _selectedFolderPath;
      _hasScannedOnce = true;
      debugPrint('Music directory not found');
      return;
    }

    final List<File> mp3Files = [];
    try {
      for (final entity in musicDir.listSync(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.mp3')) {
          mp3Files.add(entity);
        }
      }
    } catch (e) {
      debugPrint('Failed to list files: $e');
    }

    final List<String> foundSongNames = [];
    final List<String> foundArtistNames = [];
    final List<String> foundSongPaths = [];
    final List<Uint8List?> foundCoverImages = [];
    final List<int> foundSongDurations = [];

    for (final file in mp3Files) {
      String currentTitle = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : file.path.split(Platform.pathSeparator).last;
      String currentArtist = 'Unknown Artist';
      Uint8List? currentCover;
      int currentDurationSeconds = 0;

      try {
        final metadata = readMetadata(file, getImage: true);
        if (metadata.title != null && metadata.title!.trim().isNotEmpty) {
          currentTitle = metadata.title!;
        }
        if (metadata.artist != null && metadata.artist!.trim().isNotEmpty) {
          currentArtist = metadata.artist!;
        }
        currentCover = _pickPreferredCover(metadata.pictures);
        currentDurationSeconds = metadata.duration?.inSeconds ?? 0;
      } catch (_) {
        // Ignore metadata read failures per-file.
      }

      foundSongNames.add(currentTitle);
      foundArtistNames.add(currentArtist);
      foundSongPaths.add(file.path);
      foundCoverImages.add(currentCover);
      foundSongDurations.add(currentDurationSeconds);
    }

    if (!mounted) return;

    setState(() {
      songName = foundSongNames;
      artistName = foundArtistNames;
      songPaths = foundSongPaths;
      coverImages = foundCoverImages;
      songDurations = foundSongDurations;
      _isLoadingPlaylists = false;
    });

    _cachedSongNames = List<String>.from(foundSongNames);
    _cachedArtistNames = List<String>.from(foundArtistNames);
    _cachedSongPaths = List<String>.from(foundSongPaths);
    _cachedCoverImages = List<Uint8List?>.from(foundCoverImages);
    _cachedSongDurations = List<int>.from(foundSongDurations);
    _cachedFolderPath = _selectedFolderPath;
    _hasScannedOnce = true;

    debugPrint('Found ${songName.length} songs in local files folder');
  }

  Future<void> _refreshSongs() async {
    await _scanFilesPressed(forceRescan: true);
  }

  Future<void> _chooseLocation() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose music folder',
    );

    if (!mounted || selectedPath == null || selectedPath.isEmpty) return;

    setState(() {
      _selectedFolderPath = selectedPath;
    });

    await _scanFilesPressed(forceRescan: true);
  }

  Future<void> _play([int? index]) async {
    final playback = _playback;
    final playIndex = index ?? 0;

    if (songPaths.isEmpty || playIndex >= songPaths.length) return;

    final songPath = songPaths[playIndex];
    final file = File(songPath);

    if (!await file.exists()) {
      debugPrint('File not found: $songPath');
      return;
    }

    await playback.switchToLocalEngine();
    playback.setDuration(Duration.zero);
    await player.setFilePath(file.path);
    await player.seek(Duration.zero);
    await player.play();

    playback.setArtist(artistName.isNotEmpty ? artistName[playIndex] : '');
    playback.setSongName(songName.isNotEmpty ? songName[playIndex] : '');
    playback.setCurrentSongPath(songPath);
    playback.setCoverImageBytes(
      playIndex < coverImages.length ? coverImages[playIndex] : null,
    );
    playback.setIsPlaying(true);
    playback.setIsMuted(false);
    _currentSongIndex = playIndex;
  }

  void _syncCurrentIndexFromPlaybackPath() {
    if (_currentSongIndex >= 0 || songPaths.isEmpty) return;

    final currentPath = _playback.currentSongPath;
    if (currentPath == null || currentPath.isEmpty) return;

    final resolvedIndex = songPaths.indexOf(currentPath);
    if (resolvedIndex >= 0) {
      _currentSongIndex = resolvedIndex;
    }
  }

  Future<void> _autoplayNextSong() async {
    if (!mounted || songPaths.isEmpty) return;

    _syncCurrentIndexFromPlaybackPath();
    if (_currentSongIndex < 0) return;

    final nextIndex = _currentSongIndex + 1;
    if (nextIndex >= songPaths.length) return;

    await _play(nextIndex);
  }

  Future<void> _playPreviousSong() async {
    if (!mounted || songPaths.isEmpty) return;

    _syncCurrentIndexFromPlaybackPath();
    if (_currentSongIndex <= 0) return;

    await _play(_currentSongIndex - 1);
  }

  Future<void> _playNextSong() async {
    await _autoplayNextSong();
  }

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackModel>();
    _playback.setOnPreviousRequested(_playPreviousSong);
    _playback.setOnNextRequested(_playNextSong);
  }

  @override
  void dispose() {
    _playback.setOnPreviousRequested(null);
    _playback.setOnNextRequested(null);
    super.dispose();
  }

  Widget _buildLocalFilesContent() {
    final playback = context.watch<PlaybackModel>();

    if (_isLoadingPlaylists) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _localFilesTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _refreshSongs,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _chooseLocation,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose Location'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _selectedFolderPath ?? 'No folder selected',
                style: const TextStyle(color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildMetadataRow(),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: songName.isEmpty
              ? const Center(
                  child: Text(
                    'No local .mp3 files found',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.builder(
                  itemCount: songName.length,
                  itemBuilder: (context, index) {
                    final artist = artistName[index];
                    final song = songName[index];
                    final coverBytes = index < coverImages.length
                        ? coverImages[index]
                        : null;
                    final durationSeconds = index < songDurations.length
                        ? songDurations[index]
                        : 0;
                    final songDurationLabel = _formatDuration(durationSeconds);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: playback.currentSongPath == songPaths[index]
                              ? const Color(0xFFb5832e)
                              : const Color(0xFFdba43a),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          leading: coverBytes != null && coverBytes.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    coverBytes,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.music_note,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.music_note,
                                  color: Colors.white,
                                ),
                          title: Text(
                            song,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            artist,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: Text(
                            songDurationLabel,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () => _play(index),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: _buildLocalFilesContent(),
    );
  }
}
