# Pawgo Slice 1: Foundation + Onboarding/Auth — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Pawgo design-system foundation and the static Onboarding/Auth flow (Splash → 4 Onboarding → Welcome → Sign-up → Location → Create Pet → static Home), matching `design/Pawgo Prototype.dc.html`.

**Architecture:** Flutter, feature-first folders. A theme layer (`PgColors`/`PgText`/`PgRadius`) exposes the prototype's exact tokens; a set of shared widgets encapsulates all styling so each screen is thin composition. Navigation via `go_router` (full-screen routes for onboarding/auth; a `StatefulShellRoute` hosts the persistent bottom nav for Home + placeholder tabs). Screens read mock data through Riverpod-provided repository interfaces, so Firebase can slot in later without touching UI.

**Tech Stack:** Flutter 3.44+/Dart 3.12+, go_router, flutter_riverpod, google_fonts. Firebase packages already installed but unused in this slice.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Do not lower these.
- Keep `android/gradle.properties` → `kotlin.incremental=false` (Windows cross-drive build fix). Never delete it.
- **Static + mock only:** no Firebase / network / Maps / payment calls anywhere in this slice. Screens depend on repository interfaces, never on Firebase SDKs directly.
- Source of truth for every pixel value: `design/Pawgo Prototype.dc.html`. Exact hex tokens are duplicated into `PgColors` (Task 2).
- Fonts: Poppins (headings/buttons), Inter (body), via `google_fonts`.
- App default theme: **light**. Dark theme fully defined and switchable by device brightness; no in-app toggle this slice.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.
- Package/app id stays `com.example.pet_aggregator_app`.

---

### Task 1: Add dependencies, ProviderScope, app entrypoint

**Files:**
- Modify: `pubspec.yaml` (dependencies)
- Modify: `lib/main.dart`
- Create: `lib/app.dart`
- Test: `test/app_smoke_test.dart`

**Interfaces:**
- Produces: `PawgoApp` (StatelessWidget) — root widget, returns a `MaterialApp` (router wired in Task 9; a `home:` placeholder until then).

- [ ] **Step 1: Add packages**

Run: `flutter pub add go_router flutter_riverpod google_fonts`
Expected: `pubspec.yaml` gains the three deps, `Changed N dependencies!`.

- [ ] **Step 2: Write the failing smoke test**

```dart
// test/app_smoke_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/app.dart';

void main() {
  testWidgets('PawgoApp builds a MaterialApp', (tester) async {
    await tester.pumpWidget(const PawgoApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/app_smoke_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pet_aggregator_app/app.dart'`.

- [ ] **Step 4: Create `lib/app.dart`**

```dart
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
```

- [ ] **Step 5: Wire `main.dart` to ProviderScope + PawgoApp**

Replace the `MyApp` demo. Keep the existing Firebase init.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: PawgoApp()));
}
```

Delete the old `MyApp` / `MyHomePage` classes from `main.dart`.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/app_smoke_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add pubspec.yaml pubspec.lock lib/main.dart lib/app.dart test/app_smoke_test.dart
git commit -m "feat: add go_router/riverpod/google_fonts, ProviderScope, PawgoApp root"
```

---

### Task 2: Colour tokens (`PgColors`)

**Files:**
- Create: `lib/core/theme/app_colors.dart`
- Test: `test/core/theme/app_colors_test.dart`

**Interfaces:**
- Produces: `class PgColors` with fields `bg, surface, surface2, text, muted, faint, border, brand, brand2, brandDeep, brandSoft, ink, heart, blue, peach, lav, butter, mint, purple, pink` (all `Color`), plus `List<BoxShadow> shadow` and `shadowSm`. Const instances `PgColors.light` and `PgColors.dark`. Extension `context.pg` → picks set by `Theme.of(context).brightness`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/app_colors_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/theme/app_colors.dart';

