import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';

class PawgoApp extends StatelessWidget {
  const PawgoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pawgo',
      debugShowCheckedModeBanner: false,
      theme: PgTheme.light(),
      darkTheme: PgTheme.dark(),
      themeMode: ThemeMode.light, // slice default; system-aware infra in place
      home: const Scaffold(body: Center(child: Text('Pawgo'))),
    );
  }
}
