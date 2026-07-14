import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'app.dart';
import 'data/repositories/providers.dart';
import 'data/repositories/local/shared_preferences_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [preferencesRepositoryProvider.overrideWithValue(SharedPreferencesRepository(prefs))],
    child: const PawgoApp(),
  ));
}
