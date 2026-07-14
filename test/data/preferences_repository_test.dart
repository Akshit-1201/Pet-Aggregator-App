import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet_aggregator_app/data/repositories/local/shared_preferences_repository.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('SharedPreferencesRepository persists theme mode across instances', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = SharedPreferencesRepository(await SharedPreferences.getInstance());
    expect(repo.themeMode, ThemeMode.system); // default when unset
    await repo.setThemeMode(ThemeMode.dark);
    expect(repo.themeMode, ThemeMode.dark);
    final repo2 = SharedPreferencesRepository(await SharedPreferences.getInstance());
    expect(repo2.themeMode, ThemeMode.dark); // read back from the store
  });

  test('InMemoryPreferencesRepository round-trips the mode', () async {
    final repo = InMemoryPreferencesRepository();
    expect(repo.themeMode, ThemeMode.system);
    await repo.setThemeMode(ThemeMode.light);
    expect(repo.themeMode, ThemeMode.light);
  });
}
