import 'package:phamijam/models/grid_tile.dart';

class UserProfile {
  final String? displayNameOverride;
  final String? username;
  final String? bio;
  final String avatarChoice;
  final String? avatarUrl;
  final int gridLayoutVersion;
  final List<GridTile> gridLayout;

  const UserProfile({
    this.displayNameOverride,
    this.username,
    this.bio,
    this.avatarChoice = 'google',
    this.avatarUrl,
    this.gridLayoutVersion = 1,
    this.gridLayout = const [],
  });

  static const empty = UserProfile();

  Map<String, dynamic> toMap() => {
    'displayNameOverride': displayNameOverride,
    'username': username,
    'bio': bio,
    'avatarChoice': avatarChoice,
    'avatarUrl': avatarUrl,
    'gridLayoutVersion': gridLayoutVersion,
    'gridLayout': gridLayout.map((tile) => tile.toMap()).toList(),
  };

  static UserProfile fromMap(dynamic raw) {
    if (raw is! Map) return empty;
    final rawTiles = raw['gridLayout'];
    final tiles = rawTiles is List
        ? rawTiles.map(GridTile.fromMap).whereType<GridTile>().toList()
        : <GridTile>[];
    return UserProfile(
      displayNameOverride: raw['displayNameOverride'] as String?,
      username: raw['username'] as String?,
      bio: raw['bio'] as String?,
      avatarChoice: raw['avatarChoice'] as String? ?? 'google',
      avatarUrl: raw['avatarUrl'] as String?,
      gridLayoutVersion: raw['gridLayoutVersion'] as int? ?? 1,
      gridLayout: tiles,
    );
  }

  UserProfile copyWith({
    String? displayNameOverride,
    String? username,
    String? bio,
    String? avatarChoice,
    String? avatarUrl,
    List<GridTile>? gridLayout,
  }) => UserProfile(
    displayNameOverride: displayNameOverride ?? this.displayNameOverride,
    username: username ?? this.username,
    bio: bio ?? this.bio,
    avatarChoice: avatarChoice ?? this.avatarChoice,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    gridLayoutVersion: gridLayoutVersion,
    gridLayout: gridLayout ?? this.gridLayout,
  );
}
