# Pawgo Slice 8: Photos & Storage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user attach a real photo to their pet (at creation) and to their own avatar (tap-to-change), stored in Firebase Storage, and display those photos wherever the app shows an emoji placeholder for them.

**Architecture:** Two new seams on the existing repository pattern — `StorageRepository` (the `firebase_storage` boundary) and `ImagePickerService` (the `image_picker` boundary) — each with a real impl + an in-memory fake, so the upload flows are unit-testable without the plugin or a live bucket. `PgImageSlot` gains an `imageUrl` param and renders a network image (emoji fallback), so display wiring is one parameter at each site. `photoUrl` is an additive field on `PetProfile`/`UserProfile`.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `firebase_storage` (already a dependency), **`image_picker` (new)**, `cloud_firestore`, `flutter_riverpod`, `go_router`.

**Spec:** `docs/superpowers/specs/2026-07-18-pawgo-photos-storage-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false` (required for Kotlin-based Firebase/plugin builds on this machine).
- **Live backend, no mock data.** UI/tests depend only on the interfaces via Riverpod providers. `firebase_storage` may be imported ONLY in `lib/data/repositories/firebase/firebase_storage_repository.dart`; `image_picker` ONLY in `lib/data/services/image_picker_service.dart`; `cloud_firestore`/`firebase_auth` only under `data/repositories/firebase/`, `lib/main.dart`, `integration_test/`. **Models must import neither.**
- `photoUrl` is **additive** on both models: `String`, default `''`, in constructor + `toMap` + `fromMap` (default `''`).
- **Storage layout:** avatar → `users/{uid}/avatar.jpg` (overwrite); pet → `pets/{uid}_{millis}.jpg`. The download URL is what gets stored in `photoUrl`.
- **Gallery only** (`ImageSource.gallery`), downsized at pick time with `maxWidth: 1080, imageQuality: 80`. No camera.
- Every upload is wrapped in try/catch → a failure snackbar; `mounted` guarded after every `await` before touching state/context.
- Riverpod 3.x: `AsyncValue.value` (not `valueOrNull`); `Override` from `package:flutter_riverpod/misc.dart` in tests. Screen tests use `pumpPgApp`; plain-widget tests use `pumpPg`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `photoUrl` on `PetProfile` + `UserProfile`, and `UserRepository.setPhotoUrl`

**Files:**
- Modify: `lib/data/models/pet_profile.dart`, `lib/data/models/user_profile.dart`
- Modify: `lib/data/repositories/user_repository.dart`, `lib/data/repositories/firebase/firestore_user_repository.dart`
- Modify: `test/support/fakes.dart` (`InMemoryUserRepository`)
- Test: `test/data/photo_url_test.dart`

**Interfaces:**
- Produces: `PetProfile.photoUrl` (String, default `''`); `UserProfile.photoUrl` (String, default `''`) + `copyWith({String? area, int? notifsSeenAt, String? photoUrl})`; `UserRepository.setPhotoUrl(String uid, String url)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/photo_url_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import '../support/fakes.dart';

void main() {
  test('PetProfile.photoUrl round-trips and defaults to empty', () {
    final pet = PetProfile(id: 'p1', ownerId: 'u1', name: 'Bruno', breed: 'Labrador',
        ageLabel: '2 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
        vaccinated: true, accentColor: PetProfile.accentFor('Bruno'),
        photoUrl: 'https://x/pet.jpg');
    expect(PetProfile.fromMap('p1', pet.toMap()).photoUrl, 'https://x/pet.jpg');
    expect(PetProfile.fromMap('p1', const {}).photoUrl, '');
  });

  test('UserProfile.photoUrl round-trips + copyWith', () {
    const u = UserProfile(uid: 'me', name: 'Radhika', email: 'r@x.com', area: 'Bandra',
        role: Role.petParent, photoUrl: 'https://x/me.jpg');
    expect(UserProfile.fromMap('me', u.toMap()).photoUrl, 'https://x/me.jpg');
    expect(UserProfile.fromMap('me', const {}).photoUrl, '');
    expect(u.copyWith(photoUrl: 'https://x/new.jpg').photoUrl, 'https://x/new.jpg');
    expect(u.copyWith(area: 'Khar').photoUrl, 'https://x/me.jpg'); // preserved
  });

  test('setPhotoUrl persists + re-emits', () async {
    final repo = InMemoryUserRepository();
    await repo.createUser(const UserProfile(uid: 'me', name: 'R', email: 'e', area: 'a',
        role: Role.petParent));
    expect((await repo.watchUser('me').first)!.photoUrl, '');
    await repo.setPhotoUrl('me', 'https://x/me.jpg');
    expect((await repo.watchUser('me').first)!.photoUrl, 'https://x/me.jpg');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/photo_url_test.dart`
