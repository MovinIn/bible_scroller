import 'package:flutter/material.dart';

/// Shared SnackBar helpers so duration stays consistent app-wide.
class AppSnackBar {
  AppSnackBar._();

  static const Duration duration = Duration(milliseconds: 1500);

  static SnackBar build({required String message}) {
    return SnackBar(
      content: Text(message),
      duration: duration,
    );
  }

  static void show(BuildContext context, String message) {
    showWith(ScaffoldMessenger.of(context), message);
  }

  static void showWith(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(build(message: message));
  }
}
