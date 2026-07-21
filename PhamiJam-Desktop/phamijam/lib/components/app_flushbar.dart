import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';

class AppFlushbar {
  const AppFlushbar._();

  static void show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    Flushbar<void>(
      message: message,
      messageColor: foregroundColor,
      icon: Icon(icon, color: foregroundColor),
      duration: const Duration(seconds: 3),
      flushbarPosition: FlushbarPosition.TOP,
      margin: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(10),
      backgroundColor: backgroundColor,
    ).show(context);
  }

  static void success(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    show(
      context,
      message,
      icon: Icons.check_circle_rounded,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
    );
  }

  static void error(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    show(
      context,
      message,
      icon: Icons.error_rounded,
      backgroundColor: colorScheme.error,
      foregroundColor: colorScheme.onError,
    );
  }

  static void info(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    show(
      context,
      message,
      icon: Icons.info_rounded,
      backgroundColor: colorScheme.secondary,
      foregroundColor: colorScheme.onSecondary,
    );
  }
}
