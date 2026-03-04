import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';

class AppFlushbar {
  const AppFlushbar._();

  static void show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color backgroundColor,
  }) {
    Flushbar<void>(
      message: message,
      icon: Icon(icon, color: Colors.white),
      duration: const Duration(seconds: 3),
      flushbarPosition: FlushbarPosition.TOP,
      margin: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(10),
      backgroundColor: backgroundColor,
    ).show(context);
  }

  static void success(BuildContext context, String message) {
    show(
      context,
      message,
      icon: Icons.check_circle_rounded,
      backgroundColor: Theme.of(context).colorScheme.primary,
    );
  }

  static void error(BuildContext context, String message) {
    show(
      context,
      message,
      icon: Icons.error_rounded,
      backgroundColor: Theme.of(context).colorScheme.error,
    );
  }

  static void info(BuildContext context, String message) {
    show(
      context,
      message,
      icon: Icons.info_rounded,
      backgroundColor: Theme.of(context).colorScheme.secondary,
    );
  }
}
