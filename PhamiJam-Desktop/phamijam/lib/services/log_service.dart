import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class Log {
  Log._();

  static void i(String tag, String message) => _write('I', tag, message);

  static void w(String tag, String message, [Object? error]) =>
      _write('W', tag, error == null ? message : '$message | $error');

  static void e(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(' | $error');
    if (stackTrace != null) {
      final lines = stackTrace.toString().trimRight().split('\n');
      buffer.write('\n${lines.take(8).join('\n')}');
    }
    _write('E', tag, buffer.toString());
  }

  static void _write(String level, String tag, String message) {
    debugPrint('[$level][$tag] $message');
  }
}

typedef LogSnapshot = FutureOr<String> Function();

class LogService with WidgetsBindingObserver {
  LogService._();
  static final LogService instance = LogService._();

  static const int _maxBufferLines = 1500;
  static const int _maxFileBytes = 768 * 1024;
  static const int _maxLineChars = 2000;

  final List<String> _buffer = [];
  final Map<String, LogSnapshot> _snapshots = {};
  File? _logFile;
  IOSink? _sink;
  bool _initialized = false;
  String _appVersion = 'unknown';
  String? _userTag;
  int _errorCount = 0;
  final DateTime _sessionStart = DateTime.now();

  static final List<(RegExp, String)> _redactions = [
    (RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'), 'Bearer <redacted>'),
    (
      RegExp(
        r'\b(access_token|refresh_token|id_token|api[_-]?key|client_secret|'
        r'authorization|token|key|signature|sig|code)=([^&\s"'
        "'"
        r']+)',
        caseSensitive: false,
      ),
      r'$1=<redacted>',
    ),
    (
      RegExp(
        r'https?://[^\s"'
        "'"
        r']*googlevideo[^\s"'
        "'"
        r']*',
      ),
      '<stream-url>',
    ),
    (RegExp(r'AIza[0-9A-Za-z_-]{20,}'), '<api-key>'),
    (
      RegExp(
        r'([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})',
      ),
      r'$1***@$2',
    ),
  ];

  void registerSnapshot(String name, LogSnapshot snapshot) {
    _snapshots[name] = snapshot;
  }

  void unregisterSnapshot(String name) => _snapshots.remove(name);

  void setUser(String? uid) {
    final tag = uid == null || uid.isEmpty
        ? null
        : uid.substring(0, uid.length < 8 ? uid.length : 8);
    if (tag == _userTag) return;
    _userTag = tag;
    Log.i('auth', tag == null ? 'signed out' : 'signed in as user $tag');
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {}

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
      _sink = file.openWrite(mode: FileMode.append);
      Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_flushQuietly()),
      );
    } catch (_) {
      _logFile = null;
      _sink = null;
    }

    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) _capture(message);
      original(message, wrapWidth: wrapWidth);
    };

    _installErrorHooks();
    WidgetsBinding.instance.addObserver(this);

    Log.i(
      'app',
      '===== session start | v$_appVersion | ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion} | '
          '${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')} '
          '=====',
    );
  }

  void _installErrorHooks() {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      Log.e(
        'flutter',
        'UI error: ${details.exceptionAsString()}'
            '${details.library == null ? '' : ' (${details.library})'}',
        null,
        details.stack,
      );
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatformError = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      Log.e('uncaught', 'Unhandled error', error, stack);
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Log.i('lifecycle', 'app ${state.name}');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushQuietly());
    }
  }

  @override
  void didHaveMemoryPressure() {
    Log.w('lifecycle', 'system memory pressure');
  }

  String _redact(String text) {
    var result = text;
    for (final (pattern, replacement) in _redactions) {
      result = result.replaceAllMapped(pattern, (m) {
        var out = replacement;
        for (var g = 1; g <= m.groupCount; g++) {
          out = out.replaceAll('\$$g', m.group(g) ?? '');
        }
        return out;
      });
    }
    return result;
  }

  void _capture(String message) {
    var text = _redact(message);
    if (text.length > _maxLineChars) {
      text =
          '${text.substring(0, _maxLineChars)}… (+${text.length - _maxLineChars} chars)';
    }
    if (text.startsWith('[E]')) _errorCount++;
    final line = '${DateTime.now().toIso8601String()} $text';
    _buffer.add(line);
    if (_buffer.length > _maxBufferLines) _buffer.removeAt(0);
    try {
      _sink?.writeln(line);
    } catch (_) {}
  }

  Future<void> _flushQuietly() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  Future<String> _logBody() async {
    await _flushQuietly();
    final file = _logFile;
    if (file != null) {
      try {
        if (await file.exists()) return await file.readAsString();
      } catch (_) {}
    }
    return _buffer.join('\n');
  }

  Future<String> fullLogText() => _logBody();

  Future<String> buildHeader() async {
    final out = StringBuffer()
      ..writeln('PhamiJam log report')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('Version: $_appVersion')
      ..writeln(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln(
        'Mode: ${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')}',
      )
      ..writeln('Locale: ${Platform.localeName}')
      ..writeln('CPU cores: ${Platform.numberOfProcessors}')
      ..writeln('User: ${_userTag ?? 'not signed in'}')
      ..writeln(
        'Session: started ${_sessionStart.toIso8601String()}, '
        'up ${DateTime.now().difference(_sessionStart).inMinutes} min',
      )
      ..writeln('Errors this session: $_errorCount');

    for (final entry in _snapshots.entries) {
      String value;
      try {
        value = _redact(await entry.value());
      } catch (error) {
        value = '(snapshot failed: $error)';
      }
      out
        ..writeln()
        ..writeln('--- ${entry.key} ---')
        ..writeln(value.trimRight());
    }
    return out.toString();
  }

  Future<String> buildReport({int? maxChars}) async {
    final header = await buildHeader();
    final log = await _logBody();
    final divider = '\n===== LOG =====\n';
    if (maxChars == null ||
        header.length + divider.length + log.length <= maxChars) {
      return '$header$divider$log';
    }
    final room = maxChars - header.length - divider.length - 60;
    if (room <= 0) return header;
    final tail = log.substring(log.length - room);
    final firstBreak = tail.indexOf('\n');
    final clean = firstBreak >= 0 ? tail.substring(firstBreak + 1) : tail;
    return '$header$divider(older lines omitted)\n$clean';
  }

  String? get logFilePath => _logFile?.path;
}

