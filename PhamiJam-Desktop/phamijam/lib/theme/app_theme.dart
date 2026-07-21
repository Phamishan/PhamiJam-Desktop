import 'package:flutter/material.dart';

const Color kBrandGold = Color(0xFFDBA43A);
const Color kErrorRed = Color(0xFFD32F2F);

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: kBrandGold,
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF1C1B1A),
          onPrimary: Colors.white,
          surface: kBrandGold,
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFFFCEFD1),
          surfaceContainerLowest: const Color(0xFFE6B850),
          surfaceContainerLow: const Color(0xFFDDAC45),
          surfaceContainer: const Color(0xFFCC9730),
          surfaceContainerHigh: const Color(0xFFBC8A26),
          surfaceContainerHighest: const Color(0xFFAD7E1D),
          error: kErrorRed,
          onError: Colors.white,
        );

    return ThemeData(colorScheme: colorScheme, fontFamily: 'Lexend');
  }

  static ThemeData get dark {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: kBrandGold,
          brightness: Brightness.dark,
        ).copyWith(
          primary: kBrandGold,
          onPrimary: const Color(0xFF1C1B1A),
          surface: const Color(0xFF1C1B1A),
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFFCBBFA8),
          surfaceContainerLowest: const Color(0xFF121110),
          surfaceContainerLow: const Color(0xFF201E1B),
          surfaceContainer: const Color(0xFF2A2724),
          surfaceContainerHigh: const Color(0xFF35312C),
          surfaceContainerHighest: const Color(0xFF413C35),
          error: kErrorRed,
          onError: Colors.white,
        );

    return ThemeData(colorScheme: colorScheme, fontFamily: 'Lexend');
  }
}