Expected: FAIL — `photoUrl` / `setPhotoUrl` not defined.

- [ ] **Step 3: Add `photoUrl` to `PetProfile`**

In `lib/data/models/pet_profile.dart`: change the field line to include `photoUrl`, add the constructor default, and the map entries:
```dart
  final String id, ownerId, name, breed, ageLabel, sex, area, photoUrl;
```
constructor — add after `required this.accentColor,`:
```dart
    this.photoUrl = '',
```
`toMap` — add:
```dart
        'photoUrl': photoUrl,
```
`fromMap` — add:
```dart
        photoUrl: (m['photoUrl'] ?? '') as String,
```

- [ ] **Step 4: Add `photoUrl` to `UserProfile`**

In `lib/data/models/user_profile.dart`:
```dart
  final String uid, name, email, area, photoUrl;
```
constructor — add after `this.notifsSeenAt = 0,`:
```dart
    this.photoUrl = '',
```
`toMap` — add `'photoUrl': photoUrl,`; `fromMap` — add `photoUrl: (m['photoUrl'] ?? '') as String,`; and extend `copyWith`:
```dart
  UserProfile copyWith({String? area, int? notifsSeenAt, String? photoUrl}) => UserProfile(
        uid: uid, name: name, email: email, area: area ?? this.area, role: role,
        notifsSeenAt: notifsSeenAt ?? this.notifsSeenAt,
        photoUrl: photoUrl ?? this.photoUrl,
      );
```

- [ ] **Step 5: Add `setPhotoUrl` to the interface + both impls**

In `lib/data/repositories/user_repository.dart`, add to the interface:
```dart
  Future<void> setPhotoUrl(String uid, String url);
```
In `lib/data/repositories/firebase/firestore_user_repository.dart`, add:
```dart
  @override
  Future<void> setPhotoUrl(String uid, String url) => _col.doc(uid).update({'photoUrl': url});
```
In `test/support/fakes.dart`, `InMemoryUserRepository`, add:
```dart
  @override
  Future<void> setPhotoUrl(String uid, String url) async {
    final u = _users[uid];
    if (u != null) {
      _users[uid] = u.copyWith(photoUrl: url);
      _ctrl(uid).add(_users[uid]);
    }
  }
```

- [ ] **Step 6: Run tests + full suite**

Run: `flutter test test/data/photo_url_test.dart` → PASS. Then `flutter test` (whole suite) and `flutter analyze`.
If an existing model test asserts the exact `toMap` key set (e.g. a `containsKey('photoUrl')` style assertion), update that single assertion to reflect the new additive key — do not weaken any other assertion.

- [ ] **Step 7: Commit**

```bash
git add lib/data/models/pet_profile.dart lib/data/models/user_profile.dart lib/data/repositories/user_repository.dart lib/data/repositories/firebase/firestore_user_repository.dart test/support/fakes.dart test/data/photo_url_test.dart
git commit -m "feat: add photoUrl to PetProfile + UserProfile and UserRepository.setPhotoUrl"
```

---

### Task 2: `StorageRepository` seam + Firebase impl + fake + provider

**Files:**
- Create: `lib/data/repositories/storage_repository.dart`, `lib/data/repositories/firebase/firebase_storage_repository.dart`
- Modify: `lib/data/repositories/providers.dart`, `test/support/fakes.dart`
- Test: `test/data/storage_repository_test.dart`

**Interfaces:**
- Produces: `abstract interface class StorageRepository { Future<String> uploadImage({required String path, required Uint8List bytes}); }`; `FirebaseStorageRepository`; `InMemoryStorageRepository` (field `Map<String, Uint8List> uploads`, returns `https://fake.storage/$path`); `storageRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/storage_repository_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';

void main() {
  test('InMemoryStorageRepository stores the bytes and returns a URL', () async {
    final repo = InMemoryStorageRepository();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final url = await repo.uploadImage(path: 'users/u1/avatar.jpg', bytes: bytes);
    expect(url, 'https://fake.storage/users/u1/avatar.jpg');
    expect(repo.uploads['users/u1/avatar.jpg'], bytes);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage_repository_test.dart`
