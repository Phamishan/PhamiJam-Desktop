import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

class ProtocolHandlerService {
  ProtocolHandlerService._();

  static const String _scheme = 'phamijam';

  static Future<void> registerIfNeeded() async {
    if (!Platform.isWindows) return;

    try {
      final exePath = Platform.resolvedExecutable;
      final desiredCommand = '"$exePath" "%1"';

      if (_currentCommand() == desiredCommand) return;

      final classesKey = Registry.currentUser.createKey('Software\\Classes');
      try {
        final protocolKey = classesKey.createKey(_scheme);
        try {
          protocolKey.createValue(
            const RegistryValue.string('', 'URL:PhamiJam Protocol'),
          );
          protocolKey.createValue(
            const RegistryValue.string('URL Protocol', ''),
          );
        } finally {
          protocolKey.close();
        }

        final commandKey = classesKey.createKey(
          '$_scheme\\shell\\open\\command',
        );
        try {
          commandKey.createValue(RegistryValue.string('', desiredCommand));
        } finally {
          commandKey.close();
        }
      } finally {
        classesKey.close();
      }
    } catch (error) {
      debugPrint('ProtocolHandlerService: registration failed: $error');
    }
  }

  static String? _currentCommand() {
    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: 'Software\\Classes\\$_scheme\\shell\\open\\command',
      );
      try {
        return key.getStringValue('');
      } finally {
        key.close();
      }
    } catch (_) {
      return null;
    }
  }
}
