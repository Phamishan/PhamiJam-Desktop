import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:phamijam/components/add_to_playlist_dialog.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/edit_song_dialog.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/youtube_data_service.dart';
import 'package:provider/provider.dart';
import 'package:ytmusicapi_dart/enums.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

Widget _wrapSongTileWithContextMenu({
  required BuildContext context,
  required Widget child,
  required String videoId,
  required String title,
  required String artist,
  required String thumbnailUrl,
  int durationSeconds = 0,
}) {
  return ContextMenuRegion<String>(
    contextMenu: ContextMenu(
      borderRadius: BorderRadius.circular(12),
      entries: [
        MenuItem<String>(
          value: 'play_next',
          icon: const Icon(Icons.playlist_play_rounded),
          label: const Text('Add to play next'),
        ),
        MenuItem<String>(
          value: 'add_to_playlist',
          icon: const Icon(Icons.playlist_add_rounded),
          label: const Text('Add to playlist'),
        ),
        MenuItem<String>(
          value: 'edit_trim',
          icon: const Icon(Icons.content_cut_rounded),
          label: const Text('Edit song'),
        ),
      ],
    ),
    onItemSelected: (value) {
      if (videoId.isEmpty) {
        AppFlushbar.error(context, 'This song is unavailable.');
        return;
      }
      if (value == 'play_next') {
        context.read<PlaybackModel>().addToQueue(<String, dynamic>{
          'title': title,
          'artist': artist,
          'videoId': videoId,
          'thumbnailUrl': thumbnailUrl,
        });
        AppFlushbar.info(context, '"$title" will play next.');
      } else if (value == 'add_to_playlist') {
        showAddToPlaylistDialog(context, videoId: videoId, songTitle: title);
      } else if (value == 'edit_trim') {
        showEditSongDialog(
          context,
          videoId: videoId,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          durationSeconds: durationSeconds,
        );
      }
    },
    child: child,
  );
}

Widget _buildSearchEngineToggle(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  final searchEngine = context.watch<SettingsProvider>().searchEngine;
  return Align(
    alignment: Alignment.centerLeft,
    child: SegmentedButton<SearchEngine>(
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
      selected: {searchEngine},
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
        foregroundColor: colorScheme.onSurfaceVariant,
        selectedBackgroundColor: colorScheme.primary,
        selectedForegroundColor: colorScheme.onPrimary,
      ),
      onSelectionChanged: (selection) =>
          context.read<SettingsProvider>().setSearchEngine(selection.first),
    ),
  );
}

typedef PlaySongCallback =
    Future<void> Function({
      required String videoId,
      required String title,
      required String artist,
      String thumbnailUrl,
      String artistId,
    });

typedef OpenArtistCallback = void Function(String artistId, String artistName);

typedef OpenAlbumCallback =
    void Function(
      String albumId,
      String albumTitle,
      String artistId,
      String artistName,
    );

class MusicSearchResultsPage extends StatefulWidget {
  const MusicSearchResultsPage({
    super.key,
    required this.query,
    required this.ytmusicFuture,
    required this.onBack,
    required this.onPlaySong,
    required this.onOpenArtist,
    required this.onOpenAlbum,
  });

  final String query;
  final Future<YTMusic> ytmusicFuture;
  final VoidCallback onBack;
  final PlaySongCallback onPlaySong;
  final OpenArtistCallback onOpenArtist;
  final OpenAlbumCallback onOpenAlbum;

  @override
  State<MusicSearchResultsPage> createState() => _MusicSearchResultsPageState();
}

