# Pawgo Slice 7b: Chat — 1:1 Messaging — Design

> **Status:** approved design (2026-07-16). Second of four sub-slices of Phase 7 (cross-cutting). Built on the live Firebase backend — **no mock data**. Real-time 1:1 messaging that wires the "Message X" stubs across the app.

## Goal

Stand up real-time 1:1 chat on live Firestore: a **Messages list** (reached from a new Home-header icon) of the user's conversations with an **unread dot**, and a **Conversation** screen with a live message thread + composer. The four "Message X" buttons (Pro profile, Booking-confirmed, Woof-match, Host-accepted) open/create a conversation with that person. Phone numbers are **masked at write time** so they never reach Firestore.

Screens match `design/Pawgo Prototype.dc.html` (Chats 849–867, Conversation 870–882).

## Design decisions (settled during brainstorming)

- **Inbox entry = a messages icon on the Home header** (Chat is not a bottom-nav tab). The four "Message X" buttons open a specific conversation directly.
- **Unread = a simple dot** via a per-user `lastRead` timestamp on the chat doc (no message counting).
- **Write-time phone masking** — digit runs of ≥7 digits are replaced with `••••` **before** the message is stored, so the number never persists. A "Pawgo hid a phone number" notice shows in threads where masking happened.
- **The `/chat` route carries the `Chat` object via `extra`** (both the list rows and the buttons have it after `openChat`); the conversation derives the other participant's name from it.
- **Deferred:** online/presence (no "● Online" label), voice calls (📞 → coming-soon), message search (the search bar is a non-interactive stub), attachments/photos.

## Scope

**In scope**
- `chats/{id}` collection + `chats/{id}/messages/{id}` subcollection; `Chat` + `Message` models + a `maskPhones` helper; `ChatRepository` interface + Firestore impl + in-memory fake; providers.
- **ChatListScreen** (Messages) and **ChatConversationScreen**.
- A Home-header messages icon → Messages list; rewire the 4 "Message X" buttons to `openChat` + navigate.
- Write-time phone masking + the safety notice.
- `firestore.rules` for `chats` + `messages` + deploy; routes.
- TDD with in-memory fakes; emulator integration test extended for `chats`/`messages`.

**Out of scope (later)**
- Presence/online status; voice/video calls (📞 is coming-soon).
- Message search, attachments/photos, reactions, typing indicators, delete/edit.
- Group chats (this is strictly 1:1).
- Push notifications for new messages (FCM — 7d/later).

## Firestore data model

```
chats/{chatId}                 // chatId = deterministic sorted "{uidA}_{uidB}"
  participants  : [uidA, uidB]                 // array-contains query for "my chats"
  names         : {uidA: nameA, uidB: nameB}   // denormalised display names
  lastMessage   : string
  lastMessageAt : int (millis)                 // ordering + unread comparison
  lastSenderId  : string
  lastRead      : {uidA: millis, uidB: millis} // per-user read timestamps
  createdAt     : int (millis)
chats/{chatId}/messages/{messageId}
  senderId  : string
  text      : string                           // phone-masked at write time
  createdAt : int (millis)
```

## Models (`lib/data/models/chat.dart`)

- `class Chat { final String id, lastMessage, lastSenderId; final List<String> participants; final Map<String,String> names; final Map<String,int> lastRead; final int lastMessageAt, createdAt; ... }` with:
  - `static String chatIdFor(String a, String b)` → the two uids sorted and joined by `_` (so opening a chat with someone always resolves to the same id).
  - `String otherUid(String myUid)` / `String otherName(String myUid)` (from `names`).
  - `bool hasUnread(String myUid)` = `lastMessage.isNotEmpty && lastSenderId != myUid && lastMessageAt > (lastRead[myUid] ?? 0)`.
  - `toMap`/`fromMap` (maps stored as-is).
- `class Message { final String id, senderId, text; final int createdAt; toMap/fromMap; }`.
- `String maskPhones(String text)` (top-level or static) — replaces any run that contains **≥7 digits** (allowing spaces, `-`, `(`, `)`, `.`, `+` between digits) with `••••`. Pure + unit-tested.

## Repository seam

`lib/data/repositories/chat_repository.dart`:
```dart
abstract interface class ChatRepository {
  Future<Chat> openChat({required String myUid, required String myName,
                         required String otherUid, required String otherName}); // get-or-create
  Stream<List<Chat>> watchMyChats(String uid);
  Stream<List<Message>> watchMessages(String chatId);
  Future<void> sendMessage({required String chatId, required String senderId, required String text});
  Future<void> markRead({required String chatId, required String uid});
}
```
- `FirestoreChatRepository` under `repositories/firebase/`:
  - `openChat` computes `chatIdFor(myUid, otherUid)`; if the doc doesn't exist, creates it (`participants`, `names`, empty `lastRead`, `createdAt`, empty `lastMessage`); returns the current `Chat` (identity fields are create-once, not clobbered on re-open).
  - `watchMyChats` = `where('participants', arrayContains: uid)` → sort by `lastMessageAt` desc **client-side** (single array-contains query, **no composite index**).
  - `watchMessages` = the `messages` subcollection `orderBy('createdAt')`.
  - `sendMessage` = `maskPhones(text)` → `messages.add({senderId, text: masked, createdAt: now})` then `chat.update({lastMessage: masked, lastMessageAt: now, lastSenderId: senderId})`.
  - `markRead` = `chat.update({'lastRead.$uid': now})`.
