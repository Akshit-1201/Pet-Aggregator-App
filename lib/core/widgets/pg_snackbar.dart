import 'package:flutter/material.dart';

void showComingSoon(BuildContext context, String label) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('$label is coming soon 🐾'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
}
