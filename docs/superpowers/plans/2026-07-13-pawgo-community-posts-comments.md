# Pawgo Phase 6: Community — Posts & Comments — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Community forum on live Firestore — a filterable feed of posts, a create-post flow with an honest "Your post is live!" celebration, and a thread view with real comments (add a reply).

**Architecture:** Feature-first Flutter on the existing repository seam. A new `PostRepository` (interface + Firestore impl + in-memory fake) backs `posts` and the `posts/{id}/comments` subcollection; providers expose the feed and per-post comments (`StreamProvider.family`). Reply counts are real via `FieldValue.increment`. Screens are thin `Consumer`/`Stateless` composition, leaf-first so navigation targets exist when tested. Upvotes/photos are out of scope.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-13-pawgo-community-posts-comments-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, and `integration_test/`.
- **Upvotes omitted** (deferred, not faked); **reply counts are real**. Author = the user's display name; feed subtitle is a neutral "Mumbai pet parents".
- **`createdAt` is a client `millisSinceEpoch` int** (not a server `Timestamp`) — set in `toMap()` for posts and comments, so the model can read it back for "time ago". `orderBy('createdAt')` uses it.
- **`replyCount`** starts 0 and is bumped with `FieldValue.increment(1)` when a comment is added (in the repository).
- Riverpod 3.x: use `AsyncValue.value` (not `valueOrNull`); in tests, `Override` comes from `package:flutter_riverpod/misc.dart`; prefer a repo stream's `.first`.
- `go_router` builders use `(_, _)`; routes that read `extra` use `(_, state)`. Screen tests use the `pumpPgApp`/`pumpPg` harness (`pumpPgApp` accepts an `extra:` arg). Any plain `test()` touching `GoogleFonts` uses `testWidgets`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `PostCategory` + `Post` + `Comment` models

**Files:**
- Create: `lib/data/models/post.dart`
- Test: `test/data/post_test.dart`

**Interfaces:**
- Produces: `enum PostCategory { health, training, lostFound }` (with `storageKey`, `label`, `emoji`, `Color color`, `fromStorage`); `class Post { final String id, authorId, authorName, title, body; final PostCategory category; final int replyCount, createdAt; ... static String timeAgo(int); }`; `class Comment { final String id, authorId, authorName, body; final int createdAt; ... }`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/post_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/post.dart';

