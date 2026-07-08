# Pawgo Slice 2: Go Real — Firebase Auth + Firestore — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Slice 1's mock app into a live Firebase-backed app — real email/password accounts, real `users`/`pets` in Firestore, auth-aware routing, and a Home that streams live data — by swapping implementations behind the existing Riverpod repository seam.

**Architecture:** Feature-first Flutter. UI depends only on abstract repositories (`AuthRepository`, `UserRepository`, `PetRepository`) exposed via Riverpod; Firebase-backed implementations live under `data/repositories/firebase/`. Tests inject hand-rolled in-memory fakes via `ProviderScope` overrides — no network. `go_router` gains an auth-aware protective redirect driven by the auth stream.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `firebase_auth` ^6.5.4 (already installed), `cloud_firestore` ^6.6.0 (already installed), `flutter_riverpod`, `go_router`, `google_fonts`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-08-pawgo-real-backend-auth-firestore-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Do not lower these.
- Keep `android/gradle.properties` → `kotlin.incremental=false` (Windows cross-drive build fix). Never delete it.
- **Email/password auth only** this slice. No phone/OTP, Storage uploads, Maps/GPS, Cloud Functions, App Check, FCM.
- UI and tests depend only on the repository **interfaces** — never import `firebase_auth`/`cloud_firestore` outside `data/repositories/firebase/` and `lib/main.dart`.
- **No network in tests.** Every test uses the in-memory fakes from `test/support/fakes.dart` via `ProviderScope` overrides. The concrete `Firebase*Repository` classes are verified on the emulator (Task 14), not unit-tested.
- Package/app id stays `com.example.pet_aggregator_app`.
- `go_router` builders use `(_, _)` (two wildcards) to satisfy the `unnecessary_underscores` lint.
- Any plain-`test()` that touches `GoogleFonts` must use `testWidgets` + `GoogleFonts.config.allowRuntimeFetching = false` (fake-async abandons the pending font load). Screen tests use the phone-sized viewport harness.
- Firestore writes set `createdAt` in the **repository** (`FieldValue.serverTimestamp()`), never in model `toMap()` — models stay Firebase-free.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: Domain models — serialization + new fields

**Files:**
- Create: `lib/data/models/app_user.dart`
- Modify: `lib/data/models/role.dart`
- Modify: `lib/data/models/pet_profile.dart` (adds `Species` keys + `PetProfile` fields/maps)
- Modify: `lib/data/models/user_profile.dart`
- Delete: `lib/data/mock/mock_pets.dart` (mock data leaves the app path; fixtures move to tests in Task 2)
- Delete: `test/data/mock_pet_repository_test.dart` (obsolete — repo interface changes in Task 2)
- Test: `test/data/models/serialization_test.dart`

**Interfaces:**
- Produces:
  - `class AppUser { final String uid; final String? email; const AppUser({required this.uid, this.email}); }`
  - `enum Role` gains `final String storageKey;` and `static Role fromStorage(String)`.
  - `enum Species { dog, cat, other }` becomes an enhanced enum with `final String storageKey;` and `static Species fromStorage(String)`.
  - `class PetProfile` fields: `id, ownerId, name, breed, ageLabel, sex, area` (String), `species` (Species), `vaccinated` (bool), `accentColor` (Color, derived). `Map<String,dynamic> toMap()` (no id/createdAt) and `factory PetProfile.fromMap(String id, Map<String,dynamic>)`, plus `static Color accentFor(String seed)`.
  - `class UserProfile` fields: `uid, name, email, area` (String), `role` (Role). `Map<String,dynamic> toMap()` (no uid/createdAt) and `factory UserProfile.fromMap(String uid, Map<String,dynamic>)`.

- [ ] **Step 1: Delete the obsolete mock + test**

