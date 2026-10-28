import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/models/friend_activity_item.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/services/friend_activity_service.dart';
import 'package:provider/provider.dart';

class FriendActivityPage extends StatefulWidget {
  const FriendActivityPage({super.key, this.onTabSelected});

  final void Function(String, {Map<String, dynamic>? extra})? onTabSelected;

  @override
  State<FriendActivityPage> createState() => _FriendActivityPageState();
}

class _FriendActivityPageState extends State<FriendActivityPage> {
  List<FriendActivityItem>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final friends = context.read<FriendsProvider>().friends;
      final items = await FriendActivityService.fetchFeed(friends);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load activity.";
        _loading = false;
      });
    }
  }

  Future<Uint8List?> _downloadImageBytes(String imageUrl) async {
    if (imageUrl.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<void> _play(FriendActivityItem item) async {
    final event = item.event;
    if (event.videoId.isEmpty) return;
    final playback = context.read<PlaybackModel>();
    try {
      final cover = await _downloadImageBytes(event.thumbnailUrl);
      playback.setSongName(event.title.isEmpty ? 'Unknown song' : event.title);
      playback.setArtist(event.artist.isEmpty ? 'Unknown artist' : event.artist);
      playback.setArtistId(null);
      playback.setCurrentSongPath('yt:${event.videoId}');
      playback.setCoverImageBytes(cover);
      await playback.playYouTubeVideoById(event.videoId);
    } catch (error) {
      if (mounted) AppFlushbar.error(context, "Couldn't play this song.");
    }
  }

  void _openFriendProfile(String uid) {
    widget.onTabSelected?.call('friend_profile', extra: {'uid': uid});
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Activity',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loading ? null : _refresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: colorScheme.onSurfaceVariant)),
      );
    }
    final items = _items ?? const [];
    if (items.isEmpty) {
      return Center(
        child: Text(
          "No recent activity from friends.\nActivity shows up here when "
          "friends listen to music and haven't turned it off.",
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = items[index];
        return _FriendActivityTile(
          item: item,
          relativeTime: _relativeTime(item.event.startedAt),
          onPlay: () => _play(item),
          onOpenProfile: () => _openFriendProfile(item.friend.uid),
        );
      },
    );
  }
}

class _FriendActivityTile extends StatelessWidget {
  const _FriendActivityTile({
    required this.item,
    required this.relativeTime,
    required this.onPlay,
    required this.onOpenProfile,
  });

  final FriendActivityItem item;
  final String relativeTime;
  final VoidCallback onPlay;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final friend = item.friend;
    final event = item.event;

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              GestureDetector(
                onTap: onOpenProfile,
                child: CircleAvatar(
                  backgroundColor: colorScheme.primary,
                  backgroundImage:
                      (friend.photoUrl != null && friend.photoUrl!.isNotEmpty)
                      ? NetworkImage(friend.photoUrl!)
                      : null,
                  child: (friend.photoUrl == null || friend.photoUrl!.isEmpty)
                      ? Icon(Icons.person_rounded, color: colorScheme.onPrimary)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${friend.displayName} listened to',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${event.title}${event.artist.isEmpty ? '' : ' · ${event.artist}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: event.thumbnailUrl.isEmpty
                      ? Container(color: colorScheme.surfaceContainerHigh)
                      : Image.network(
                          event.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: colorScheme.surfaceContainerHigh),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                relativeTime,
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
