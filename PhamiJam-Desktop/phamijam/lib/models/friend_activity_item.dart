import 'package:phamijam/models/friend.dart';
import 'package:phamijam/models/play_event.dart';

class FriendActivityItem {
  final Friend friend;
  final PlayEvent event;

  const FriendActivityItem({required this.friend, required this.event});
}
