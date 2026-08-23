import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/pages/jamstats_page.dart';
import 'package:phamijam/providers/profile_grid_provider.dart';
import 'package:phamijam/providers/profile_provider.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:phamijam/services/share_link_service.dart';
import 'package:phamijam/widgets/profile_grid/profile_grid_view.dart';
import 'package:provider/provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onTabSelected});

  final void Function(String, {Map<String, dynamic>? extra})? onTabSelected;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ProfileGridProvider? _gridProvider;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    context.read<ProfileProvider>().refresh();
  }

  void _openPlaylist(String playlistId, String title, String? thumbnailUrl) {
    widget.onTabSelected?.call(
      'playlist_inspect',
      extra: {
        'playlistId': playlistId,
        'playlistTitle': title,
        'thumbnailUrl': thumbnailUrl,
      },
    );
  }

  @override
  void dispose() {
    _gridProvider?.dispose();
    super.dispose();
  }

  void _startEdit(ProfileProvider profileProvider) {
    setState(() {
      _gridProvider = ProfileGridProvider(profileProvider.profile.gridLayout);
    });
  }

  void _cancelEdit() {
    _gridProvider?.dispose();
    setState(() => _gridProvider = null);
  }

  Future<void> _saveEdit() async {
    final gridProvider = _gridProvider;
    if (gridProvider == null) return;
    setState(() => _saving = true);
    try {
      await context.read<ProfileProvider>().saveGridLayout(gridProvider.tiles);
      if (!mounted) return;
      gridProvider.dispose();
      setState(() {
        _gridProvider = null;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFlushbar.error(context, "Couldn't save your layout: $error");
    }
  }

  Future<void> _editInfo(ProfileProvider profileProvider) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EditProfileDialog(profileProvider: profileProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final profileProvider = context.watch<ProfileProvider>();
    if (uid == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final gridProvider = _gridProvider;
    final editing = gridProvider != null;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Profile',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (editing) ...[
                  TextButton(
                    onPressed: _cancelEdit,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _saving ? null : _saveEdit,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Done'),
                  ),
                ] else
                  IconButton(
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => ShareLinkService.shareProfile(
                      context,
                      uid,
                      username: profileProvider.profile.username,
                      subject:
                          '${profileProvider.effectiveDisplayName} on PhamiJam',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!editing) ...[
              _ProfileHeader(
                profileProvider: profileProvider,
                onEdit: () => _editInfo(profileProvider),
              ),
              const SizedBox(height: 12),
              _JamstatsCard(),
              const SizedBox(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your profile',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!editing)
                  TextButton.icon(
                    onPressed: () => _startEdit(profileProvider),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit layout'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!editing && !profileProvider.hasLoadedOnce)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!editing && profileProvider.profile.gridLayout.isEmpty)
              _EmptyGridHint(onEdit: () => _startEdit(profileProvider))
            else
              ProfileGridView(
                profileUid: uid,
                editable: editing,
                tiles: editing ? null : profileProvider.profile.gridLayout,
                gridProvider: gridProvider,
                onOpenPlaylist: _openPlaylist,
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profileProvider, required this.onEdit});

  final ProfileProvider profileProvider;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final profile = profileProvider.profile;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: colorScheme.primary,
            backgroundImage: profileProvider.effectivePhotoUrl != null
                ? NetworkImage(profileProvider.effectivePhotoUrl!)
                : null,
            child: profileProvider.effectivePhotoUrl == null
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
                  profileProvider.effectiveDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if ((profile.username ?? '').trim().isNotEmpty)
                  Text(
                    '@${profile.username}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                if ((profile.bio ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.bio!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.edit_rounded), onPressed: onEdit),
        ],
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.profileProvider});

  final ProfileProvider profileProvider;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  String? _usernameError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profileProvider.profile;
    _nameController = TextEditingController(
      text: profile.displayNameOverride ?? '',
    );
    _usernameController = TextEditingController(text: profile.username ?? '');
    _bioController = TextEditingController(text: profile.bio ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _usernameError = null;
    });

    final newUsername = _usernameController.text.trim().toLowerCase();
    final currentUsername = widget.profileProvider.profile.username ?? '';
    if (newUsername.isNotEmpty && newUsername != currentUsername) {
      if (!ProfileService.usernamePattern.hasMatch(newUsername)) {
        setState(() {
          _saving = false;
          _usernameError =
              '3-20 characters: lowercase letters, numbers, underscore. '
              'Must start with a letter.';
        });
        return;
      }
      try {
        await widget.profileProvider.setUsername(newUsername);
      } on UsernameTakenException {
        setState(() {
          _saving = false;
          _usernameError = 'That username is already taken.';
        });
        return;
      } catch (error) {
        setState(() {
          _saving = false;
          _usernameError = "Couldn't save username: $error";
        });
        return;
      }
    }

    try {
      await widget.profileProvider.updateProfile(
        displayNameOverride: _nameController.text.trim(),
        bio: _bioController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        AppFlushbar.error(context, "Couldn't save profile info: $error");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Display name'),
              maxLength: 40,
            ),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                helperText:
                    'Optional - gives you a shareable link like '
                    'phamijam-share.workers.dev/u/yourname',
                helperMaxLines: 2,
                errorText: _usernameError,
                errorMaxLines: 2,
              ),
              maxLength: 20,
            ),
            TextField(
              controller: _bioController,
              decoration: const InputDecoration(labelText: 'Bio'),
              maxLength: 120,
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _JamstatsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Jamstats ✨',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your year in PhamiJam, wrapped. Stats sync across '
            'desktop and mobile.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const JamstatsPage())),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Open Jamstats ✨'),
            style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _EmptyGridHint extends StatelessWidget {
  const _EmptyGridHint({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your profile is empty',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Click "Edit layout" to add your bio, featured playlists, and more.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onEdit,
            child: const Text('Edit layout'),
          ),
        ],
      ),
    );
  }
}
