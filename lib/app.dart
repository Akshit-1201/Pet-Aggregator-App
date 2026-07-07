import 'package:flutter/material.dart';

class PawgoApp extends StatelessWidget {
  const PawgoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Pawgo',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text('Pawgo'))),
    );
  }
}
