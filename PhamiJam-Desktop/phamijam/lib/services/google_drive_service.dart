import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/services/drive_duration_cache_service.dart';
import 'package:phamijam/services/drive_folder_service.dart';
import 'package:phamijam/services/google_drive_auth_service.dart';

const String _driveApiBase = 'https://www.googleapis.com/drive/v3';
const String driveTrackIdPrefix = 'drive:';
const String phamiJamFolderName = 'PhamiJam';

class GoogleDriveService {
  GoogleDriveService._();

  static String get _apiKey => dotenv.env['DRIVE_API_KEY'] ?? '';

  static Future<Map<String, String>> _authHeaders() async {
    final requiresAuth = await DriveFolderService.getRequiresAuth();
    if (!requiresAuth) return const {};
    final token = await GoogleDriveAuthService.ensureAccessToken();
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  static Future<List<Map<String, dynamic>>?> listAudioFiles() async {
    final folderId = await DriveFolderService.getFolderId();
    if (folderId == null) return null;

    final headers = await _authHeaders();
    final uri = Uri.parse('$_driveApiBase/files').replace(
      queryParameters: {
        'q':
            "'$folderId' in parents and trashed = false and mimeType contains 'audio/'",
        'fields': 'files(id,name,createdTime)',
        'pageSize': '200',
        'key': _apiKey,
      },
    );

    final response = await http.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to list Google Drive folder (${response.statusCode}).',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final files = (payload['files'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();

    return Future.wait(files.map(_songFromFile));
  }

  static Future<String> findOrCreatePhamiJamFolder(String accessToken) async {
    final headers = {'Authorization': 'Bearer $accessToken'};

    final listUri = Uri.parse('$_driveApiBase/files').replace(
      queryParameters: {
        'q':
            "name = '$phamiJamFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        'fields': 'files(id,name)',
        'pageSize': '1',
      },
    );
    final listResponse = await http.get(listUri, headers: headers);
    if (listResponse.statusCode < 200 || listResponse.statusCode >= 300) {
      throw Exception(
        'Failed to search Google Drive (${listResponse.statusCode}).',
      );
    }

    final listPayload = jsonDecode(listResponse.body) as Map<String, dynamic>;
    final existing = (listPayload['files'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as String?;
      if (id != null && id.isNotEmpty) return id;
    }

    final createResponse = await http.post(
      Uri.parse('$_driveApiBase/files'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': phamiJamFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );
    if (createResponse.statusCode < 200 || createResponse.statusCode >= 300) {
      throw Exception(
        'Failed to create the PhamiJam Drive folder '
        '(${createResponse.statusCode}).',
      );
    }

    final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final id = created['id'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('Drive did not return a folder id.');
    }
    return id;
  }

  static Future<Map<String, dynamic>> _songFromFile(
    Map<String, dynamic> file,
  ) async {
    final id = file['id'] as String? ?? '';
    final name = file['name'] as String? ?? 'Unknown song';
    final parsed = _titleArtistFromFileName(_stripExtension(name));
    final cachedDuration = await DriveDurationCacheService.getDuration(id);

    return <String, dynamic>{
      'title': parsed.title,
      'artist': parsed.artist,
      'artistId': '',
      'videoId': '$driveTrackIdPrefix$id',
      'thumbnailUrl': '',
      'durationSeconds': cachedDuration?.inSeconds ?? 0,
      'addedAt': file['createdTime'] as String?,
    };
  }

  static ({String title, String artist}) _titleArtistFromFileName(
    String nameWithoutExtension,
  ) {
    final separatorIndex = nameWithoutExtension.indexOf(' - ');
    if (separatorIndex > 0) {
      final artist = nameWithoutExtension.substring(0, separatorIndex).trim();
      final title = nameWithoutExtension.substring(separatorIndex + 3).trim();
      if (artist.isNotEmpty && title.isNotEmpty) {
        return (title: title, artist: artist);
      }
    }
    return (title: nameWithoutExtension, artist: 'Unknown artist');
  }

  static String _stripExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) return fileName;
    return fileName.substring(0, dotIndex);
  }

  static Future<bool> canAccessFolder(String folderId) async {
    final uri = Uri.parse(
      '$_driveApiBase/files/$folderId',
    ).replace(queryParameters: {'fields': 'id,mimeType', 'key': _apiKey});
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return payload['mimeType'] == 'application/vnd.google-apps.folder';
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>> streamHeaders(String fileId) =>
      _authHeaders();

  static Uri streamUri(String fileId) => Uri.parse(
    '$_driveApiBase/files/$fileId',
  ).replace(queryParameters: {'alt': 'media', 'key': _apiKey});
}
