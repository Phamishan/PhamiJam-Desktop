import 'package:flutter/material.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/services/youtube_channel_service.dart';

class _RecentArtist {
  final String channelId;
  final String name;

  const _RecentArtist({required this.channelId, required this.name});
}

List<_RecentArtist> _distinctArtists(List<PlayEvent> events, int max) {
  final seen = <String>{};
  final artists = <_RecentArtist>[];
  for (final event in events) {
    final channelId = event.channelId;
    if (channelId == null || channelId.isEmpty) continue;
    if (!seen.add(channelId)) continue;
    artists.add(_RecentArtist(channelId: channelId, name: event.artist));
    if (artists.length >= max) break;
  }
  return artists;
}

class RecentArtistsRow extends StatefulWidget {
  final List<PlayEvent> events;
  final void Function(String channelId, String artistName) onOpenArtist;
  final int maxArtists;

  const RecentArtistsRow({
    super.key,
    required this.events,
    required this.onOpenArtist,
    this.maxArtists = 5,
  });

  @override
  State<RecentArtistsRow> createState() => _RecentArtistsRowState();
}

class _RecentArtistsRowState extends State<RecentArtistsRow> {
  late List<_RecentArtist> _artists;
  Map<String, ChannelInfo> _channels = {};

  @override
  void initState() {
    super.initState();
    _artists = _distinctArtists(widget.events, widget.maxArtists);
    _loadChannels();
  }

  @override
  void didUpdateWidget(covariant RecentArtistsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events == widget.events) return;
    final artists = _distinctArtists(widget.events, widget.maxArtists);
    if (artists.map((a) => a.channelId).join() ==
        _artists.map((a) => a.channelId).join()) {
      return;
    }
    setState(() => _artists = artists);
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    if (_artists.isEmpty) return;
    try {
      final channels = await YoutubeChannelService.fetchChannelsInfo(
        _artists.map((a) => a.channelId).toList(),
      );
      if (!mounted) return;
      setState(() => _channels = channels);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_artists.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _artists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final artist = _artists[index];
          final channel = _channels[artist.channelId];
          return _RecentArtistCard(
            name: channel?.name ?? artist.name,
            thumbnailUrl: channel?.thumbnailUrl ?? '',
            onTap: () => widget.onOpenArtist(artist.channelId, artist.name),
          );
        },
      ),
    );
  }
}

class _RecentArtistCard extends StatefulWidget {
  final String name;
  final String thumbnailUrl;
  final VoidCallback onTap;

  const _RecentArtistCard({
    required this.name,
    required this.thumbnailUrl,
    required this.onTap,
  });

  @override
  State<_RecentArtistCard> createState() => _RecentArtistCardState();
}

class _RecentArtistCardState extends State<_RecentArtistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 148,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovering
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: widget.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        widget.thumbnailUrl,
                        width: 108,
                        height: 108,
                        cacheWidth: 216,
                        cacheHeight: 216,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 108,
                          height: 108,
                          color: colorScheme.surfaceContainerHigh,
                          child: Icon(
                            Icons.person_rounded,
                            color: colorScheme.onSurface,
                            size: 44,
                          ),
                        ),
                      )
                    : Container(
                        width: 108,
                        height: 108,
                        color: colorScheme.surfaceContainerHigh,
                        child: Icon(
                          Icons.person_rounded,
                          color: colorScheme.onSurface,
                          size: 44,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