void main() {
  test('PostCategory round-trips with label/emoji', () {
    expect(PostCategory.lostFound.label, 'Lost & Found');
    expect(PostCategory.fromStorage('training'), PostCategory.training);
    expect(PostCategory.fromStorage('nonsense'), PostCategory.health); // safe default
  });

  test('Post toMap omits id, keeps createdAt/replyCount; fromMap restores', () {
    const p = Post(authorId: 'u1', authorName: 'Radhika', category: PostCategory.health,
        title: 'Vet in Bandra?', body: 'Bruno needs boosters.', createdAt: 1234);
    final m = p.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m['category'], 'health');
    expect(m['createdAt'], 1234);
    expect(m['replyCount'], 0);
    final back = Post.fromMap('post1', m);
    expect(back.id, 'post1');
    expect(back.title, 'Vet in Bandra?');
    expect(back.category, PostCategory.health);
  });

  test('Comment round-trips', () {
    const c = Comment(authorId: 'u2', authorName: 'Pali', body: 'Dr. Sequeira is great', createdAt: 99);
    final back = Comment.fromMap('c1', c.toMap());
    expect(back.id, 'c1');
    expect(back.body, 'Dr. Sequeira is great');
    expect(back.createdAt, 99);
  });

  test('timeAgo buckets', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(Post.timeAgo(0), 'just now');
    expect(Post.timeAgo(now - 30 * 1000), 'just now');
    expect(Post.timeAgo(now - 5 * 60 * 1000), '5m');
    expect(Post.timeAgo(now - 3 * 3600 * 1000), '3h');
    expect(Post.timeAgo(now - 2 * 86400 * 1000), '2d');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/post_test.dart`
Expected: FAIL — `Post`/`PostCategory`/`Comment` not found.

- [ ] **Step 3: Implement `lib/data/models/post.dart`**

```dart
import 'package:flutter/material.dart';

enum PostCategory {
  health('health', 'Health', '🩺', Color(0xFFF59E2E)),
  training('training', 'Training', '🎓', Color(0xFF6B8DE0)),
  lostFound('lostFound', 'Lost & Found', '🔎', Color(0xFFF2547B));

  final String storageKey, label, emoji;
  final Color color;
  const PostCategory(this.storageKey, this.label, this.emoji, this.color);

  static PostCategory fromStorage(String key) =>
      PostCategory.values.firstWhere((c) => c.storageKey == key, orElse: () => PostCategory.health);
}

class Post {
  final String id, authorId, authorName, title, body;
  final PostCategory category;
  final int replyCount, createdAt;

  const Post({
    this.id = '',
    required this.authorId, required this.authorName, required this.category,
    required this.title, required this.body, required this.createdAt,
    this.replyCount = 0,
  });

  Map<String, dynamic> toMap() => {
        'authorId': authorId,
        'authorName': authorName,
        'category': category.storageKey,
        'title': title,
        'body': body,
        'replyCount': replyCount,
        'createdAt': createdAt,
      };

  factory Post.fromMap(String id, Map<String, dynamic> m) => Post(
        id: id,
        authorId: (m['authorId'] ?? '') as String,
        authorName: (m['authorName'] ?? '') as String,
        category: PostCategory.fromStorage((m['category'] ?? 'health') as String),
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        replyCount: (m['replyCount'] ?? 0) as int,
        createdAt: (m['createdAt'] ?? 0) as int,
      );

  static String timeAgo(int millis) {
    if (millis <= 0) return 'just now';
    final secs = (DateTime.now().millisecondsSinceEpoch - millis) ~/ 1000;
    if (secs < 60) return 'just now';
    final mins = secs ~/ 60;
    if (mins < 60) return '${mins}m';
    final hours = mins ~/ 60;
    if (hours < 24) return '${hours}h';
    return '${hours ~/ 24}d';
  }
}

class Comment {
  final String id, authorId, authorName, body;
  final int createdAt;

  const Comment({
    this.id = '',
    required this.authorId, required this.authorName, required this.body, required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'authorId': authorId,
        'authorName': authorName,
        'body': body,
        'createdAt': createdAt,
      };

  factory Comment.fromMap(String id, Map<String, dynamic> m) => Comment(
        id: id,
        authorId: (m['authorId'] ?? '') as String,
        authorName: (m['authorName'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        createdAt: (m['createdAt'] ?? 0) as int,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/post_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/data/models/post.dart
git add lib/data/models/post.dart test/data/post_test.dart
git commit -m "feat: add Post + Comment + PostCategory models"
```

---

### Task 2: `PostRepository` interface + in-memory fake

**Files:**
- Create: `lib/data/repositories/post_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemoryPostRepository`)
- Test: `test/data/post_repository_test.dart`

**Interfaces:**
- Consumes: `Post`, `Comment` (Task 1).
- Produces: `abstract interface class PostRepository { Future<Post> createPost(Post post); Stream<List<Post>> watchPosts(); Future<void> addComment(String postId, Comment comment); Stream<List<Comment>> watchComments(String postId); }` and `InMemoryPostRepository`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/post_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import '../support/fakes.dart';

Post _post(int createdAt, String title) => Post(authorId: 'u1', authorName: 'Me',
    category: PostCategory.health, title: title, body: 'b', createdAt: createdAt);

void main() {
  test('createPost returns a post with an id and lists newest-first', () async {
    final repo = InMemoryPostRepository();
    expect(await repo.watchPosts().first, isEmpty);
    final older = await repo.createPost(_post(1000, 'Older'));
    final newer = await repo.createPost(_post(2000, 'Newer'));
    expect(older.id, isNotEmpty);
    final list = await repo.watchPosts().first;
    expect(list.map((p) => p.title).toList(), ['Newer', 'Older']); // desc by createdAt
    expect(newer.title, 'Newer');
  });

  test('addComment emits in watchComments (oldest-first) and increments replyCount', () async {
    final repo = InMemoryPostRepository();
    final post = await repo.createPost(_post(1000, 'T'));
    expect(await repo.watchComments(post.id).first, isEmpty);
    await repo.addComment(post.id, const Comment(authorId: 'a', authorName: 'A', body: 'first', createdAt: 10));
    await repo.addComment(post.id, const Comment(authorId: 'b', authorName: 'B', body: 'second', createdAt: 20));
    final comments = await repo.watchComments(post.id).first;
    expect(comments.map((c) => c.body).toList(), ['first', 'second']);
    final updated = (await repo.watchPosts().first).firstWhere((p) => p.id == post.id);
    expect(updated.replyCount, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/post_repository_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Create `lib/data/repositories/post_repository.dart`**

```dart
import '../models/post.dart';

abstract interface class PostRepository {
  Future<Post> createPost(Post post);
  Stream<List<Post>> watchPosts();
  Future<void> addComment(String postId, Comment comment);
  Stream<List<Comment>> watchComments(String postId);
}
```

- [ ] **Step 4: Add `InMemoryPostRepository` to `test/support/fakes.dart`**

Add these imports next to the existing ones: `import 'package:pet_aggregator_app/data/models/post.dart';` and `import 'package:pet_aggregator_app/data/repositories/post_repository.dart';`. Then append:

```dart
class InMemoryPostRepository implements PostRepository {
  final List<Post> _posts = [];
  final Map<String, List<Comment>> _comments = {};
  final _postsCtrl = StreamController<List<Post>>.broadcast();
  final Map<String, StreamController<List<Comment>>> _commentCtrls = {};
  int _seq = 0;

  InMemoryPostRepository([List<Post>? seed]) {
    if (seed != null) _posts.addAll(seed);
  }

  StreamController<List<Comment>> _cctrl(String postId) =>
      _commentCtrls.putIfAbsent(postId, () => StreamController<List<Comment>>.broadcast());

  List<Post> _sortedPosts() => [..._posts]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<Post> createPost(Post post) async {
    final created = Post.fromMap('post_${_seq++}', post.toMap());
    _posts.add(created);
    _postsCtrl.add(_sortedPosts());
    return created;
  }

  @override
  Stream<List<Post>> watchPosts() async* {
    yield _sortedPosts();
    yield* _postsCtrl.stream;
  }

  @override
  Future<void> addComment(String postId, Comment comment) async {
    final list = _comments.putIfAbsent(postId, () => []);
    list.add(Comment.fromMap('c_${_seq++}', comment.toMap()));
    _cctrl(postId).add([...list]);
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i >= 0) {
      _posts[i] = Post.fromMap(_posts[i].id, {..._posts[i].toMap(), 'replyCount': _posts[i].replyCount + 1});
      _postsCtrl.add(_sortedPosts());
    }
  }

  @override
  Stream<List<Comment>> watchComments(String postId) async* {
    List<Comment> sorted() =>
        [...(_comments[postId] ?? const <Comment>[])]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    yield sorted();
    yield* _cctrl(postId).stream.map((_) => sorted());
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/post_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze lib/data test/support/fakes.dart test/data/post_repository_test.dart
git add lib/data/repositories/post_repository.dart test/support/fakes.dart test/data/post_repository_test.dart
git commit -m "feat: add PostRepository interface + in-memory fake"
```

---

### Task 3: `FirestorePostRepository`

**Files:**
- Create: `lib/data/repositories/firebase/firestore_post_repository.dart`

**Interfaces:**
- Consumes: `PostRepository`, `Post`, `Comment` (Tasks 1–2).
- Produces: `FirestorePostRepository` (verified on the emulator in Task 11).

- [ ] **Step 1: Create `firestore_post_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/post.dart';
import '../post_repository.dart';

class FirestorePostRepository implements PostRepository {
  final FirebaseFirestore _db;
  FirestorePostRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('posts');

  @override
  Future<Post> createPost(Post post) async {
    final ref = await _col.add(post.toMap());
    return Post.fromMap(ref.id, post.toMap());
  }

  @override
  Stream<List<Post>> watchPosts() => _col
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Post.fromMap(d.id, d.data())).toList());

  @override
  Future<void> addComment(String postId, Comment comment) async {
    await _col.doc(postId).collection('comments').add(comment.toMap());
    await _col.doc(postId).update({'replyCount': FieldValue.increment(1)});
  }

  @override
  Stream<List<Comment>> watchComments(String postId) => _col
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Comment.fromMap(d.id, d.data())).toList());
}
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/repositories/firebase
git add lib/data/repositories/firebase/firestore_post_repository.dart
git commit -m "feat: add FirestorePostRepository"
```

---

### Task 4: Providers — `postRepositoryProvider`, `postsProvider`, `commentsProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/posts_provider_test.dart`

**Interfaces:**
- Produces: `postRepositoryProvider` → `Provider<PostRepository>`; `postsProvider` → `StreamProvider<List<Post>>`; `commentsProvider` → `StreamProvider.family<List<Comment>, String>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/posts_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('postsProvider streams created posts; commentsProvider streams a post\'s comments', () async {
    final repo = InMemoryPostRepository();
    final container = ProviderContainer(overrides: [postRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    container.listen(postsProvider, (_, _) {}, fireImmediately: true);
    final post = await repo.createPost(const Post(authorId: 'u1', authorName: 'Me',
        category: PostCategory.health, title: 'T', body: 'B', createdAt: 1000));
    await pumpEventQueue();
    expect((container.read(postsProvider).value ?? []).length, 1);

    container.listen(commentsProvider(post.id), (_, _) {}, fireImmediately: true);
    await repo.addComment(post.id, const Comment(authorId: 'u2', authorName: 'You', body: 'Hi', createdAt: 2000));
    await pumpEventQueue();
    expect((container.read(commentsProvider(post.id)).value ?? []).length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/posts_provider_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Extend `lib/data/repositories/providers.dart`**

Add these imports next to the existing ones: `import '../models/post.dart';`, `import 'post_repository.dart';`, `import 'firebase/firestore_post_repository.dart';`. Then append:

```dart
final postRepositoryProvider = Provider<PostRepository>((ref) => FirestorePostRepository());

final postsProvider = StreamProvider<List<Post>>((ref) => ref.watch(postRepositoryProvider).watchPosts());

final commentsProvider = StreamProvider.family<List<Comment>, String>(
    (ref, postId) => ref.watch(postRepositoryProvider).watchComments(postId));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/posts_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart test/data/posts_provider_test.dart
git commit -m "feat: add post providers (postRepositoryProvider, postsProvider, commentsProvider)"
```

---

### Task 5: `PgTextField` gains an optional `maxLines`

**Files:**
- Modify: `lib/core/widgets/pg_text_field.dart`
- Test: `test/core/widgets/pg_text_field_test.dart` (add a case)

**Interfaces:**
- Produces: `PgTextField(..., int maxLines = 1)` — passes `maxLines` to the inner `TextField`.

- [ ] **Step 1: Add a failing test case**

Append to `test/core/widgets/pg_text_field_test.dart` (inside its existing `main()`):
```dart
  testWidgets('maxLines passes through to the inner TextField', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpPg(tester, PgTextField(label: 'Details', controller: controller, maxLines: 6));
    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 6);
  });
```
(If `pumpPg`/`PgTextField` imports aren't already present at the top of the file, add `import 'package:pet_aggregator_app/core/widgets/pg_text_field.dart';`, `import 'package:flutter/material.dart';`, and `import '../../support/pump.dart';`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/pg_text_field_test.dart`
Expected: FAIL — `maxLines` isn't a parameter of `PgTextField` (compile error).

- [ ] **Step 3: Add the `maxLines` parameter**

In `lib/core/widgets/pg_text_field.dart`: add the field and constructor param, and pass it to the `TextField`.
```dart
  final int maxLines;
```
Add `this.maxLines = 1,` to the constructor (after `this.hint,`). In the `TextField(...)`, add `maxLines: maxLines,` (next to `keyboardType: keyboardType,`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/pg_text_field_test.dart`
Expected: PASS (existing cases + the new one).

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/core/widgets/pg_text_field.dart
git add lib/core/widgets/pg_text_field.dart test/core/widgets/pg_text_field_test.dart
git commit -m "feat: add optional maxLines to PgTextField (for multiline fields)"
```

---

### Task 6: `PostLiveScreen` + route constants + `/post-live` route

**Files:**
- Create: `lib/features/community/post_live_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `newPost`, `thread`, `postLive`)
- Modify: `lib/core/router/app_router.dart` (import + protect all three + add `/post-live` route)
- Test: `test/features/post_live_screen_test.dart`

**Interfaces:**
- Consumes: `Post`, `Routes`, theme.
- Produces: `PostLiveScreen({Post? post})` (`StatelessWidget`); `Routes.newPost == '/new-post'`, `Routes.thread == '/thread'`, `Routes.postLive == '/post-live'`.

Built first so later screens' navigation targets exist and are testable.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/post_live_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/features/community/post_live_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the post-live celebration + actions', (tester) async {
    const p = Post(id: 'p1', authorId: 'u1', authorName: 'Radhika', category: PostCategory.health,
        title: 'Vet in Bandra?', body: 'x', createdAt: 1000);
    await pumpPg(tester, const PostLiveScreen(post: p));
    expect(find.text('Your post is live! 🎉'), findsOneWidget);
    expect(find.text('View my post'), findsOneWidget);
    expect(find.text('Back to community'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/post_live_screen_test.dart`
Expected: FAIL — `PostLiveScreen` not found.

- [ ] **Step 3: Add the route constants**

In `lib/core/router/routes.dart`, add inside `class Routes` (after `hostAccepted`):
```dart
  static const newPost = '/new-post';
  static const thread = '/thread';
  static const postLive = '/post-live';
```

- [ ] **Step 4: Implement `lib/features/community/post_live_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/post.dart';

class PostLiveScreen extends StatelessWidget {
  final Post? post;
  const PostLiveScreen({super.key, this.post});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final p = post;
    if (p == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No post')));
    }
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 24),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 108, height: 108, alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0x1F6B8DE0), shape: BoxShape.circle),
              child: Container(
                width: 78, height: 78, alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF9DB6EC), Color(0xFF6B8DE0)]),
                  shape: BoxShape.circle),
                child: const Text('💬', style: TextStyle(fontSize: 34)))),
            const SizedBox(height: 20),
            Text('Your post is live! 🎉', textAlign: TextAlign.center,
              style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 10),
            Text('Pet parents near you can now see and reply.',
              textAlign: TextAlign.center,
              style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
            const Spacer(),
            SizedBox(width: double.infinity, child: GestureDetector(
              onTap: () => context.go(Routes.thread, extra: p),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('View my post', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => context.go(Routes.community),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Back to community', style: PgText.inter(14, FontWeight.w600, color: c.muted)))),
          ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the route + protect all three constants in `app_router.dart`**

Add `import '../../features/community/post_live_screen.dart';` and `import '../../data/models/post.dart';`; add `Routes.newPost, Routes.thread, Routes.postLive` to the `_protected` set; add this route (after the `Routes.hostAccepted` route):
```dart
      GoRoute(path: Routes.postLive, builder: (_, state) => PostLiveScreen(post: state.extra as Post?)),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/post_live_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/features/community/post_live_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/post_live_screen_test.dart
git commit -m "feat: add Post-live screen + community route constants"
```

---

### Task 7: `ThreadScreen` + `/thread` route

**Files:**
- Create: `lib/features/community/thread_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/thread` route)
- Test: `test/features/thread_screen_test.dart`

**Interfaces:**
- Consumes: `Post`, `Comment`, `commentsProvider`, `postRepositoryProvider`, `authRepositoryProvider`, `userRepositoryProvider`, `PgAppBar`, `PgImageSlot`.
- Produces: `ThreadScreen({Post? post})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/thread_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the OP + comments; sending a reply adds a comment', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
        email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    const post = Post(id: 'post1', authorId: 'op', authorName: 'Dev', category: PostCategory.health,
        title: 'Best vet in Bandra?', body: 'Bruno needs boosters.', createdAt: 1000);
    final repo = InMemoryPostRepository([post]);
    await repo.addComment('post1', const Comment(authorId: 'x', authorName: 'Pali',
        body: 'Dr. Sequeira is great', createdAt: 10));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      postRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.thread, extra: post);
    await tester.pumpAndSettle();

    expect(find.text('Best vet in Bandra?'), findsOneWidget);
    expect(find.textContaining('Dr. Sequeira'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Try Happy Tails clinic');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    final comments = await repo.watchComments('post1').first;
    expect(comments.length, 2);
    expect(comments.last.body, 'Try Happy Tails clinic');
    expect(comments.last.authorName, 'Radhika');
    expect(find.textContaining('Happy Tails'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/thread_screen_test.dart`
Expected: FAIL — `ThreadScreen` not found.

- [ ] **Step 3: Implement `lib/features/community/thread_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/post.dart';
import '../../data/repositories/providers.dart';

class ThreadScreen extends ConsumerStatefulWidget {
  final Post? post;
  const ThreadScreen({super.key, this.post});
  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send(Post post) async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    final profile = await ref.read(userRepositoryProvider).watchUser(me.uid).first;
    setState(() => _sending = true);
    await ref.read(postRepositoryProvider).addComment(post.id, Comment(
        authorId: me.uid, authorName: profile?.name ?? 'Someone', body: text,
        createdAt: DateTime.now().millisecondsSinceEpoch));
    _reply.clear();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final post = widget.post;
    if (post == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No post')));
    }
    final commentsAsync = ref.watch(commentsProvider(post.id));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: post.category.label, onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              children: [
                Text(post.title, style: PgText.poppins(19, FontWeight.w700, color: c.text)),
                const SizedBox(height: 11),
                Row(children: [
                  const PgImageSlot(size: 34, circle: true, emoji: '🙂'),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(post.authorName, style: PgText.inter(12.5, FontWeight.w700, color: c.text)),
                    Text(Post.timeAgo(post.createdAt), style: PgText.inter(11, FontWeight.w400, color: c.faint)),
                  ])),
                ]),
                const SizedBox(height: 12),
                Text(post.body, style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.6)),
                const SizedBox(height: 14),
                Divider(color: c.border),
                const SizedBox(height: 6),
                commentsAsync.when(
                  loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Could not load replies.',
                    style: PgText.inter(13.5, FontWeight.w500, color: c.muted)),
                  data: (comments) => comments.isEmpty
                      ? Padding(padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('No replies yet — be the first.',
                            style: PgText.inter(13.5, FontWeight.w400, color: c.muted)))
                      : Column(children: [
                          for (final cm in comments) ...[_CommentRow(comment: cm), const SizedBox(height: 12)],
                        ]),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: EdgeInsets.fromLTRB(16, 11, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(22)),
                child: TextField(
                  controller: _reply,
                  style: PgText.inter(13.5, FontWeight.w500, color: c.text),
                  cursorColor: c.brand,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: InputBorder.none,
                    hintText: 'Add a reply…',
                    hintStyle: PgText.inter(13.5, FontWeight.w400, color: c.faint)),
                ))),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : () => _send(post),
                child: Container(
                  width: 44, height: 44, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.brand, c.brand2]), shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 19))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final Comment comment;
  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PgImageSlot(size: 34, circle: true, emoji: '🙂'),
      const SizedBox(width: 11),
      Expanded(child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(15)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(comment.authorName, style: PgText.inter(12.5, FontWeight.w700, color: c.text)),
            const SizedBox(width: 7),
            Text(Post.timeAgo(comment.createdAt), style: PgText.inter(11, FontWeight.w400, color: c.faint)),
          ]),
          const SizedBox(height: 5),
          Text(comment.body, style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.5)),
        ]),
      )),
    ]);
  }
}
```

- [ ] **Step 4: Add the `/thread` route**

In `lib/core/router/app_router.dart`: add `import '../../features/community/thread_screen.dart';` and this route (next to `Routes.postLive`):
```dart
      GoRoute(path: Routes.thread, builder: (_, state) => ThreadScreen(post: state.extra as Post?)),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/thread_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/features/community/thread_screen.dart lib/core/router/app_router.dart test/features/thread_screen_test.dart