Expected: FAIL — `InMemoryStorageRepository` not found.

- [ ] **Step 3: Create the interface**

`lib/data/repositories/storage_repository.dart`:
```dart
import 'dart:typed_data';

abstract interface class StorageRepository {
  /// Uploads [bytes] (a JPEG) to [path]; returns the public download URL.
  Future<String> uploadImage({required String path, required Uint8List bytes});
}
```

- [ ] **Step 4: Create the Firebase implementation**

`lib/data/repositories/firebase/firebase_storage_repository.dart`:
```dart
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import '../storage_repository.dart';

class FirebaseStorageRepository implements StorageRepository {
  final FirebaseStorage _storage;
  FirebaseStorageRepository([FirebaseStorage? storage])
      : _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<String> uploadImage({required String path, required Uint8List bytes}) async {
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
```

- [ ] **Step 5: Add the fake**

In `test/support/fakes.dart`, add `import 'dart:typed_data';` and `import 'package:pet_aggregator_app/data/repositories/storage_repository.dart';` alongside the existing imports (do not duplicate), then append:
```dart
class InMemoryStorageRepository implements StorageRepository {
  final Map<String, Uint8List> uploads = {};

  @override
  Future<String> uploadImage({required String path, required Uint8List bytes}) async {
    uploads[path] = bytes;
    return 'https://fake.storage/$path';
  }
}
```

- [ ] **Step 6: Add the provider**

In `lib/data/repositories/providers.dart`, add imports `import 'storage_repository.dart';` and `import 'firebase/firebase_storage_repository.dart';`, then append:
```dart
final storageRepositoryProvider =
    Provider<StorageRepository>((ref) => FirebaseStorageRepository());
```

- [ ] **Step 7: Run test + analyze + commit**

Run: `flutter test test/data/storage_repository_test.dart` → PASS; `flutter analyze` clean.
```bash
git add lib/data/repositories/storage_repository.dart lib/data/repositories/firebase/firebase_storage_repository.dart lib/data/repositories/providers.dart test/support/fakes.dart test/data/storage_repository_test.dart
git commit -m "feat: add StorageRepository seam (Firebase Storage impl + fake)"
```

---

### Task 3: `ImagePickerService` seam + `image_picker` dependency + fake + provider

**Files:**
- Modify: `pubspec.yaml` (add `image_picker`)
- Create: `lib/data/services/image_picker_service.dart`
- Modify: `lib/data/repositories/providers.dart`, `test/support/fakes.dart`
- Test: `test/data/image_picker_service_test.dart`

**Interfaces:**
- Produces: `abstract interface class ImagePickerService { Future<Uint8List?> pickImage(); }`; `ImagePickerServiceImpl`; `FakeImagePickerService` (constructor takes optional `Uint8List? next`, exposes `int calls`); `imagePickerServiceProvider`.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add image_picker`
Expected: `pubspec.yaml` gains `image_picker: ^<latest>` and `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing test**

```dart
// test/data/image_picker_service_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';

void main() {
  test('FakeImagePickerService returns the configured bytes and counts calls', () async {
    final bytes = Uint8List.fromList([9, 9]);
    final picker = FakeImagePickerService(bytes);
    expect(await picker.pickImage(), bytes);
    expect(picker.calls, 1);
  });

  test('FakeImagePickerService returns null when nothing is configured (cancelled pick)', () async {
    final picker = FakeImagePickerService();
    expect(await picker.pickImage(), isNull);
    expect(picker.calls, 1);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/image_picker_service_test.dart`
Expected: FAIL — `FakeImagePickerService` not found.

- [ ] **Step 4: Create the service (the only file importing `image_picker`)**

