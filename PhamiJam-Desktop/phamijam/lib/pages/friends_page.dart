import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/friend.dart';
import 'package:phamijam/models/friend_request.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:provider/provider.dart';

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key, this.onTabSelected});

  final void Function(String, {Map<String, dynamic>? extra})? onTabSelected;

  void _openFriendProfile(String uid) {
    onTabSelected?.call('friend_profile', extra: {'uid': uid});
  }

  @override
  Widget build(BuildContext context) {
    final friendsProvider = context.watch<FriendsProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: !friendsProvider.hasLoadedOnce
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Friends',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: 'Requests received',
                    children: friendsProvider.received
                        .map((r) => _ReceivedRequestTile(request: r))
                        .toList(),
                  ),
                  _Section(
                    title: 'Requests sent',
                    children: friendsProvider.sent
                        .map((r) => _SentRequestTile(request: r))
                        .toList(),
                  ),
                  _Section(
                    children: friendsProvider.friends.isEmpty
                        ? [
                            const _EmptyHint(
                              text:
                                  "You don't have any friends yet - share "
                                  'your profile link from the Profile page '
                                  'to add some.',
                            ),
                          ]
                        : friendsProvider.friends
                              .map(
                                (f) => _FriendTile(
                                  friend: f,
                                  onTap: () => _openFriendProfile(f.uid),
                                ),
                              )
                              .toList(),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
          ],
          ...children,
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: colorScheme.primary,
      backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
          ? NetworkImage(photoUrl!)
          : null,
      child: (photoUrl == null || photoUrl!.isEmpty)
          ? Icon(Icons.person_rounded, color: colorScheme.onPrimary)
          : null,
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: TextStyle(color: colorScheme.onSurfaceVariant)),
    );
  }
}

class _ReceivedRequestTile extends StatefulWidget {
  const _ReceivedRequestTile({required this.request});

  final FriendRequest request;

  @override
  State<_ReceivedRequestTile> createState() => _ReceivedRequestTileState();
}

class _ReceivedRequestTileState extends State<_ReceivedRequestTile> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    final provider = context.read<FriendsProvider>();
    try {
      if (accept) {
        await provider.acceptFriendRequest(widget.request);
      } else {
        await provider.declineFriendRequest(widget.request.otherUid);
      }
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't respond to request: $error");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Avatar(photoUrl: widget.request.otherPhotoUrl),
      title: Text(widget.request.otherDisplayName),
      subtitle: const Text('Wants to be friends'),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded),
                  color: Colors.green,
                  onPressed: () => _respond(true),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_rounded),
                  onPressed: () => _respond(false),
                ),
              ],
            ),
    );
  }
}

class _SentRequestTile extends StatefulWidget {
  const _SentRequestTile({required this.request});

  final FriendRequest request;

  @override
  State<_SentRequestTile> createState() => _SentRequestTileState();
}

class _SentRequestTileState extends State<_SentRequestTile> {
  bool _busy = false;

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await context.read<FriendsProvider>().cancelSentRequest(
        widget.request.otherUid,
      );
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't cancel request: $error");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Avatar(photoUrl: widget.request.otherPhotoUrl),
      title: Text(widget.request.otherDisplayName),
      subtitle: const Text('Request sent'),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(onPressed: _cancel, child: const Text('Cancel')),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend, required this.onTap});

  final Friend friend;
  final VoidCallback onTap;

  Future<void> _unfriend(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          'You and ${friend.displayName} will no longer be friends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<FriendsProvider>().unfriend(friend.uid);
    } catch (error) {
      if (context.mounted) {
        AppFlushbar.error(context, "Couldn't remove friend: $error");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Avatar(photoUrl: friend.photoUrl),
      title: Text(friend.displayName),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        tooltip: '',
        onSelected: (value) {
          if (value == 'unfriend') _unfriend(context);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'unfriend', child: Text('Remove friend')),
        ],
      ),
    );
  }
}