git commit -m "feat: add Thread screen (OP + live comments + reply composer) + /thread route"
```

---

### Task 8: `NewPostScreen` + `/new-post` route

**Files:**
- Create: `lib/features/community/new_post_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/new-post` route)
- Test: `test/features/new_post_screen_test.dart`

**Interfaces:**
- Consumes: `Post`, `PostCategory`, `postRepositoryProvider`, `authRepositoryProvider`, `userRepositoryProvider`, `PgAppBar`, `PgPrimaryButton`, `PgTextField` (with `maxLines`), `showComingSoon`, `Routes`.
- Produces: `NewPostScreen` (writes a post, navigates to `/post-live`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/new_post_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('posting writes a post and shows Post-live', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
        email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    final repo = InMemoryPostRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      postRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.newPost);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Best paw balm?');
    await tester.enterText(find.byType(TextField).at(1), 'Monsoon is rough.');
    await tester.tap(find.text('Post to community'));
    await tester.pumpAndSettle();

    final posts = await repo.watchPosts().first;
    expect(posts.single.title, 'Best paw balm?');
    expect(posts.single.authorName, 'Radhika');
    expect(find.text('Your post is live! 🎉'), findsOneWidget);
  });

  testWidgets('empty title is blocked', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final repo = InMemoryPostRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      postRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.newPost);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post to community'));
    await tester.pumpAndSettle();
    expect(await repo.watchPosts().first, isEmpty);
    expect(find.text('Add a title.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/new_post_screen_test.dart`
