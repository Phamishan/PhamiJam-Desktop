import 'package:flutter/foundation.dart';
import 'package:phamijam/models/friend.dart';
import 'package:phamijam/models/friend_activity_item.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/profile_service.dart';

class FriendActivityService {
  FriendActivityService._();

  static const Duration _window = Duration(days: 3);
  static const int _perFriendLimit = 5;
  static const int _feedLimit = 50;

  static Future<List<FriendActivityItem>> fetchFeed(
    List<Friend> friends,
  ) async {
    if (friends.isEmpty) return [];
    final since = DateTime.now().subtract(_window);

    final perFriendResults = await Future.wait(
      friends.map((friend) => _fetchForFriend(friend, since)),
    );

    final items = perFriendResults.expand((list) => list).toList()
      ..sort((a, b) => b.event.startedAt.compareTo(a.event.startedAt));

    return items.length > _feedLimit ? items.sublist(0, _feedLimit) : items;
  }

  static Future<List<FriendActivityItem>> _fetchForFriend(
    Friend friend,
    DateTime since,
  ) async {
    try {
      final profile = await ProfileService.fetchProfile(friend.uid);
      if (!profile.showActivityEnabled) return const [];

      final events = await ListeningHistoryService.eventsSinceForUid(
        friend.uid,
        since,
      );
      final recent = events.reversed.take(_perFriendLimit);
      return recent
          .map((event) => FriendActivityItem(friend: friend, event: event))
          .toList();
    } catch (error) {
      debugPrint('FriendActivityService: failed to fetch ${friend.uid}: $error');
      return const [];
    }
  }
}
