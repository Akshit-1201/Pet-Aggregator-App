import 'package:flutter/material.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_screen_scaffold.dart';

class PlaceholderTab extends StatelessWidget {
  final String title;
  const PlaceholderTab({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return PgScreenScaffold(
      child: Center(child: Text(title, style: PgText.screenTitle(context))),
    );
  }
}