`lib/data/services/image_picker_service.dart`:
```dart
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

abstract interface class ImagePickerService {
  /// Opens the gallery picker; returns downsized JPEG bytes, or null if cancelled.
  Future<Uint8List?> pickImage();
}

class ImagePickerServiceImpl implements ImagePickerService {
  final ImagePicker _picker;
  ImagePickerServiceImpl([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  @override
  Future<Uint8List?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery, maxWidth: 1080, imageQuality: 80);
    if (file == null) return null;
    return file.readAsBytes();
  }
}
```

- [ ] **Step 5: Add the fake**

In `test/support/fakes.dart`, add `import 'package:pet_aggregator_app/data/services/image_picker_service.dart';` alongside the existing imports, then append:
```dart
class FakeImagePickerService implements ImagePickerService {
  final Uint8List? next;
  int calls = 0;
  FakeImagePickerService([this.next]);

  @override
  Future<Uint8List?> pickImage() async {
    calls++;
    return next;
  }
}
```

- [ ] **Step 6: Add the provider**

In `lib/data/repositories/providers.dart`, add `import '../services/image_picker_service.dart';`, then append:
```dart
final imagePickerServiceProvider =
    Provider<ImagePickerService>((ref) => ImagePickerServiceImpl());
```

- [ ] **Step 7: Run test + analyze + commit**

Run: `flutter test test/data/image_picker_service_test.dart` → PASS; `flutter analyze` clean.
```bash
git add pubspec.yaml pubspec.lock lib/data/services/image_picker_service.dart lib/data/repositories/providers.dart test/support/fakes.dart test/data/image_picker_service_test.dart
git commit -m "feat: add ImagePickerService seam + image_picker dependency"
```

---

### Task 4: `PgImageSlot` network-image support

**Files:**
- Modify: `lib/core/widgets/pg_image_slot.dart`
- Test: `test/core/pg_image_slot_test.dart`