void main() {
  test('light/dark brand + backgrounds match the prototype', () {
    expect(PgColors.light.brand, const Color(0xFFF59E2E));
    expect(PgColors.light.bg, const Color(0xFFFBF1E8));
    expect(PgColors.dark.bg, const Color(0xFF1A1410));
    expect(PgColors.dark.brand, const Color(0xFFF59E2E)); // constant across themes
    expect(PgColors.light.shadow, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/app_colors_test.dart`
Expected: FAIL — file/type not found.

- [ ] **Step 3: Implement `app_colors.dart`**

```dart
import 'package:flutter/material.dart';

@immutable
class PgColors {
  final Color bg, surface, surface2, text, muted, faint, border;
  final Color brand, brand2, brandDeep, brandSoft, ink, heart, blue;
  final Color peach, lav, butter, mint, purple, pink;
  final List<BoxShadow> shadow, shadowSm;

  const PgColors({
    required this.bg, required this.surface, required this.surface2,
    required this.text, required this.muted, required this.faint,
    required this.border, required this.brand, required this.brand2,
    required this.brandDeep, required this.brandSoft, required this.ink,
    required this.heart, required this.blue, required this.peach,
    required this.lav, required this.butter, required this.mint,
    required this.purple, required this.pink,
    required this.shadow, required this.shadowSm,
  });

  static const light = PgColors(
    bg: Color(0xFFFBF1E8), surface: Color(0xFFFFFFFF), surface2: Color(0xFFFBEDE1),
    text: Color(0xFF1F1A17), muted: Color(0xFF8A7F77), faint: Color(0xFFB7ACA2),
    border: Color(0xFFF1E5D8), brand: Color(0xFFF59E2E), brand2: Color(0xFFF0871E),
    brandDeep: Color(0xFFE07712), brandSoft: Color(0xFFFCE7CC), ink: Color(0xFF211B17),
    heart: Color(0xFFEF4B5E), blue: Color(0xFF6B8DE0), peach: Color(0xFFF4C9B6),
    lav: Color(0xFFE7DBF7), butter: Color(0xFFFBE7B0), mint: Color(0xFFCFEBD9),
    purple: Color(0xFFB79BE8), pink: Color(0xFFEC8FB0),
    shadow: [BoxShadow(color: Color(0x1F78481E), blurRadius: 32, offset: Offset(0, 12))],
    shadowSm: [BoxShadow(color: Color(0x1478481E), blurRadius: 16, offset: Offset(0, 5))],
  );

  static const dark = PgColors(
    bg: Color(0xFF1A1410), surface: Color(0xFF241C16), surface2: Color(0xFF2F251D),
    text: Color(0xFFF7EFE7), muted: Color(0xFFB6A99C), faint: Color(0xFF857667),
    border: Color(0xFF3A2E24), brand: Color(0xFFF59E2E), brand2: Color(0xFFF0871E),
    brandDeep: Color(0xFFE07712), brandSoft: Color(0xFF3D2A12), ink: Color(0xFF0E0A07),
    heart: Color(0xFFEF4B5E), blue: Color(0xFF6B8DE0), peach: Color(0xFF5A3D2C),
    lav: Color(0xFF352A47), butter: Color(0xFF403517), mint: Color(0xFF1E3A2C),
    purple: Color(0xFFB79BE8), pink: Color(0xFFEC8FB0),
    shadow: [BoxShadow(color: Color(0x8C000000), blurRadius: 36, offset: Offset(0, 14))],
    shadowSm: [BoxShadow(color: Color(0x73000000), blurRadius: 18, offset: Offset(0, 5))],
  );
}

extension PgColorsX on BuildContext {
  PgColors get pg =>
      Theme.of(this).brightness == Brightness.dark ? PgColors.dark : PgColors.light;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/app_colors_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_colors.dart test/core/theme/app_colors_test.dart
git commit -m "feat: add PgColors light/dark tokens from Pawgo prototype"
```

---

### Task 3: Radii/spacing + typography (`PgRadius`, `PgGap`, `PgText`)

**Files:**
- Create: `lib/core/theme/app_spacing.dart`
- Create: `lib/core/theme/app_typography.dart`
- Test: `test/core/theme/app_typography_test.dart`

**Interfaces:**
- Produces: `PgRadius` (static `double` consts: `button=16, input=14, card=18, bigCard=28, pill=24, iconBtn=13, sheet=28`). `PgGap` (`xs=6, sm=10, md=14, lg=22, xl=30`). `PgText` — static methods `poppins(double size, FontWeight w, {Color? color, double ls})` and `inter(...)`, plus named helpers `screenTitle(BuildContext)`, `sectionHeader(BuildContext)`, `body(BuildContext)`, `label(BuildContext)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/app_typography_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/theme/app_typography.dart';

void main() {
  test('poppins helper applies size and weight', () {
    final s = PgText.poppins(27, FontWeight.w800);
    expect(s.fontSize, 27);
    expect(s.fontWeight, FontWeight.w800);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/app_typography_test.dart`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement `app_spacing.dart`**

```dart
class PgRadius {
  static const double button = 16, input = 14, card = 18, bigCard = 28,
      pill = 24, iconBtn = 13, sheet = 28;
}

class PgGap {
  static const double xs = 6, sm = 10, md = 14, lg = 22, xl = 30;
}
```

- [ ] **Step 4: Implement `app_typography.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class PgText {
  static TextStyle poppins(double size, FontWeight w, {Color? color, double ls = 0}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: color, letterSpacing: ls);

  static TextStyle inter(double size, FontWeight w, {Color? color, double height = 1.0}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color, height: height);

  static TextStyle screenTitle(BuildContext c) =>
      poppins(24, FontWeight.w800, color: c.pg.text, ls: -0.5);
  static TextStyle sectionHeader(BuildContext c) =>
      poppins(16, FontWeight.w700, color: c.pg.text);
  static TextStyle body(BuildContext c) =>
      inter(14.5, FontWeight.w400, color: c.pg.muted, height: 1.55);
  static TextStyle label(BuildContext c) =>
      inter(12.5, FontWeight.w600, color: c.pg.muted);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/theme/app_typography_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/app_spacing.dart lib/core/theme/app_typography.dart test/core/theme/app_typography_test.dart
git commit -m "feat: add PgRadius/PgGap spacing and PgText typography helpers"
```

---

### Task 4: ThemeData + wire into `PawgoApp`

**Files:**
- Create: `lib/core/theme/app_theme.dart`
- Modify: `lib/app.dart`
- Test: `test/core/theme/app_theme_test.dart`

**Interfaces:**
- Produces: `PgTheme.light()` and `PgTheme.dark()` → `ThemeData`. `PawgoApp` uses `theme: PgTheme.light()`, `darkTheme: PgTheme.dark()`, `themeMode: ThemeMode.system`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/app_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';
import 'package:pet_aggregator_app/core/theme/app_colors.dart';

void main() {
  test('light theme uses Pawgo bg as scaffold background', () {
    expect(PgTheme.light().scaffoldBackgroundColor, PgColors.light.bg);
    expect(PgTheme.light().brightness, Brightness.light);
    expect(PgTheme.dark().brightness, Brightness.dark);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement `app_theme.dart`**

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class PgTheme {
  static ThemeData _base(PgColors c, Brightness b) => ThemeData(
        useMaterial3: true,
        brightness: b,
        scaffoldBackgroundColor: c.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: c.brand,
          brightness: b,
          surface: c.surface,
        ),
      );

  static ThemeData light() => _base(PgColors.light, Brightness.light);
  static ThemeData dark() => _base(PgColors.dark, Brightness.dark);
}
```

- [ ] **Step 4: Wire into `app.dart`**

Replace `PawgoApp.build` body:

```dart
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
```

- [ ] **Step 5: Run tests to verify pass**

Run: `flutter test test/core/theme/app_theme_test.dart test/app_smoke_test.dart`
Expected: PASS (both).

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/app_theme.dart lib/app.dart test/core/theme/app_theme_test.dart
git commit -m "feat: add PgTheme ThemeData and wire into PawgoApp"
```

---

### Task 5: Shared widgets — buttons, scaffold, test helper

**Files:**
- Create: `lib/core/widgets/pg_screen_scaffold.dart`
- Create: `lib/core/widgets/pg_buttons.dart`
- Create: `test/support/pump.dart`
- Test: `test/core/widgets/pg_buttons_test.dart`

**Interfaces:**
- Produces:
  - `PgScreenScaffold({required Widget child, Color? background})` — SafeArea + themed background.
  - `PgPrimaryButton({required String label, required VoidCallback onPressed, IconData? icon})` — amber gradient (`brand→brand2`, 135°), Poppins w700 15.5, white, radius `PgRadius.button`, brand glow shadow, scale-on-tap.
  - `PgGhostButton({required String label, required VoidCallback onPressed})` — transparent, muted text.
  - Test helper `pumpPg(WidgetTester, Widget, {Brightness})` wrapping child in `MaterialApp(theme..., home: Scaffold(body: child))`.

- [ ] **Step 1: Write the test helper**

```dart
// test/support/pump.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';

Future<void> pumpPg(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(MaterialApp(
    theme: brightness == Brightness.dark ? PgTheme.dark() : PgTheme.light(),
    home: Scaffold(body: child),
  ));
}
```

- [ ] **Step 2: Write the failing test**

```dart
// test/core/widgets/pg_buttons_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_buttons.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('PgPrimaryButton shows label and fires onPressed', (tester) async {
    var tapped = false;
    await pumpPg(tester, PgPrimaryButton(label: 'Log in', onPressed: () => tapped = true));
    expect(find.text('Log in'), findsOneWidget);
    await tester.tap(find.text('Log in'));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/core/widgets/pg_buttons_test.dart`
Expected: FAIL — `pg_buttons.dart` not found.

- [ ] **Step 4: Implement `pg_screen_scaffold.dart`**

```dart
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
```

- [ ] **Step 5: Implement `pg_buttons.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PgPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  const PgPrimaryButton(
      {super.key, required this.label, required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [c.brand, c.brand2],
          ),
          borderRadius: BorderRadius.circular(PgRadius.button),
          boxShadow: [
            BoxShadow(color: c.brand.withValues(alpha: 0.25),
                blurRadius: 30, offset: const Offset(0, 14)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
            Text(label, style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class PgGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const PgGhostButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label,
          style: PgText.inter(14, FontWeight.w600, color: context.pg.muted)),
    );
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/core/widgets/pg_buttons_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/core/widgets/pg_screen_scaffold.dart lib/core/widgets/pg_buttons.dart test/support/pump.dart test/core/widgets/pg_buttons_test.dart
git commit -m "feat: add PgScreenScaffold, PgPrimaryButton/PgGhostButton + test helper"
```

---

### Task 6: Shared widgets — inputs, choice card, toggle, page dots, chip, app bar, image slot

**Files:**
- Create: `lib/core/widgets/pg_field.dart`
- Create: `lib/core/widgets/pg_choice_card.dart`
- Create: `lib/core/widgets/pg_toggle.dart`
- Create: `lib/core/widgets/pg_page_dots.dart`
- Create: `lib/core/widgets/pg_chip.dart`
- Create: `lib/core/widgets/pg_app_bar.dart`
- Create: `lib/core/widgets/pg_image_slot.dart`
- Test: `test/core/widgets/pg_widgets_test.dart`

**Interfaces:**
- Produces:
  - `PgField({required String label, required String value, IconData? icon, bool obscure})` — surface2 fill, border, radius 14, label above (display-only).
  - `PgChoiceCard({required String emoji, required String title, required String subtitle, required bool selected, required VoidCallback onTap})` — selected = 2px brand border on brandSoft + check circle.
  - `PgToggle({required bool value, ValueChanged<bool>? onChanged})` — pill switch, brand when on.
  - `PgPageDots({required int count, required int index})` — active dot 24px brand bar.
  - `PgChip({required String label, Color? bg, Color? fg})` — pill.
  - `PgAppBar({required String title, VoidCallback? onBack})` — back chevron + Poppins 700 title.
  - `PgImageSlot({double? size, bool circle, String? emoji})` — rounded placeholder standing in for `<image-slot>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/pg_widgets_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_choice_card.dart';
import 'package:pet_aggregator_app/core/widgets/pg_page_dots.dart';
import 'package:pet_aggregator_app/core/widgets/pg_app_bar.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('PgChoiceCard fires onTap and shows title', (tester) async {
    var tapped = false;
    await pumpPg(tester, PgChoiceCard(
      emoji: '🐾', title: 'Pet Parent', subtitle: 'Discover, book, board & chat',
      selected: true, onTap: () => tapped = true));
    expect(find.text('Pet Parent'), findsOneWidget);
    await tester.tap(find.text('Pet Parent'));
    expect(tapped, isTrue);
  });

  testWidgets('PgPageDots renders `count` dots', (tester) async {
    await pumpPg(tester, const PgPageDots(count: 4, index: 0));
    expect(find.byKey(const ValueKey('pg-dot')), findsNWidgets(4));
  });

  testWidgets('PgAppBar shows title and back button', (tester) async {
    await pumpPg(tester, PgAppBar(title: 'Add your pet', onBack: () {}));
    expect(find.text('Add your pet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/pg_widgets_test.dart`
Expected: FAIL — files not found.

- [ ] **Step 3: Implement the seven widget files**

`lib/core/widgets/pg_field.dart`:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PgField extends StatelessWidget {
  final String label, value;
  final IconData? icon;
  final bool obscure;
  const PgField({super.key, required this.label, required this.value, this.icon, this.obscure = false});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: PgText.label(context)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(PgRadius.input),
          ),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: c.muted), const SizedBox(width: 11)],
            Text(obscure ? '••••••••' : value,
                style: PgText.inter(14.5, FontWeight.w500, color: c.text)),
          ]),
        ),
      ],
    );
  }
}
```

`lib/core/widgets/pg_choice_card.dart`:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class PgChoiceCard extends StatelessWidget {
  final String emoji, title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const PgChoiceCard({super.key, required this.emoji, required this.title,
      required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected ? c.brandSoft : c.surface,
          border: Border.all(color: selected ? c.brand : c.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.brand.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12)),
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
            Text(subtitle, style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          Container(
            width: 22, height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? c.brand : null,
              border: selected ? null : Border.all(color: c.border, width: 2)),
            child: selected ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
          ),
        ]),
      ),
    );
  }
}
```

`lib/core/widgets/pg_toggle.dart`:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const PgToggle({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Container(
        width: 46, height: 27,
        decoration: BoxDecoration(
          color: value ? c.brand : c.border,
          borderRadius: BorderRadius.circular(14)),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(width: 21, height: 21,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
        ),
      ),
    );
  }
}
```

`lib/core/widgets/pg_page_dots.dart`:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgPageDots extends StatelessWidget {
  final int count, index;
  const PgPageDots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Row(children: List.generate(count, (i) {
      final active = i == index;
      return Padding(
        padding: const EdgeInsets.only(right: 7),
        child: AnimatedContainer(
          key: const ValueKey('pg-dot'),
          duration: const Duration(milliseconds: 200),
          width: active ? 24 : 7, height: 7,
          decoration: BoxDecoration(
            color: active ? c.brand : c.border,
            borderRadius: BorderRadius.circular(4)),
        ),
      );
    }));
  }
}
```

`lib/core/widgets/pg_chip.dart`:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class PgChip extends StatelessWidget {
  final String label;
  final Color? bg, fg;
  const PgChip({super.key, required this.label, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? c.brandSoft,
        borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: PgText.poppins(11, FontWeight.w700, color: fg ?? c.brand)),
    );
  }
}
```

`lib/core/widgets/pg_app_bar.dart`:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PgAppBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  const PgAppBar({super.key, required this.title, this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
      child: Row(children: [
        if (onBack != null)
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 42, height: 42, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface, border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(PgRadius.iconBtn)),
              child: Icon(Icons.chevron_left, color: c.text)),
          ),
        if (onBack != null) const SizedBox(width: 14),
        Text(title, style: PgText.poppins(19, FontWeight.w700, color: c.text)),
      ]),
    );
  }
}
```

`lib/core/widgets/pg_image_slot.dart`:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgImageSlot extends StatelessWidget {
  final double? size;
  final bool circle;
  final String? emoji;
  final double radius;
  const PgImageSlot({super.key, this.size, this.circle = false, this.emoji, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: Border.all(color: c.border),
      ),
      child: Text(emoji ?? '🐾', style: const TextStyle(fontSize: 22)),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/pg_widgets_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/ test/core/widgets/pg_widgets_test.dart
git commit -m "feat: add PgField/PgChoiceCard/PgToggle/PgPageDots/PgChip/PgAppBar/PgImageSlot"
```

---

### Task 7: Domain models

**Files:**
- Create: `lib/data/models/role.dart`
- Create: `lib/data/models/user_profile.dart`
- Create: `lib/data/models/pet_profile.dart`
- Test: `test/data/models/pet_profile_test.dart`

**Interfaces:**
- Produces:
  - `enum Role { petParent, servicePro, homestayHost }` with `String get label`.
  - `class UserProfile { final String name, phone, area; final Role role; const UserProfile(...); }`
  - `enum Species { dog, cat, other }`
  - `class PetProfile { final String name, breed, ageLabel, distanceLabel; final Species species; final bool vaccinated; final Color accentColor; const PetProfile(...); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/data/models/pet_profile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';

void main() {
  test('PetProfile holds its fields', () {
    const p = PetProfile(name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
        distanceLabel: '0.4 km', species: Species.dog, vaccinated: true,
        accentColor: Color(0xFFF59E2E));
    expect(p.name, 'Bruno');
    expect(p.species, Species.dog);
  });

  test('Role label is human readable', () {
    expect(Role.petParent.label, 'Pet Parent');
    expect(Role.homestayHost.label, 'Homestay Host');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/pet_profile_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement the models**

`lib/data/models/role.dart`:
```dart
enum Role {
  petParent('Pet Parent'),
  servicePro('Service Professional'),
  homestayHost('Homestay Host');

  final String label;
  const Role(this.label);
}
```

`lib/data/models/user_profile.dart`:
```dart
import 'role.dart';

class UserProfile {
  final String name, phone, area;
  final Role role;
  const UserProfile({
    required this.name, required this.phone, required this.area, required this.role,
  });
}
```

`lib/data/models/pet_profile.dart`:
```dart
import 'package:flutter/material.dart';

enum Species { dog, cat, other }

class PetProfile {
  final String name, breed, ageLabel, distanceLabel;
  final Species species;
  final bool vaccinated;
  final Color accentColor;
  const PetProfile({
    required this.name, required this.breed, required this.ageLabel,
    required this.distanceLabel, required this.species,
    required this.vaccinated, required this.accentColor,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/pet_profile_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/ test/data/models/pet_profile_test.dart
git commit -m "feat: add Role/UserProfile/PetProfile domain models"
```

---

### Task 8: Repositories + mock data + Riverpod providers

**Files:**
- Create: `lib/data/repositories/pet_repository.dart`
- Create: `lib/data/mock/mock_pets.dart`
- Create: `lib/data/repositories/providers.dart`
- Test: `test/data/mock_pet_repository_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class PetRepository { List<PetProfile> nearbyPets(); }`
  - `class MockPetRepository implements PetRepository` — returns `mockPets`.
  - `const List<PetProfile> mockPets` — Bruno (Labrador/dog/0.4 km), Mochi (Persian/cat/0.9 km), Simba (Beagle/dog/0.7 km), Coco (Indie/dog/1.2 km).
  - `final petRepositoryProvider = Provider<PetRepository>((ref) => MockPetRepository());`
  - `final nearbyPetsProvider = Provider<List<PetProfile>>((ref) => ref.watch(petRepositoryProvider).nearbyPets());`

- [ ] **Step 1: Write the failing test**

```dart
// test/data/mock_pet_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';

void main() {
  test('MockPetRepository returns the prototype pets', () {
    final pets = MockPetRepository().nearbyPets();
    expect(pets.length, greaterThanOrEqualTo(3));
    expect(pets.first.name, 'Bruno');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/mock_pet_repository_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement mock data + repository**

`lib/data/mock/mock_pets.dart`:
```dart
import 'package:flutter/material.dart';
import '../models/pet_profile.dart';

const List<PetProfile> mockPets = [
  PetProfile(name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
      distanceLabel: '0.4 km · Bandra West', species: Species.dog,
      vaccinated: true, accentColor: Color(0xFFF0871E)),
  PetProfile(name: 'Mochi', breed: 'Persian cat', ageLabel: '1 yr',
      distanceLabel: '0.9 km · Khar', species: Species.cat,
      vaccinated: true, accentColor: Color(0xFFEC8FB0)),
  PetProfile(name: 'Simba', breed: 'Beagle', ageLabel: '3 yrs',
      distanceLabel: '0.7 km · Bandra West', species: Species.dog,
      vaccinated: true, accentColor: Color(0xFF6B8DE0)),
  PetProfile(name: 'Coco', breed: 'Indie', ageLabel: '4 yrs',
      distanceLabel: '1.2 km · Santacruz', species: Species.dog,
      vaccinated: false, accentColor: Color(0xFFB79BE8)),
];
```

`lib/data/repositories/pet_repository.dart`:
```dart
import '../models/pet_profile.dart';
import '../mock/mock_pets.dart';

abstract interface class PetRepository {
  List<PetProfile> nearbyPets();
}

class MockPetRepository implements PetRepository {
  const MockPetRepository();
  @override
  List<PetProfile> nearbyPets() => mockPets;
}
```

`lib/data/repositories/providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pet_profile.dart';
import 'pet_repository.dart';

final petRepositoryProvider =
    Provider<PetRepository>((ref) => const MockPetRepository());

final nearbyPetsProvider =
    Provider<List<PetProfile>>((ref) => ref.watch(petRepositoryProvider).nearbyPets());
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/mock_pet_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/ lib/data/mock/ test/data/mock_pet_repository_test.dart
git commit -m "feat: add PetRepository interface, mock pets, Riverpod providers"
```

---

### Task 9: Router, route constants, shell + bottom nav, placeholder tabs

**Files:**
- Create: `lib/core/router/routes.dart`
- Create: `lib/core/widgets/pg_bottom_nav.dart`
- Create: `lib/features/home/home_shell.dart`
- Create: `lib/features/home/placeholder_tab.dart`
- Create: `lib/core/router/app_router.dart`
- Modify: `lib/app.dart`
- Test: `test/core/router/app_router_test.dart`

**Interfaces:**
- Consumes: screen widgets are added to routes in later tasks; until then route builders point to a temporary `Placeholder`-style stub for onboarding/auth and real `PlaceholderTab` for tabs.
- Produces:
  - `class Routes { static const splash='/', onboarding='/onboarding', welcome='/welcome', signup='/signup', location='/location', createPet='/create-pet', home='/home', discover='/discover', services='/services', community='/community', profile='/profile'; }`
  - `appRouter` — a `GoRouter`. Onboarding/auth are top-level routes; `home/discover/services/community/profile` live in a `StatefulShellRoute.indexedStack` rendering `HomeShell` + `PgBottomNav`.
  - `PgBottomNav({required int currentIndex, required ValueChanged<int> onTap})`.
  - `PlaceholderTab({required String title})`.

> Screens built in later tasks replace the temporary stubs by editing `app_router.dart` (each later task lists this edit).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/router/app_router_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/core/router/app_router.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';

void main() {
  testWidgets('router starts at splash and can navigate to home shell', (tester) async {
    final router = buildRouter(initialLocation: '/home');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(theme: PgTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // bottom nav label present
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/router/app_router_test.dart`
Expected: FAIL — `buildRouter` not found.

- [ ] **Step 3: Implement routes + bottom nav + shell + placeholder**

`lib/core/router/routes.dart`:
```dart
class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const welcome = '/welcome';
  static const signup = '/signup';
  static const location = '/location';
  static const createPet = '/create-pet';
  static const home = '/home';
  static const discover = '/discover';
  static const services = '/services';
  static const community = '/community';
  static const profile = '/profile';
}
```

`lib/core/widgets/pg_bottom_nav.dart`:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class PgBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const PgBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.explore_rounded, label: 'Discover'),
    (icon: Icons.pets_rounded, label: 'Services'),
    (icon: Icons.forum_rounded, label: 'Community'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.of(context).padding.bottom),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_items.length, (i) {
          final active = i == currentIndex;
          final color = active ? c.brand : c.faint;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(_items[i].icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(_items[i].label, style: PgText.inter(10.5, FontWeight.w600, color: color)),
            ]),
          );
        }),
      ),
    );
  }
}
```

`lib/features/home/placeholder_tab.dart`:
```dart
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
```

`lib/features/home/home_shell.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/pg_bottom_nav.dart';

class HomeShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const HomeShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: PgBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (i) => navigationShell.goBranch(i,
            initialLocation: i == navigationShell.currentIndex),
      ),
    );
  }
}
```

`lib/core/router/app_router.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/placeholder_tab.dart';
import 'routes.dart';

// Temporary stub until onboarding/auth screens land (Tasks 10-15).
Widget _stub(String name) => Scaffold(body: Center(child: Text(name)));

GoRouter buildRouter({String initialLocation = Routes.splash}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => _stub('Splash')),
      GoRoute(path: Routes.onboarding, builder: (_, __) => _stub('Onboarding')),
      GoRoute(path: Routes.welcome, builder: (_, __) => _stub('Welcome')),
      GoRoute(path: Routes.signup, builder: (_, __) => _stub('Signup')),
      GoRoute(path: Routes.location, builder: (_, __) => _stub('Location')),
      GoRoute(path: Routes.createPet, builder: (_, __) => _stub('Create Pet')),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, __) => const PlaceholderTab(title: 'Home')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.discover, builder: (_, __) => const PlaceholderTab(title: 'Discover')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.services, builder: (_, __) => const PlaceholderTab(title: 'Services')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.community, builder: (_, __) => const PlaceholderTab(title: 'Community')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.profile, builder: (_, __) => const PlaceholderTab(title: 'Profile')),
          ]),
        ],
      ),
    ],
  );
}

