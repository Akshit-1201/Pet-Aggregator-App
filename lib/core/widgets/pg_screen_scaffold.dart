import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgScreenScaffold extends StatelessWidget {
  final Widget child;
  final Color? background;
  const PgScreenScaffold({super.key, required this.child, this.background});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background ?? context.pg.bg,
      body: SafeArea(bottom: false, child: child),
    );
  }
}