**Interfaces:**
- Produces: `PgImageSlot({..., String? imageUrl})` — renders `Image.network(imageUrl)` cover-fit clipped to the slot shape when non-empty, else the emoji placeholder; `errorBuilder` falls back to the placeholder.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/pg_image_slot_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_image_slot.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders a network image when imageUrl is set', (tester) async {
    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾', imageUrl: 'https://x/img.jpg'));
    expect(
      find.byWidgetPredicate((w) =>
          w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == 'https://x/img.jpg'),
      findsOneWidget,
    );
  });

  testWidgets('renders the emoji placeholder when imageUrl is null or empty', (tester) async {
    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾'));
    expect(find.text('🐾'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾', imageUrl: ''));
    expect(find.text('🐾'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/pg_image_slot_test.dart`
Expected: FAIL — `imageUrl` is not a parameter of `PgImageSlot`.

- [ ] **Step 3: Implement**

Replace the body of `lib/core/widgets/pg_image_slot.dart` with:
```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgImageSlot extends StatelessWidget {
  final double? size;
  final bool circle;
  final String? emoji;
  final double radius;
  final String? imageUrl;
  const PgImageSlot({
    super.key, this.size, this.circle = false, this.emoji, this.radius = 20, this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final placeholder = Text(emoji ?? '🐾', style: const TextStyle(fontSize: 22));
    final url = imageUrl;
    final hasImage = url != null && url.isNotEmpty;
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface2,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: Border.all(color: c.border),
      ),
      child: hasImage
          ? Image.network(url, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(child: placeholder))
          : placeholder,
    );
  }
}
```
(The `Container`'s `clipBehavior: Clip.antiAlias` clips the image to the circle/rounded-rect from the decoration — no separate `ClipOval`/`ClipRRect` needed. Every existing call site omits `imageUrl` and is unaffected.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/pg_image_slot_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite + analyze + commit**

Run `flutter test` (the widget is used across many screens — confirm no regression) and `flutter analyze`.
```bash
git add lib/core/widgets/pg_image_slot.dart test/core/pg_image_slot_test.dart
git commit -m "feat: PgImageSlot renders a network image with emoji fallback"
```

---

### Task 5: Pet-photo pick + upload in `CreatePetScreen`

**Files:**
- Modify: `lib/features/pets/create_pet_screen.dart`
- Test: `test/features/create_pet_photo_test.dart`

**Interfaces:**
- Consumes: `imagePickerServiceProvider` (`pickImage()`), `storageRepositoryProvider` (`uploadImage(path:, bytes:)`), `PetProfile.photoUrl`, existing `petRepositoryProvider.addPet`, `authRepositoryProvider`, `currentUserProfileProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/create_pet_photo_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_image_slot.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('picking a photo previews it; Finish uploads and saves photoUrl', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final pets = InMemoryPetRepository();
    final storage = InMemoryStorageRepository();
    final picker = FakeImagePickerService(Uint8List.fromList([1, 2, 3]));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(pets),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(picker),
    ], initialLocation: Routes.createPet);
    await tester.pumpAndSettle();

    // Tap the photo slot -> picker runs -> the picked bytes preview.
    await tester.tap(find.byType(PgImageSlot));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('Tap to change photo'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // Image.memory preview

    await tester.enterText(find.byType(TextField).first, 'Bruno');
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    final saved = (await pets.watchMyPets(uid).first).single;
    expect(saved.name, 'Bruno');
    expect(saved.photoUrl, startsWith('https://fake.storage/pets/$uid'));
    expect(storage.uploads.length, 1);
  });

  testWidgets('cancelling the picker leaves the placeholder and saves without a photo', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final pets = InMemoryPetRepository();
    final storage = InMemoryStorageRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(pets),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(FakeImagePickerService()), // returns null
    ], initialLocation: Routes.createPet);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PgImageSlot));
    await tester.pumpAndSettle();
    expect(find.text('Upload a cute photo 📸'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Mochi');
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    expect((await pets.watchMyPets(uid).first).single.photoUrl, '');
    expect(storage.uploads, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/create_pet_photo_test.dart`
Expected: FAIL — tapping the slot does nothing (`picker.calls` is 0 / no preview).

- [ ] **Step 3: Add photo state + the picker handler**

In `lib/features/pets/create_pet_screen.dart`, add `import 'dart:typed_data';` at the top. In `_CreatePetScreenState`, add the field next to `_saving`:
```dart
  Uint8List? _photoBytes;
```
and add this method (next to `_finish`):
```dart
  Future<void> _pickPhoto() async {
    final bytes = await ref.read(imagePickerServiceProvider).pickImage();
    if (!mounted || bytes == null) return;
    setState(() => _photoBytes = bytes);
  }
```

- [ ] **Step 4: Make the slot tappable + preview the pick**

Replace the photo block (the `Center(child: Column(children: [const PgImageSlot(size: 110, circle: true, emoji: '📸'), … 'Upload a cute photo 📸' …]))`) with:
```dart
                Center(child: Column(children: [
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: _photoBytes == null
                        ? const PgImageSlot(size: 110, circle: true, emoji: '📸')
                        : ClipOval(child: Image.memory(_photoBytes!,
                            width: 110, height: 110, fit: BoxFit.cover)),
                  ),
                  const SizedBox(height: 10),
                  Text(_photoBytes == null ? 'Upload a cute photo 📸' : 'Tap to change photo',
                    style: PgText.inter(13, FontWeight.w600, color: c.brand)),
                ])),
```

- [ ] **Step 5: Upload on Finish and pass `photoUrl` to `addPet`**

Replace `_finish` with:
```dart
  Future<void> _finish() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    final area = ref.read(currentUserProfileProvider).value?.area ?? '';
    final name = _name.text.trim();

    var photoUrl = '';
    final bytes = _photoBytes;
    if (bytes != null) {
      try {
        photoUrl = await ref.read(storageRepositoryProvider).uploadImage(
            path: 'pets/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg', bytes: bytes);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text("Couldn't upload the photo — saving without it."),
              behavior: SnackBarBehavior.floating));
        }
      }
    }

    await ref.read(petRepositoryProvider).addPet(PetProfile(
          id: '', ownerId: uid, name: name, breed: _breed.text.trim(),
          ageLabel: _age.text.trim(), sex: '', area: area, species: _species,
          vaccinated: _vaccinated, accentColor: PetProfile.accentFor(name),
          photoUrl: photoUrl));
    if (mounted) context.go(Routes.home);
  }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/create_pet_photo_test.dart`
Expected: PASS (both tests).

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/features/pets/create_pet_screen.dart test/features/create_pet_photo_test.dart
git commit -m "feat: pick + upload a pet photo when creating a pet"
```

---

### Task 6: Avatar pick + upload in `ProfileScreen`