Expected: FAIL — `NewPostScreen` not found.

- [ ] **Step 3: Implement `lib/features/community/new_post_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/post.dart';
import '../../data/repositories/providers.dart';

class NewPostScreen extends ConsumerStatefulWidget {
  const NewPostScreen({super.key});
  @override
  ConsumerState<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends ConsumerState<NewPostScreen> {
  PostCategory _category = PostCategory.health;
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _posting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Add a title.');
      return;
    }
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    final profile = await ref.read(userRepositoryProvider).watchUser(me.uid).first;
    setState(() { _posting = true; _error = null; });
    final created = await ref.read(postRepositoryProvider).createPost(Post(
        authorId: me.uid, authorName: profile?.name ?? 'Someone', category: _category,
        title: title, body: _body.text.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch));
    if (mounted) context.go(Routes.postLive, extra: created);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'New post', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Text('CATEGORY', style: PgText.inter(12.5, FontWeight.w700, color: c.muted)),
                const SizedBox(height: 9),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final cat in PostCategory.values)
                    GestureDetector(
                      onTap: () => setState(() => _category = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                        decoration: BoxDecoration(
                          color: _category == cat ? c.brand : c.surface,
                          border: _category == cat ? null : Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(13)),
                        child: Text('${cat.emoji} ${cat.label}',
                          style: PgText.inter(13, FontWeight.w600,
                            color: _category == cat ? Colors.white : c.text)),
                      ),
                    ),
                ]),
                const SizedBox(height: 18),
                PgTextField(label: 'Title', controller: _title, hint: 'Ask the community…'),
                const SizedBox(height: 16),
                PgTextField(label: 'Details', controller: _body, maxLines: 6, hint: 'Share the details…'),
                const SizedBox(height: 16),
                Row(children: [
                  _decoChip('📷 Photo', c, () => showComingSoon(context, 'Photos')),
                  const SizedBox(width: 11),
                  _decoChip('📍 Location', c, () => showComingSoon(context, 'Location')),
                ]),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 18),
            child: PgPrimaryButton(label: _posting ? 'Posting…' : 'Post to community',
              onPressed: _posting ? () {} : _post),
          ),
        ]),
      ),
    );
  }

  Widget _decoChip(String label, PgColors c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(13)),
          child: Text(label, style: PgText.inter(13, FontWeight.w600, color: c.muted))),
      );
}
```

