class AppUpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
  });
}