- `InMemoryChatRepository` fake in `test/support/fakes.dart`.
- Providers (`providers.dart`): `chatRepositoryProvider`; `myChatsProvider` → `StreamProvider<List<Chat>>` (empty when signed out); `chatMessagesProvider` → `StreamProvider.family<List<Message>, String>`.

## Screens (`features/chat/`)

1. **ChatListScreen** (`ConsumerWidget`, pushed from the Home header icon) — "Messages" header + back; a **non-interactive** search stub row; conversation rows from `myChatsProvider`: avatar placeholder, `chat.otherName(myUid)`, `chat.lastMessage`, `timeAgo(lastMessageAt)`, and an **unread dot** when `chat.hasUnread(myUid)`. Each row → `context.push(Routes.chat, extra: chat)`. Empty state ("No conversations yet — say hi from a match, booking, or host").
2. **ChatConversationScreen** (`ConsumerStatefulWidget`, `Chat` via `extra`) — header (back, avatar, `chat.otherName(myUid)`; a 📞 icon → `showComingSoon(context, 'Calls')`); a live thread from `chatMessagesProvider(chat.id)` (bubbles: `senderId == myUid` right/gradient, else left/surface); a centered **"🛡️ Pawgo hid a phone number to keep your chat safe"** notice shown when any thread message contains the `••••` marker; a bottom composer (`TextField` + send). On first build → `markRead(chat.id, myUid)`; **Send** → `sendMessage(chatId, myUid, text)` (masks), clears the field (the message appears live). Empty message is a no-op; the send handler guards `mounted` after the await.

## Wiring, routes, rules

- **Home header** (`home_screen.dart`): add a messages icon (top-right, before the avatar) → `context.push(Routes.chatList)`.
- **Rewire the 4 "Message X" buttons** to an async handler that reads my uid + name (`currentUserProfileProvider`), calls `openChat(...)`, then `context.push(Routes.chat, extra: chat)`:
  - `pro_profile_screen.dart` chat button → other = `pro.uid`/`pro.name`.
  - `booking_confirmed_screen.dart` "Message {pro}" → other = `booking.proId`/`booking.proName`.
  - `host_accepted_screen.dart` "Message {host}" → other = `booking.hostId`/`booking.hostName`.
  - `woof_match_screen.dart` "Send a message 💬" → other = `pet.ownerId` + owner name via `userByIdProvider(pet.ownerId)` (makes `WoofMatchScreen` a `ConsumerWidget`).
- **Routes:** `chatList = '/messages'`, `chat = '/chat'` (top-level **protected**); `/chat` reads a `Chat` from `state.extra`.
- **`firestore.rules`** (deploy via CLI):
```
match /chats/{chatId} {
  allow read: if request.auth != null && request.auth.uid in resource.data.participants;
  allow create: if request.auth != null && request.auth.uid in request.resource.data.participants;
  allow update: if request.auth != null && request.auth.uid in resource.data.participants;
  allow delete: if false;
  match /messages/{messageId} {
    allow read: if request.auth != null
                && request.auth.uid in get(/databases/$(database)/documents/chats/$(chatId)).data.participants;
    allow create: if request.auth != null
                && request.resource.data.senderId == request.auth.uid
                && request.auth.uid in get(/databases/$(database)/documents/chats/$(chatId)).data.participants;
    allow update, delete: if false;
  }
}
```
(A participant may update the chat doc — covers `sendMessage`'s last-message fields and `markRead`'s `lastRead`. Fine-grained field constraints are a later hardening item, consistent with the tracked rules follow-ups.)

## Testing

TDD with in-memory fakes via `pumpPgApp` overrides:
- `Chat`/`Message` serialization; `Chat.chatIdFor` deterministic (order-independent); `hasUnread` (true only when last message is newer than my `lastRead` and I'm not the sender); `maskPhones` (masks a 10-digit number and a spaced/dashed number; leaves short digit runs alone).
- `InMemoryChatRepository`: `openChat` is idempotent (same id, doesn't clobber an existing thread); `sendMessage` masks + updates `lastMessage`/`lastMessageAt`/`lastSenderId` + the message appears in `watchMessages`; `watchMyChats` returns my chats sorted newest-first; `markRead` flips `hasUnread` to false.
- `ChatListScreen`: renders my conversations + the unread dot; empty state; a row → Conversation.
- `ChatConversationScreen`: renders mine-vs-theirs bubbles; sending a message writes a **masked** message that appears; the safety notice shows for a masked message; `markRead` is called on open.
- Home messages icon → Messages list (router).
- A rewired button (e.g. Host-accepted "Message") opens a Conversation (router harness).
- Extend `integration_test/firebase_repos_test.dart`: `openChat` → `sendMessage` → `watchMessages` round-trip, `watchMyChats` reflects the chat, `markRead` updates, against the Firestore emulator with the new rules.

## Prerequisites

None new — Firestore + Email/Password are live. New rules deploy via the CLI.

## Deliverable / definition of done

From a match/booking/host, tapping "Message" opens a real conversation; messages send and appear live for both participants; the Messages list (from the Home icon) shows conversations with an unread dot that clears on open; a typed phone number is stored masked. `flutter analyze` clean, `flutter test` green (fakes), emulator integration test passes with the new rules, debug APK builds.