class _MusicSearchResultsPageState extends State<MusicSearchResultsPage> {
  late Future<_SearchResultsData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadResults();
  }

  @override
  void didUpdateWidget(covariant MusicSearchResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _loadFuture = _loadResults();
    }
  }

  List<Map<String, dynamic>> _asMapList(List<dynamic> results) {
    return results
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<_SearchResultsData> _loadResults() async {
    final query = widget.query.trim();
    if (query.isEmpty) {
      return const _SearchResultsData();
    }

    final ytmusic = await widget.ytmusicFuture;
    final responses = await Future.wait([
      ytmusic.search(query, filter: SearchFilterType.songs, limit: 25),
      ytmusic.search(query, filter: SearchFilterType.artists, limit: 10),
      ytmusic.search(query, filter: SearchFilterType.albums, limit: 10),
    ]);

    return _SearchResultsData(
      songs: _asMapList(responses[0]),
      artists: _asMapList(responses[1]),
      albums: _asMapList(responses[2]),
    );
  }

  String _readString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _thumbnailUrl(Map<String, dynamic> item) {
    final direct = _readString(item['thumbnailUrl']);
    if (direct.isNotEmpty) return direct;

    final thumbnails = item['thumbnails'];
    if (thumbnails is List) {
      for (final thumbnail in thumbnails) {
        if (thumbnail is Map) {
          final url = _readString(thumbnail['url']);
          if (url.isNotEmpty) return url;
        }
      }
    }

    return '';
  }

  String _songArtistName(Map<String, dynamic> item) {
    final artists = item['artists'];
    if (artists is List && artists.isNotEmpty) {
      final firstArtist = artists.first;
      if (firstArtist is Map) {
        final name = _readString(firstArtist['name']);
        if (name.isNotEmpty) return name;
      }
    }

    return _readString(item['artist'], 'Unknown artist');
  }

  String? _songArtistId(Map<String, dynamic> item) {
    final artists = item['artists'];
    if (artists is List && artists.isNotEmpty) {
      final firstArtist = artists.first;
      if (firstArtist is Map) {
        final id = _readString(firstArtist['id']);
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  String? _songAlbumId(Map<String, dynamic> item) {
    final album = item['album'];
    if (album is Map) {
      final id = _readString(album['id']);
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  String _songAlbumTitle(Map<String, dynamic> item) {
    final album = item['album'];
    if (album is Map) {
      final name = _readString(album['name']);
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  Widget _buildCardShell({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Text('$count', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildSongTile(Map<String, dynamic> item) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _readString(item['title'], 'Unknown song');
    final artistName = _songArtistName(item);
    final artistId = _songArtistId(item);
    final albumTitle = _songAlbumTitle(item);
    final albumId = _songAlbumId(item);
    final videoId = _readString(item['videoId']);
    final thumbnailUrl = _thumbnailUrl(item);
    debugPrint("name$item");

    return _wrapSongTileWithContextMenu(
      context: context,
      videoId: videoId,
      title: title,
      artist: artistName,
      thumbnailUrl: thumbnailUrl,
      child: _buildCardShell(
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            leading: thumbnailUrl.isEmpty
                ? Icon(Icons.music_note_rounded, color: colorScheme.onSurface)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      thumbnailUrl,
                      width: 54,
                      height: 54,
                      cacheWidth: 108,
                      cacheHeight: 108,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.music_note_rounded,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    'Artist:',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  if (artistId != null && artistId.isNotEmpty)
                    _LinkLabel(
                      label: artistName,
                      onTap: () => widget.onOpenArtist(artistId, artistName),
                    )
                  else
                    Text(
                      artistName,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  if (albumId != null &&
                      albumId.isNotEmpty &&
                      albumTitle.isNotEmpty) ...[
                    Text(
                      'Album:',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    _LinkLabel(
                      label: albumTitle,
                      onTap: () => widget.onOpenAlbum(
                        albumId,
                        albumTitle,
                        artistId ?? '',
                        artistName,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: Icon(
              Icons.play_arrow_rounded,
              color: colorScheme.onSurface,
            ),
            onTap: videoId.isEmpty
                ? null
                : () => widget.onPlaySong(
                    videoId: videoId,
                    title: title,
                    artist: artistName,
                    thumbnailUrl: thumbnailUrl,
                    artistId: artistId ?? '',
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtistTile(Map<String, dynamic> item) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _readString(
      item['artist'],
      _readString(item['title'], 'Artist'),
    );
    final browseId = _readString(item['browseId']);
    final thumbnailUrl = _thumbnailUrl(item);
    final subtitle = _readString(item['category']);

    return _buildCardShell(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: thumbnailUrl.isEmpty
            ? Icon(Icons.person_rounded, color: colorScheme.onSurface)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  thumbnailUrl,
                  width: 54,
                  height: 54,
                  cacheWidth: 108,
                  cacheHeight: 108,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.person_rounded, color: colorScheme.onSurface),
                ),
              ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle.isEmpty ? 'Artist' : subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colorScheme.onSurface,
        ),
        onTap: browseId.isEmpty
            ? null
            : () => widget.onOpenArtist(browseId, title),
      ),
    );
  }

  Widget _buildAlbumTile(Map<String, dynamic> item) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _readString(item['title'], 'Album');
    final artistName = _songArtistName(item);
    final artistId = _songArtistId(item) ?? '';
    final browseId = _readString(item['browseId']);
    final thumbnailUrl = _thumbnailUrl(item);
    final year = _readString(item['year']);

    return _buildCardShell(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: thumbnailUrl.isEmpty
            ? Icon(Icons.album_rounded, color: colorScheme.onSurface)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  thumbnailUrl,
                  width: 54,
                  height: 54,
                  cacheWidth: 108,
                  cacheHeight: 108,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.album_rounded, color: colorScheme.onSurface),
                ),
              ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Row(
          children: [
            if (artistId.isNotEmpty)
              _LinkLabel(
                label: artistName,
                onTap: () => widget.onOpenArtist(artistId, artistName),
              )
            else
              Flexible(
                child: Text(
                  artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            if (year.isNotEmpty)
              Text(
                ' • $year',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colorScheme.onSurface,
        ),
        onTap: browseId.isEmpty
            ? null
            : () => widget.onOpenAlbum(browseId, title, artistId, artistName),
      ),
    );
  }

  Widget _buildSection<T>(
    String title,
    List<T> items,
    Widget Function(T) builder,
  ) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title, items.length),
        ...items.map(builder),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SearchResultsData>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final colorScheme = Theme.of(context).colorScheme;
        final query = widget.query.trim();

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to search "${query.isEmpty ? 'music' : query}": ${snapshot.error}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          );
        }

        final data = snapshot.data ?? const _SearchResultsData();
        final hasResults =
            data.songs.isNotEmpty ||
            data.artists.isNotEmpty ||
            data.albums.isNotEmpty;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      query.isEmpty ? 'Search' : 'Results for "$query"',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (!hasResults)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No songs, artists or albums matched that search.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else ...[
                _buildSection('Songs', data.songs, _buildSongTile),
                _buildSection('Artists', data.artists, _buildArtistTile),
                _buildSection('Albums', data.albums, _buildAlbumTile),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ArtistDetailsPage extends StatefulWidget {
  const ArtistDetailsPage({
    super.key,
    required this.artistId,
    required this.artistName,
    required this.ytmusicFuture,
    required this.onBack,
    required this.onPlaySong,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  final String artistId;
  final String artistName;
  final Future<YTMusic> ytmusicFuture;
  final VoidCallback onBack;
  final PlaySongCallback onPlaySong;
  final OpenAlbumCallback onOpenAlbum;
  final OpenArtistCallback onOpenArtist;

  @override
  State<ArtistDetailsPage> createState() => _ArtistDetailsPageState();
}

class _ArtistDetailsPageState extends State<ArtistDetailsPage> {
  late Future<_ArtistDetailsData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadArtist();
  }

  @override
  void didUpdateWidget(covariant ArtistDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistId != widget.artistId) {
      _loadFuture = _loadArtist();
    }
  }

  String _readString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _thumbnailUrl(Map<String, dynamic> item) {
    final direct = _readString(item['thumbnailUrl']);
    if (direct.isNotEmpty) return direct;

    final thumbnails = item['thumbnails'];
    if (thumbnails is List) {
      for (final thumbnail in thumbnails) {
        if (thumbnail is Map) {
          final url = _readString(thumbnail['url']);
          if (url.isNotEmpty) return url;
        }
      }
    }

    return '';
  }

  String _artistNameFromSong(Map<String, dynamic> item) {
    final artists = item['artists'];
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map) {
        final name = _readString(first['name']);
        if (name.isNotEmpty) return name;
      }
    }
    return widget.artistName;
  }

  String _albumTitleFromSong(Map<String, dynamic> item) {
    final album = item['album'];
    if (album is Map) {
      final name = _readString(album['name']);
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  String? _albumIdFromSong(Map<String, dynamic> item) {
    final album = item['album'];
    if (album is Map) {
      final id = _readString(album['id']);
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  String _artistIdFromSong(Map<String, dynamic> item) {
    final artists = item['artists'];
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map) {
        final id = _readString(first['id']);
        if (id.isNotEmpty) return id;
      }
    }
    return widget.artistId;
  }

  Future<_ArtistDetailsData> _loadArtist() async {
    final ytmusic = await widget.ytmusicFuture;
    final artist = Map<String, dynamic>.from(
      await ytmusic.getArtist(widget.artistId),
    );

    final songs = _asMapList(artist['songs']?['results']);
    final albumsSection = artist['albums'];
    final singlesSection = artist['singles'];
    final albums = <Map<String, dynamic>>[];
    final singles = <Map<String, dynamic>>[];

    if (albumsSection is Map) {
      final browseId = _readString(albumsSection['browseId']);
      final params = _readString(albumsSection['params']);
      if (browseId.isNotEmpty && params.isNotEmpty) {
        final results = await ytmusic.getArtistAlbums(
          browseId,
          params,
          limit: 12,
        );
        albums.addAll(
          results.whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      } else {
        albums.addAll(_asMapList(albumsSection['results']));
      }
    }

    if (singlesSection is Map) {
      final browseId = _readString(singlesSection['browseId']);
      final params = _readString(singlesSection['params']);
      if (browseId.isNotEmpty && params.isNotEmpty) {
        final results = await ytmusic.getArtistAlbums(
          browseId,
          params,
          limit: 12,
        );
        singles.addAll(
          results.whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      } else {
        singles.addAll(_asMapList(singlesSection['results']));
      }
    }

    return _ArtistDetailsData(
      artist: artist,
      songs: songs,
      albums: albums,
      singles: singles,
    );
  }

  Widget _buildCardShell({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildHeader(_ArtistDetailsData data) {
    final colorScheme = Theme.of(context).colorScheme;
    final description = _readString(data.artist['description']);
    final subscribers = _readString(data.artist['subscribers']);
    final views = _readString(data.artist['views']);
    final thumbnailUrl = _thumbnailUrl(data.artist);

    return _buildCardShell(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: thumbnailUrl.isEmpty
                  ? Container(
                      width: 96,
                      height: 96,
                      color: colorScheme.onSurface.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.person_rounded,
                        color: colorScheme.onSurface,
                      ),
                    )
                  : Image.network(
                      thumbnailUrl,
                      width: 96,
                      height: 96,
                      cacheWidth: 192,
                      cacheHeight: 192,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 96,
                        height: 96,
                        color: colorScheme.onSurface.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.person_rounded,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _readString(data.artist['name'], widget.artistName),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      if (subscribers.isNotEmpty)
                        Text(
                          subscribers,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      if (views.isNotEmpty)
                        Text(
                          views,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongTile(Map<String, dynamic> item) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _readString(item['title'], 'Unknown song');
    final artistName = _artistNameFromSong(item);
    final artistId = _artistIdFromSong(item);
    final albumTitle = _albumTitleFromSong(item);
    final albumId = _albumIdFromSong(item);
    final videoId = _readString(item['videoId']);
    final thumbnailUrl = _thumbnailUrl(item);

    return _wrapSongTileWithContextMenu(
      context: context,
      videoId: videoId,
      title: title,
      artist: artistName,
      thumbnailUrl: thumbnailUrl,
      child: _buildCardShell(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: thumbnailUrl.isEmpty
              ? Icon(Icons.music_note_rounded, color: colorScheme.onSurface)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    thumbnailUrl,
                    width: 54,
                    height: 54,
                    cacheWidth: 108,
                    cacheHeight: 108,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.music_note_rounded,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (artistId.isNotEmpty)
                  _LinkLabel(
                    label: artistName,
                    onTap: () => widget.onOpenArtist(artistId, artistName),
                  )
                else
                  Text(
                    artistName,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                if (albumId != null &&
                    albumId.isNotEmpty &&
                    albumTitle.isNotEmpty)
                  _LinkLabel(
                    label: albumTitle,
                    onTap: () => widget.onOpenAlbum(
                      albumId,
                      albumTitle,
                      artistId,
                      artistName,
                    ),
                  ),
              ],
            ),
          ),
          trailing: Icon(
            Icons.play_arrow_rounded,
            color: colorScheme.onSurface,
          ),
          onTap: videoId.isEmpty
              ? null
              : () => widget.onPlaySong(
                  videoId: videoId,
                  title: title,
                  artist: artistName,
                  thumbnailUrl: thumbnailUrl,
                  artistId: artistId,
                ),
        ),
      ),
    );
  }

  Widget _buildAlbumTile(Map<String, dynamic> item) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _readString(item['title'], 'Album');
    final artists = item['artists'];
    final artistName = (artists is List && artists.isNotEmpty)
        ? _readString((artists.first as Map?)?['name'], widget.artistName)
        : _readString(item['artist'], widget.artistName);
    final browseId = _readString(item['browseId']);
    final thumbnailUrl = _thumbnailUrl(item);
    final year = _readString(item['year']);

    return _buildCardShell(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: thumbnailUrl.isEmpty
            ? Icon(Icons.album_rounded, color: colorScheme.onSurface)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  thumbnailUrl,
                  width: 54,
                  height: 54,
                  cacheWidth: 108,
                  cacheHeight: 108,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.album_rounded, color: colorScheme.onSurface),
                ),
              ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          [artistName, if (year.isNotEmpty) year].join(' - '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colorScheme.onSurface,
        ),
        onTap: browseId.isEmpty
            ? null
            : () => widget.onOpenAlbum(
                browseId,
                title,
                widget.artistId,
                artistName,
              ),
      ),
    );
  }

  Widget _buildSection<T>(
    String title,
    List<T> items,
    Widget Function(T) builder,
  ) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title, items.length),
        ...items.map(builder),
      ],
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ArtistDetailsData>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final colorScheme = Theme.of(context).colorScheme;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load artist details: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return Center(
            child: Text(
              'Artist data is unavailable.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                      _readString(data.artist['name'], widget.artistName),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildHeader(data),
              const SizedBox(height: 14),
              _buildSearchEngineToggle(context),
              const SizedBox(height: 6),
              _buildSection('Songs', data.songs, _buildSongTile),
              _buildSection('Albums', data.albums, _buildAlbumTile),
              _buildSection('Singles', data.singles, _buildAlbumTile),
            ],
          ),
        );
      },
    );
  }
}

class AlbumDetailsPage extends StatefulWidget {
  const AlbumDetailsPage({
    super.key,
    required this.albumId,
    required this.albumTitle,
    required this.artistId,
    required this.artistName,
    required this.ytmusicFuture,
    required this.onBack,
    required this.onPlaySong,
    required this.onOpenArtist,
  });

  final String albumId;
  final String albumTitle;
  final String artistId;
  final String artistName;
  final Future<YTMusic> ytmusicFuture;
  final VoidCallback onBack;
  final PlaySongCallback onPlaySong;
  final OpenArtistCallback onOpenArtist;

  @override
  State<AlbumDetailsPage> createState() => _AlbumDetailsPageState();
}

class _AlbumDetailsPageState extends State<AlbumDetailsPage> {
  late Future<_AlbumDetailsData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadAlbum();
  }

  @override
  void didUpdateWidget(covariant AlbumDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumId != widget.albumId) {
      _loadFuture = _loadAlbum();
    }
  }

  String _readString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _thumbnailUrl(Map<String, dynamic> item) {
    final direct = _readString(item['thumbnailUrl']);
    if (direct.isNotEmpty) return direct;

    final thumbnails = item['thumbnails'];
    if (thumbnails is List) {
      for (final thumbnail in thumbnails) {
        if (thumbnail is Map) {
          final url = _readString(thumbnail['url']);
          if (url.isNotEmpty) return url;
        }
      }
    }

    return '';
  }

  String _artistNameFromTrack(Map<String, dynamic> item) {
    final artists = item['artists'];
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map) {
        final name = _readString(first['name']);
        if (name.isNotEmpty) return name;
      }
    }
    return widget.artistName;
  }

  String _artistIdFromTrack(Map<String, dynamic> item) {
    final artists = item['artists'];
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map) {
        final id = _readString(first['id']);
        if (id.isNotEmpty) return id;
      }
    }
    return widget.artistId;
  }

  String _artistIdFromAlbum(Map<String, dynamic> album) {
    final artists = album['artists'];
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map) {
        final id = _readString(first['id']);
        if (id.isNotEmpty) return id;
      }
    }
    return widget.artistId;
  }

  Future<_AlbumDetailsData> _loadAlbum() async {
    final ytmusic = await widget.ytmusicFuture;
    final album = Map<String, dynamic>.from(
      await ytmusic.getAlbum(widget.albumId),
    );
    final tracks = _asMapList(album['tracks']);
    return _AlbumDetailsData(album: album, tracks: tracks);
  }

  Widget _buildCardShell({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildHeader(_AlbumDetailsData data) {
    final colorScheme = Theme.of(context).colorScheme;
    final artistNames = <String>[];
    final artists = data.album['artists'];
    if (artists is List) {
      for (final artist in artists) {
        if (artist is Map) {
          final name = _readString(artist['name']);
          if (name.isNotEmpty) artistNames.add(name);
        }
      }
    }

    final thumbnailUrl = _thumbnailUrl(data.album);
    final year = _readString(data.album['year']);
    final description = _readString(data.album['description']);

    return _buildCardShell(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: thumbnailUrl.isEmpty
                  ? Container(
                      width: 96,
                      height: 96,
                      color: colorScheme.onSurface.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.album_rounded,
                        color: colorScheme.onSurface,
                      ),
                    )
                  : Image.network(
                      thumbnailUrl,
                      width: 96,
                      height: 96,
                      cacheWidth: 192,
                      cacheHeight: 192,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 96,
                        height: 96,
                        color: colorScheme.onSurface.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.album_rounded,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _readString(data.album['title'], widget.albumTitle),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      if (artistNames.isNotEmpty)
                        ...artistNames.map((artistName) {
                          final artistId = _artistIdFromAlbum(data.album);
                          return _LinkLabel(
                            label: artistName,
                            onTap: () =>
                                widget.onOpenArtist(artistId, artistName),
                          );
                        }),
                      if (year.isNotEmpty)
                        Text(
                          year,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackTile(Map<String, dynamic> item, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _readString(item['title'], 'Unknown song');
    final artistName = _artistNameFromTrack(item);
    final artistId = _artistIdFromTrack(item);
    final videoId = _readString(item['videoId']);
    final thumbnailUrl = _thumbnailUrl(item);
    final albumTitle = _readString(item['album'], widget.albumTitle);

    return _wrapSongTileWithContextMenu(
      context: context,
      videoId: videoId,
      title: title,
      artist: artistName,
      thumbnailUrl: thumbnailUrl,
      child: _buildCardShell(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: Text(
            '${index + 1}',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (artistId.isNotEmpty)
                  _LinkLabel(
                    label: artistName,
                    onTap: () => widget.onOpenArtist(artistId, artistName),
                  )
                else
                  Text(
                    artistName,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                if (albumTitle.isNotEmpty)
                  Text(
                    albumTitle,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          trailing: Icon(
            Icons.play_arrow_rounded,
            color: colorScheme.onSurface,
          ),
          onTap: videoId.isEmpty
              ? null
              : () => widget.onPlaySong(
                  videoId: videoId,
                  title: title,
                  artist: artistName,
                  thumbnailUrl: thumbnailUrl,
                  artistId: artistId,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AlbumDetailsData>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final colorScheme = Theme.of(context).colorScheme;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load album details: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return Center(
            child: Text(
              'Album data is unavailable.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                      _readString(data.album['title'], widget.albumTitle),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildHeader(data),
              if (data.tracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No playable tracks were found for this album.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 10),
                  child: Text(
                    'Songs (${data.tracks.length})',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...data.tracks.asMap().entries.map(
                  (entry) => _buildTrackTile(entry.value, entry.key),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LinkLabel extends StatelessWidget {
  const _LinkLabel({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colorScheme.onSurface,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _SearchResultsData {
  const _SearchResultsData({
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
  });

  final List<Map<String, dynamic>> songs;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> albums;
}

class _ArtistDetailsData {
  const _ArtistDetailsData({
    required this.artist,
    required this.songs,
    required this.albums,
    required this.singles,
  });

  final Map<String, dynamic> artist;
  final List<Map<String, dynamic>> songs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> singles;
}

class _AlbumDetailsData {
  const _AlbumDetailsData({required this.album, required this.tracks});

  final Map<String, dynamic> album;
  final List<Map<String, dynamic>> tracks;
}

class YoutubeChannelDetailsPage extends StatefulWidget {
  const YoutubeChannelDetailsPage({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.onBack,
    required this.onPlaySong,
  });

  final String channelId;
  final String channelName;
  final VoidCallback onBack;
  final PlaySongCallback onPlaySong;

  @override
  State<YoutubeChannelDetailsPage> createState() =>
      _YoutubeChannelDetailsPageState();
}

class _YoutubeChannelDetailsPageState extends State<YoutubeChannelDetailsPage> {
  late Future<_YoutubeChannelData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void didUpdateWidget(covariant YoutubeChannelDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) {
      _loadFuture = _load();
    }
  }

  Future<_YoutubeChannelData> _load() async {
    final results = await Future.wait([
      YoutubeDataService.fetchChannelInfo(widget.channelId),
      YoutubeDataService.fetchChannelVideos(widget.channelId, maxItems: 25),
    ]);
    return _YoutubeChannelData(
      channel: results[0] as Map<String, dynamic>?,
      videos: results[1] as List<Map<String, dynamic>>,
    );
  }

  String _formatSubscribers(String raw) {
    final value = int.tryParse(raw);
    if (value == null || raw.isEmpty) return raw;
    if (value >= 1000000) {
      final millions = value / 1000000;
      final rounded = millions.truncateToDouble() == millions ? 0 : 1;
      return '${millions.toStringAsFixed(rounded)}M subscribers';
    }
    if (value >= 1000) {
      final thousands = value / 1000;
      final rounded = thousands.truncateToDouble() == thousands ? 0 : 1;
      return '${thousands.toStringAsFixed(rounded)}K subscribers';
    }
    return '$value subscribers';
  }

  Widget _buildCardShell({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildHeader(Map<String, dynamic>? channel) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = (channel?['name'] as String?) ?? widget.channelName;
    final description = (channel?['description'] as String?) ?? '';
    final subscriberCount = (channel?['subscriberCount'] as String?) ?? '';
    final thumbnailUrl = (channel?['thumbnailUrl'] as String?) ?? '';

    return _buildCardShell(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: thumbnailUrl.isEmpty
                  ? Container(
                      width: 96,
                      height: 96,
                      color: colorScheme.onSurface.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.person_rounded,
                        color: colorScheme.onSurface,
                      ),
                    )
                  : Image.network(
                      thumbnailUrl,
                      width: 96,
                      height: 96,
                      cacheWidth: 192,
                      cacheHeight: 192,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 96,
                        height: 96,
                        color: colorScheme.onSurface.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.person_rounded,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subscriberCount.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _formatSubscribers(subscriberCount),
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoTile(Map<String, dynamic> item) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = (item['title'] as String?) ?? 'Unknown video';
    final artist = (item['artist'] as String?) ?? widget.channelName;
    final videoId = (item['videoId'] as String?) ?? '';
    final thumbnailUrl = (item['thumbnailUrl'] as String?) ?? '';

    return _wrapSongTileWithContextMenu(
      context: context,
      videoId: videoId,
      title: title,
      artist: artist,
      thumbnailUrl: thumbnailUrl,
      child: _buildCardShell(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: thumbnailUrl.isEmpty
              ? Icon(Icons.smart_display_rounded, color: colorScheme.onSurface)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    thumbnailUrl,
                    width: 54,
                    height: 54,
                    cacheWidth: 108,
                    cacheHeight: 108,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.smart_display_rounded,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Icon(
            Icons.play_arrow_rounded,
            color: colorScheme.onSurface,
          ),
          onTap: videoId.isEmpty
              ? null
              : () => widget.onPlaySong(
                  videoId: videoId,
                  title: title,
                  artist: artist,
                  thumbnailUrl: thumbnailUrl,
                  artistId: widget.channelId,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_YoutubeChannelData>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final colorScheme = Theme.of(context).colorScheme;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load this channel: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          );
        }

        final data = snapshot.data;
        final channel = data?.channel;
        final videos = data?.videos ?? const <Map<String, dynamic>>[];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                      (channel?['name'] as String?) ?? widget.channelName,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildHeader(channel),
              const SizedBox(height: 14),
              _buildSearchEngineToggle(context),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 10),
                child: Text(
                  'Videos (${videos.length})',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (videos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No videos found for this channel.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              else
                ...videos.map(_buildVideoTile),
            ],
          ),
        );
      },
    );
  }
}

class _YoutubeChannelData {
  const _YoutubeChannelData({required this.channel, required this.videos});

  final Map<String, dynamic>? channel;
  final List<Map<String, dynamic>> videos;
}

class YoutubeSearchResultsPage extends StatefulWidget {
  const YoutubeSearchResultsPage({
    super.key,
    required this.query,
    required this.onBack,
    required this.onPlaySong,
    required this.onOpenArtist,
  });

  final String query;
  final VoidCallback onBack;
  final PlaySongCallback onPlaySong;
  final OpenArtistCallback onOpenArtist;

  @override
  State<YoutubeSearchResultsPage> createState() =>
      _YoutubeSearchResultsPageState();
}

class _YoutubeSearchResultsPageState extends State<YoutubeSearchResultsPage> {
  late Future<List<Map<String, dynamic>>> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void didUpdateWidget(covariant YoutubeSearchResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _loadFuture = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() {
    final query = widget.query.trim();
    if (query.isEmpty) return Future.value(const []);
    return YoutubeDataService.searchVideos(query, maxResults: 25);
  }

  Widget _buildCardShell({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildVideoTile(Map<String, dynamic> item) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = (item['title'] as String?) ?? 'Unknown video';
    final artist = (item['artist'] as String?) ?? 'YouTube';
    final artistId = (item['artistId'] as String?) ?? '';
    final videoId = (item['videoId'] as String?) ?? '';
    final thumbnailUrl = (item['thumbnailUrl'] as String?) ?? '';

    return _wrapSongTileWithContextMenu(
      context: context,
      videoId: videoId,
      title: title,
      artist: artist,
      thumbnailUrl: thumbnailUrl,
      child: _buildCardShell(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: thumbnailUrl.isEmpty
              ? Icon(Icons.smart_display_rounded, color: colorScheme.onSurface)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    thumbnailUrl,
                    width: 54,
                    height: 54,
                    cacheWidth: 108,
                    cacheHeight: 108,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.smart_display_rounded,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  'Channel:',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                if (artistId.isNotEmpty)
                  _LinkLabel(
                    label: artist,
                    onTap: () => widget.onOpenArtist(artistId, artist),
                  )
                else
                  Text(artist, style: TextStyle(color: colorScheme.onSurface)),
              ],
            ),
          ),
          trailing: Icon(
            Icons.play_arrow_rounded,
            color: colorScheme.onSurface,
          ),
          onTap: videoId.isEmpty
              ? null
              : () => widget.onPlaySong(
                  videoId: videoId,
                  title: title,
                  artist: artist,
                  thumbnailUrl: thumbnailUrl,
                  artistId: artistId,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final colorScheme = Theme.of(context).colorScheme;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to search YouTube: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          );
        }

        final videos = snapshot.data ?? const <Map<String, dynamic>>[];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                      'Results for "${widget.query}"',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (videos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No results found.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              else
                ...videos.map(_buildVideoTile),
            ],
          ),
        );
      },
    );
  }
}