- [ ] **Step 4: Add the `/new-post` route**

In `lib/core/router/app_router.dart`: add `import '../../features/community/new_post_screen.dart';` and this route (next to `Routes.thread`):
```dart
      GoRoute(path: Routes.newPost, builder: (_, _) => const NewPostScreen()),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/new_post_screen_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/features/community/new_post_screen.dart lib/core/router/app_router.dart test/features/new_post_screen_test.dart
git commit -m "feat: add New-post screen + /new-post route"
```

---

### Task 9: `CommunityFeedScreen` + Community tab

**Files:**
- Create: `lib/features/community/community_feed_screen.dart`
- Modify: `lib/core/router/app_router.dart` (Community branch → `CommunityFeedScreen`)
- Test: `test/features/community_feed_screen_test.dart`

**Interfaces:**
- Consumes: `postsProvider`, `Post`, `PostCategory`, `Routes`, theme.
- Produces: `CommunityFeedScreen` (replaces `PlaceholderTab(title:'Community')`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/community_feed_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _p1 = Post(id: 'p1', authorId: 'a', authorName: 'Dev', category: PostCategory.health,
    title: 'Vet in Bandra?', body: 'x', createdAt: 2000, replyCount: 3);
const _p2 = Post(id: 'p2', authorId: 'b', authorName: 'Kim', category: PostCategory.training,
    title: 'Puppy classes?', body: 'y', createdAt: 1000);

void main() {
  testWidgets('lists live posts; category filter narrows the list', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      postRepositoryProvider.overrideWithValue(InMemoryPostRepository([_p1, _p2])),
    ], initialLocation: Routes.community);
    await tester.pumpAndSettle();

    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Vet in Bandra?'), findsOneWidget);
    expect(find.text('Puppy classes?'), findsOneWidget);

    await tester.tap(find.text('🎓 Training'));
    await tester.pumpAndSettle();
    expect(find.text('Vet in Bandra?'), findsNothing);
    expect(find.text('Puppy classes?'), findsOneWidget);
  });

  testWidgets('the + FAB opens New post', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      postRepositoryProvider.overrideWithValue(InMemoryPostRepository()),
    ], initialLocation: Routes.community);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New post'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/community_feed_screen_test.dart`
