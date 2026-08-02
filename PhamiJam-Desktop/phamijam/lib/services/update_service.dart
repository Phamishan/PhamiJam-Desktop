import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phamijam/models/app_update_info.dart';

class UpdateService {
  UpdateService._();

  static const String _repo = 'Phamishan/PhamiJam-Desktop';
  static const String _installerAssetName = 'phamijam_setup.exe';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to check for updates (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = (payload['tag_name'] as String?) ?? '';
    final latestVersion = tagName.startsWith('v')
        ? tagName.substring(1)
        : tagName;
    if (latestVersion.isEmpty) return null;

    String? downloadUrl;
    for (final asset in (payload['assets'] as List? ?? const [])) {
      if (asset is Map && asset['name'] == _installerAssetName) {
        downloadUrl = asset['browser_download_url'] as String?;
        break;
      }
    }
    if (downloadUrl == null) return null;

    final packageInfo = await PackageInfo.fromPlatform();
    if (!_isNewer(latestVersion, packageInfo.version)) return null;

    return AppUpdateInfo(
      latestVersion: latestVersion,
      downloadUrl: downloadUrl,
      releaseNotes: payload['body'] as String?,
    );
  }

  static bool _isNewer(String latest, String current) {
    List<int> parse(String value) => value
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList();

    final latestParts = parse(latest);
    final currentParts = parse(current);
    final length = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (var i = 0; i < length; i++) {
      final latestPart = i < latestParts.length ? latestParts[i] : 0;
      final currentPart = i < currentParts.length ? currentParts[i] : 0;
      if (latestPart != currentPart) return latestPart > currentPart;
    }
    return false;
  }

  static Future<String> downloadInstaller(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw Exception('Failed to download update (${response.statusCode}).');
      }

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}$_installerAssetName',
      );
      final sink = file.openWrite();
      final total = response.contentLength ?? 0;
      var received = 0;

      await response.stream
          .map((chunk) {
            received += chunk.length;
            if (total > 0) onProgress?.call(received / total);
            return chunk;
          })
          .pipe(sink);
      await sink.close();

      return file.path;
    } finally {
      client.close();
    }
  }

  static Future<void> runInstallerAndExit(String installerPath) async {
    await Process.start(installerPath, [
      '/VERYSILENT',
      '/SUPPRESSMSGBOX',
      '/NORESTART',
    ], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }
}
