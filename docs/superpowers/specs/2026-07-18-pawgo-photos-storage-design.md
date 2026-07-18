# Pawgo Slice 8: Photos & Storage — Design

> **Status:** approved design (2026-07-18). First of the deferred integrations. Firebase Storage-backed image upload + display, replacing the emoji placeholders for **pet photos** and the **user avatar**. Built on the live backend.

## Goal

Let a user attach a real photo to their **pet** (at pet creation) and to their **own profile avatar** (tap-to-change), stored in Firebase Storage, and display those photos wherever the app currently shows an emoji placeholder for them. Build the reusable storage plumbing (an upload seam, an image-picker seam, and network-image display) so later surfaces (pro/host listings, review photos) are incremental.

## Design decisions (settled during brainstorming)

- **Scope = pet photos + user avatar.** Pro/host listing photos, review photos, and other users' avatars (in chat/review rows) are deferred to a follow-up once the infra is proven.
- **Two new seams** (repository pattern): `StorageRepository` (the Firebase-Storage boundary) and `ImagePickerService` (the `image_picker` boundary). Both have a Firebase/plugin impl + an in-memory fake, so upload flows are unit-testable without the plugin or a live bucket.
- **One new package: `image_picker`** (first new dependency since `shared_preferences`). `firebase_storage` is already a dependency.
- **`PgImageSlot` gains an `imageUrl`** param: renders `Image.network` (cover-fit, respecting size/circle/radius) when set, else the existing emoji placeholder; loading/error → placeholder. Every existing call site is unaffected (default `imageUrl: null`).
- **Gallery only** (the system photo picker — no camera permission). Camera capture deferred.
- **Downsize at pick time** via `image_picker`'s `maxWidth: 1080, imageQuality: 80` (no extra package; keeps uploads small).
- **Storage layout:** avatar → `users/{uid}/avatar.jpg` (overwrite on change); pet → `pets/{uid}_{millis}.jpg` (client-keyed, so upload doesn't depend on the Firestore doc id). The **download URL** is stored on the doc's `photoUrl`.
- **Deferred:** camera capture; pro/host listing photos; review photos; other users' avatars in chat/review rows; multi-photo galleries; delete-old-file cleanup on avatar replace.

## Scope

**In scope**
- New dep `image_picker`; `StorageRepository` (+ `FirebaseStorageRepository` + fake) and `ImagePickerService` (+ `image_picker` impl + fake) + providers.
- `PetProfile.photoUrl` + `UserProfile.photoUrl` (additive); `UserRepository.setPhotoUrl(uid, url)`.
- `PgImageSlot` network-image support.
- Pet-photo upload in `CreatePetScreen`; avatar upload (tap avatar) in `ProfileScreen`.
- Display wiring at the pet + my-avatar sites.
- `storage.rules` + `firebase.json` storage block + deploy; owner enables Storage.
- TDD with fakes; optional Storage-emulator integration test.

**Out of scope (later)**
- Camera capture; pro/host listing photos; review photos; other users' avatars in chat/review rows; multi-image galleries; server-side image processing/thumbnails; deleting the previous file when an avatar is replaced (overwrite at a fixed path handles the avatar; stale pet files are acceptable for now).

## New dependency

`image_picker` (latest stable compatible with the SDK floor). Android uses the system photo picker (no runtime permission needed for gallery on modern Android). Keep `android/gradle.properties` → `kotlin.incremental=false` (already present).

## Data-model & repository changes

```
pets/{id}      .photoUrl : string (download URL, default '')
users/{uid}    .photoUrl : string (download URL, default '')
Firebase Storage:
  users/{uid}/avatar.jpg          (owner-write)
  pets/{uid}_{millis}.jpg         (signed-in write, uid-prefixed)
```

- `PetProfile`: add `final String photoUrl;` (default `''`) to constructor + `toMap` + `fromMap` (default `''`). (`accentColor` stays derived.)
- `UserProfile`: add `final String photoUrl;` (default `''`) to constructor + `toMap` + `fromMap` + `copyWith`.
- `UserRepository`: add `Future<void> setPhotoUrl(String uid, String url)` → Firestore `users/{uid}.update({'photoUrl': url})`; fake sets it via `copyWith` + re-emits (mirrors `updateArea`/`markNotificationsSeen`).

## Seams (`data/repositories/`)

`storage_repository.dart`:
```dart
abstract interface class StorageRepository {
  /// Uploads [bytes] (a JPEG) to [path]; returns the public download URL.
  Future<String> uploadImage({required String path, required Uint8List bytes});
}
```
- `FirebaseStorageRepository` under `repositories/firebase/`: `ref(path).putData(bytes, SettableMetadata(contentType: 'image/jpeg'))` → `ref(path).getDownloadURL()`. Constructor injects `FirebaseStorage` (`([FirebaseStorage? s])`), matching the other Firestore repos.
- `InMemoryStorageRepository` fake: stores `path→bytes`, returns a deterministic fake URL (e.g. `https://fake.storage/$path`).

`image_picker_service.dart` (a thin service seam, not a "repository" but same pattern):
```dart
abstract interface class ImagePickerService {
  /// Opens the gallery picker; returns downsized JPEG bytes, or null if cancelled.
  Future<Uint8List?> pickImage();
}
```
- `ImagePickerServiceImpl`: wraps `ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 80)` → `readAsBytes()` (or null). This file is the only one importing `image_picker`.
- `FakeImagePickerService` (test support): returns injectable canned bytes (or null to simulate cancel).

Providers (`providers.dart`): `storageRepositoryProvider` → `Provider<StorageRepository>(FirebaseStorageRepository())`; `imagePickerServiceProvider` → `Provider<ImagePickerService>(ImagePickerServiceImpl())`. Overridden with fakes in tests + in `main.dart` if needed (real impls are fine in `main`).

## `PgImageSlot` change

Add `final String? imageUrl;` (default null). In `build`, when `imageUrl != null && imageUrl!.isNotEmpty`, render the image clipped to the slot's shape:
```dart
child: (imageUrl != null && imageUrl!.isNotEmpty)
    ? ClipRRect/ClipOval(Image.network(imageUrl!, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => <emoji placeholder>))
    : <emoji placeholder>,
```
Circle → `ClipOval`; rectangle → `ClipRRect(borderRadius: radius)`. The container's border/background remain (visible while loading / on error). Existing call sites keep their emoji (no `imageUrl` passed).

## Upload flows

- **Pet** (`CreatePetScreen`, already a `ConsumerStatefulWidget` with the "Upload a cute photo 📸" slot): tap the slot → `imagePickerService.pickImage()`; on non-null, hold the bytes in state and preview them (`Image.memory` inside the slot). On **Finish**: if bytes present, `uploadImage(path: 'pets/${uid}_${now}.jpg', bytes)` → URL; pass `photoUrl:` into the `PetProfile` given to `addPet`. Upload wrapped in try/catch → on failure, a snackbar and the pet still saves without a photo. `mounted`-guarded after awaits.
- **Avatar** (`ProfileScreen`): wrap the header avatar `PgImageSlot` in a tap → `pickImage()`; on non-null, `uploadImage(path: 'users/${uid}/avatar.jpg', bytes)` → `setPhotoUrl(uid, url)`; the avatar re-renders from `currentUserProfileProvider`. Try/catch → failure snackbar; `mounted`-guarded. A brief uploading state (e.g. a spinner over the avatar) while in flight.

## Display wiring

Pass `imageUrl:` to `PgImageSlot` (or the equivalent image area) where the object is already in hand:
- **Pet photo:** Home pet-rows (`PetRow`), the Discovery deck card, Pet-profile header, and the Profile screen's pet card → `pet.photoUrl`.
- **My avatar:** Profile header + Home header → `currentUserProfileProvider.value?.photoUrl`.

(Sites showing *other* users — chat rows, review authors, pet-parent on pet profile — keep their emoji this slice; those need the other user's `photoUrl` and are deferred.)

## Rules, config, owner setup

`storage.rules` (new):
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
(If the `file.matches(...)` prefix rule proves troublesome to deploy, fall back to `allow write: if request.auth != null` and track the prefix enforcement as a rules-hardening follow-up — consistent with the codebase's current posture.) Add to `firebase.json`: `"storage": { "rules": "storage.rules" }`. **Owner one-time step:** enable Firebase Storage (create the default bucket) in the console; then `firebase deploy --only storage`. (Read requires auth via the SDK; `getDownloadURL` tokens render fine in `Image.network`.)

## Error handling

Both flows wrap `uploadImage` in try/catch → a "Couldn't upload the photo" snackbar; the pet save proceeds photo-less, the avatar keeps its prior value. `mounted` guarded after each await. `PgImageSlot`'s `errorBuilder` falls back to the emoji, so a broken/loading URL never blanks the UI.

## Testing

TDD with fakes via `pumpPgApp` overrides (`storageRepositoryProvider`, `imagePickerServiceProvider`, plus the usual repos):
- `PetProfile`/`UserProfile` `photoUrl` round-trip; `InMemoryUserRepository.setPhotoUrl` sets it + re-emits.
- `InMemoryStorageRepository.uploadImage` returns a URL and stores the bytes; `FakeImagePickerService` returns canned bytes / null.
- **Pet flow:** tapping the slot with a fake picker previews the image; Finish uploads and `addPet` receives a non-empty `photoUrl` (assert via the fake pet repo).
- **Avatar flow:** tapping the avatar uploads and `setPhotoUrl` persists a non-empty URL (assert via the fake user repo); a cancelled pick (null) is a no-op.
- **`PgImageSlot`:** renders an `Image` with `NetworkImage(url)` when `imageUrl` is set (asserted via `find.byWidgetPredicate`, no network fetch), and the emoji `Text` when null/empty.
- Optional: add the **Storage emulator** to `firebase.json` (`"storage": { "port": 9199 }`) + one integration test (`FirebaseStorageRepository.uploadImage` → non-empty URL, `useStorageEmulator`) for parity with the other repos.

## Prerequisites

- Owner enables **Firebase Storage** in the console (creates the default bucket) — required before `firebase deploy --only storage` and before real uploads work on-device. Fakes make all `flutter test` work without it.

## Deliverable / definition of done

At pet creation the user can pick a gallery photo and it shows on the pet everywhere; from the Profile screen the user can tap their avatar to set a photo that shows on Profile + the Home header; both persist to Storage with the URL on the Firestore doc. `flutter analyze` clean, `flutter test` green (fakes), debug APK builds, and (once the owner enables Storage) `firebase deploy --only storage` succeeds and a real upload round-trips on the emulator/device.