**Files:**
- Modify: `lib/features/profile/profile_screen.dart`
- Test: `test/features/profile_avatar_upload_test.dart`

**Interfaces:**
- Consumes: `imagePickerServiceProvider`, `storageRepositoryProvider`, `userRepositoryProvider.setPhotoUrl`, `currentUserProfileProvider`, `PgImageSlot.imageUrl`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/profile_avatar_upload_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_image_slot.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('tapping the avatar uploads the pick and persists photoUrl', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final storage = InMemoryStorageRepository();
    final picker = FakeImagePickerService(Uint8List.fromList([7, 7]));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(picker),
    ], initialLocation: Routes.profile);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PgImageSlot).first); // the header avatar
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(storage.uploads.keys.single, 'users/$uid/avatar.jpg');
    expect((await users.watchUser(uid).first)!.photoUrl,
        'https://fake.storage/users/$uid/avatar.jpg');
  });

  testWidgets('cancelling the picker leaves photoUrl untouched', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final storage = InMemoryStorageRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(FakeImagePickerService()), // null
    ], initialLocation: Routes.profile);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PgImageSlot).first);
    await tester.pumpAndSettle();

    expect(storage.uploads, isEmpty);
    expect((await users.watchUser(uid).first)!.photoUrl, '');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/profile_avatar_upload_test.dart`
Expected: FAIL — tapping the avatar does nothing (`picker.calls` is 0).

- [ ] **Step 3: Convert `ProfileScreen` to a `ConsumerStatefulWidget`**

In `lib/features/profile/profile_screen.dart`, add `import 'dart:typed_data';` is NOT needed (bytes are only passed through). Change the class declaration from:
```dart
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```
to:
```dart
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploading = false;

  Future<void> _pickAndUploadAvatar() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null || _uploading) return;
    final bytes = await ref.read(imagePickerServiceProvider).pickImage();
    if (!mounted || bytes == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref.read(storageRepositoryProvider)
          .uploadImage(path: 'users/$uid/avatar.jpg', bytes: bytes);
      await ref.read(userRepositoryProvider).setPhotoUrl(uid, url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text("Couldn't upload the photo. Please try again."),
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
```
The rest of `build`'s body and the existing `_stat`, `_menuGroup`, `_row` helper methods move into `_ProfileScreenState` **unchanged** (they are now methods of the State class; `ref` is available as a field, so the old `ref` parameter is simply gone).

- [ ] **Step 4: Make the header avatar tappable + show the photo**

In that same file, replace the header avatar line:
```dart
                const PgImageSlot(size: 72, circle: true, emoji: '🙂'),
```
with:
```dart
                GestureDetector(
                  onTap: _pickAndUploadAvatar,
                  child: Stack(alignment: Alignment.center, children: [
                    PgImageSlot(size: 72, circle: true, emoji: '🙂', imageUrl: profile?.photoUrl),
                    if (_uploading)
                      const SizedBox(width: 26, height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                  ]),
                ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/profile_avatar_upload_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Full suite + analyze + commit**

Run `flutter test` (the ProfileScreen conversion touches an existing screen — confirm no regression; if an existing Profile test breaks only because it now needs `storageRepositoryProvider`/`imagePickerServiceProvider` overrides, add those overrides without changing any assertion) and `flutter analyze`.
```bash
git add lib/features/profile/profile_screen.dart test/features/profile_avatar_upload_test.dart
git commit -m "feat: tap the Profile avatar to pick + upload a photo"
```

---

### Task 7: Display the photos everywhere they're already available

**Files:**
- Modify: `lib/features/home/widgets/pet_row.dart`, `lib/core/widgets/pg_swipe_card.dart`, `lib/features/pets/pet_profile_detail_screen.dart`, `lib/features/profile/profile_screen.dart`, `lib/features/home/home_screen.dart`
- Test: `test/features/photo_display_test.dart`

**Interfaces:**
- Consumes: `PetProfile.photoUrl`, `UserProfile.photoUrl`, `PgImageSlot.imageUrl`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/photo_display_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('a pet photo and my avatar render as network images on Home', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent, photoUrl: 'https://x/me.jpg'));
    final pets = InMemoryPetRepository([
      PetProfile(id: 'p1', ownerId: 'someone-else', name: 'Bruno', breed: 'Labrador',
          ageLabel: '2 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
          vaccinated: true, accentColor: PetProfile.accentFor('Bruno'),
          photoUrl: 'https://x/bruno.jpg'),
    ]);

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(pets),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();

    bool hasNetworkImage(String url) => find
        .byWidgetPredicate((w) =>
            w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url)
        .evaluate()
        .isNotEmpty;

    expect(hasNetworkImage('https://x/bruno.jpg'), isTrue); // pet row
    expect(hasNetworkImage('https://x/me.jpg'), isTrue);    // header avatar
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/photo_display_test.dart`
Expected: FAIL — no network images (slots still render emoji only).

- [ ] **Step 3: Wire the pet photo into the Home row and the Discovery deck**

In `lib/features/home/widgets/pet_row.dart`, replace:
```dart
          const PgImageSlot(size: 54, circle: true),
```
with:
```dart
          PgImageSlot(size: 54, circle: true, imageUrl: pet.photoUrl),
```
In `lib/core/widgets/pg_swipe_card.dart`, replace:
```dart
                  const Positioned.fill(child: PgImageSlot(radius: 0, emoji: '🐶')),
```
with:
```dart
                  Positioned.fill(
                    child: PgImageSlot(radius: 0, emoji: '🐶', imageUrl: widget.pet.photoUrl)),
```

- [ ] **Step 4: Wire the pet photo into the Pet-profile header**

In `lib/features/pets/pet_profile_detail_screen.dart`, replace the header image container:
```dart
            Container(height: 280, width: double.infinity, color: c.surface2, alignment: Alignment.center,
              child: Text(_speciesEmoji(p.species), style: const TextStyle(fontSize: 64))),
```
with:
```dart
            Container(
              height: 280, width: double.infinity, color: c.surface2, alignment: Alignment.center,
              child: p.photoUrl.isEmpty
                  ? Text(_speciesEmoji(p.species), style: const TextStyle(fontSize: 64))
                  : Image.network(p.photoUrl, height: 280, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Text(_speciesEmoji(p.species), style: const TextStyle(fontSize: 64))),
            ),
```

- [ ] **Step 5: Wire my avatar into the Home header and the Profile pet card**

In `lib/features/home/home_screen.dart`, replace the header avatar:
```dart
              const PgImageSlot(size: 46, circle: true),
```
with:
```dart
              PgImageSlot(size: 46, circle: true, imageUrl: profile?.photoUrl),
```
(`profile` is the existing `ref.watch(currentUserProfileProvider).value` local in `build`.)

In `lib/features/profile/profile_screen.dart`, replace the pet-card slot:
```dart
                  const PgImageSlot(size: 52, circle: true, emoji: '🐾'),
```
with:
```dart
                  PgImageSlot(size: 52, circle: true, emoji: '🐾', imageUrl: pets.first.photoUrl),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/photo_display_test.dart`
Expected: PASS.

- [ ] **Step 7: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/home/widgets/pet_row.dart lib/core/widgets/pg_swipe_card.dart lib/features/pets/pet_profile_detail_screen.dart lib/features/profile/profile_screen.dart lib/features/home/home_screen.dart test/features/photo_display_test.dart
git commit -m "feat: display pet photos + my avatar wherever they're available"
```
Expected: whole suite green, analyze clean.

---

### Task 8: Storage rules + `firebase.json`; deploy + final verification

**Files:**
- Create: `storage.rules`
- Modify: `firebase.json`

- [ ] **Step 1: Create `storage.rules`**

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{uid}/{file} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == uid;
    }
    match /pets/{file} {
      allow read: if request.auth != null;
      // pet files are named "{uid}_{millis}.jpg" — enforce the uploader's own prefix
      allow write: if request.auth != null && file.matches(request.auth.uid + '_.*');
    }
  }
}
```

- [ ] **Step 2: Register the rules file in `firebase.json`**

Add a `storage` block as a sibling of the existing `firestore` block:
```json
  "storage": {
    "rules": "storage.rules"
  },
