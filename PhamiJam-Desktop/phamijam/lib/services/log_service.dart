import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const int _maxBufferLines = 1000;
  static const int _maxFileBytes = 512 * 1024;

  final List<String> _buffer = [];
  File? _logFile;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/phamijam_log.txt');
      if (await file.exists()) {
        final length = await file.length();
        if (length > _maxFileBytes) {
          final content = await file.readAsString();
          await file.writeAsString(
            content.substring(content.length - _maxFileBytes ~/ 2),
          );
        }
      }
      _logFile = file;
    } catch (_) {
      _logFile = null;
    }

    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) _capture(message);
      original(message, wrapWidth: wrapWidth);
    };
  }

  void _capture(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    _buffer.add(line);
    if (_buffer.length > _maxBufferLines) _buffer.removeAt(0);

    final file = _logFile;
    if (file == null) return;
    unawaited(_appendToFile(file, line));
  }

  Future<void> _appendToFile(File file, String line) async {
    try {
      await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  Future<String> fullLogText() async {
    final file = _logFile;
    if (file != null) {
      try {
        if (await file.exists()) return await file.readAsString();
      } catch (_) {}
    }
    return _buffer.join('\n');
  }

  String? get logFilePath => _logFile?.path;
}