final appRouter = buildRouter();
```

- [ ] **Step 4: Wire router into `app.dart`**

```dart
import 'package:flutter/material.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class PawgoApp extends StatelessWidget {
  const PawgoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Pawgo',
      debugShowCheckedModeBanner: false,
      theme: PgTheme.light(),
      darkTheme: PgTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
```

- [ ] **Step 5: Run tests to verify pass**

Run: `flutter test test/core/router/app_router_test.dart test/app_smoke_test.dart`
Expected: PASS. (Update `app_smoke_test.dart` if it asserted `MaterialApp`; `MaterialApp.router` still satisfies `find.byType(MaterialApp)`.)

- [ ] **Step 6: Commit**

```bash
git add lib/core/router/ lib/core/widgets/pg_bottom_nav.dart lib/features/home/ lib/app.dart test/core/router/app_router_test.dart
git commit -m "feat: add go_router config, StatefulShellRoute, PgBottomNav, placeholder tabs"
```

---

### Task 10: Splash screen

**Files:**
- Create: `lib/features/onboarding/splash_screen.dart`
- Modify: `lib/core/router/app_router.dart` (replace splash stub)
- Test: `test/features/splash_screen_test.dart`

**Fidelity reference:** `design/Pawgo Prototype.dc.html` lines 111–132.

**Interfaces:**
- Produces: `SplashScreen` — amber gradient (`#F8B45E→#F0871E→#E07712`, top-left→bottom-right), centred rounded-square logo tile (104×104, radius 33, white paw icon → use `Icons.pets` size 58 white as stand-in), "Pawgo" (Poppins 800/34 white) + tagline "Your pet's whole world, nearby" (Inter 13.5 `#FFF5E8`). After 1600 ms, `context.go(Routes.onboarding)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/splash_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/onboarding/splash_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('SplashScreen shows brand name and tagline', (tester) async {
    await pumpPg(tester, const SplashScreen());
    expect(find.text('Pawgo'), findsOneWidget);
    expect(find.text("Your pet's whole world, nearby"), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // let the timer fire
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/splash_screen_test.dart`
Expected: FAIL — `SplashScreen` not found.

- [ ] **Step 3: Implement `splash_screen.dart`**

```dart
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
```

- [ ] **Step 4: Replace splash stub in `app_router.dart`**

Change the splash route to: `GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen())` and add `import '../../features/onboarding/splash_screen.dart';`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/splash_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/onboarding/splash_screen.dart lib/core/router/app_router.dart test/features/splash_screen_test.dart
git commit -m "feat: add Splash screen"
```

