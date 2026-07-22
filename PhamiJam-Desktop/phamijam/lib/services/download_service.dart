import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String formatDownloadSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class DownloadedItem {
  final String videoId;
  final String songName;
  final String artistName;
  final String? artistId;
  final int durationSeconds;
  final String filePath;
  final int fileSizeBytes;
  final DateTime downloadedAt;

  const DownloadedItem({
    required this.videoId,
    required this.songName,
    required this.artistName,
    this.artistId,
    this.durationSeconds = 0,
    required this.filePath,
    required this.fileSizeBytes,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'songName': songName,
    'artistName': artistName,
    'artistId': artistId,
    'durationSeconds': durationSeconds,
    'filePath': filePath,
    'fileSizeBytes': fileSizeBytes,
    'downloadedAt': downloadedAt.millisecondsSinceEpoch,
  };

  static DownloadedItem? fromJson(dynamic json) {
    if (json is! Map) return null;
    final videoId = json['videoId'];
    final filePath = json['filePath'];
    if (videoId is! String || videoId.isEmpty || filePath is! String) {
      return null;
    }
    return DownloadedItem(
      videoId: videoId,
      songName: json['songName'] is String ? json['songName'] as String : '',
      artistName: json['artistName'] is String
          ? json['artistName'] as String
          : '',
      artistId: json['artistId'] is String ? json['artistId'] as String : null,
      durationSeconds: json['durationSeconds'] is int
          ? json['durationSeconds'] as int
          : 0,
      filePath: filePath,
      fileSizeBytes: json['fileSizeBytes'] is int
          ? json['fileSizeBytes'] as int
          : 0,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(
        json['downloadedAt'] is int ? json['downloadedAt'] as int : 0,
      ),
    );
  }
}

class DownloadsProvider extends ChangeNotifier {
  DownloadsProvider() {
    _load();
  }

  static const String _manifestKey = 'phamijam.downloads.manifest';

  Future<List<String>> Function(String videoId)? resolveStreamUrls;

  final Map<String, DownloadedItem> _downloaded = {};
  final Map<String, double> _progress = {};
  final Set<String> _failed = {};
  final Map<String, http.Client> _activeClients = {};
  final Set<String> _cancelled = {};
  bool _stopBulkRequested = false;
  bool _loaded = false;

  bool get isReady => _loaded;
  int get totalTracks => _downloaded.length;

  int get totalSizeBytes =>
      _downloaded.values.fold(0, (sum, d) => sum + d.fileSizeBytes);

  List<DownloadedItem> get all =>
      _downloaded.values.toList()
        ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

  bool isDownloaded(String? videoId) =>
      videoId != null && videoId.isNotEmpty && _downloaded.containsKey(videoId);

  bool isDownloading(String? videoId) =>
      videoId != null && _progress.containsKey(videoId);

  double? progressFor(String? videoId) =>
      videoId == null ? null : _progress[videoId];

  bool didFail(String? videoId) => videoId != null && _failed.contains(videoId);

  bool isCancellable(String? videoId) =>
      videoId != null && _activeClients.containsKey(videoId);

  String? localPathFor(String videoId) => _downloaded[videoId]?.filePath;

  Future<void> cancelDownload(String videoId) async {
    final client = _activeClients[videoId];
    if (client == null) return;
    _cancelled.add(videoId);
    client.close();
  }

  void cancelAllDownloads() {
    _stopBulkRequested = true;
    for (final videoId in _progress.keys.toList()) {
      cancelDownload(videoId);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_manifestKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            final item = DownloadedItem.fromJson(entry);
            if (item != null) _downloaded[item.videoId] = item;
          }
        }
      } catch (error) {
        debugPrint('DownloadsProvider: failed to parse manifest: $error');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveManifest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _manifestKey,
      jsonEncode(_downloaded.values.map((d) => d.toJson()).toList()),
    );
  }

  Future<Directory> _downloadsDir() async {
    final dir = await getApplicationSupportDirectory();
    final downloads = Directory('${dir.path}/downloads');
    if (!downloads.existsSync()) {
      downloads.createSync(recursive: true);
    }
    return downloads;
  }

  Future<void> _downloadToFile(Uri url, File file, String videoId) async {
    final client = http.Client();
    _activeClients[videoId] = client;
    try {
      final response = await client.send(http.Request('GET', url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      var received = 0;

      final sink = file.openWrite();
      await response.stream
          .map((chunk) {
            received += chunk.length;
            if (total > 0) {
              _progress[videoId] = received / total;
              notifyListeners();
            }
            return chunk;
          })
          .pipe(sink);
      await sink.close();
    } finally {
      client.close();
      if (identical(_activeClients[videoId], client)) {
        _activeClients.remove(videoId);
      }
    }
  }

  Future<void> download({
    required String videoId,
    required String songName,
    required String artistName,
    String? artistId,
    int durationSeconds = 0,
  }) async {
    if (videoId.isEmpty || isDownloaded(videoId) || isDownloading(videoId)) {
      return;
    }
    final resolve = resolveStreamUrls;
    if (resolve == null) return;

    _failed.remove(videoId);
    _cancelled.remove(videoId);
    _progress[videoId] = 0;
    notifyListeners();

    final dir = await _downloadsDir();
    final file = File('${dir.path}/$videoId.m4a');

    try {
      final candidates = await resolve(videoId);
      if (candidates.isEmpty) {
        throw Exception('No playable streams found for this video.');
      }

      Object? lastError;
      var succeeded = false;
      for (final url in candidates) {
        if (_cancelled.contains(videoId)) break;
        try {
          await _downloadToFile(Uri.parse(url), file, videoId);
          succeeded = true;
          break;
        } catch (error) {
          lastError = error;
          if (_cancelled.contains(videoId)) break;
        }
      }
      if (!succeeded) throw lastError ?? Exception('Download failed');

      _downloaded[videoId] = DownloadedItem(
        videoId: videoId,
        songName: songName,
        artistName: artistName,
        artistId: artistId,
        durationSeconds: durationSeconds,
        filePath: file.path,
        fileSizeBytes: await file.length(),
        downloadedAt: DateTime.now(),
      );
      await _saveManifest();
    } catch (error) {
      final wasCancelled = _cancelled.remove(videoId);
      if (wasCancelled) {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      } else {
        debugPrint('DownloadsProvider: download failed for $videoId: $error');
        _failed.add(videoId);
      }
    } finally {
      _activeClients.remove(videoId);
      _progress.remove(videoId);
      notifyListeners();
    }
  }

  Future<void> downloadTracks(List<Map<String, dynamic>> tracks) async {
    _stopBulkRequested = false;
    for (final track in tracks) {
      if (_stopBulkRequested) break;
      final videoId = track['videoId']?.toString() ?? '';
      if (videoId.isEmpty || isDownloaded(videoId)) continue;
      await download(
        videoId: videoId,
        songName: track['songName']?.toString() ?? 'Unknown Song',
        artistName: track['artistName']?.toString() ?? 'Unknown Artist',
        artistId: track['artistId']?.toString(),
        durationSeconds: track['durationSeconds'] is int
            ? track['durationSeconds'] as int
            : 0,
      );
    }
  }

  Future<void> remove(String videoId) async {
    final entry = _downloaded.remove(videoId);
    if (entry != null) {
      try {
        final file = File(entry.filePath);
        if (file.existsSync()) file.deleteSync();
      } catch (error) {
        debugPrint('DownloadsProvider: failed to delete file: $error');
      }
    }
    await _saveManifest();
    notifyListeners();
  }

  Future<void> clearAll() async {
    final entries = _downloaded.values.toList();
    _downloaded.clear();
    for (final entry in entries) {
      try {
        final file = File(entry.filePath);
        if (file.existsSync()) file.deleteSync();
      } catch (error) {
        debugPrint('DownloadsProvider: failed to delete file: $error');
      }
    }
    await _saveManifest();
    notifyListeners();
  }
}
