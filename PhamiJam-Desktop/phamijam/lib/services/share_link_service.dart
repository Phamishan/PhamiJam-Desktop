import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phamijam/components/app_flushbar.dart';

const String shareBaseHost = 'phamijam-share.phamijam.workers.dev';

class ShareLinkService {
  ShareLinkService._();

  static Uri buildSongUrl(String videoId) =>
      Uri.https(shareBaseHost, '/s/$videoId');

  static Uri buildPlaylistUrl(String playlistId) =>
      Uri.https(shareBaseHost, '/p/$playlistId');

  static Uri buildProfileUrl(String uid, {String? username}) => Uri.https(
    shareBaseHost,
    '/u/${(username != null && username.isNotEmpty) ? username : uid}',
  );

  static Future<void> shareSong(BuildContext context, String videoId) async {
    if (videoId.isEmpty) return;
    await _copyToClipboard(context, buildSongUrl(videoId));
  }

  static Future<void> shareProfile(
    BuildContext context,
    String uid, {
    String? username,
    required String subject,
  }) async {
    if (uid.isEmpty) return;
    await _copyToClipboard(context, buildProfileUrl(uid, username: username));
  }

  static Future<void> sharePlaylist(
    BuildContext context,
    String playlistId,
  ) async {
    if (playlistId.isEmpty) return;
    await _copyToClipboard(context, buildPlaylistUrl(playlistId));
  }

  static Future<void> _copyToClipboard(BuildContext context, Uri url) async {
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (context.mounted) {
      AppFlushbar.success(context, 'Link copied to clipboard');
    }
  }
}