Expected: FAIL — `CommunityFeedScreen` not found.

- [ ] **Step 3: Implement `lib/features/community/community_feed_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/post.dart';
import '../../data/repositories/providers.dart';

class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});
  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  PostCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final postsAsync = ref.watch(postsProvider);

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
              decoration: BoxDecoration(color: c.peach,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Community', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.4)),
                const SizedBox(height: 3),
                Text('Mumbai pet parents', style: PgText.inter(12.5, FontWeight.w500, color: c.text)),
              ]),
            ),
            SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
                children: [
                  _catChip('All', _filter == null, () => setState(() => _filter = null), c),
                  for (final cat in PostCategory.values) ...[
                    const SizedBox(width: 9),
                    _catChip('${cat.emoji} ${cat.label}', _filter == cat,
                      () => setState(() => _filter = _filter == cat ? null : cat), c),
                  ],
                ],
              ),
            ),
            Expanded(
              child: postsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Could not load posts.',
                  style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
                data: (posts) {
                  final list = _filter == null ? posts : posts.where((p) => p.category == _filter).toList();
                  if (list.isEmpty) {
                    return Center(child: Text('No posts yet — start the conversation.',
                      style: PgText.inter(13.5, FontWeight.w400, color: c.muted)));
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 100),
                    children: [
                      for (final p in list) ...[_PostCard(post: p), const SizedBox(height: 12)],
                    ],
                  );
                },
              ),
            ),
          ]),
          Positioned(
            right: 22, bottom: 22,
            child: GestureDetector(
              onTap: () => context.push(Routes.newPost),
              child: Container(
                width: 58, height: 58, alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(19), boxShadow: c.shadow),
                child: const Icon(Icons.add, color: Colors.white, size: 30)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _catChip(String label, bool active, VoidCallback onTap, PgColors c) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.blue : c.surface,
            border: active ? null : Border.all(color: c.border),
            borderRadius: BorderRadius.circular(20)),
          child: Text(label,
            style: PgText.inter(12.5, active ? FontWeight.w700 : FontWeight.w600,
              color: active ? Colors.white : c.text)),
        ),
      );
}

class _PostCard extends StatelessWidget {
  final Post post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final cat = post.category;
    return GestureDetector(
      onTap: () => context.push(Routes.thread, extra: post),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
              child: Text(cat.label, style: PgText.inter(11, FontWeight.w700, color: cat.color))),
            const SizedBox(width: 8),
            Text(Post.timeAgo(post.createdAt), style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
          ]),
          const SizedBox(height: 9),
          Text(post.title, style: PgText.poppins(15, FontWeight.w600, color: c.text)),
          const SizedBox(height: 11),
          Row(children: [
            Text(post.authorName, style: PgText.inter(12, FontWeight.w400, color: c.muted)),
            const SizedBox(width: 14),
            Text('💬 ${post.replyCount}', style: PgText.inter(12, FontWeight.w600, color: c.muted)),
          ]),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Point the Community branch at `CommunityFeedScreen`**

In `lib/core/router/app_router.dart`: add `import '../../features/community/community_feed_screen.dart';` and change the Community branch route from `const PlaceholderTab(title: 'Community')` to `const CommunityFeedScreen()`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/community_feed_screen_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/community/community_feed_screen.dart lib/core/router/app_router.dart test/features/community_feed_screen_test.dart
git commit -m "feat: add Community feed screen (live posts, category filter, + FAB); wire Community tab"
```
Expected: whole suite green, analyze clean.

