import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/friend_request.dart';
import 'package:phamijam/models/user_profile.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:phamijam/widgets/profile.dart';
import 'package:phamijam/widgets/profile_grid/profile_grid_view.dart';
import 'package:provider/provider.dart';

class FriendProfilePage extends StatelessWidget {
  const FriendProfilePage({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const SizedBox.shrink();
    if (uid == FirebaseAuth.instance.currentUser?.uid) {
      return const ProfilePage();
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<UserProfile>(
        future: ProfileService.fetchProfile(uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data!;
          final displayName =
              (profile.displayNameOverride?.trim().isNotEmpty ?? false)
              ? profile.displayNameOverride!.trim()
              : 'PhamiJam User';

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FriendHeader(profile: profile, displayName: displayName),
                const SizedBox(height: 12),
                _RelationshipActionRow(
                  uid: uid,
                  displayName: displayName,
                  photoUrl: profile.avatarUrl,
                ),
                const SizedBox(height: 16),
                if (profile.gridLayout.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "$displayName hasn't set up their profile yet.",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  ProfileGridView(
                    profileUid: uid,
                    editable: false,
                    tiles: profile.gridLayout,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FriendHeader extends StatelessWidget {
  const _FriendHeader({required this.profile, required this.displayName});

  final UserProfile profile;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarUrl = profile.avatarUrl;
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: colorScheme.primary,
          backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
              ? NetworkImage(avatarUrl)
              : null,
          child: (avatarUrl == null || avatarUrl.isEmpty)
              ? Icon(
                  Icons.person_rounded,
                  color: colorScheme.onPrimary,
                  size: 28,
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              if ((profile.bio ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  profile.bio!.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RelationshipActionRow extends StatefulWidget {
  const _RelationshipActionRow({
    required this.uid,
    required this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;

  @override
  State<_RelationshipActionRow> createState() => _RelationshipActionRowState();
}

class _RelationshipActionRowState extends State<_RelationshipActionRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String errorMessage) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) AppFlushbar.error(context, '$errorMessage: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final friendsProvider = context.watch<FriendsProvider>();

    if (friendsProvider.isFriend(widget.uid)) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Friends'),
      );
    }

    if (friendsProvider.hasReceivedRequestFrom(widget.uid)) {
      final request = friendsProvider.received.firstWhere(
        (r) => r.otherUid == widget.uid,
        orElse: () => FriendRequest(
          otherUid: widget.uid,
          otherDisplayName: widget.displayName,
          otherPhotoUrl: widget.photoUrl,
        ),
      );
      return Row(
        children: [
          FilledButton(
            onPressed: () => _run(
              () =>
                  context.read<FriendsProvider>().acceptFriendRequest(request),
              "Couldn't accept request",
            ),
            child: const Text('Accept'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _run(
              () => context.read<FriendsProvider>().declineFriendRequest(
                widget.uid,
              ),
              "Couldn't decline request",
            ),
            child: const Text('Decline'),
          ),
        ],
      );
    }

    if (friendsProvider.hasSentRequestTo(widget.uid)) {
      return OutlinedButton(
        onPressed: () => _run(
          () => context.read<FriendsProvider>().cancelSentRequest(widget.uid),
          "Couldn't cancel request",
        ),
        child: const Text('Request sent · Cancel'),
      );
    }

    return FilledButton.icon(
      onPressed: () => _run(
        () => context.read<FriendsProvider>().sendFriendRequest(
          widget.uid,
          toDisplayName: widget.displayName,
          toPhotoUrl: widget.photoUrl,
        ),
        "Couldn't send friend request",
      ),
      icon: const Icon(Icons.person_add_rounded),
      label: const Text('Add Friend'),
    );
  }
}
