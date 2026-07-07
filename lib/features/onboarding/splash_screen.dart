import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_typography.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) context.go(Routes.onboarding);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFF8B45E), Color(0xFFF0871E), Color(0xFFE07712)],
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 104, height: 104, alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)]),
                borderRadius: BorderRadius.circular(33),
                boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 50, offset: Offset(0, 20))],
              ),
              child: const Icon(Icons.pets, size: 58, color: Colors.white),
            ),
            const SizedBox(height: 26),
            Text('Pawgo', style: PgText.poppins(34, FontWeight.w800, color: Colors.white, ls: -0.5)),
            const SizedBox(height: 3),
            Text("Your pet's whole world, nearby",
                style: PgText.inter(13.5, FontWeight.w500, color: const Color(0xFFFFF5E8))),
          ]),
        ),
      ),
    );
  }
}