---

### Task 11: Onboarding (data-driven, 4 pages)

**Files:**
- Create: `lib/features/onboarding/onboarding_screen.dart`
- Modify: `lib/core/router/app_router.dart` (replace onboarding stub)
- Test: `test/features/onboarding_screen_test.dart`

**Fidelity reference:** lines 134–249.

**Interfaces:**
- Produces: `OnboardingScreen` — a `PageView` of 4 `_OnboardPage`s. Each page: 460px header (per-page gradient + `PgImageSlot` floating card) over content (title Poppins 800/27, body Inter 14.5 muted, `PgPageDots(count:4,index:i)`, Skip + Next; page 4 uses full-width `PgPrimaryButton('Get started')`). Skip/Get started → `context.go(Routes.welcome)`. Next → animate to next page.
- Page copy (title / body / header gradient start-end):
  1. `Find playmates just around the corner` / `Discover pets and parents near you, send a friendly Woof 👋 and set up a playdate at the park.` / `#FDF1D8→#FAE3B0`
  2. `Trusted walkers, sitters & groomers` / `Book verified pros near you, pay in-app and rate them after — all in a few taps.` / `#E0F5EF→#BFEBDD`
  3. `Homestays with verified hosts` / `Going away? Find a loving, vetted home to board your pet — like Airbnb, built on trust and reviews.` / `#EDE6FB→#D6C8F5`
  4. `A community that has your back` / `Ask questions, share advice, post lost & found — your neighbourhood pet circle, always on.` / `#DCEBFB→#BBD8F7`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/onboarding_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/onboarding/onboarding_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Onboarding shows first page title and a Next action', (tester) async {
    await pumpPg(tester, const OnboardingScreen());
    expect(find.text('Find playmates just around the corner'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/onboarding_screen_test.dart`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement `onboarding_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_page_dots.dart';
import '../../core/widgets/pg_image_slot.dart';

class _Page {
  final String title, body;
  final List<Color> gradient;
  const _Page(this.title, this.body, this.gradient);
}

const _pages = [
  _Page('Find playmates just around the corner',
      'Discover pets and parents near you, send a friendly Woof 👋 and set up a playdate at the park.',
      [Color(0xFFFDF1D8), Color(0xFFFAE3B0)]),
  _Page('Trusted walkers, sitters & groomers',
      'Book verified pros near you, pay in-app and rate them after — all in a few taps.',
      [Color(0xFFE0F5EF), Color(0xFFBFEBDD)]),
  _Page('Homestays with verified hosts',
      'Going away? Find a loving, vetted home to board your pet — like Airbnb, built on trust and reviews.',
      [Color(0xFFEDE6FB), Color(0xFFD6C8F5)]),
  _Page('A community that has your back',
      'Ask questions, share advice, post lost & found — your neighbourhood pet circle, always on.',
      [Color(0xFFDCEBFB), Color(0xFFBBD8F7)]),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  void _toWelcome() => context.go(Routes.welcome);
  void _next() {
    if (_index == _pages.length - 1) {
      _toWelcome();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: PageView.builder(
        controller: _controller,
        itemCount: _pages.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final p = _pages[i];
          final isLast = i == _pages.length - 1;
          return Column(children: [
            SizedBox(
              height: 460,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: p.gradient),
                ),
                alignment: Alignment.center,
                child: Transform.rotate(
                  angle: (i.isEven ? -4 : 4) * 3.1416 / 180,
                  child: Container(
                    width: 236, height: 300, padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: c.shadow),
                    child: const PgImageSlot(radius: 20, emoji: '🐶'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 34, 30, 30),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.title, style: PgText.poppins(27, FontWeight.w800, color: c.text, ls: -0.5)),
                  const SizedBox(height: 14),
                  Text(p.body, style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: PgPageDots(count: _pages.length, index: i),
                  ),
                  if (isLast)
                    PgPrimaryButton(label: 'Get started', onPressed: _toWelcome)
                  else
                    Row(children: [
                      GestureDetector(
                        onTap: _toWelcome,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                          child: Text('Skip', style: PgText.inter(14, FontWeight.w600, color: c.muted)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: PgPrimaryButton(label: 'Next', onPressed: _next)),
                    ]),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Replace onboarding stub in `app_router.dart`**

Change onboarding route to `builder: (_, __) => const OnboardingScreen()` + add its import.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/onboarding_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/onboarding/onboarding_screen.dart lib/core/router/app_router.dart test/features/onboarding_screen_test.dart
git commit -m "feat: add data-driven 4-page Onboarding screen"
```

---

### Task 12: Welcome / Login screen

**Files:**
- Create: `lib/features/auth/welcome_screen.dart`
- Modify: `lib/core/router/app_router.dart`
- Test: `test/features/welcome_screen_test.dart`

**Fidelity reference:** lines 251–282.

**Interfaces:**
- Produces: `WelcomeScreen` — amber gradient top with logo tile + "Welcome back 👋" (Poppins 800/30 white) + "Log in to your Pawgo account"; white rounded-top sheet (radius 32 top) with two `PgField`s (phone `+91 98200 41122` icon phone; password obscured, trailing "Forgot?"), `PgPrimaryButton('Log in')` → `context.go(Routes.home)`, "or continue with" divider, Google/Apple ghost buttons (visual only), and "New to Pawgo? Create account" → `context.go(Routes.signup)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/welcome_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/auth/welcome_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Welcome shows heading and Log in button', (tester) async {
    await pumpPg(tester, const WelcomeScreen());
    expect(find.text('Welcome back 👋'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/welcome_screen_test.dart`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement `welcome_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_field.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFF8B45E), Color(0xFFF0871E)]),
        ),
        child: Column(children: [
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 84, height: 84, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)]),
                    borderRadius: BorderRadius.circular(26)),
                  child: const Icon(Icons.pets, size: 46, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text('Welcome back 👋', style: PgText.poppins(30, FontWeight.w800, color: Colors.white, ls: -0.5)),
                const SizedBox(height: 5),
                Text('Log in to your Pawgo account',
                    style: PgText.inter(14, FontWeight.w500, color: const Color(0xFFFFF5E8))),
              ]),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const PgField(label: '', value: '+91 98200 41122', icon: Icons.phone_outlined),
              const SizedBox(height: 14),
              const PgField(label: '', value: '', icon: Icons.lock_outline, obscure: true),
              const SizedBox(height: 18),
              PgPrimaryButton(label: 'Log in', onPressed: () => context.go(Routes.home)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => context.go(Routes.signup),
                child: Text.rich(TextSpan(
                  text: 'New to Pawgo? ',
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted),
                  children: [TextSpan(text: 'Create account',
                      style: PgText.inter(13.5, FontWeight.w700, color: c.brand))],
                )),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
```

> Note: `PgField` with an empty `label` renders no label row — acceptable for the login sheet. (Login fields are display-only this slice.)

- [ ] **Step 4: Replace welcome stub in `app_router.dart`** (route builder → `const WelcomeScreen()` + import).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/welcome_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/welcome_screen.dart lib/core/router/app_router.dart test/features/welcome_screen_test.dart
git commit -m "feat: add Welcome/Login screen"
```

---

### Task 13: Sign-up + Role screen

**Files:**
- Create: `lib/features/auth/signup_screen.dart`
- Modify: `lib/core/router/app_router.dart`
- Test: `test/features/signup_screen_test.dart`

**Fidelity reference:** lines 284–319.

**Interfaces:**
- Produces: `SignupScreen` (StatefulWidget for role selection) — `PgAppBar('Create account', onBack: context.pop or go welcome)`; scrolling body with intro line + three `PgField`s (Full name `Radhika Nair`, Mobile `+91 98200 41122`, Password obscured); "I'M JOINING AS" label; three `PgChoiceCard`s bound to `Role` (default `Role.petParent` selected). Sticky bottom `PgPrimaryButton('Continue')` → `context.go(Routes.location)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/signup_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/auth/signup_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Signup shows the three roles and Continue', (tester) async {
    await pumpPg(tester, const SignupScreen());
    expect(find.text('Pet Parent'), findsOneWidget);
    expect(find.text('Service Professional'), findsOneWidget);
    expect(find.text('Homestay Host'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Tapping a role selects it', (tester) async {
    await pumpPg(tester, const SignupScreen());
    await tester.tap(find.text('Homestay Host'));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget); // only the selected card shows a check
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/signup_screen_test.dart`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement `signup_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_choice_card.dart';
import '../../core/widgets/pg_field.dart';
import '../../data/models/role.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  Role _role = Role.petParent;

  static const _subtitles = {
    Role.petParent: 'Discover, book, board & chat',
    Role.servicePro: 'Offer walks, grooming & sitting',
    Role.homestayHost: 'Board pets & earn (needs verification)',
  };
  static const _emojis = {
    Role.petParent: '🐾', Role.servicePro: '🎒', Role.homestayHost: '🏡',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Create account', onBack: () => context.go(Routes.welcome)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
              children: [
                Text('Just a few details to get you and your pet started.',
                    style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                const SizedBox(height: 13),
                const PgField(label: 'Full name', value: 'Radhika Nair'),
                const SizedBox(height: 13),
                const PgField(label: 'Mobile number', value: '+91 98200 41122'),
                const SizedBox(height: 13),
                const PgField(label: 'Password', value: '', obscure: true),
                const SizedBox(height: 16),
                Text("I'M JOINING AS", style: PgText.inter(12.5, FontWeight.w700, color: c.muted)),
                const SizedBox(height: 10),
                for (final r in Role.values) ...[
                  PgChoiceCard(
                    emoji: _emojis[r]!, title: r.label, subtitle: _subtitles[r]!,
                    selected: _role == r, onTap: () => setState(() => _role = r)),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(label: 'Continue', onPressed: () => context.go(Routes.location)),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Replace signup stub in `app_router.dart`** (builder → `const SignupScreen()` + import).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/signup_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/signup_screen.dart lib/core/router/app_router.dart test/features/signup_screen_test.dart
git commit -m "feat: add Sign-up + role selection screen"
```

---

### Task 14: Location permission screen

**Files:**
- Create: `lib/features/auth/location_screen.dart`
- Modify: `lib/core/router/app_router.dart`
- Test: `test/features/location_screen_test.dart`

**Fidelity reference:** lines 321–337.

**Interfaces:**
- Produces: `LocationScreen` — centred illustration (stacked circles + `Icons.location_on` brand, size 92), "Enable location" (Poppins 800/25), copy stressing approximate area only; `PgPrimaryButton('Allow while using app')` and a `PgGhostButton('Set location manually')` — both `context.go(Routes.createPet)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/location_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/auth/location_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Location screen shows heading and allow button', (tester) async {
    await pumpPg(tester, const LocationScreen());
    expect(find.text('Enable location'), findsOneWidget);
    expect(find.text('Allow while using app'), findsOneWidget);
    expect(find.text('Set location manually'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/location_screen_test.dart`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement `location_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';

class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 220, height: 220, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
              child: Icon(Icons.location_on, size: 92, color: c.brand),
            ),
            const SizedBox(height: 28),
            Text('Enable location', style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 12),
            Text(
              'Pawgo shows pets, pros and homestays near you. We only ever share your approximate area — never your exact address.',
              textAlign: TextAlign.center,
              style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
            const Spacer(),
            PgPrimaryButton(label: 'Allow while using app', onPressed: () => context.go(Routes.createPet)),
            const SizedBox(height: 6),
            PgGhostButton(label: 'Set location manually', onPressed: () => context.go(Routes.createPet)),
          ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Replace location stub in `app_router.dart`** (builder → `const LocationScreen()` + import).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/location_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/location_screen.dart lib/core/router/app_router.dart test/features/location_screen_test.dart
git commit -m "feat: add Location permission screen"
```

---

### Task 15: Create Pet screen

**Files:**
- Create: `lib/features/pets/create_pet_screen.dart`
- Modify: `lib/core/router/app_router.dart`
- Test: `test/features/create_pet_screen_test.dart`

**Fidelity reference:** lines 339–372.

**Interfaces:**
- Produces: `CreatePetScreen` (Stateful — species selection + vaccinated toggle) — `PgAppBar('Add your pet', onBack → go signup)`; circular `PgImageSlot(size 110, circle)` + "Upload a cute photo 📸"; `PgField`s Pet name `Bruno`, Breed `Labrador` + Age `2 yrs` in a row; Species segmented (Dog/Cat/Other, default Dog) via `Species`; Vaccinated row with `PgToggle` (default on); sticky `PgPrimaryButton('Finish & explore Pawgo')` → `context.go(Routes.home)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/create_pet_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/pets/create_pet_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Create pet shows fields and finish button', (tester) async {
    await pumpPg(tester, const CreatePetScreen());
    expect(find.text('Add your pet'), findsOneWidget);
    expect(find.text('Vaccinated'), findsOneWidget);
    expect(find.text('Finish & explore Pawgo'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/create_pet_screen_test.dart`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement `create_pet_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_field.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_toggle.dart';
import '../../data/models/pet_profile.dart';

class CreatePetScreen extends StatefulWidget {
  const CreatePetScreen({super.key});
  @override
  State<CreatePetScreen> createState() => _CreatePetScreenState();
}

class _CreatePetScreenState extends State<CreatePetScreen> {
  Species _species = Species.dog;
  bool _vaccinated = true;

  static const _speciesLabel = {
    Species.dog: '🐶 Dog', Species.cat: '🐱 Cat', Species.other: '🐦 Other',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Add your pet', onBack: () => context.go(Routes.signup)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
              children: [
                Center(child: Column(children: [
                  const PgImageSlot(size: 110, circle: true, emoji: '📸'),
                  const SizedBox(height: 10),
                  Text('Upload a cute photo 📸', style: PgText.inter(13, FontWeight.w600, color: c.brand)),
                ])),
                const SizedBox(height: 14),
                const PgField(label: 'Pet name', value: 'Bruno'),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Expanded(child: PgField(label: 'Breed', value: 'Labrador')),
                  SizedBox(width: 12),
                  SizedBox(width: 104, child: PgField(label: 'Age', value: '2 yrs')),
                ]),
                const SizedBox(height: 14),
                Text('Species', style: PgText.label(context)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final s in Species.values) ...[
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => _species = s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _species == s ? c.brandSoft : null,
                          border: Border.all(
                            color: _species == s ? c.brand : c.border,
                            width: _species == s ? 2 : 1),
                          borderRadius: BorderRadius.circular(13)),
                        child: Text(_speciesLabel[s]!,
                          style: PgText.inter(13.5, FontWeight.w600,
                            color: _species == s ? c.brand : c.muted)),
                      ),
                    )),
                    if (s != Species.other) const SizedBox(width: 9),
                  ],
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  decoration: BoxDecoration(
                    color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Text('💉', style: TextStyle(fontSize: 17)),
                    const SizedBox(width: 10),
                    Text('Vaccinated', style: PgText.inter(14, FontWeight.w600, color: c.text)),
                    const Spacer(),
                    PgToggle(value: _vaccinated, onChanged: (v) => setState(() => _vaccinated = v)),
                  ]),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(
              label: 'Finish & explore Pawgo', onPressed: () => context.go(Routes.home)),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Replace create-pet stub in `app_router.dart`** (builder → `const CreatePetScreen()` + import).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/create_pet_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/pets/create_pet_screen.dart lib/core/router/app_router.dart test/features/create_pet_screen_test.dart
git commit -m "feat: add Create Pet profile screen"
```

---

### Task 16: Home feed (static, in shell) + PetRow

**Files:**
- Create: `lib/features/home/widgets/pet_row.dart`
- Create: `lib/features/home/home_screen.dart`
- Modify: `lib/core/router/app_router.dart` (Home branch → `HomeScreen`)
- Test: `test/features/home_screen_test.dart`

**Fidelity reference:** lines 374–437.

**Interfaces:**
- Consumes: `nearbyPetsProvider` (Task 8), `PgChip`, `PgImageSlot`.
- Produces:
  - `PetRow({required PetProfile pet, required VoidCallback onWoof})` — avatar + name/accent dot + `breed · age · dist` + "Woof!" button.
  - `HomeScreen` (ConsumerWidget) — header (📍 Bandra West, Mumbai · "Hey Radhika 👋" · "6 pets near you today" · bell + avatar); 2×2 quick-action grid (Discover=brand gradient, Services=butter, Homestay=lav, Community=mint), each `onTap` navigates to its tab/route; "Pets near you" section listing `PetRow` from `nearbyPetsProvider`; "Community picks" card with a `PgChip('Health')`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/home_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';
import 'package:pet_aggregator_app/features/home/home_screen.dart';

void main() {
  testWidgets('Home shows greeting and a nearby pet', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: PgTheme.light(), home: const HomeScreen()),
    ));
    expect(find.text('Hey Radhika 👋'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Woof!'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/home_screen_test.dart`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement `pet_row.dart`**

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pg_image_slot.dart';
import '../../../data/models/pet_profile.dart';

class PetRow extends StatelessWidget {
  final PetProfile pet;
  final VoidCallback onWoof;
  const PetRow({super.key, required this.pet, required this.onWoof});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface, border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
      child: Row(children: [
        const PgImageSlot(size: 54, circle: true),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(pet.name, style: PgText.poppins(15, FontWeight.w700, color: c.text)),
            const SizedBox(width: 6),
            Container(width: 7, height: 7,
              decoration: BoxDecoration(color: pet.accentColor, shape: BoxShape.circle)),
          ]),
          const SizedBox(height: 2),
          Text('${pet.breed} · ${pet.ageLabel} · ${pet.distanceLabel}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ])),
        GestureDetector(
          onTap: onWoof,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.brand, c.brand2]),
              borderRadius: BorderRadius.circular(13)),
            child: Text('Woof!', style: PgText.poppins(13, FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Implement `home_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_chip.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/repositories/providers.dart';
import 'widgets/pet_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final pets = ref.watch(nearbyPetsProvider);
    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
            decoration: BoxDecoration(
              color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.location_on, size: 14, color: c.brand),
                  const SizedBox(width: 4),
                  Text('Bandra West, Mumbai', style: PgText.inter(12.5, FontWeight.w600, color: c.muted)),
                ]),
                const SizedBox(height: 5),
                Text('Hey Radhika 👋', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.5)),
                const SizedBox(height: 2),
                Text('6 pets near you today', style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
              ])),
              const PgImageSlot(size: 46, circle: true),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              children: [
                GridView.count(
                  crossAxisCount: 2, shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5,
                  children: [
                    _QuickAction(emoji: '🐾', title: 'Discover', subtitle: 'Swipe & Woof nearby pets',
                      bg: null, gradient: [c.brand2, const Color(0xFFF8B45E)], fg: Colors.white,
                      onTap: () => context.go(Routes.discover)),
                    _QuickAction(emoji: '🦮', title: 'Services', subtitle: 'Walkers, sitters, groomers',
                      bg: c.butter, fg: c.text, onTap: () => context.go(Routes.services)),
                    _QuickAction(emoji: '🏡', title: 'Homestay', subtitle: 'Verified boarding hosts',
                      bg: c.lav, fg: c.text, onTap: () => context.go(Routes.services)),
                    _QuickAction(emoji: '💬', title: 'Community', subtitle: 'Ask, share, lost & found',
                      bg: c.mint, fg: c.text, onTap: () => context.go(Routes.community)),
                  ],
                ),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Pets near you', style: PgText.sectionHeader(context)),
                  GestureDetector(
                    onTap: () => context.go(Routes.discover),
                    child: Text('See map →', style: PgText.inter(12.5, FontWeight.w600, color: c.brand))),
                ]),
                const SizedBox(height: 13),
                for (final p in pets) ...[
                  PetRow(pet: p, onWoof: () {}),
                  const SizedBox(height: 11),
                ],
                const SizedBox(height: 11),
                Text('Community picks', style: PgText.sectionHeader(context)),
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const PgChip(label: 'Health'),
                    const SizedBox(height: 10),
                    Text('"Best vet in Bandra for vaccinations?"',
                      style: PgText.poppins(15, FontWeight.w600, color: c.text)),
                    const SizedBox(height: 8),
                    Text('24 replies · posted by @dachshund_dad',
                      style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color? bg;
  final List<Color>? gradient;
  final Color fg;
  final VoidCallback onTap;
  const _QuickAction({required this.emoji, required this.title, required this.subtitle,
      required this.bg, this.gradient, required this.fg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          gradient: gradient == null ? null : LinearGradient(colors: gradient!),
          borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.poppins(15, FontWeight.w700, color: fg)),
            Text(subtitle, style: PgText.inter(11.5, FontWeight.w400,
              color: fg.withValues(alpha: 0.8))),
          ]),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 5: Point the Home branch at `HomeScreen`**

In `app_router.dart`, Home branch builder → `const HomeScreen()` and add its import (replaces `PlaceholderTab(title:'Home')`).

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/home_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/home/ lib/core/router/app_router.dart test/features/home_screen_test.dart
git commit -m "feat: add static Home feed with quick actions, nearby pets, community pick"
```

---

### Task 17: Manual run + slice verification

**Files:** none (verification only).

- [ ] **Step 1: Launch on the emulator**

Run: `flutter run -d emulator-5554`
Expected: app boots to Splash → auto-advances to Onboarding.

- [ ] **Step 2: Walk the flow**

Verify by hand: Onboarding (swipe 4 pages, Skip/Next work) → Welcome (Log in → Home; Create account → Sign-up) → Sign-up (role selection toggles, Continue → Location) → Location (Allow → Create Pet) → Create Pet (species + vaccinated toggle, Finish → Home) → Home shows greeting, quick-action grid, nearby pets, community pick, and the bottom nav switches tabs.

- [ ] **Step 3: Compare against the prototype**

Open `design/Pawgo Prototype.dc.html` in a browser (or the `screens/` PNGs) and eyeball colours, fonts, spacing per screen. Note any drift as follow-up polish items — do not block the slice on pixel-perfection.

- [ ] **Step 4: Final commit if any polish tweaks were made**

```bash
git add -A
git commit -m "chore: onboarding/auth fidelity polish against prototype"
```

---

## Self-Review

**Spec coverage:** Architecture (Task 1,4,9) ✓ · design tokens light+dark (Task 2,3) ✓ · shared widgets list (Task 5,6) ✓ · models/mock/repositories/providers (Task 7,8) ✓ · router + shell + bottom nav (Task 9) ✓ · all 7 flow screens + static Home (Tasks 10–16) ✓ · testing (widget test per screen) ✓ · fidelity/deviations note (Task 17) ✓ · phone-frame dropped ✓. Out-of-scope items (Firebase wiring, Maps, payments, real OTP/upload/validation) are not implemented, as intended.

**Placeholder scan:** No "TBD/TODO/handle edge cases". The router uses explicit temporary `_stub` builders that each later task explicitly replaces — these are named and tracked, not vague placeholders.

**Type consistency:** `Routes.*` constants used identically across tasks; `PetProfile`/`Species`/`Role` fields match their Task 7 definitions; `nearbyPetsProvider` (Task 8) consumed in Task 16; `PgPrimaryButton(label:,onPressed:)`, `PgChoiceCard(...)`, `PgToggle(value:,onChanged:)`, `PgPageDots(count:,index:)`, `PgAppBar(title:,onBack:)` signatures consistent between definition (Tasks 5–6) and use (Tasks 10–16).

**Note for implementer:** `Color.withValues(alpha:)` requires a recent Flutter (3.27+); this repo is on 3.44, so it is available. If `flutter analyze` ever flags it, substitute `.withOpacity(...)`.