---

### Task 10: Firestore rules for `posts` + `comments`; deploy

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the `posts` block to `firestore.rules`**

Inside `match /databases/{database}/documents { ... }`, after the `homestayBookings` block:
```
    match /posts/{postId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.resource.data.authorId == request.auth.uid;
      allow update: if request.auth != null
                    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['replyCount']);
      allow delete: if false;
      match /comments/{commentId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null && request.resource.data.authorId == request.auth.uid;
        allow update, delete: if false;
      }
    }
```

- [ ] **Step 2: Deploy the rules**

Run: `firebase deploy --only firestore:rules --project pet-aggregator-app`
Expected: `Deploy complete!`

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "chore: add + deploy Firestore rules for posts + comments (author-create, replyCount-only update)"
```

---

### Task 11: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a `posts`/`comments` round-trip test)

- [ ] **Step 1: Append a posts/comments test to `integration_test/firebase_repos_test.dart`**

Add `import 'package:pet_aggregator_app/data/models/post.dart';` and `import 'package:pet_aggregator_app/data/repositories/firebase/firestore_post_repository.dart';` with the other imports, then add this `testWidgets` inside `main()`:
```dart
  testWidgets('posts + comments create/watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final repo = FirestorePostRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'post_$stamp@x.com', password: 'secret1');

    final created = await repo.createPost(Post(authorId: me.uid, authorName: 'Radhika',
        category: PostCategory.health, title: 'Vet in Bandra?', body: 'Boosters due.', createdAt: stamp));
    expect(created.id, isNotEmpty);
    final posts = await repo.watchPosts().firstWhere((l) => l.any((p) => p.id == created.id));
    expect(posts.firstWhere((p) => p.id == created.id).title, 'Vet in Bandra?');

    await repo.addComment(created.id, Comment(authorId: me.uid, authorName: 'Radhika',
        body: 'Any tips?', createdAt: stamp + 1));
    final comments = await repo.watchComments(created.id).firstWhere((l) => l.isNotEmpty);
    expect(comments.single.body, 'Any tips?');
    final afterReply = await repo.watchPosts().firstWhere((l) =>
        l.any((p) => p.id == created.id && p.replyCount == 1));
    expect(afterReply.firstWhere((p) => p.id == created.id).replyCount, 1);

    await auth.signOut();
  });