Run:
```bash
git rm lib/data/mock/mock_pets.dart test/data/mock_pet_repository_test.dart
```
Expected: both files removed. (`mock/` folder may now be empty — that's fine.)

- [ ] **Step 2: Write the failing test**

```dart
// test/data/models/serialization_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';

void main() {
  test('Role/Species round-trip through storage keys', () {
    expect(Role.homestayHost.storageKey, 'homestayHost');
    expect(Role.fromStorage('servicePro'), Role.servicePro);
    expect(Role.fromStorage('garbage'), Role.petParent); // safe default
    expect(Species.cat.storageKey, 'cat');
    expect(Species.fromStorage('dog'), Species.dog);
  });

  test('UserProfile toMap omits uid/createdAt and fromMap restores', () {
    const u = UserProfile(
        uid: 'u1', name: 'Radhika', email: 'r@x.com', area: 'Khar', role: Role.petParent);
    final m = u.toMap();
    expect(m.containsKey('uid'), isFalse);
    expect(m.containsKey('createdAt'), isFalse);
    expect(m['role'], 'petParent');
    final back = UserProfile.fromMap('u1', m);
    expect(back.name, 'Radhika');
    expect(back.area, 'Khar');
    expect(back.role, Role.petParent);
  });

  test('PetProfile toMap/fromMap round-trip; accent is derived', () {
    const p = PetProfile(
        id: 'p1', ownerId: 'u1', name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
        sex: 'male', area: 'Bandra West', species: Species.dog, vaccinated: true,
        accentColor: Color(0xFF000000));
    final m = p.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m['species'], 'dog');
    final back = PetProfile.fromMap('p1', m);
    expect(back.name, 'Bruno');
    expect(back.ownerId, 'u1');
    expect(back.species, Species.dog);
    expect(back.accentColor, PetProfile.accentFor('Bruno')); // derived, not stored
  });
}
```
(The test needs `Color`; add `import 'package:flutter/material.dart';` at the top.)

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/models/serialization_test.dart`
Expected: FAIL — `AppUser`/new fields/`toMap` not defined.

- [ ] **Step 4: Create `app_user.dart`**

```dart
// lib/data/models/app_user.dart
class AppUser {
  final String uid;
  final String? email;
  const AppUser({required this.uid, this.email});
}
```

- [ ] **Step 5: Rewrite `role.dart`**

```dart
// lib/data/models/role.dart
enum Role {
  petParent('Pet Parent', 'petParent'),
  servicePro('Service Professional', 'servicePro'),
  homestayHost('Homestay Host', 'homestayHost');

  final String label;
  final String storageKey;
  const Role(this.label, this.storageKey);

  static Role fromStorage(String key) =>
      Role.values.firstWhere((r) => r.storageKey == key, orElse: () => Role.petParent);
}
```

- [ ] **Step 6: Rewrite `pet_profile.dart`**

```dart
// lib/data/models/pet_profile.dart
import 'package:flutter/material.dart';

enum Species {
  dog('dog'),
  cat('cat'),
  other('other');

  final String storageKey;
  const Species(this.storageKey);

  static Species fromStorage(String key) =>
      Species.values.firstWhere((s) => s.storageKey == key, orElse: () => Species.dog);
}

class PetProfile {
  final String id, ownerId, name, breed, ageLabel, sex, area;
  final Species species;
  final bool vaccinated;
  final Color accentColor;

  const PetProfile({
    required this.id, required this.ownerId, required this.name, required this.breed,
    required this.ageLabel, required this.sex, required this.area,
    required this.species, required this.vaccinated, required this.accentColor,
  });

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'name': name,
        'breed': breed,
        'species': species.storageKey,
        'ageLabel': ageLabel,
        'sex': sex,
        'area': area,
        'vaccinated': vaccinated,
      };

  factory PetProfile.fromMap(String id, Map<String, dynamic> m) => PetProfile(
        id: id,
        ownerId: (m['ownerId'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        breed: (m['breed'] ?? '') as String,
        ageLabel: (m['ageLabel'] ?? '') as String,
        sex: (m['sex'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        species: Species.fromStorage((m['species'] ?? 'dog') as String),
        vaccinated: (m['vaccinated'] ?? false) as bool,
        accentColor: accentFor((m['name'] ?? '') as String),
      );

  static const _accents = [
    Color(0xFFF0871E), Color(0xFFEC8FB0), Color(0xFF6B8DE0),
    Color(0xFFB79BE8), Color(0xFF2FB479),
  ];

  static Color accentFor(String seed) {
    if (seed.isEmpty) return _accents[0];
    final sum = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return _accents[sum % _accents.length];
  }
}
```

- [ ] **Step 7: Rewrite `user_profile.dart`**

```dart
// lib/data/models/user_profile.dart
import 'role.dart';

class UserProfile {
  final String uid, name, email, area;
  final Role role;

  const UserProfile({
    required this.uid, required this.name, required this.email,
    required this.area, required this.role,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'area': area,
        'role': role.storageKey,
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        name: (m['name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        role: Role.fromStorage((m['role'] ?? 'petParent') as String),
      );

  UserProfile copyWith({String? area}) => UserProfile(
        uid: uid, name: name, email: email, area: area ?? this.area, role: role,
      );
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/data/models/serialization_test.dart`
Expected: PASS.

- [ ] **Step 9: Analyze + commit**

```bash
flutter analyze
git add lib/data/models/ test/data/models/serialization_test.dart
git commit -m "feat: add AppUser + Firestore serialization to models; drop mock pets"
```
> Note: `flutter analyze` will now flag `create_pet_screen.dart`, `home_screen.dart`, `providers.dart`, `pet_repository.dart`, `mock_pets` importers as broken (removed fields/file). That is expected mid-refactor — those files are rewritten in Tasks 2–12. **Exception to the "analyze clean" rule for Tasks 1–4 only:** the app is in a known-broken intermediate state until the repository seam is rebuilt. Analyze must be clean again by the end of Task 4, and every task from Task 5 on ends fully clean. Commit anyway to keep steps atomic.

---

### Task 2: Repository interfaces + in-memory fakes

**Files:**
- Create: `lib/data/repositories/auth_repository.dart`
- Create: `lib/data/repositories/user_repository.dart`
- Modify: `lib/data/repositories/pet_repository.dart` (replace the whole file — new stream interface, no `MockPetRepository`)
- Create: `test/support/fakes.dart`
- Test: `test/data/fakes_test.dart`

**Interfaces:**
- Produces:
  - `enum AuthFailureType { invalidCredentials, emailInUse, weakPassword, invalidEmail, network, unknown }`
  - `class AuthFailure implements Exception { final AuthFailureType type; final String message; const AuthFailure(this.type, this.message); factory AuthFailure.fromCode(String code); }`
  - `abstract interface class AuthRepository { Stream<AppUser?> authStateChanges(); AppUser? get currentUser; Future<AppUser> signUp({required String email, required String password}); Future<AppUser> signIn({required String email, required String password}); Future<void> signOut(); }`
  - `abstract interface class UserRepository { Future<void> createUser(UserProfile profile); Future<void> updateArea(String uid, String area); Stream<UserProfile?> watchUser(String uid); }`
  - `abstract interface class PetRepository { Stream<List<PetProfile>> watchNearbyPets({required String excludeOwnerId}); Stream<List<PetProfile>> watchMyPets(String ownerId); Future<void> addPet(PetProfile pet); }`
  - Test fakes: `FakeAuthRepository`, `InMemoryUserRepository`, `InMemoryPetRepository`, and `List<PetProfile> fixturePets(String ownerId)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/fakes_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import '../support/fakes.dart';

void main() {
  test('FakeAuthRepository signs up, signs in, and rejects bad credentials', () async {
    final auth = FakeAuthRepository();
    expect(auth.currentUser, isNull);
    final u = await auth.signUp(email: 'a@b.com', password: 'secret1');
    expect(u.email, 'a@b.com');
    expect(auth.currentUser, isNotNull);
    await auth.signOut();
    expect(auth.currentUser, isNull);
    final again = await auth.signIn(email: 'a@b.com', password: 'secret1');
    expect(again.uid, u.uid);
    expect(
      () => auth.signIn(email: 'a@b.com', password: 'wrong'),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('InMemoryUserRepository stores and updates area', () async {
    final repo = InMemoryUserRepository();
    await repo.createUser(const UserProfile(
        uid: 'u1', name: 'R', email: 'r@x.com', area: '', role: Role.petParent));
    await repo.updateArea('u1', 'Bandra West');
    final u = await repo.watchUser('u1').first;
    expect(u!.area, 'Bandra West');
  });

  test('InMemoryPetRepository addPet emits and watchNearby excludes owner', () async {
    final repo = InMemoryPetRepository(fixturePets('other'));
    final nearby = await repo.watchNearbyPets(excludeOwnerId: 'me').first;
    expect(nearby, isNotEmpty);
    expect(nearby.every((p) => p.ownerId != 'me'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/fakes_test.dart`
Expected: FAIL — repository types/fakes not found.

- [ ] **Step 3: Create `auth_repository.dart`**

```dart
// lib/data/repositories/auth_repository.dart
import '../models/app_user.dart';

enum AuthFailureType { invalidCredentials, emailInUse, weakPassword, invalidEmail, network, unknown }

class AuthFailure implements Exception {
  final AuthFailureType type;
  final String message;
  const AuthFailure(this.type, this.message);

  factory AuthFailure.fromCode(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return const AuthFailure(AuthFailureType.invalidCredentials, 'Incorrect email or password.');
      case 'email-already-in-use':
        return const AuthFailure(AuthFailureType.emailInUse, 'That email is already registered.');
      case 'weak-password':
        return const AuthFailure(AuthFailureType.weakPassword, 'Password is too weak (min 6 characters).');
      case 'invalid-email':
        return const AuthFailure(AuthFailureType.invalidEmail, 'That email address looks invalid.');
      case 'network-request-failed':
        return const AuthFailure(AuthFailureType.network, 'Network error. Check your connection.');
      default:
        return const AuthFailure(AuthFailureType.unknown, 'Something went wrong. Please try again.');
    }
  }

  @override
  String toString() => 'AuthFailure($type): $message';
}

abstract interface class AuthRepository {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<AppUser> signUp({required String email, required String password});
  Future<AppUser> signIn({required String email, required String password});
  Future<void> signOut();
}
```

- [ ] **Step 4: Create `user_repository.dart`**

```dart
// lib/data/repositories/user_repository.dart
import '../models/user_profile.dart';

abstract interface class UserRepository {
  Future<void> createUser(UserProfile profile);
  Future<void> updateArea(String uid, String area);
  Stream<UserProfile?> watchUser(String uid);
}
```

- [ ] **Step 5: Replace `pet_repository.dart`**

```dart
// lib/data/repositories/pet_repository.dart
import '../models/pet_profile.dart';

abstract interface class PetRepository {
  Stream<List<PetProfile>> watchNearbyPets({required String excludeOwnerId});
  Stream<List<PetProfile>> watchMyPets(String ownerId);
  Future<void> addPet(PetProfile pet);
}
```

- [ ] **Step 6: Create `test/support/fakes.dart`**

```dart
// test/support/fakes.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pet_aggregator_app/data/models/app_user.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  final Map<String, String> _passwords = {}; // email -> password
  AppUser? _current;

  /// If set, the next signUp/signIn throws this and clears it.
  AuthFailure? nextError;

  FakeAuthRepository({AppUser? initialUser}) : _current = initialUser;

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  void _set(AppUser? u) {
    _current = u;
    _controller.add(u);
  }

  @override
  Future<AppUser> signUp({required String email, required String password}) async {
    if (nextError != null) { final e = nextError!; nextError = null; throw e; }
    if (_passwords.containsKey(email)) {
      throw const AuthFailure(AuthFailureType.emailInUse, 'That email is already registered.');
    }
    _passwords[email] = password;
    final u = AppUser(uid: 'uid_$email', email: email);
    _set(u);
    return u;
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    if (nextError != null) { final e = nextError!; nextError = null; throw e; }
    if (_passwords[email] != password) {
      throw const AuthFailure(AuthFailureType.invalidCredentials, 'Incorrect email or password.');
    }
    final u = AppUser(uid: 'uid_$email', email: email);
    _set(u);
    return u;
  }

  @override
  Future<void> signOut() async => _set(null);
}

class InMemoryUserRepository implements UserRepository {
  final Map<String, UserProfile> _users = {};
  final Map<String, StreamController<UserProfile?>> _ctrls = {};

  StreamController<UserProfile?> _ctrl(String uid) =>
      _ctrls.putIfAbsent(uid, () => StreamController<UserProfile?>.broadcast());

  @override
  Future<void> createUser(UserProfile profile) async {
    _users[profile.uid] = profile;
    _ctrl(profile.uid).add(profile);
  }

  @override
  Future<void> updateArea(String uid, String area) async {
    final u = _users[uid];
    if (u != null) {
      _users[uid] = u.copyWith(area: area);
      _ctrl(uid).add(_users[uid]);
    }
  }

  @override
  Stream<UserProfile?> watchUser(String uid) async* {
    yield _users[uid];
    yield* _ctrl(uid).stream;
  }
}

class InMemoryPetRepository implements PetRepository {
  final List<PetProfile> _pets = [];
  final _controller = StreamController<List<PetProfile>>.broadcast();

  InMemoryPetRepository([List<PetProfile>? seed]) {
    if (seed != null) _pets.addAll(seed);
  }

  void _emit() => _controller.add(List.unmodifiable(_pets));

  List<PetProfile> _nearby(String exclude) =>
      _pets.where((p) => p.ownerId != exclude).toList();

  @override
  Stream<List<PetProfile>> watchNearbyPets({required String excludeOwnerId}) async* {
    yield _nearby(excludeOwnerId);
    yield* _controller.stream.map((_) => _nearby(excludeOwnerId));
  }

  @override
  Stream<List<PetProfile>> watchMyPets(String ownerId) async* {
    yield _pets.where((p) => p.ownerId == ownerId).toList();
    yield* _controller.stream.map((_) => _pets.where((p) => p.ownerId == ownerId).toList());
  }

  @override
  Future<void> addPet(PetProfile pet) async {
    _pets.add(pet);
    _emit();
  }
}

List<PetProfile> fixturePets(String ownerId) => [
      PetProfile(id: 'p1', ownerId: ownerId, name: 'Bruno', breed: 'Labrador',
          ageLabel: '2 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
          vaccinated: true, accentColor: PetProfile.accentFor('Bruno')),
      PetProfile(id: 'p2', ownerId: ownerId, name: 'Mochi', breed: 'Persian cat',
          ageLabel: '1 yr', sex: 'female', area: 'Khar', species: Species.cat,
          vaccinated: true, accentColor: PetProfile.accentFor('Mochi')),
      const PetProfile(id: 'p3', ownerId: ownerId, name: 'Simba', breed: 'Beagle',
          ageLabel: '3 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
          vaccinated: true, accentColor: Color(0xFF6B8DE0)),
    ];
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/data/fakes_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit** (analyze still broken app-wide until Task 4 — see Task 1 note)

```bash
git add lib/data/repositories/auth_repository.dart lib/data/repositories/user_repository.dart lib/data/repositories/pet_repository.dart test/support/fakes.dart test/data/fakes_test.dart
git commit -m "feat: add Auth/User/Pet repository interfaces + in-memory test fakes"
```

---

### Task 3: Firebase repository implementations

**Files:**
- Create: `lib/data/repositories/firebase/firebase_auth_repository.dart`
- Create: `lib/data/repositories/firebase/firestore_user_repository.dart`
- Create: `lib/data/repositories/firebase/firestore_pet_repository.dart`
- Test: `test/data/auth_failure_test.dart` (pure mapping only — the repos are verified on the emulator in Task 14)

**Interfaces:**
- Consumes: `AuthRepository`, `UserRepository`, `PetRepository`, `AuthFailure`, models (Task 1–2).
- Produces: `FirebaseAuthRepository`, `FirestoreUserRepository`, `FirestorePetRepository` (concrete). No new public types.

- [ ] **Step 1: Write the failing test (pure mapping)**

```dart
// test/data/auth_failure_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';

void main() {
  test('AuthFailure.fromCode maps Firebase codes to friendly types', () {
    expect(AuthFailure.fromCode('wrong-password').type, AuthFailureType.invalidCredentials);
    expect(AuthFailure.fromCode('email-already-in-use').type, AuthFailureType.emailInUse);
    expect(AuthFailure.fromCode('weak-password').type, AuthFailureType.weakPassword);
    expect(AuthFailure.fromCode('anything-else').type, AuthFailureType.unknown);
  });
}
```

- [ ] **Step 2: Run test to verify it fails, then passes trivially**

Run: `flutter test test/data/auth_failure_test.dart`
Expected: PASS immediately (mapping exists from Task 2). This test guards the mapping the Firebase repo depends on; if it fails, `AuthFailure.fromCode` regressed.

- [ ] **Step 3: Create `firebase_auth_repository.dart`**

```dart
// lib/data/repositories/firebase/firebase_auth_repository.dart
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/app_user.dart';
import '../auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth;
  FirebaseAuthRepository([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  AppUser? _map(User? u) => u == null ? null : AppUser(uid: u.uid, email: u.email);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  Future<AppUser> signUp({required String email, required String password}) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      return _map(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return _map(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
```

- [ ] **Step 4: Create `firestore_user_repository.dart`**

```dart
// lib/data/repositories/firebase/firestore_user_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_profile.dart';
import '../user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  final FirebaseFirestore _db;
  FirestoreUserRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('users');

  @override
  Future<void> createUser(UserProfile profile) => _col.doc(profile.uid).set({
        ...profile.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> updateArea(String uid, String area) => _col.doc(uid).update({'area': area});

  @override
  Stream<UserProfile?> watchUser(String uid) => _col.doc(uid).snapshots().map(
      (doc) => doc.exists ? UserProfile.fromMap(uid, doc.data()!) : null);
}
```

- [ ] **Step 5: Create `firestore_pet_repository.dart`**

```dart
// lib/data/repositories/firebase/firestore_pet_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/pet_profile.dart';
import '../pet_repository.dart';

class FirestorePetRepository implements PetRepository {
  final FirebaseFirestore _db;
  FirestorePetRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('pets');

  @override
  Stream<List<PetProfile>> watchNearbyPets({required String excludeOwnerId}) =>
      _col.orderBy('createdAt', descending: true).snapshots().map((snap) => snap.docs
          .map((d) => PetProfile.fromMap(d.id, d.data()))
          .where((p) => p.ownerId != excludeOwnerId)
          .toList());

  @override
  Stream<List<PetProfile>> watchMyPets(String ownerId) => _col
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => PetProfile.fromMap(d.id, d.data())).toList());

  @override
  Future<void> addPet(PetProfile pet) => _col.add({
        ...pet.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
}
```

- [ ] **Step 6: Commit** (analyze still broken until Task 4)

```bash
git add lib/data/repositories/firebase/ test/data/auth_failure_test.dart
git commit -m "feat: add Firebase Auth/Firestore repository implementations"
```

---

### Task 4: Riverpod providers (wire the seam)

**Files:**
- Modify: `lib/data/repositories/providers.dart` (replace whole file)
- Test: `test/data/providers_test.dart`

**Interfaces:**
- Produces:
  - `authRepositoryProvider` → `Provider<AuthRepository>`
  - `userRepositoryProvider` → `Provider<UserRepository>`
  - `petRepositoryProvider` → `Provider<PetRepository>`
  - `authStateProvider` → `StreamProvider<AppUser?>`
  - `currentUserProfileProvider` → `StreamProvider<UserProfile?>`
  - `nearbyPetsProvider` → `StreamProvider<List<PetProfile>>`

- [ ] **Step 1: Write the failing test**

```dart
// test/data/providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('nearbyPetsProvider streams pets excluding the signed-in user', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(
          InMemoryPetRepository(fixturePets('someone-else'))),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ]);
    addTearDown(container.dispose);

    // Let authStateProvider emit the signed-in user.
    await container.read(authStateProvider.future);
    final pets = await container.read(nearbyPetsProvider.future);
    expect(pets, isNotEmpty);
    expect(pets.every((p) => p.ownerId != 'uid_me@x.com'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/providers_test.dart`
Expected: FAIL — providers not defined / old `providers.dart` references removed types.

- [ ] **Step 3: Replace `providers.dart`**

```dart
// lib/data/repositories/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/pet_profile.dart';
import '../models/user_profile.dart';
import 'auth_repository.dart';
import 'user_repository.dart';
import 'pet_repository.dart';
import 'firebase/firebase_auth_repository.dart';
import 'firebase/firestore_user_repository.dart';
import 'firebase/firestore_pet_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => FirebaseAuthRepository());
final userRepositoryProvider = Provider<UserRepository>((ref) => FirestoreUserRepository());
final petRepositoryProvider = Provider<PetRepository>((ref) => FirestorePetRepository());

final authStateProvider = StreamProvider<AppUser?>(
    (ref) => ref.watch(authRepositoryProvider).authStateChanges());

final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchUser(user.uid);
});

final nearbyPetsProvider = StreamProvider<List<PetProfile>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  return ref.watch(petRepositoryProvider).watchNearbyPets(excludeOwnerId: user?.uid ?? '__none__');
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze the data layer**

Run: `flutter analyze lib/data`
Expected: No issues in `lib/data`. (The screens under `lib/features` may still reference the old API — those are fixed in Tasks 7–12. The router/app fixes land in Task 6.)

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/providers.dart test/data/providers_test.dart
git commit -m "feat: wire Riverpod providers to Firebase repositories (auth/user/pets streams)"
```

---

### Task 5: `PgTextField` — real styled text input

**Files:**
- Create: `lib/core/widgets/pg_text_field.dart`
- Test: `test/core/widgets/pg_text_field_test.dart`

**Interfaces:**
- Produces: `PgTextField({required String label, required TextEditingController controller, IconData? icon, bool obscure = false, TextInputType? keyboardType, String? hint})` — same visual language as `PgField` (surface2 fill, border, radius 14, label above), but a real editable `TextField`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/pg_text_field_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_text_field.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('PgTextField shows label and accepts input', (tester) async {
    final controller = TextEditingController();
    await pumpPg(tester, PgTextField(label: 'Email', controller: controller));
    expect(find.text('Email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'r@x.com');
    expect(controller.text, 'r@x.com');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/pg_text_field_test.dart`
Expected: FAIL — `PgTextField` not found.

- [ ] **Step 3: Implement `pg_text_field.dart`**

```dart
// lib/core/widgets/pg_text_field.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PgTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? hint;

  const PgTextField({
    super.key,
    required this.label,
    required this.controller,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: PgText.label(context)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(PgRadius.input),
          ),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: c.muted), const SizedBox(width: 11)],
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                keyboardType: keyboardType,
                style: PgText.inter(14.5, FontWeight.w500, color: c.text),
                cursorColor: c.brand,
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: PgText.inter(14.5, FontWeight.w400, color: c.faint),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/pg_text_field_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/core
git add lib/core/widgets/pg_text_field.dart test/core/widgets/pg_text_field_test.dart
git commit -m "feat: add PgTextField (editable input matching PgField styling)"
```

---

### Task 6: Auth-aware router + app wiring + test harness

**Files:**
- Create: `lib/core/router/go_router_refresh_stream.dart`
- Modify: `lib/core/router/app_router.dart` (redirect + `buildRouter(auth:)` + `routerProvider`)
- Modify: `lib/app.dart` (ConsumerWidget reading `routerProvider`)
- Modify: `test/support/pump.dart` (add `pumpPgApp` harness)
- Modify: `test/app_smoke_test.dart` (wrap in `ProviderScope` with a fake auth)
- Modify: `test/core/router/app_router_test.dart` (auth-aware assertions)

**Interfaces:**
- Consumes: `authRepositoryProvider`, `AuthRepository` (Task 2/4).
- Produces:
  - `class GoRouterRefreshStream extends ChangeNotifier` (bridges a `Stream` to `Listenable`).
  - `GoRouter buildRouter({required AuthRepository auth, String initialLocation = Routes.splash})` — adds a protective `redirect`.
  - `final routerProvider = Provider<GoRouter>(...)`.
  - Test helper `pumpPgApp(WidgetTester, {List<Override> overrides, String initialLocation, Brightness})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/router/app_router_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../../support/fakes.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('signed-out user is redirected away from /home to Welcome', (tester) async {
    await pumpPgApp(tester,
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget); // Welcome screen (Task 8)
  });

  testWidgets('signed-in user can load the Home shell', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signIn == null; // ignore
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // bottom-nav label
  });
}
```
> Remove the stray `await auth.signIn == null;` line — it's shown only to flag: do NOT call signIn before a signUp exists. Correct body: just `final auth = FakeAuthRepository(); await auth.signUp(email: 'me@x.com', password: 'secret1');`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/router/app_router_test.dart`
Expected: FAIL — `pumpPgApp` / new `buildRouter` signature not found.

- [ ] **Step 3: Create `go_router_refresh_stream.dart`**

```dart
// lib/core/router/go_router_refresh_stream.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

/// Notifies go_router to re-run its redirect whenever [stream] emits.
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _sub;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Rewrite `app_router.dart`**

```dart
// lib/core/router/app_router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/location_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/placeholder_tab.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/pets/create_pet_screen.dart';
import 'go_router_refresh_stream.dart';
import 'routes.dart';

/// Routes that require an authenticated user. Signed-out users hitting any of
/// these are bounced to Welcome. The onboarding/auth funnel entry pages
/// (splash, onboarding, welcome, signup) are intentionally NOT protected;
/// funnel progression and post-login navigation are explicit in the screens.
const _protected = {
  Routes.home, Routes.discover, Routes.services, Routes.community, Routes.profile,
  Routes.location, Routes.createPet,
};

GoRouter buildRouter({required AuthRepository auth, String initialLocation = Routes.splash}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: GoRouterRefreshStream(auth.authStateChanges()),
    redirect: (context, state) {
      final loggedIn = auth.currentUser != null;
      if (!loggedIn && _protected.contains(state.matchedLocation)) return Routes.welcome;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.signup, builder: (_, _) => const SignupScreen()),
      GoRoute(path: Routes.location, builder: (_, _) => const LocationScreen()),
      GoRoute(path: Routes.createPet, builder: (_, _) => const CreatePetScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.discover, builder: (_, _) => const PlaceholderTab(title: 'Discover')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.services, builder: (_, _) => const PlaceholderTab(title: 'Services')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.community, builder: (_, _) => const PlaceholderTab(title: 'Community')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.profile, builder: (_, _) => const PlaceholderTab(title: 'Profile')),
          ]),
        ],
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter(auth: ref.watch(authRepositoryProvider));
  ref.onDispose(router.dispose);
  return router;
});
```

- [ ] **Step 5: Rewrite `app.dart` as a ConsumerWidget**

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class PawgoApp extends ConsumerWidget {
  const PawgoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Pawgo',
      debugShowCheckedModeBanner: false,
      theme: PgTheme.light(),
      darkTheme: PgTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
```

- [ ] **Step 6: Add the `pumpPgApp` harness to `test/support/pump.dart`**

Append to the existing file (keep `pumpPg`):

```dart
// --- appended to test/support/pump.dart ---
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/core/router/app_router.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';

/// Pumps the full app (router + providers) on a phone-sized surface, with
/// [overrides] (inject fakes) and a starting [initialLocation].
Future<void> pumpPgApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  String initialLocation = Routes.splash,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  final AuthRepository auth = container.read(authRepositoryProvider);
  final router = buildRouter(auth: auth, initialLocation: initialLocation);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? PgTheme.dark() : PgTheme.light(),
      routerConfig: router,
    ),
  ));
}
```
> The `import 'package:pet_aggregator_app/core/theme/app_theme.dart';` already exists at the top of `pump.dart` from Slice 1. Add the other imports shown above to the top of the file (Dart requires imports at the top — move them up, not literally at the bottom).

- [ ] **Step 7: Update `test/app_smoke_test.dart`**

```dart
// test/app_smoke_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/app.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('PawgoApp builds a MaterialApp', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
      child: const PawgoApp(),
    ));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
```

- [ ] **Step 8: Fix the router test body**

Apply the correction noted in Step 1 (remove the stray line). Final second test body:
```dart
  testWidgets('signed-in user can load the Home shell', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
  });
```
> The first test (signed-out → Welcome) depends on `WelcomeScreen` still rendering the text `'Log in'`. Slice 1's Welcome shows `'Log in'`; it is rewritten in Task 8 but keeps that button label, so this test stays valid throughout.

- [ ] **Step 9: Run tests to verify pass**

Run: `flutter test test/core/router/app_router_test.dart test/app_smoke_test.dart`
Expected: PASS. (`lib/features` screens still use the old data API, so a full `flutter analyze` is not yet clean — that resolves as Tasks 7–12 land. `flutter analyze lib/core lib/data lib/app.dart` should be clean now.)

- [ ] **Step 10: Commit**

```bash
git add lib/core/router/ lib/app.dart test/support/pump.dart test/app_smoke_test.dart test/core/router/app_router_test.dart
git commit -m "feat: auth-aware go_router redirect + routerProvider; ConsumerWidget app; pumpPgApp harness"
```

---

### Task 7: Splash auth gate

**Files:**
- Modify: `lib/features/onboarding/splash_screen.dart` (ConsumerStatefulWidget; route on real auth state)
- Modify: `test/features/splash_screen_test.dart`

**Interfaces:**
- Consumes: `authStateProvider` (Task 4), `Routes` (existing).
- Produces: no new public types. On first auth value (after a brief brand delay): signed-in → `Routes.home`, else → `Routes.onboarding`.

- [ ] **Step 1: Rewrite the test**

```dart
// test/features/splash_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('signed-out splash advances to Onboarding', (tester) async {
    await pumpPgApp(tester,
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        initialLocation: Routes.splash);
    expect(find.text('Pawgo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600)); // brand delay + auth
    await tester.pumpAndSettle();
    expect(find.text('Find playmates just around the corner'), findsOneWidget);
  });

  testWidgets('signed-in splash advances to Home', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.splash);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // bottom nav
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/splash_screen_test.dart`
Expected: FAIL — Splash still uses a fixed timer to Onboarding (ignores auth); the signed-in case fails.

- [ ] **Step 3: Rewrite `splash_screen.dart`**

```dart
// lib/features/onboarding/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/repositories/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decideRoute();
  }

  Future<void> _decideRoute() async {
    // Wait for a minimum brand-visible delay AND the first auth value.
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 1400)),
      ref.read(authStateProvider.future).catchError((_) => null),
    ]);
    if (!mounted) return;
    final signedIn = ref.read(authStateProvider).valueOrNull != null;
    context.go(signedIn ? Routes.home : Routes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFF8B45E), Color(0xFFF0871E), Color(0xFFE07712)]),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 104, height: 104, alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)]),
                borderRadius: BorderRadius.circular(33),
                boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 50, offset: Offset(0, 20))]),
              child: const Icon(Icons.pets, size: 58, color: Colors.white)),
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/splash_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/onboarding/splash_screen.dart test/features/splash_screen_test.dart
git commit -m "feat: splash routes on real auth state (signed-in -> Home, else Onboarding)"
```

---

### Task 8: Welcome/Login — real sign-in

**Files:**
- Modify: `lib/features/auth/welcome_screen.dart` (ConsumerStatefulWidget)
- Modify: `test/features/welcome_screen_test.dart`

**Interfaces:**
- Consumes: `authRepositoryProvider`, `AuthFailure`, `PgTextField`, `Routes`.
- Produces: no new public types. Keeps the `'Log in'` button label (router test relies on it).

- [ ] **Step 1: Rewrite the test**

```dart
// test/features/welcome_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pumpWelcome(WidgetTester tester, FakeAuthRepository auth) =>
    pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.welcome);

void main() {
  testWidgets('successful login navigates to Home', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'r@x.com', password: 'secret1');
    await auth.signOut();
    await _pumpWelcome(tester, auth);

    await tester.enterText(find.byType(TextField).at(0), 'r@x.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('wrong password shows an error', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'r@x.com', password: 'secret1');
    await auth.signOut();
    await _pumpWelcome(tester, auth);

    await tester.enterText(find.byType(TextField).at(0), 'r@x.com');
    await tester.enterText(find.byType(TextField).at(1), 'nope');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/welcome_screen_test.dart`
Expected: FAIL — Welcome has no real inputs/sign-in yet.

- [ ] **Step 3: Rewrite `welcome_screen.dart`**

```dart
// lib/features/auth/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider)
          .signIn(email: _email.text.trim(), password: _password.text);
      if (mounted) context.go(Routes.home);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFF8B45E), Color(0xFFF0871E)]),
        ),
        child: Column(children: [
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 84, height: 84, alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)]),
                borderRadius: BorderRadius.circular(26)),
              child: const Icon(Icons.pets, size: 46, color: Colors.white)),
            const SizedBox(height: 18),
            Text('Welcome back 👋', style: PgText.poppins(30, FontWeight.w800, color: Colors.white, ls: -0.5)),
            const SizedBox(height: 5),
            Text('Log in to your Pawgo account',
              style: PgText.inter(14, FontWeight.w500, color: const Color(0xFFFFF5E8))),
          ]))),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(color: c.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              PgTextField(label: 'Email', controller: _email, icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress, hint: 'you@example.com'),
              const SizedBox(height: 14),
              PgTextField(label: 'Password', controller: _password, icon: Icons.lock_outline, obscure: true),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
              const SizedBox(height: 18),
              PgPrimaryButton(label: _loading ? 'Logging in…' : 'Log in',
                onPressed: _loading ? () {} : _login),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => context.go(Routes.signup),
                child: Text.rich(TextSpan(text: 'New to Pawgo? ',
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted),
                  children: [TextSpan(text: 'Create account',
                    style: PgText.inter(13.5, FontWeight.w700, color: c.brand))]))),
            ]),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/welcome_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/welcome_screen.dart test/features/welcome_screen_test.dart
git commit -m "feat: real email/password login on Welcome screen"
```

---

### Task 9: Sign-up — real account + profile creation

**Files:**
- Modify: `lib/features/auth/signup_screen.dart` (ConsumerStatefulWidget)
- Modify: `test/features/signup_screen_test.dart`

**Interfaces:**
- Consumes: `authRepositoryProvider`, `userRepositoryProvider`, `AuthFailure`, `UserProfile`, `Role`, `PgTextField`, `PgChoiceCard`, `PgAppBar`.
- Produces: no new public types. On Continue: `signUp` → `createUser(UserProfile(uid, name, email, area:'', role))` → `Routes.location`.

- [ ] **Step 1: Rewrite the test**

```dart
// test/features/signup_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('shows the three roles and Continue', (tester) async {
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.signup);
    expect(find.text('Pet Parent'), findsOneWidget);
    expect(find.text('Homestay Host'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('filling the form creates account + profile and goes to Location', (tester) async {
    final auth = FakeAuthRepository();
    final users = InMemoryUserRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.signup);

    await tester.enterText(find.byType(TextField).at(0), 'Radhika Nair');
    await tester.enterText(find.byType(TextField).at(1), 'radhika@x.com');
    await tester.enterText(find.byType(TextField).at(2), 'secret1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(auth.currentUser, isNotNull);
    final profile = await users.watchUser(auth.currentUser!.uid).first;
    expect(profile!.name, 'Radhika Nair');
    expect(find.text('Enable location'), findsOneWidget); // Location screen
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/signup_screen_test.dart`
Expected: FAIL — Sign-up has no real inputs / account creation yet.

- [ ] **Step 3: Rewrite `signup_screen.dart`**

```dart
// lib/features/auth/signup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_choice_card.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/role.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  Role _role = Role.petParent;
  bool _loading = false;
  String? _error;

  static const _subtitles = {
    Role.petParent: 'Discover, book, board & chat',
    Role.servicePro: 'Offer walks, grooming & sitting',
    Role.homestayHost: 'Board pets & earn (needs verification)',
  };
  static const _emojis = {
    Role.petParent: '🐾', Role.servicePro: '🎒', Role.homestayHost: '🏡',
  };

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final user = await ref.read(authRepositoryProvider)
          .signUp(email: _email.text.trim(), password: _password.text);
      await ref.read(userRepositoryProvider).createUser(UserProfile(
            uid: user.uid, name: _name.text.trim(), email: _email.text.trim(),
            area: '', role: _role));
      if (mounted) context.go(Routes.location);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
                PgTextField(label: 'Full name', controller: _name, hint: 'Radhika Nair'),
                const SizedBox(height: 13),
                PgTextField(label: 'Email', controller: _email,
                    keyboardType: TextInputType.emailAddress, hint: 'you@example.com'),
                const SizedBox(height: 13),
                PgTextField(label: 'Password', controller: _password, obscure: true,
                    hint: 'At least 6 characters'),
                const SizedBox(height: 16),
                Text("I'M JOINING AS", style: PgText.inter(12.5, FontWeight.w700, color: c.muted)),
                const SizedBox(height: 10),
                for (final r in Role.values) ...[
                  PgChoiceCard(
                    emoji: _emojis[r]!, title: r.label, subtitle: _subtitles[r]!,
                    selected: _role == r, onTap: () => setState(() => _role = r)),
                  const SizedBox(height: 10),
                ],
                if (_error != null)
                  Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(
              label: _loading ? 'Creating…' : 'Continue',
              onPressed: _loading ? () {} : _submit),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/signup_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/signup_screen.dart test/features/signup_screen_test.dart
git commit -m "feat: real sign-up creates Firebase account + Firestore user profile"
```

---

### Task 10: Location — persist area onto the profile

**Files:**
- Modify: `lib/features/auth/location_screen.dart` (ConsumerWidget)
- Modify: `test/features/location_screen_test.dart`

**Interfaces:**
- Consumes: `authStateProvider`, `userRepositoryProvider`, `Routes`, `PgPrimaryButton`, `PgGhostButton`.
- Produces: no new public types. Both buttons: `updateArea(uid, 'Bandra West')` → `Routes.createPet`.

- [ ] **Step 1: Rewrite the test**

```dart
// test/features/location_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Allow persists area and continues to Create Pet', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(
        uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com', area: '', role: Role.petParent));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.location);

    expect(find.text('Enable location'), findsOneWidget);
    await tester.tap(find.text('Allow while using app'));
    await tester.pumpAndSettle();

    final profile = await users.watchUser(auth.currentUser!.uid).first;
    expect(profile!.area, 'Bandra West');
    expect(find.text('Add your pet'), findsOneWidget); // Create Pet screen
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/location_screen_test.dart`
Expected: FAIL — Location doesn't persist area yet.

- [ ] **Step 3: Rewrite `location_screen.dart`**

```dart
// lib/features/auth/location_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../data/repositories/providers.dart';

class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  Future<void> _continue(WidgetRef ref, BuildContext context) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid != null) {
      await ref.read(userRepositoryProvider).updateArea(uid, 'Bandra West');
    }
    if (context.mounted) context.go(Routes.createPet);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
          child: Column(children: [
            const Spacer(),
            Container(width: 220, height: 220, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
              child: Icon(Icons.location_on, size: 92, color: c.brand)),
            const SizedBox(height: 28),
            Text('Enable location', style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 12),
            Text(
              'Pawgo shows pets, pros and homestays near you. We only ever share your approximate area — never your exact address.',
              textAlign: TextAlign.center,
              style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
            const Spacer(),
            PgPrimaryButton(label: 'Allow while using app', onPressed: () => _continue(ref, context)),
            const SizedBox(height: 6),
            PgGhostButton(label: 'Set location manually', onPressed: () => _continue(ref, context)),
          ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/location_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/location_screen.dart test/features/location_screen_test.dart
git commit -m "feat: Location persists approximate area onto the user profile"
```

---

### Task 11: Create Pet — real pet write

**Files:**
- Modify: `lib/features/pets/create_pet_screen.dart` (ConsumerStatefulWidget)
- Modify: `test/features/create_pet_screen_test.dart`

**Interfaces:**
- Consumes: `authStateProvider`, `currentUserProfileProvider`, `petRepositoryProvider`, `PetProfile`, `Species`, `PgTextField`, `PgToggle`, `PgAppBar`, `PgImageSlot`.
- Produces: no new public types. On Finish: `addPet(PetProfile(id:'', ownerId: uid, name, breed, ageLabel, sex:'', area, species, vaccinated, accentColor))` → `Routes.home`.

- [ ] **Step 1: Rewrite the test**

```dart
// test/features/create_pet_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Finish writes a pet owned by the current user and goes Home', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = InMemoryPetRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(pets),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.createPet);

    expect(find.text('Add your pet'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Bruno');   // Pet name
    await tester.enterText(find.byType(TextField).at(1), 'Labrador');// Breed
    await tester.enterText(find.byType(TextField).at(2), '2 yrs');   // Age
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    final mine = await pets.watchMyPets(auth.currentUser!.uid).first;
    expect(mine.single.name, 'Bruno');
    expect(mine.single.ownerId, auth.currentUser!.uid);
    expect(find.text('Home'), findsWidgets); // Home shell
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/create_pet_screen_test.dart`
Expected: FAIL — Create Pet uses display-only fields and does not persist.

- [ ] **Step 3: Rewrite `create_pet_screen.dart`**

```dart
// lib/features/pets/create_pet_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../core/widgets/pg_toggle.dart';
import '../../data/models/pet_profile.dart';
import '../../data/repositories/providers.dart';

class CreatePetScreen extends ConsumerStatefulWidget {
  const CreatePetScreen({super.key});
  @override
  ConsumerState<CreatePetScreen> createState() => _CreatePetScreenState();
}

class _CreatePetScreenState extends ConsumerState<CreatePetScreen> {
  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _age = TextEditingController();
  Species _species = Species.dog;
  bool _vaccinated = true;
  bool _saving = false;

  static const _speciesLabel = {
    Species.dog: '🐶 Dog', Species.cat: '🐱 Cat', Species.other: '🐦 Other',
  };

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    final area = ref.read(currentUserProfileProvider).valueOrNull?.area ?? '';
    final name = _name.text.trim();
    await ref.read(petRepositoryProvider).addPet(PetProfile(
          id: '', ownerId: uid, name: name, breed: _breed.text.trim(),
          ageLabel: _age.text.trim(), sex: '', area: area, species: _species,
          vaccinated: _vaccinated, accentColor: PetProfile.accentFor(name)));
    if (mounted) context.go(Routes.home);
  }

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
                PgTextField(label: 'Pet name', controller: _name, hint: 'Bruno'),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: PgTextField(label: 'Breed', controller: _breed, hint: 'Labrador')),
                  const SizedBox(width: 12),
                  SizedBox(width: 104, child: PgTextField(label: 'Age', controller: _age, hint: '2 yrs')),
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
                            color: _species == s ? c.brand : c.border, width: _species == s ? 2 : 1),
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
                  decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
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
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(
              label: _saving ? 'Saving…' : 'Finish & explore Pawgo',
              onPressed: _saving ? () {} : _finish),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/create_pet_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/pets/create_pet_screen.dart test/features/create_pet_screen_test.dart
git commit -m "feat: Create Pet writes a real pet doc owned by the current user"
```

---

### Task 12: Home — live data + PetRow area

**Files:**
- Modify: `lib/features/home/widgets/pet_row.dart` (use `area`, not the removed `distanceLabel`)
- Modify: `lib/features/home/home_screen.dart` (AsyncValue: loading/empty/error/data; real greeting)
- Modify: `test/features/home_screen_test.dart`

**Interfaces:**
- Consumes: `nearbyPetsProvider` (`AsyncValue<List<PetProfile>>`), `currentUserProfileProvider`, `PgChip`, `PgImageSlot`, `PetRow`.
- Produces: no new public types. `PetRow` unchanged signature (`{required PetProfile pet, required VoidCallback onWoof}`), just its subtitle source changes.

- [ ] **Step 1: Rewrite the test**

```dart
// test/features/home_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Home greets the user and lists live nearby pets', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(
        uid: auth.currentUser!.uid, name: 'Radhika Nair', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('someone-else'))),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();

    expect(find.text('Hey Radhika 👋'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Woof!'), findsWidgets);
  });

  testWidgets('Home shows an empty state when there are no nearby pets', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('No pets nearby yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/home_screen_test.dart`
Expected: FAIL — Home reads the old sync provider / `PetProfile.distanceLabel` no longer exists.

- [ ] **Step 3: Update `pet_row.dart`**

Replace the subtitle line (the only change) so it reads `area` instead of the removed `distanceLabel`:

```dart
// in lib/features/home/widgets/pet_row.dart — the Text under the name Row:
          Text('${pet.breed} · ${pet.ageLabel} · ${pet.area}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
```
(Everything else in `pet_row.dart` stays as written in Slice 1.)

- [ ] **Step 4: Rewrite `home_screen.dart`**

```dart
// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_chip.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/pet_profile.dart';
import '../../data/repositories/providers.dart';
import 'widgets/pet_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final petsAsync = ref.watch(nearbyPetsProvider);
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final firstName = (profile?.name ?? '').split(' ').first;
    final greetName = firstName.isEmpty ? 'there' : firstName;

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
            decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.location_on, size: 14, color: c.brand),
                  const SizedBox(width: 4),
                  Text(profile?.area.isNotEmpty == true ? '${profile!.area}, Mumbai' : 'Mumbai',
                      style: PgText.inter(12.5, FontWeight.w600, color: c.muted)),
                ]),
                const SizedBox(height: 5),
                Text('Hey $greetName 👋', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.5)),
                const SizedBox(height: 2),
                Text('Pets near you today', style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
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
                petsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('Could not load nearby pets.',
                      style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
                  data: (pets) => pets.isEmpty
                      ? _EmptyPets(c: c)
                      : Column(children: [
                          for (final p in pets) ...[
                            PetRow(pet: p, onWoof: () {}),
                            const SizedBox(height: 11),
                          ],
                        ]),
                ),
                const SizedBox(height: 11),
                Text('Community picks', style: PgText.sectionHeader(context)),
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
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

class _EmptyPets extends StatelessWidget {
  final PgColors c;
  const _EmptyPets({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        const Text('🐾', style: TextStyle(fontSize: 30)),
        const SizedBox(height: 8),
        Text('No pets nearby yet', style: PgText.poppins(15, FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text('Check back soon — new pets join every day.',
          textAlign: TextAlign.center,
          style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
      ]),
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
        decoration: BoxDecoration(color: bg,
          gradient: gradient == null ? null : LinearGradient(colors: gradient!),
          borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.poppins(15, FontWeight.w700, color: fg)),
            Text(subtitle, style: PgText.inter(11.5, FontWeight.w400, color: fg.withValues(alpha: 0.8))),
          ]),
        ]),
      ),
    );
  }
}
```
> `_EmptyPets` takes `PgColors c` — `PgColors` is exported from `app_colors.dart` (already imported). `PgColors` is a public class, so this is fine.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/home_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/home/ test/features/home_screen_test.dart
git commit -m "feat: Home streams live nearby pets (loading/empty/error) with real greeting"
```
Expected: whole suite green and `flutter analyze` fully clean now (all screens migrated).

---

### Task 13: Firestore security rules + config

**Files:**
- Create: `firestore.rules`
- Create: `firestore.indexes.json`
- Modify: `firebase.json` (add `firestore` section)

**Interfaces:** none (infra).

> **Prerequisite:** the Firestore database must exist (console: *Firestore → Create database*, Native mode, `asia-south1`) and `firebase login` must be done. Without the database, `deploy` returns a 403 (API disabled).

- [ ] **Step 1: Create `firestore.rules`**

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
    match /pets/{petId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null
                    && request.resource.data.ownerId == request.auth.uid;
      allow update, delete: if request.auth != null
                    && resource.data.ownerId == request.auth.uid;
    }
  }
}
```

- [ ] **Step 2: Create `firestore.indexes.json`**

```json
{
  "indexes": [],
  "fieldOverrides": []
}
```

- [ ] **Step 3: Add a `firestore` section to `firebase.json`**

The file currently holds only a `"flutter"` key. Add a sibling `"firestore"` key so the top level reads:
```json
{
  "flutter": { "...unchanged...": {} },
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  }
}
```
(Keep the existing `"flutter"` object exactly as-is; only add the `"firestore"` key.)

- [ ] **Step 4: Deploy the rules**

Run: `firebase deploy --only firestore:rules --project pet-aggregator-app`
Expected: `✔ Deploy complete!` (If it 403s: create the Firestore database in the console first, wait ~1 min, retry.)

- [ ] **Step 5: Commit**

```bash
git add firestore.rules firestore.indexes.json firebase.json
git commit -m "chore: add + deploy Firestore security rules (users owner-only, pets read-if-authed)"
```

---

### Task 14: Manual verification on the emulator

**Files:** none (verification only). `lib/main.dart` already runs `ProviderScope(child: PawgoApp())` and initialises Firebase — confirm, don't change.

> **Prerequisites:** Email/Password enabled in the console; Firestore created; rules deployed (Task 13).

- [ ] **Step 1: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: all tests pass, analyze clean, APK builds.

- [ ] **Step 2: First run — sign up**

Run: `flutter run -d emulator-5554`
Walk: Splash → Onboarding → Welcome → **Create account** → fill name/email/password, pick a role → Continue → Location (Allow) → Create Pet (fill name/breed/age, pick species, toggle vaccinated) → Finish → **Home**. Confirm in the Firebase console that a `users/{uid}` and a `pets/{petId}` document now exist.

- [ ] **Step 3: Session persistence + login**

Hot-restart (or relaunch) the app → it should skip onboarding and land directly on **Home** (auth persisted). If you add a temporary sign-out path or clear app data, logging back in via Welcome with the same email/password returns to Home.

- [ ] **Step 4: Live data across accounts**

Create a **second** account (different email) that adds its own pet. Sign in as the first account → Home's "Pets near you" now shows the second account's pet (real Firestore stream, excluding your own). This confirms live, non-mock data.

- [ ] **Step 5: Final commit (if any polish tweaks were made)**

```bash
git add -A
git commit -m "chore: Slice 2 verification polish"
```

---

## Self-Review

**Spec coverage:**
- Firebase Auth email/password (signUp/signIn/signOut/stream) → Tasks 2 (interface), 3 (impl), 8/9 (screens). ✓
- Firestore `users`/`pets` + models with `fromMap`/`toMap` → Tasks 1, 3. ✓
- Repository seam + Riverpod providers (`authStateProvider`, `currentUserProfileProvider`, `nearbyPetsProvider`) → Task 4. ✓
- Interactive screens (Signup/Login/Create Pet real forms; Location persists area; Splash auth gate; Home live `AsyncValue`) → Tasks 7–12. ✓
- Auth-aware routing (protective redirect + `GoRouterRefreshStream`) → Task 6. ✓
- Security rules committed + deployed → Task 13. ✓
- TDD with in-memory fakes, no network → `test/support/fakes.dart` (Task 2) used by every screen/provider test. ✓
- Prerequisites (console toggles + `firebase login`) → called out in Tasks 13–14. ✓
- Out-of-scope (OTP, Storage, Maps/GPS, Functions, App Check, Discover) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". The one deliberate flagged line in Task 6 Step 1 (the stray `await auth.signIn == null;`) is explicitly corrected in the same step and again in Step 8 — it is a teaching call-out, not a left-in placeholder. `sex` is intentionally written as `''` at Create-Pet (the prototype screen doesn't collect it; it's a Discover-slice field) — documented in Task 11.

**Type consistency:**
- `PetProfile` fields (`id, ownerId, name, breed, ageLabel, sex, area, species, vaccinated, accentColor`) are identical across Task 1 (model), Task 2 fixtures, Task 11 (`addPet`), Task 12 (`PetRow` uses `area`). No lingering `distanceLabel` (removed in Task 1, PetRow updated in Task 12). ✓
- `UserProfile` (`uid, name, email, area, role`) consistent across Tasks 1, 9, 10, 12; `copyWith({String? area})` used by `InMemoryUserRepository.updateArea`. ✓
- Repository method names match between interfaces (Task 2), Firebase impls (Task 3), fakes (Task 2), and call sites: `signUp/signIn/signOut/authStateChanges/currentUser`, `createUser/updateArea/watchUser`, `watchNearbyPets({excludeOwnerId})/watchMyPets/addPet`. ✓
- Provider names (`authRepositoryProvider`, `userRepositoryProvider`, `petRepositoryProvider`, `authStateProvider`, `currentUserProfileProvider`, `nearbyPetsProvider`) consistent between Task 4 (definition) and every consumer (Tasks 6–12, tests). ✓
- `buildRouter({required AuthRepository auth, String initialLocation})` signature matches its callers in `routerProvider` (Task 6) and `pumpPgApp` (Task 6). ✓

**Analyze-clean timing note:** Tasks 1–4 leave the app in a known-broken intermediate state (screens still reference the old API); `flutter analyze` is scoped to migrated directories during those tasks and is fully clean again from Task 6 Step 9 onward, with the whole-app clean gate re-asserted in Task 12 Step 6 and Task 14 Step 1.

