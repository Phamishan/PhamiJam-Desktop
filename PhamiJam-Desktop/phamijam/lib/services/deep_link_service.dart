import 'package:flutter/services.dart';

enum DeepLinkType { song, playlist, profile }

class DeepLinkTarget {
  final DeepLinkType type;
  final String id;

  const DeepLinkTarget(this.type, this.id);
}

class DeepLinkService {
  DeepLinkService._();

  static const EventChannel _channel = EventChannel('phamijam/deep_link');

  static Stream<DeepLinkTarget> get incomingLinks => _channel
      .receiveBroadcastStream()
      .map((value) => parse(value as String))
      .where((target) => target != null)
      .cast<DeepLinkTarget>();

  static DeepLinkTarget? parseLaunchArgs(List<String> args) {
    for (final arg in args) {
      final target = parse(arg);
      if (target != null) return target;
    }
    return null;
  }

  static DeepLinkTarget? parse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'phamijam') return null;

    final segments = uri.host.isNotEmpty
        ? [uri.host, ...uri.pathSegments]
        : uri.pathSegments;
    if (segments.length < 2) return null;

    final id = segments[1];
    if (id.isEmpty) return null;
    if (segments[0] == 's') return DeepLinkTarget(DeepLinkType.song, id);
    if (segments[0] == 'p') return DeepLinkTarget(DeepLinkType.playlist, id);
    if (segments[0] == 'u') return DeepLinkTarget(DeepLinkType.profile, id);
    return null;
  }
}