```

- [ ] **Step 2: Start emulators + run the integration test**

```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app   # one terminal
flutter test integration_test/firebase_repos_test.dart -d emulator-5554        # another
```
Expected: all integration tests pass. (If an emulator is already running on ports 8080/9099, reuse it — the Firestore emulator hot-reloads `firestore.rules`.) Stop the emulators after if you started them.

- [ ] **Step 3: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: unit/widget tests pass, analyze clean, APK builds.

- [ ] **Step 4: Manual walkthrough (real cloud)**

Run: `flutter run -d emulator-5554`. Sign in → Community tab shows the live feed → tap `＋` → pick a category, write a title + details → "Post to community" → "Your post is live!" → "View my post" → the thread → type a reply + send → the reply appears. Confirm a `posts/{id}` doc (with `replyCount: 1`) and a `posts/{id}/comments/{id}` doc exist in the console.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify posts/comments round-trip + replyCount increment against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- `posts` + `comments` collections; `Post`/`Comment`/`PostCategory` models → Tasks 1, 3. ✓
- `PostRepository` + fake + Firestore + providers (`postsProvider`, `commentsProvider`) → Tasks 2–4. ✓
- `PgTextField` `maxLines` enhancement → Task 5. ✓
- Community feed (live posts, category filter, `＋` FAB, empty state) → Task 9. ✓
- New post (category/title/multiline details, writes a post → post-live) → Task 8. ✓
- Thread (OP + live comments + reply composer that writes a comment) → Task 7. ✓
- Post-live (honest celebration, View/Back) → Task 6. ✓
- Rules (author-create, replyCount-only update, comments) + deploy → Task 10. ✓
- TDD fakes + emulator integration (round-trip + replyCount increment) → each task + Task 11. ✓
- Out-of-scope (upvotes, photos, edit/delete, notifications, moderation) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. Photo/Location buttons intentionally call `showComingSoon`. `timeAgo` tests are relative to `DateTime.now()` at test time, so they're deterministic.

**Type consistency:**
- `Post` fields (`id, authorId, authorName, category, title, body, replyCount, createdAt`) + `timeAgo` and `Comment` fields (`id, authorId, authorName, body, createdAt`) identical across Task 1 (model), Task 2 (fake/tests), Tasks 6–9 (screens), Task 11 (integration). ✓
- `PostRepository` methods (`createPost` returns `Post`, `watchPosts`, `addComment`, `watchComments`) match between interface (Task 2), fake (Task 2), Firestore (Task 3), and callers (Tasks 4, 7, 8, 9, 11). ✓
- Providers (`postRepositoryProvider`, `postsProvider`, `commentsProvider` family) defined Task 4, consumed Tasks 7 (`commentsProvider(post.id)`), 8, 9. ✓
- `Routes.newPost`/`thread`/`postLive` added Task 6, used Task 6 (`/post-live` route + `postLive`→thread/community nav), 7 (`/thread` route), 8 (`/new-post` route + `postLive` nav), 9 (`push newPost` FAB, `push thread` card). ✓
- `PostCategory` (`label`, `emoji`, `storageKey`, `color`, `fromStorage`) consistent across Tasks 1, 8, 9. ✓
- `PgTextField(maxLines:)` added Task 5, consumed Task 8. ✓
- `showComingSoon(context, label)` reused Task 8. ✓
