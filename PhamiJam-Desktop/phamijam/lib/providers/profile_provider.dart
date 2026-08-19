import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:phamijam/models/grid_tile.dart';
import 'package:phamijam/models/user_profile.dart';
import 'package:phamijam/services/profile_service.dart';

class ProfileProvider extends ChangeNotifier {
  UserProfile profile = UserProfile.empty;
  bool isLoading = false;
  bool hasLoadedOnce = false;

  String get effectiveDisplayName =>
      profile.displayNameOverride?.trim().isNotEmpty == true
      ? profile.displayNameOverride!.trim()
      : (FirebaseAuth.instance.currentUser?.displayName ?? 'PhamiJam User');

  String? get effectivePhotoUrl => profile.avatarChoice == 'custom'
      ? profile.avatarUrl
      : FirebaseAuth.instance.currentUser?.photoURL;

  Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    isLoading = true;
    notifyListeners();
    try {
      profile = await ProfileService.fetchProfile(user.uid);
      await _backfillFromAuthIfNeeded(user);
    } catch (error) {
      debugPrint('ProfileProvider: refresh failed: $error');
    } finally {
      isLoading = false;
      hasLoadedOnce = true;
      notifyListeners();
    }
  }

  Future<void> _backfillFromAuthIfNeeded(User user) async {
    final needsName =
        (profile.displayNameOverride ?? '').trim().isEmpty &&
        (user.displayName ?? '').trim().isNotEmpty;
    final needsAvatarRefresh =
        profile.avatarChoice == 'google' &&
        (user.photoURL ?? '').trim().isNotEmpty &&
        profile.avatarUrl != user.photoURL;
    if (!needsName && !needsAvatarRefresh) return;
    await ProfileService.updateProfile(
      displayNameOverride: needsName ? user.displayName : null,
      avatarUrl: needsAvatarRefresh ? user.photoURL : null,
    );
    profile = profile.copyWith(
      displayNameOverride: needsName ? user.displayName : null,
      avatarUrl: needsAvatarRefresh ? user.photoURL : null,
    );
  }

  Future<void> updateProfile({
    String? displayNameOverride,
    String? bio,
    String? avatarChoice,
    String? avatarUrl,
  }) async {
    final previous = profile;
    profile = profile.copyWith(
      displayNameOverride: displayNameOverride,
      bio: bio,
      avatarChoice: avatarChoice,
      avatarUrl: avatarUrl,
    );
    notifyListeners();
    try {
      await ProfileService.updateProfile(
        displayNameOverride: displayNameOverride,
        bio: bio,
        avatarChoice: avatarChoice,
        avatarUrl: avatarUrl,
      );
    } catch (error) {
      profile = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setUsername(String username) async {
    final previous = profile;
    profile = profile.copyWith(username: username);
    notifyListeners();
    try {
      await ProfileService.claimUsername(username);
    } catch (error) {
      profile = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> saveGridLayout(List<GridTile> tiles) async {
    final previous = profile.gridLayout;
    profile = profile.copyWith(gridLayout: tiles);
    notifyListeners();
    try {
      await ProfileService.saveGridLayout(tiles);
    } catch (error) {
      profile = profile.copyWith(gridLayout: previous);
      notifyListeners();
      rethrow;
    }
  }
}
