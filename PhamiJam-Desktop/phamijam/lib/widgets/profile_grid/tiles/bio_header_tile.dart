import 'package:flutter/material.dart';
import 'package:phamijam/models/user_profile.dart';
import 'package:phamijam/services/profile_service.dart';

class BioHeaderTile extends StatelessWidget {
  const BioHeaderTile({super.key, required this.profileUid});

  final String profileUid;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile>(
      future: ProfileService.fetchProfile(profileUid),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? UserProfile.empty;
        final colorScheme = Theme.of(context).colorScheme;
        final displayName =
            (profile.displayNameOverride?.trim().isNotEmpty ?? false)
            ? profile.displayNameOverride!.trim()
            : 'PhamiJam User';
        final avatarUrl = profile.avatarUrl;

        return Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: colorScheme.primary,
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? Icon(Icons.person_rounded, color: colorScheme.onPrimary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if ((profile.bio ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        profile.bio!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