```

- [ ] **Step 3: Commit the config**

```bash
git add storage.rules firebase.json
git commit -m "chore: add Firebase Storage rules (owner-scoped avatars, uid-prefixed pet photos)"
```

- [ ] **Step 4: Deploy the rules (owner-gated)**

Run: `firebase deploy --only storage --project pet-aggregator-app`
Expected: `Deploy complete!`.
**If it fails because Storage is not enabled** (the default bucket doesn't exist yet), that is the one owner step: the project owner must enable **Storage** in the Firebase console (Build → Storage → Get started), then re-run the deploy. If the `file.matches(...)` prefix rule fails to compile, fall back to `allow write: if request.auth != null;`, redeploy, and note the prefix enforcement as a rules-hardening follow-up.

- [ ] **Step 5: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: unit/widget tests pass, analyze clean, APK builds (this also proves the new `image_picker` native plugin compiles — keep `kotlin.incremental=false`).

- [ ] **Step 6: Manual walkthrough (real device/emulator)**

Run: `flutter run -d emulator-5554`. Create a pet with a gallery photo → it appears on Home, the Discovery deck, and the Pet-profile header. On Profile, tap the avatar → pick a photo → it uploads and shows on Profile + the Home header. Kill and relaunch the app → both photos persist (loaded from their stored URLs).

---

## Self-Review

**Spec coverage:**
- `image_picker` dep + `ImagePickerService` seam (+ fake, provider) → Task 3. ✓
- `StorageRepository` seam + Firebase impl (+ fake, provider) → Task 2. ✓
- `PetProfile.photoUrl` / `UserProfile.photoUrl` / `UserRepository.setPhotoUrl` → Task 1. ✓
- `PgImageSlot` network-image support with emoji fallback → Task 4. ✓
- Pet-photo upload in `CreatePetScreen` → Task 5; avatar upload in `ProfileScreen` → Task 6. ✓
- Display wiring (pet row, deck, pet-profile header, profile pet card, profile + home avatars) → Task 7. ✓
- `storage.rules` + `firebase.json` + deploy + owner step → Task 8. ✓
- Error handling (try/catch + snackbar, `mounted` guards) → Tasks 5–6. ✓
- Deferred (camera, pro/host/review photos, other users' avatars, galleries) → none implemented. ✓
- The spec's optional Storage-emulator integration test is intentionally **not** included: the Storage emulator isn't in `firebase.json`'s emulator block and the seam is fully covered by fakes + the Task 8 manual walkthrough. Recorded as a follow-up rather than a task.

**Placeholder scan:** No "TBD/TODO". Every code step shows the exact code. `Uint8List` imports are named where needed (`dart:typed_data`). Upload paths are exact (`users/{uid}/avatar.jpg`, `pets/{uid}_{millis}.jpg`).

**Type consistency:**
- `StorageRepository.uploadImage({required String path, required Uint8List bytes}) → Future<String>` defined Task 2, consumed Tasks 5–6. ✓
- `ImagePickerService.pickImage() → Future<Uint8List?>` defined Task 3, consumed Tasks 5–6. ✓
- `PetProfile.photoUrl` / `UserProfile.photoUrl` / `copyWith(photoUrl:)` / `setPhotoUrl(uid, url)` defined Task 1, consumed Tasks 5 (addPet), 6 (setPhotoUrl), 7 (display). ✓
- `PgImageSlot({..., String? imageUrl})` defined Task 4, consumed Tasks 6–7. ✓
- `storageRepositoryProvider` (Task 2) / `imagePickerServiceProvider` (Task 3) consumed Tasks 5–6. ✓
- Fakes `InMemoryStorageRepository` (field `uploads`, URL `https://fake.storage/$path`) and `FakeImagePickerService([Uint8List? next])` with `calls` — defined Tasks 2–3, used in Tasks 5–7 tests exactly as defined. ✓
- Existing APIs reused with verified signatures: `PetRow`'s `const PgImageSlot(size: 54, circle: true)`, `PgSwipeCard`'s `const Positioned.fill(child: PgImageSlot(radius: 0, emoji: '🐶'))`, `ProfileScreen`'s `const PgImageSlot(size: 72/52, …)`, `home_screen.dart`'s `const PgImageSlot(size: 46, circle: true)` + its `profile` local, `pet_profile_detail_screen.dart`'s 280px header + `_speciesEmoji(p.species)`, `InMemoryPetRepository([List<PetProfile>? seed])` + `watchMyPets`, `InMemoryUserRepository.watchUser`, and `pumpPg`/`pumpPgApp`. ✓
