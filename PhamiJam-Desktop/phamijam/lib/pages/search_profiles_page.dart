import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/services/profile_service.dart';

class SearchProfilesPage extends StatefulWidget {
  const SearchProfilesPage({super.key, this.onTabSelected});

  final void Function(String, {Map<String, dynamic>? extra})? onTabSelected;

  @override
  State<SearchProfilesPage> createState() => _SearchProfilesPageState();
}

class _SearchProfilesPageState extends State<SearchProfilesPage> {
  final _controller = TextEditingController();
  List<ProfileSearchResult> _results = const [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(value),
    );
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await ProfileService.searchByUsername(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openProfile(String uid) {
    widget.onTabSelected?.call('friend_profile', extra: {'uid': uid});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find people',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Search by username',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _controller.text.trim().isEmpty
                    ? 'Search for a username to find people'
                    : 'No one found',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final result = _results[index];
                  final profile = result.profile;
                  final displayName =
                      (profile.displayNameOverride?.trim().isNotEmpty ??
                          false)
                      ? profile.displayNameOverride!.trim()
                      : 'PhamiJam User';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primary,
                      backgroundImage:
                          (profile.avatarUrl != null &&
                              profile.avatarUrl!.isNotEmpty)
                          ? NetworkImage(profile.avatarUrl!)
                          : null,
                      child:
                          (profile.avatarUrl == null ||
                              profile.avatarUrl!.isEmpty)
                          ? Icon(
                              Icons.person_rounded,
                              color: colorScheme.onPrimary,
                            )
                          : null,
                    ),
                    title: Text(displayName),
                    subtitle: (profile.username ?? '').isNotEmpty
                        ? Text('@${profile.username}')
                        : null,
                    onTap: () => _openProfile(result.uid),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
