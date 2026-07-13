# Pawgo Phase 6: Community — Posts & Comments — Design

> **Status:** approved design (2026-07-13). The Community forum pillar, in one slice, on the live Firebase backend — **no mock data**. Upvotes and photo uploads are deferred (not faked); reply counts are real.

## Goal

Stand up the Community forum on live Firestore: the Community tab becomes a live **feed** of posts (filterable by category); a signed-in user creates a post → an honest "Your post is live!" celebration → opens any post's **thread** (the original post + real comments) and adds a reply. The complete forum loop — post, browse, thread, reply.

Screens match `design/Pawgo Prototype.dc.html` (Community feed 773–800, New post 803–814, Thread 817–834, Post live 837–846).

## Design decisions (settled during brainstorming)

- **Posts + comments in one slice.** Replies are real (a `comments` subcollection, live). Reply counts are real (`FieldValue.increment`).
- **Upvotes deferred, not faked.** The prototype's ▲ upvote control is omitted this slice (honest counts would need a per-user vote mechanism + rules — a later enhancement). Cards/threads show the real **reply count**, not upvotes.
- **Author = the user's display name.** We have no @handles; the post denormalises `authorName` from the profile. The feed subtitle is a neutral "Mumbai pet parents" (no fabricated member count).
- **`createdAt` is a client `millisSinceEpoch` int**, not a server `Timestamp` — a deliberate deviation from the other collections. Post/Comment genuinely need to read the time back to render "time ago", and deserializing a Firestore `Timestamp` inside a Firebase-free model is awkward. Ordering (`orderBy('createdAt')`) and the `timeAgo` helper both work off the int.
- **`PgTextField` gains an optional `maxLines`** (default 1) so the post-details field can be multiline — a small, reusable widget enhancement.

## Scope

**In scope**
- `posts/{id}` collection + `posts/{id}/comments/{id}` subcollection; `Post` + `Comment` + `PostCategory` models; `PostRepository` interface + Firestore impl + in-memory fake; providers.
- **CommunityFeedScreen** — replaces the Community tab placeholder; category filter + live post cards + a `＋` FAB.
- **NewPostScreen** — category / title / multiline details; writes a post.
- **ThreadScreen** — the OP + live comments + an "Add a reply" composer that writes a comment.
- **PostLiveScreen** — honest "Your post is live!" celebration.
- `firestore.rules` for `posts` + `comments` + deploy; routes; the `PgTextField` `maxLines` enhancement.
- TDD with in-memory fakes; emulator integration test extended for `posts`/`comments`.

**Out of scope (later)**
- Real upvoting (per-user vote mechanism) — the ▲ control is omitted.
- Photo/Location on posts (Storage/geo) — the Photo/Location buttons are `showComingSoon`.
- Editing/deleting posts or comments; author-only content edits.
- Notifications on reply, moderation (Phase 12), @-mentions, search.

## Firestore data model

```
posts/{postId}
  authorId    : string    // == auth.uid
  authorName  : string    // denormalised display name
  category    : string    // "health" | "training" | "lostFound"
  title       : string
  body        : string
  replyCount  : int        // starts 0; bumped via FieldValue.increment(1) when a comment is added
  createdAt   : int        // client millisSinceEpoch

posts/{postId}/comments/{commentId}
  authorId    : string
  authorName  : string
  body        : string
  createdAt   : int        // client millisSinceEpoch
```

## Models (`lib/data/models/`)

- `enum PostCategory { health, training, lostFound }` (`post_category.dart` or in `post.dart`) with `storageKey`, `label` ("Health"/"Training"/"Lost & Found"), `emoji` ("🩺"/"🎓"/"🔎"), `Color color` (fixed: health `#F59E2E`, training `#6B8DE0`, lostFound `#F2547B`), and `static PostCategory fromStorage(String)` (default `health`).
- `class Post { final String id, authorId, authorName, title, body; final PostCategory category; final int replyCount, createdAt; const Post({this.id='', required ..., this.replyCount=0, required this.createdAt}); Map<String,dynamic> toMap(); factory Post.fromMap(String id, Map); static String timeAgo(int millis); }` — `toMap` omits `id`, **includes** `createdAt` (client-set) and `replyCount`; a new post is reconstructed with its id via `Post.fromMap(docId, post.toMap())`.
- `class Comment { final String id, authorId, authorName, body; final int createdAt; const Comment({this.id='', required ..., required this.createdAt}); Map<String,dynamic> toMap(); factory Comment.fromMap(String id, Map); }`.
- `timeAgo(int millis)` → "just now" (<60s), "{n}m", "{n}h", "{n}d" (const helper, no `intl`).

## Repository seam

