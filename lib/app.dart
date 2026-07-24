import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/providers.dart';
import 'features/notifications/push_registrar.dart';

class PawgoApp extends ConsumerWidget {
  const PawgoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Pawgo',
      debugShowCheckedModeBanner: false,
      theme: PgTheme.light(),
      darkTheme: PgTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      // Inside the router's builder so notification taps have a navigation
      // context to deep-link with.
      builder: (context, child) => PushRegistrar(child: child ?? const SizedBox()),
    );
  }
}
