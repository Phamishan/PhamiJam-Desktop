import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/firebase_options.dart';
import 'package:phamijam/pages/login.dart';
import 'package:phamijam/pages/home.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/providers/liked_songs_provider.dart';
import 'package:phamijam/providers/playlist_pin_provider.dart';
import 'package:phamijam/providers/profile_provider.dart';
import 'package:phamijam/providers/saved_playlists_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/deep_link_service.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/protocol_handler_service.dart';
import 'package:phamijam/services/unavailable_songs_service.dart';
import 'package:phamijam/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _applyGrpcDnsResolverWorkaround() {
  if (!Platform.isWindows) return;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setEnvironmentVariable = kernel32
        .lookupFunction<
          Int32 Function(Pointer<Utf16> name, Pointer<Utf16> value),
          int Function(Pointer<Utf16> name, Pointer<Utf16> value)
        >('SetEnvironmentVariableW');
    final name = 'GRPC_DNS_RESOLVER'.toNativeUtf16();
    final value = 'native'.toNativeUtf16();
    setEnvironmentVariable(name, value);
    calloc.free(name);
    calloc.free(value);
  } catch (error) {
    Log.w('startup', 'could not apply gRPC DNS workaround', error);
  }
}

Future<void> _recoverFromCorruptedPreferences() async {
  if (!Platform.isWindows) return;
  try {
    await SharedPreferences.getInstance();
  } catch (error) {
    Log.e('startup', 'saved settings file is corrupted, resetting it', error);
    try {
      final supportDir = await getApplicationSupportDirectory();
      final file = File('${supportDir.path}\\shared_preferences.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (deleteError) {
      Log.e('startup', 'could not delete corrupted settings file', deleteError);
    }
  }
}

void main(List<String> args) async {
  _applyGrpcDnsResolverWorkaround();
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.instance.init();
  await _recoverFromCorruptedPreferences();
  MediaKit.ensureInitialized();
  Log.i('startup', 'initializing Firebase');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseAuth.instance.authStateChanges().listen(
    (user) => LogService.instance.setUser(user?.uid),
    onError: (Object error) => Log.e('auth', 'auth state stream error', error),
  );
  await dotenv.load(fileName: '.env');
  Log.i('startup', 'config loaded, launching UI');
  unawaited(ProtocolHandlerService.registerIfNeeded());
  unawaited(UnavailableSongs.instance.ensureLoaded());
  final pendingDeepLink = DeepLinkService.parseLaunchArgs(args);
  if (args.isNotEmpty) {
    Log.i(
      'startup',
      'launched with ${args.length} argument(s), deep link: '
          '${pendingDeepLink?.type.name ?? 'none'}',
    );
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlaybackModel()..bindToPlayer()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => DownloadsProvider()),
        ChangeNotifierProvider(create: (_) => LikedSongsProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistPinProvider()),
        ChangeNotifierProvider(create: (_) => EditedSongsProvider()),
        ChangeNotifierProvider(create: (_) => SavedPlaylistsProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MyApp(pendingDeepLink: pendingDeepLink),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.pendingDeepLink});

  final DeepLinkTarget? pendingDeepLink;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Stream<User?> _authStateChanges = FirebaseAuth.instance
      .authStateChanges();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'PhamiJam',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [LogNavigatorObserver()],
      theme: AppTheme.light(accentColor: themeProvider.accentColor),
      darkTheme: AppTheme.dark(accentColor: themeProvider.accentColor),
      themeMode: themeProvider.flutterThemeMode,
      home: StreamBuilder<User?>(
        stream: _authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return Home(pendingDeepLink: widget.pendingDeepLink);
          }
          if (snapshot.hasError) {
            Log.e('auth', 'auth stream error', snapshot.error);
          }

          return const Login();
        },
      ),
    );
  }
}