`lib/data/repositories/post_repository.dart`:
```dart
abstract interface class PostRepository {
  Future<Post> createPost(Post post);                 // returns the post with its new doc id
  Stream<List<Post>> watchPosts();                    // orderBy createdAt desc
  Future<void> addComment(String postId, Comment comment); // add + increment replyCount
  Stream<List<Comment>> watchComments(String postId); // orderBy createdAt asc
}
```
- `FirestorePostRepository` under `repositories/firebase/`: `createPost` = `_col.add(post.toMap())` then `return Post.fromMap(ref.id, post.toMap())`; `addComment` = add to the `comments` subcollection then `_col.doc(postId).update({'replyCount': FieldValue.increment(1)})`.
- `InMemoryPostRepository` fake in `test/support/fakes.dart`.
- Providers (`providers.dart`): `postRepositoryProvider`; `postsProvider` → `StreamProvider<List<Post>>`; `commentsProvider` → `StreamProvider.family<List<Comment>, String>` (comments for a postId).

## Screens (`features/community/`)

1. **CommunityFeedScreen** (`ConsumerStatefulWidget`, replaces `PlaceholderTab(title:'Community')`) — peach header "Community / Mumbai pet parents"; a horizontal category-chip row (All + the 3 categories) toggling a local `PostCategory? _filter`; post cards from `postsProvider` filtered by the selected category. Each card: a category pill (`category.color` at ~12% alpha bg + colored text), `Post.timeAgo(createdAt)`, the title, and a footer "{authorName} · 💬 {replyCount}". Tap → `context.push(Routes.thread, extra: post)`. A `＋` FAB (bottom-right) → `context.push(Routes.newPost)`. Empty state ("No posts yet — start the conversation").
2. **NewPostScreen** (`ConsumerStatefulWidget`) — `PgAppBar('New post')`; a 3-way `PostCategory` chip selector (default `health`); a title `PgTextField`; a multiline details `PgTextField(maxLines: 6)`; decorative "📷 Photo" / "📍 Location" chips → `showComingSoon`. Sticky "Post to community" → validates title non-empty → `createPost(Post(authorId, authorName from profile, category, title, body, createdAt: now))` → `context.go(Routes.postLive, extra: createdPost)`. Loading state.
3. **ThreadScreen** (`ConsumerStatefulWidget`, `Post` via `extra`) — header showing `post.category.label` + back; an OP block (title, `authorName` + `timeAgo`, body, "💬 {n} replies"); a live comments list from `commentsProvider(post.id)` (each: avatar placeholder, `authorName`, `timeAgo`, body); a bottom composer ("Add a reply…" `TextField` + send button) → `addComment(post.id, Comment(authorId, authorName, body, createdAt: now))`, clears the field (the new comment appears live; user stays on the thread). Empty comments → "No replies yet".
4. **PostLiveScreen** (`StatelessWidget`, `Post` via `extra`) — a 💬 celebration "Your post is live! 🎉"; "Bandra pet parents can now see and reply."; "View my post" → `context.go(Routes.thread, extra: post)`; "Back to community" → `context.go(Routes.community)`.

## Routing & rules

- Community branch builder → `CommunityFeedScreen` (replaces `PlaceholderTab`).
- Add `Routes.newPost = '/new-post'`, `Routes.thread = '/thread'`, `Routes.postLive = '/post-live'` as top-level **protected** routes; `/thread` and `/post-live` read a `Post` from `state.extra`.
- `firestore.rules` (deploy via CLI):
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
The `update` rule lets any signed-in commenter bump `replyCount` but not touch any other field (so nobody can edit another user's post content).

## Testing

TDD with in-memory fakes via `pumpPgApp`/`pumpPg` overrides:
- `Post`/`Comment`/`PostCategory` serialization round-trip; `Post.timeAgo` boundaries (just now / m / h / d).
- `InMemoryPostRepository`: `createPost` returns a post with an id and it appears in `watchPosts` (newest first); `addComment` emits in `watchComments` (oldest first) **and** increments the post's `replyCount`.
- `CommunityFeedScreen`: renders live post cards; the category filter narrows the list; empty state.
- `NewPostScreen`: filling title + details + "Post to community" calls `createPost` with the right fields and navigates to Post-live; empty title is blocked.
- `ThreadScreen`: renders the OP + existing comments; typing a reply + send calls `addComment` and the comment appears.
- `PostLiveScreen`: renders the celebration; "View my post" → Thread; "Back to community" → Community.
- `CommunityFeedScreen` `＋` FAB navigates to New post (router harness).
- Extend `integration_test/firebase_repos_test.dart`: `createPost` → `watchPosts`, then `addComment` → `watchComments` + `replyCount` increment, round-trip against the Firestore emulator with the new rules.

## Prerequisites

None new — Firestore + Email/Password are live. New rules deploy via the CLI.

## Deliverable / definition of done

The Community tab shows a live feed; a signed-in user creates a post (persists in `posts`, celebration shown), opens a thread, and adds a reply (persists in `comments`, `replyCount` bumped) — all live from Firestore, owner-scoped by rules. `flutter analyze` clean, `flutter test` green (fakes), emulator integration test passes with the new rules, debug APK builds.