class LogNavigatorObserver extends NavigatorObserver {
  static final Expando<String> _names = Expando<String>('route names');

  static const Set<String> _frameworkNames = {
    'Builder',
    'Semantics',
    'Offstage',
    'Directionality',
    'Theme',
    'Material',
    'MediaQuery',
    'Focus',
    'FocusScope',
    'PageStorage',
    'FadeTransition',
    'SlideTransition',
    'Align',
    'Padding',
    'SafeArea',
    'DefaultTextStyle',
    'AnimatedBuilder',
    'RepaintBoundary',
    'IgnorePointer',
    'Actions',
    'Shortcuts',
    'PrimaryScrollController',
    'ColoredBox',
    'ClipRect',
    'ClipPath',
    'ClipRRect',
    'Container',
    'DecoratedBox',
    'Center',
    'SizedBox',
    'ConstrainedBox',
    'Stack',
    'Positioned',
    'Column',
    'Row',
    'Expanded',
    'Flexible',
    'Scaffold',
    'DisplayFeatureSubScreen',
    'SingleChildScrollView',
    'CustomSingleChildLayout',
    'LayoutBuilder',
    'Viewport',
    'Scrollable',
    'ListView',
    'Listener',
    'GestureDetector',
    'RawGestureDetector',
    'MouseRegion',
    'TapRegion',
    'Navigator',
    'Overlay',
    'NotificationListener',
    'FocusTraversalGroup',
    'AnimatedPadding',
    'AnimatedSwitcher',
    'Opacity',
    'Transform',
    'ListBody',
    'Wrap',
    'ModalBarrier',
    'Barrier',
    'UnconstrainedBox',
    'LimitedBox',
    'FractionallySizedBox',
    'IntrinsicHeight',
    'IntrinsicWidth',
    'Spacer',
    'Text',
    'Icon',
    'DefaultSelectionStyle',
    'Localizations',
    'Title',
  };

  static String _routeKind(Route<dynamic> route) {
    final named = route.settings.name;
    if (named != null && named.isNotEmpty) return named;
    final type = route.runtimeType.toString();
    if (type.contains('Dialog')) return 'dialog';
    if (type.contains('BottomSheet')) return 'bottom sheet';
    if (type.contains('Popup')) return 'popup menu';
    return 'page';
  }

  static String? _findPageWidgetName(BuildContext context) {
    String? fallback;
    String? preferred;
    var visited = 0;
    void visit(Element element) {
      if (preferred != null || visited > 60) return;
      visited++;
      final widget = element.widget;
      if (widget is StatefulWidget || widget is StatelessWidget) {
        final name = widget.runtimeType.toString();
        if (!name.startsWith('_') && !_frameworkNames.contains(name)) {
          fallback ??= name;
          if (RegExp(
            r'(Page|Screen|Sheet|Dialog|Shell|View)$',
          ).hasMatch(name)) {
            preferred = name;
            return;
          }
        }
      }
      element.visitChildElements(visit);
    }

    try {
      (context as Element).visitChildElements(visit);
    } catch (_) {}
    return preferred ?? fallback;
  }

  void _logOpen(Route<dynamic> route, String verb) {
    final kind = _routeKind(route);
    Log.i('nav', '$verb $kind');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = route is ModalRoute ? route.subtreeContext : null;
      if (context == null) return;
      final name = _findPageWidgetName(context);
      if (name == null) return;
      _names[route] = name;
      Log.i('nav', '  └ $kind is $name');
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _logOpen(route, 'open');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _logOpen(newRoute, 'replace with');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    Log.i('nav', 'close ${_names[route] ?? _routeKind(route)}');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    Log.i('nav', 'remove ${_names[route] ?? _routeKind(route)}');
  }
}
