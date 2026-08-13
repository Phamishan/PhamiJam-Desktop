import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/firebase_options.dart';
import 'package:phamijam/pages/login.dart';
import 'package:phamijam/pages/home.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/liked_songs_provider.dart';
import 'package:phamijam/providers/playlist_pin_provider.dart';
import 'package:phamijam/providers/saved_playlists_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/deep_link_service.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/protocol_handler_service.dart';
import 'package:phamijam/theme/app_theme.dart';
import 'package:provider/provider.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: '.env');
  unawaited(ProtocolHandlerService.registerIfNeeded());
  final pendingDeepLink = DeepLinkService.parseLaunchArgs(args);
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
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MyApp(pendingDeepLink: pendingDeepLink),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.pendingDeepLink});

  final DeepLinkTarget? pendingDeepLink;

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'PhamiJam',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accentColor: themeProvider.accentColor),
      darkTheme: AppTheme.dark(accentColor: themeProvider.accentColor),
      themeMode: themeProvider.flutterThemeMode,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return Home(pendingDeepLink: pendingDeepLink);
          }

          return const Login();
        },
      ),
    );
  }
}
