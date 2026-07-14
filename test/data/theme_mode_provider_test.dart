import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('themeModeProvider loads the saved mode and persists changes', () async {
    final prefs = InMemoryPreferencesRepository(ThemeMode.dark);
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.dark); // loaded from prefs
    await container.read(themeModeProvider.notifier).toggleDark(false);
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(prefs.themeMode, ThemeMode.light); // persisted through the repo
  });
}
