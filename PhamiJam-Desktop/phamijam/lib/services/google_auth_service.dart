import 'dart:convert';

import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GoogleAuthService {
  GoogleAuthService._();

  static const String _youtubeScope = 'https://www.googleapis.com/auth/youtube';

  static final GoogleSignIn googleSignIn = GoogleSignIn(
    params: GoogleSignInParams(
      clientId: dotenv.env['CLIENT_ID'],
      clientSecret: dotenv.env['CLIENT_SECRET'],
      scopes: [
        'openid',
        'profile',
        'email',
        'https://www.googleapis.com/auth/youtube',
      ],
    ),
  );

  static String? _accessToken;
  static GoogleSignInCredentials? _credentials;

  static String? get accessToken => _accessToken;

  static bool _isAccessTokenUsable(String? token, DateTime? expiresIn) {
    if (token == null || token.isEmpty) {
      return false;
    }

    if (expiresIn == null) {
      return true;
    }

    return expiresIn.isAfter(
      DateTime.now().toUtc().add(const Duration(minutes: 1)),
    );
  }

  static bool _hasRequiredScopes(List<String>? scopes) {
    if (scopes == null || scopes.isEmpty) {
      return false;
    }
    return scopes.contains(_youtubeScope);
  }

  static void _updateCredentials(GoogleSignInCredentials? credentials) {
    _credentials = credentials;
    _accessToken = credentials?.accessToken;
  }

  static Future<GoogleSignInCredentials?> _refreshAccessToken(
    GoogleSignInCredentials credentials,
  ) async {
    final refreshToken = credentials.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final clientId = dotenv.env['CLIENT_ID'];
    if (clientId == null || clientId.isEmpty) {
      return null;
    }

    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        if ((dotenv.env['CLIENT_SECRET'] ?? '').isNotEmpty)
          'client_secret': dotenv.env['CLIENT_SECRET']!,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final refreshedAccessToken = payload['access_token'] as String?;
    if (refreshedAccessToken == null || refreshedAccessToken.isEmpty) {
      return null;
    }

    final expiresInSeconds = (payload['expires_in'] as num?)?.toInt();
    final expiresAt = expiresInSeconds == null
        ? null
        : DateTime.now().toUtc().add(Duration(seconds: expiresInSeconds));
    final scopeString = payload['scope'] as String?;
    final refreshedScopes = scopeString == null || scopeString.isEmpty
        ? credentials.scopes
        : scopeString.split(' ').where((scope) => scope.isNotEmpty).toList();

    return credentials.copyWith(
      accessToken: refreshedAccessToken,
      tokenType: payload['token_type'] as String? ?? credentials.tokenType,
      expiresIn: expiresAt,
      scopes: refreshedScopes,
    );
  }

  static Future<GoogleSignInCredentials?> _tryRestoringCredentials() async {
    try {
      final lightweightCredentials = await googleSignIn.lightweightSignIn();
      if (lightweightCredentials != null) {
        return lightweightCredentials;
      }
    } catch (_) {}

    try {
      final silentCredentials = await googleSignIn.silentSignIn();
      if (silentCredentials != null) {
        return silentCredentials;
      }
    } catch (_) {}

    return null;
  }

  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  static Future<String?> ensureAccessToken({
    bool forceOnline = false,
    bool forceRefresh = false,
  }) async {
    if (!forceOnline &&
        !forceRefresh &&
        _hasRequiredScopes(_credentials?.scopes) &&
        _isAccessTokenUsable(_accessToken, _credentials?.expiresIn)) {
      return _accessToken;
    }

    if (!forceOnline) {
      final restoredCredentials = await _tryRestoringCredentials();
      if (restoredCredentials != null) {
        _updateCredentials(restoredCredentials);
        if (!forceRefresh &&
            _hasRequiredScopes(restoredCredentials.scopes) &&
            _isAccessTokenUsable(
              restoredCredentials.accessToken,
              restoredCredentials.expiresIn,
            )) {
          return _accessToken;
        }

        final refreshedCredentials = await _refreshAccessToken(
          restoredCredentials,
        );
        if (_isAccessTokenUsable(
              refreshedCredentials?.accessToken,
              refreshedCredentials?.expiresIn,
            ) &&
            _hasRequiredScopes(refreshedCredentials?.scopes)) {
          _updateCredentials(refreshedCredentials);
          return _accessToken;
        }
      }

      if (_credentials != null) {
        final refreshedCachedCredentials = await _refreshAccessToken(
          _credentials!,
        );
        if (_isAccessTokenUsable(
              refreshedCachedCredentials?.accessToken,
              refreshedCachedCredentials?.expiresIn,
            ) &&
            _hasRequiredScopes(refreshedCachedCredentials?.scopes)) {
          _updateCredentials(refreshedCachedCredentials);
          return _accessToken;
        }
      }
    }

    final onlineCredentials = await googleSignIn.signInOnline();
    _updateCredentials(onlineCredentials);
    if (!_hasRequiredScopes(onlineCredentials?.scopes)) {
      return null;
    }
    return _accessToken;
  }

  static Future<GoogleSignInCredentials?> signIn() async {
    final credentials = await googleSignIn.signInOnline();
    _updateCredentials(credentials);
    return credentials;
  }

  static Future<GoogleSignInCredentials?> signInFresh() async {
    await signOut();
    final credentials = await googleSignIn.signInOnline();
    _updateCredentials(credentials);
    return credentials;
  }

  static Future<void> signOut() async {
    await googleSignIn.signOut();
    _accessToken = null;
    _credentials = null;
  }
}
