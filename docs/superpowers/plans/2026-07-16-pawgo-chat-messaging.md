# Pawgo Slice 7b: Chat — 1:1 Messaging — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real-time 1:1 chat on live Firestore — a Messages list (from a Home-header icon) with an unread dot, a Conversation screen with a live thread + composer, and the four "Message X" buttons opening a conversation. Phone numbers are masked at write time.

**Architecture:** Feature-first Flutter on the existing repository seam. A `ChatRepository` (interface + Firestore impl + in-memory fake) backs `chats` + a `messages` subcollection; conversation ids are deterministic (sorted uids). Providers expose the chat list and per-chat messages (`autoDispose.family`). Two screens are thin `Consumer` composition; a shared `openChatWith` helper get-or-creates a chat and navigates. Leaf-first so navigation targets exist when tested.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`, `shared_preferences`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-16-pawgo-chat-messaging-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, and `integration_test/`.
- **Deterministic 1:1 chat id:** `Chat.chatIdFor(a,b)` = the two uids sorted, joined by `_`. `openChat` is get-or-create (identity fields create-once, not clobbered on re-open).
- **Write-time phone masking:** `sendMessage` runs `maskPhones(text)` (digit runs of ≥7 digits → `••••`) **before** storing — the number never persists.
- **Unread dot:** per-user `lastRead` map on the chat doc; `hasUnread(myUid)` = `lastMessage.isNotEmpty && lastSenderId != myUid && lastMessageAt > (lastRead[myUid] ?? 0)`. `markRead` on opening a conversation.
- **`/chat` carries a `Chat` via `extra`.** Deferred: presence/online, calls (📞 → coming-soon), search (stub), attachments.
- Timestamps are client `millisSinceEpoch` ints (consistent with `Post`).
- Riverpod 3.x: `AsyncValue.value` (not `valueOrNull`); `Override` from `package:flutter_riverpod/misc.dart` in tests; async handlers guard post-`await` state/context with `mounted`.
- `go_router` builders use `(_, _)`; routes reading `extra` use `(_, state)`. Screen tests use `pumpPgApp`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `Chat` + `Message` models + `maskPhones`

**Files:**
- Create: `lib/data/models/chat.dart`
- Test: `test/data/chat_test.dart`

**Interfaces:**
- Produces: `class Chat` (fields `id, participants, names, lastMessage, lastSenderId, lastMessageAt, lastRead, createdAt`; `static chatIdFor`, `otherUid`, `otherName`, `hasUnread`, `toMap`/`fromMap`); `class Message` (`id, senderId, text, createdAt`); `String maskPhones(String)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/chat_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/chat.dart';

void main() {
  test('chatIdFor is deterministic regardless of order', () {
    expect(Chat.chatIdFor('bbb', 'aaa'), 'aaa_bbb');
    expect(Chat.chatIdFor('aaa', 'bbb'), 'aaa_bbb');
  });

  test('otherName + hasUnread', () {
    const chat = Chat(id: 'aaa_bbb', participants: ['aaa', 'bbb'],
        names: {'aaa': 'Me', 'bbb': 'Aarav'}, lastMessage: 'hi', lastSenderId: 'bbb',
        lastMessageAt: 100, lastRead: {'aaa': 50});
    expect(chat.otherName('aaa'), 'Aarav');
    expect(chat.hasUnread('aaa'), isTrue);          // their msg newer than my lastRead
    expect(chat.hasUnread('bbb'), isFalse);         // I'm the sender
    const read = Chat(id: 'aaa_bbb', participants: ['aaa', 'bbb'], names: {},
        lastMessage: 'hi', lastSenderId: 'bbb', lastMessageAt: 100, lastRead: {'aaa': 100});
    expect(read.hasUnread('aaa'), isFalse);         // caught up
  });

  test('Chat/Message round-trip', () {
    const chat = Chat(id: 'c1', participants: ['a', 'b'], names: {'a': 'A', 'b': 'B'},
        lastMessage: 'yo', lastSenderId: 'a', lastMessageAt: 7, lastRead: {'a': 7}, createdAt: 3);
    final back = Chat.fromMap('c1', chat.toMap());
    expect(back.participants, ['a', 'b']);
    expect(back.names['b'], 'B');
    expect(back.lastRead['a'], 7);
    final m = Message.fromMap('m1', const Message(senderId: 'a', text: 'hey', createdAt: 9).toMap());
    expect(m.id, 'm1');
    expect(m.text, 'hey');
  });

  test('maskPhones masks 7+ digit runs, leaves short ones', () {
    expect(maskPhones('call me at 9876543210'), 'call me at ••••');
    expect(maskPhones('num +91 98765 43210 ok'), 'num •••• ok');
    expect(maskPhones('I have 3 dogs in room 204'), 'I have 3 dogs in room 204');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/chat_test.dart`
Expected: FAIL — `Chat`/`Message`/`maskPhones` not found.

- [ ] **Step 3: Implement `lib/data/models/chat.dart`**

```dart
class Chat {
  final String id, lastMessage, lastSenderId;
  final List<String> participants;
  final Map<String, String> names;
  final Map<String, int> lastRead;
  final int lastMessageAt, createdAt;

  const Chat({
    this.id = '',
    required this.participants, required this.names,
    this.lastMessage = '', this.lastSenderId = '',
    this.lastMessageAt = 0, this.createdAt = 0,
    this.lastRead = const {},
  });

  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  String otherUid(String myUid) => participants.firstWhere((p) => p != myUid, orElse: () => '');
  String otherName(String myUid) => names[otherUid(myUid)] ?? 'Someone';

  bool hasUnread(String myUid) =>
      lastMessage.isNotEmpty && lastSenderId != myUid && lastMessageAt > (lastRead[myUid] ?? 0);

  Map<String, dynamic> toMap() => {
        'participants': participants,
        'names': names,
        'lastMessage': lastMessage,
        'lastSenderId': lastSenderId,
        'lastMessageAt': lastMessageAt,
        'lastRead': lastRead,
        'createdAt': createdAt,
      };

  factory Chat.fromMap(String id, Map<String, dynamic> m) => Chat(
        id: id,
        participants: ((m['participants'] ?? const []) as List).map((e) => e as String).toList(),
        names: ((m['names'] ?? const {}) as Map).map((k, v) => MapEntry(k as String, v as String)),
        lastMessage: (m['lastMessage'] ?? '') as String,
        lastSenderId: (m['lastSenderId'] ?? '') as String,
        lastMessageAt: (m['lastMessageAt'] ?? 0) as int,
        lastRead: ((m['lastRead'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
        createdAt: (m['createdAt'] ?? 0) as int,
      );
}

class Message {
  final String id, senderId, text;
  final int createdAt;
  const Message({this.id = '', required this.senderId, required this.text, required this.createdAt});

  Map<String, dynamic> toMap() => {'senderId': senderId, 'text': text, 'createdAt': createdAt};

  factory Message.fromMap(String id, Map<String, dynamic> m) => Message(
        id: id,
        senderId: (m['senderId'] ?? '') as String,
        text: (m['text'] ?? '') as String,
        createdAt: (m['createdAt'] ?? 0) as int,
      );
}

final RegExp _phoneRe = RegExp(r'\+?\d[\d\s().-]{5,}\d');

/// Replaces any run containing >= 7 digits (allowing spaces/dashes/()/./+) with ••••.
String maskPhones(String text) => text.replaceAllMapped(_phoneRe, (m) {
      final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
      return digits.length >= 7 ? '••••' : m[0]!;
    });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/chat_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/data/models/chat.dart
git add lib/data/models/chat.dart test/data/chat_test.dart
git commit -m "feat: add Chat + Message models + maskPhones helper"
```

---

### Task 2: `ChatRepository` interface + in-memory fake

**Files:**
- Create: `lib/data/repositories/chat_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemoryChatRepository`)
- Test: `test/data/chat_repository_test.dart`

**Interfaces:**
- Consumes: `Chat`, `Message`, `maskPhones` (Task 1).
- Produces: `abstract interface class ChatRepository { Future<Chat> openChat({required String myUid, required String myName, required String otherUid, required String otherName}); Stream<List<Chat>> watchMyChats(String uid); Stream<List<Message>> watchMessages(String chatId); Future<void> sendMessage({required String chatId, required String senderId, required String text}); Future<void> markRead({required String chatId, required String uid}); }` and `InMemoryChatRepository`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/chat_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/chat.dart';
import '../support/fakes.dart';

void main() {
  test('openChat is idempotent; sendMessage masks + updates; markRead clears unread', () async {
    final repo = InMemoryChatRepository();
    final chat = await repo.openChat(myUid: 'me', myName: 'Me', otherUid: 'aarav', otherName: 'Aarav');
    expect(chat.id, Chat.chatIdFor('me', 'aarav'));
    // Re-open returns the same chat, no duplicate.
    final again = await repo.openChat(myUid: 'aarav', myName: 'Aarav', otherUid: 'me', otherName: 'Me');
    expect(again.id, chat.id);
    expect((await repo.watchMyChats('me').first).length, 1);

    // Send a message with a phone number -> masked + surfaces in the thread + updates last-message.
    await repo.sendMessage(chatId: chat.id, senderId: 'aarav', text: 'call me 9876543210');
    final msgs = await repo.watchMessages(chat.id).first;
    expect(msgs.single.text, 'call me ••••');
    final mine = (await repo.watchMyChats('me').first).single;
    expect(mine.lastMessage, 'call me ••••');
    expect(mine.hasUnread('me'), isTrue); // their message, I haven't read

    await repo.markRead(chatId: chat.id, uid: 'me');
    expect((await repo.watchMyChats('me').first).single.hasUnread('me'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/chat_repository_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Create `lib/data/repositories/chat_repository.dart`**

```dart
import '../models/chat.dart';

abstract interface class ChatRepository {
  Future<Chat> openChat({
    required String myUid, required String myName,
    required String otherUid, required String otherName,
  });
  Stream<List<Chat>> watchMyChats(String uid);
  Stream<List<Message>> watchMessages(String chatId);
  Future<void> sendMessage({required String chatId, required String senderId, required String text});
  Future<void> markRead({required String chatId, required String uid});
}
```

- [ ] **Step 4: Add `InMemoryChatRepository` to `test/support/fakes.dart`**

Add these imports next to the existing ones: `import 'package:pet_aggregator_app/data/models/chat.dart';` and `import 'package:pet_aggregator_app/data/repositories/chat_repository.dart';`. Then append:

```dart
class InMemoryChatRepository implements ChatRepository {
  final Map<String, Chat> _chats = {};
  final Map<String, List<Message>> _messages = {};
  final _chatsCtrl = StreamController<List<Chat>>.broadcast();
  final Map<String, StreamController<List<Message>>> _msgCtrls = {};
  int _seq = 0;

  StreamController<List<Message>> _mctrl(String chatId) =>
      _msgCtrls.putIfAbsent(chatId, () => StreamController<List<Message>>.broadcast());

  @override
  Future<Chat> openChat({required String myUid, required String myName,
      required String otherUid, required String otherName}) async {
    final id = Chat.chatIdFor(myUid, otherUid);
    final existing = _chats[id];
    if (existing != null) return existing;
    final chat = Chat(id: id, participants: [myUid, otherUid]..sort(),
        names: {myUid: myName, otherUid: otherName},
        createdAt: DateTime.now().millisecondsSinceEpoch);
    _chats[id] = chat;
    _chatsCtrl.add(_chats.values.toList());
    return chat;
  }

  @override
  Stream<List<Chat>> watchMyChats(String uid) async* {
    List<Chat> mine() => _chats.values.where((c) => c.participants.contains(uid)).toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    yield mine();
    yield* _chatsCtrl.stream.map((_) => mine());
  }

  @override
  Stream<List<Message>> watchMessages(String chatId) async* {
    List<Message> msgs() =>
        [...(_messages[chatId] ?? const <Message>[])]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    yield msgs();
    yield* _mctrl(chatId).stream.map((_) => msgs());
  }

  @override
  Future<void> sendMessage({required String chatId, required String senderId, required String text}) async {
    final masked = maskPhones(text);
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = _messages.putIfAbsent(chatId, () => []);
    list.add(Message(id: 'm_${_seq++}', senderId: senderId, text: masked, createdAt: now));
    _mctrl(chatId).add([...list]);
    final c = _chats[chatId];
    if (c != null) {
      _chats[chatId] = Chat.fromMap(chatId,
          {...c.toMap(), 'lastMessage': masked, 'lastMessageAt': now, 'lastSenderId': senderId});
      _chatsCtrl.add(_chats.values.toList());
    }
  }

  @override
  Future<void> markRead({required String chatId, required String uid}) async {
    final c = _chats[chatId];
    if (c != null) {
      final lr = {...c.lastRead, uid: DateTime.now().millisecondsSinceEpoch};
      _chats[chatId] = Chat.fromMap(chatId, {...c.toMap(), 'lastRead': lr});
      _chatsCtrl.add(_chats.values.toList());
    }
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/chat_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze lib/data test/support/fakes.dart test/data/chat_repository_test.dart
git add lib/data/repositories/chat_repository.dart test/support/fakes.dart test/data/chat_repository_test.dart
git commit -m "feat: add ChatRepository interface + in-memory fake"
```

---

### Task 3: `FirestoreChatRepository`

**Files:**
- Create: `lib/data/repositories/firebase/firestore_chat_repository.dart`

**Interfaces:**
- Consumes: `ChatRepository`, `Chat`, `Message`, `maskPhones` (Tasks 1–2).
- Produces: `FirestoreChatRepository` (verified on the emulator in Task 11).

- [ ] **Step 1: Create `firestore_chat_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/chat.dart';
import '../chat_repository.dart';

class FirestoreChatRepository implements ChatRepository {
  final FirebaseFirestore _db;
  FirestoreChatRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('chats');

  @override
  Future<Chat> openChat({required String myUid, required String myName,
      required String otherUid, required String otherName}) async {
    final id = Chat.chatIdFor(myUid, otherUid);
    final doc = _col.doc(id);
    final snap = await doc.get();
    if (!snap.exists) {
      await doc.set(Chat(id: id, participants: [myUid, otherUid]..sort(),
          names: {myUid: myName, otherUid: otherName},
          createdAt: DateTime.now().millisecondsSinceEpoch).toMap());
    }
    final fresh = await doc.get();
    return Chat.fromMap(id, fresh.data()!);
  }

  @override
  Stream<List<Chat>> watchMyChats(String uid) => _col
      .where('participants', arrayContains: uid)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Chat.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt)));

  @override
  Stream<List<Message>> watchMessages(String chatId) => _col
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Message.fromMap(d.id, d.data())).toList());

  @override
  Future<void> sendMessage({required String chatId, required String senderId, required String text}) async {
    final masked = maskPhones(text);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _col.doc(chatId).collection('messages')
        .add(Message(senderId: senderId, text: masked, createdAt: now).toMap());
    await _col.doc(chatId).update({'lastMessage': masked, 'lastMessageAt': now, 'lastSenderId': senderId});
  }

  @override
  Future<void> markRead({required String chatId, required String uid}) =>
      _col.doc(chatId).update({'lastRead.$uid': DateTime.now().millisecondsSinceEpoch});
}
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/repositories/firebase
git add lib/data/repositories/firebase/firestore_chat_repository.dart
git commit -m "feat: add FirestoreChatRepository"
```

---

### Task 4: Providers — `chatRepositoryProvider`, `myChatsProvider`, `chatMessagesProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/chat_providers_test.dart`

**Interfaces:**
- Produces: `chatRepositoryProvider` → `Provider<ChatRepository>`; `myChatsProvider` → `StreamProvider<List<Chat>>`; `chatMessagesProvider` → `StreamProvider.autoDispose.family<List<Message>, String>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/chat_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('myChatsProvider streams my chats; chatMessagesProvider streams a thread', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final chats = InMemoryChatRepository();
    final chat = await chats.openChat(myUid: uid, myName: 'Me', otherUid: 'aarav', otherName: 'Aarav');

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      chatRepositoryProvider.overrideWithValue(chats),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(myChatsProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    expect((container.read(myChatsProvider).value ?? []).length, 1);

    container.listen(chatMessagesProvider(chat.id), (_, _) {}, fireImmediately: true);
    await chats.sendMessage(chatId: chat.id, senderId: 'aarav', text: 'hi');
    await pumpEventQueue();
    expect((container.read(chatMessagesProvider(chat.id)).value ?? []).length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/chat_providers_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Append to `lib/data/repositories/providers.dart`**

Add imports: `import '../models/chat.dart';`, `import 'chat_repository.dart';`, `import 'firebase/firestore_chat_repository.dart';`. Then append:

```dart
final chatRepositoryProvider = Provider<ChatRepository>((ref) => FirestoreChatRepository());

final myChatsProvider = StreamProvider<List<Chat>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(chatRepositoryProvider).watchMyChats(user.uid);
});

final chatMessagesProvider = StreamProvider.autoDispose.family<List<Message>, String>(
    (ref, chatId) => ref.watch(chatRepositoryProvider).watchMessages(chatId));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/chat_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart test/data/chat_providers_test.dart
git commit -m "feat: add chat providers (chatRepositoryProvider, myChatsProvider, chatMessagesProvider)"
```

---

### Task 5: `ChatConversationScreen` + route constants + `/chat` route

**Files:**
- Create: `lib/features/chat/chat_conversation_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `chatList`, `chat`)
- Modify: `lib/core/router/app_router.dart` (import + protect both + add `/chat` route)
- Test: `test/features/chat_conversation_screen_test.dart`

**Interfaces:**
- Consumes: `Chat`, `Message`, `chatMessagesProvider`, `chatRepositoryProvider`, `authRepositoryProvider`, `authStateProvider`, `PgImageSlot`, `showComingSoon`, `Routes`.
- Produces: `ChatConversationScreen({Chat? chat})`; `Routes.chatList == '/messages'`, `Routes.chat == '/chat'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat_conversation_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/chat.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the thread; sending masks + appears; markRead on open', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final chats = InMemoryChatRepository();
    final chat = await chats.openChat(myUid: uid, myName: 'Me', otherUid: 'aarav', otherName: 'Aarav Sharma');
    await chats.sendMessage(chatId: chat.id, senderId: 'aarav', text: 'Hi Radhika! 🐾');
    // Re-fetch the chat so extra carries the up-to-date names/id.
    final live = (await chats.watchMyChats(uid).first).single;

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      chatRepositoryProvider.overrideWithValue(chats),
    ], initialLocation: Routes.chat, extra: live);
    await tester.pumpAndSettle();

    expect(find.text('Aarav Sharma'), findsOneWidget);         // header
    expect(find.textContaining('Hi Radhika'), findsOneWidget); // their bubble
    expect(live.hasUnread(uid), isFalse);                      // markRead ran on open (fake updated in place)

    await tester.enterText(find.byType(TextField), 'my number is 9876543210');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    final msgs = await chats.watchMessages(chat.id).first;
    expect(msgs.last.text, 'my number is ••••');               // write-time masked
    expect(find.textContaining('••••'), findsWidgets);
    expect(find.textContaining('hid a phone number'), findsOneWidget); // safety notice
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat_conversation_screen_test.dart`
Expected: FAIL — `ChatConversationScreen` / routes not found.

- [ ] **Step 3: Add the route constants**

In `lib/core/router/routes.dart`, add inside `class Routes` (after `petProfile`):
```dart
  static const chatList = '/messages';
  static const chat = '/chat';
```

- [ ] **Step 4: Implement `lib/features/chat/chat_conversation_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/chat.dart';
import '../../data/repositories/providers.dart';

class ChatConversationScreen extends ConsumerStatefulWidget {
  final Chat? chat;
  const ChatConversationScreen({super.key, this.chat});
  @override
  ConsumerState<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends ConsumerState<ChatConversationScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final chat = widget.chat;
    final me = ref.read(authRepositoryProvider).currentUser;
    if (chat != null && me != null) {
      ref.read(chatRepositoryProvider).markRead(chatId: chat.id, uid: me.uid);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send(Chat chat, String myUid) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await ref.read(chatRepositoryProvider).sendMessage(chatId: chat.id, senderId: myUid, text: text);
    if (!mounted) return;
    _input.clear();
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final chat = widget.chat;
    if (chat == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No conversation')));
    }
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
    final otherName = chat.otherName(myUid);
    final messagesAsync = ref.watch(chatMessagesProvider(chat.id));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          // header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 16, 10),
            decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: SizedBox(width: 40, height: 40,
                  child: Icon(Icons.chevron_left, color: c.text))),
              const PgImageSlot(size: 42, circle: true, emoji: '🙂'),
              const SizedBox(width: 11),
              Expanded(child: Text(otherName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(15, FontWeight.w700, color: c.text))),
              GestureDetector(
                onTap: () => showComingSoon(context, 'Calls'),
                child: Icon(Icons.call_outlined, color: c.muted, size: 21)),
            ]),
          ),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load messages.',
                style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
              data: (messages) {
                final masked = messages.any((m) => m.text.contains('••••'));
                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  children: [
                    for (final m in messages) _Bubble(mine: m.senderId == myUid, text: m.text),
                    if (masked) ...[
                      const SizedBox(height: 8),
                      _SafetyNotice(c: c),
                    ],
                  ],
                );
              },
            ),
          ),
          // composer
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: EdgeInsets.fromLTRB(16, 11, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(22)),
                child: TextField(
                  controller: _input,
                  style: PgText.inter(13.5, FontWeight.w500, color: c.text),
                  cursorColor: c.brand,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: InputBorder.none,
                    hintText: 'Message…',
                    hintStyle: PgText.inter(13.5, FontWeight.w400, color: c.faint)),
                ))),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : () => _send(chat, myUid),
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

class _Bubble extends StatelessWidget {
  final bool mine;
  final String text;
  const _Bubble({required this.mine, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      margin: const EdgeInsets.only(bottom: 10),
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: mine ? LinearGradient(colors: [c.brand, c.brand2]) : null,
          color: mine ? null : c.surface,
          border: mine ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16))),
        child: Text(text, style: PgText.inter(14, FontWeight.w400, color: mine ? Colors.white : c.text, height: 1.35)),
      ),
    );
  }
}

class _SafetyNotice extends StatelessWidget {
  final PgColors c;
  const _SafetyNotice({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(child: Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
      child: Text('🛡️ Pawgo hid a phone number to keep your chat safe. Share contact details only after you meet.',
        textAlign: TextAlign.center, style: PgText.inter(12, FontWeight.w500, color: c.brandDeep, height: 1.4)),
    ));
  }
}
```
Add the missing import for `Routes` at the top: `import '../../core/router/routes.dart';`.

- [ ] **Step 5: Wire the route + protect both constants in `app_router.dart`**

Add `import '../../features/chat/chat_conversation_screen.dart';` and `import '../../data/models/chat.dart';`; add `Routes.chatList, Routes.chat` to the `_protected` set; add this route (after the `Routes.thread` route):
```dart
      GoRoute(path: Routes.chat, builder: (_, state) => ChatConversationScreen(chat: state.extra as Chat?)),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/chat_conversation_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/features/chat/chat_conversation_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/chat_conversation_screen_test.dart
git commit -m "feat: add Chat conversation screen (live thread, composer, safety notice) + /chat route"
```

---

### Task 6: `ChatListScreen` + `/messages` route

**Files:**
- Create: `lib/features/chat/chat_list_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/messages` route)
- Test: `test/features/chat_list_screen_test.dart`

**Interfaces:**
- Consumes: `myChatsProvider`, `Chat`, `Post.timeAgo` (reused time-ago helper), `PgImageSlot`, `PgAppBar`, `Routes`, `authRepositoryProvider`.
- Produces: `ChatListScreen`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat_list_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('lists my conversations with an unread dot; tap opens the thread', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final chats = InMemoryChatRepository();
    final chat = await chats.openChat(myUid: uid, myName: 'Me', otherUid: 'aarav', otherName: 'Aarav Sharma');
    await chats.sendMessage(chatId: chat.id, senderId: 'aarav', text: 'See you at 5!');

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      chatRepositoryProvider.overrideWithValue(chats),
    ], initialLocation: Routes.chatList);
    await tester.pumpAndSettle();

    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.textContaining('See you at 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget); // unread (their message)

    await tester.tap(find.text('Aarav Sharma'));
    await tester.pumpAndSettle();
    expect(find.text('Message…'), findsOneWidget); // conversation composer hint
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat_list_screen_test.dart`
Expected: FAIL — `ChatListScreen` not found.

- [ ] **Step 3: Implement `lib/features/chat/chat_list_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/chat.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/repositories/providers.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
    final chatsAsync = ref.watch(myChatsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PgAppBar(title: 'Messages', onBack: () => context.canPop() ? context.pop() : context.go(Routes.home)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 2, 22, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.search, size: 17, color: c.faint),
                const SizedBox(width: 10),
                Text('Search conversations', style: PgText.inter(13.5, FontWeight.w400, color: c.faint)),
              ]),
            ),
          ),
          Expanded(child: chatsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load messages.',
              style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
            data: (chats) => chats.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Text('No conversations yet — say hi from a match, booking, or host.',
                      textAlign: TextAlign.center, style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    children: [for (final chat in chats) _ChatRow(chat: chat, myUid: myUid)],
                  ),
          )),
        ]),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final Chat chat;
  final String myUid;
  const _ChatRow({required this.chat, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final unread = chat.hasUnread(myUid);
    return GestureDetector(
      onTap: () => context.push(Routes.chat, extra: chat),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(children: [
          const PgImageSlot(size: 54, circle: true, emoji: '🙂'),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(chat.otherName(myUid), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(14.5, FontWeight.w700, color: c.text))),
              if (chat.lastMessageAt > 0)
                Text(Post.timeAgo(chat.lastMessageAt), style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(child: Text(chat.lastMessage.isEmpty ? 'Say hi 👋' : chat.lastMessage,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.inter(13, FontWeight.w400, color: unread ? c.text : c.muted))),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(key: const ValueKey('unread-dot'), width: 9, height: 9,
                  decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle)),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the `/messages` route**

In `lib/core/router/app_router.dart`: add `import '../../features/chat/chat_list_screen.dart';` and this route (next to `Routes.chat`):
```dart
      GoRoute(path: Routes.chatList, builder: (_, _) => const ChatListScreen()),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/chat_list_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/features/chat/chat_list_screen.dart lib/core/router/app_router.dart test/features/chat_list_screen_test.dart
git commit -m "feat: add Chat list screen (conversations + unread dot) + /messages route"
```

---

### Task 7: Home header messages icon

**Files:**
- Modify: `lib/features/home/home_screen.dart` (add a messages icon to the header)
- Test: `test/features/home_messages_icon_test.dart`

**Interfaces:**
- Consumes: `Routes.chatList`.
- Produces: a header icon → `context.push(Routes.chatList)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/home_messages_icon_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('the Home messages icon opens the Messages list', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Messages'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/home_messages_icon_test.dart`
Expected: FAIL — no such icon / no navigation.

- [ ] **Step 3: Add the messages icon to the Home header**

In `lib/features/home/home_screen.dart`, the header row ends with `const PgImageSlot(size: 46, circle: true),`. Insert a messages icon before it:
```dart
              GestureDetector(
                onTap: () => context.push(Routes.chatList),
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.chat_bubble_outline_rounded, size: 20, color: c.text)),
              ),
              const PgImageSlot(size: 46, circle: true),
```
(`Routes` and `context.push` are already available in `home_screen.dart`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/home_messages_icon_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/features/home/home_screen.dart test/features/home_messages_icon_test.dart
git commit -m "feat: add a messages icon to the Home header"
```

---

### Task 8: `openChatWith` helper + rewire Booking-confirmed & Host-accepted

**Files:**
- Create: `lib/features/chat/chat_actions.dart`
- Modify: `lib/features/services/booking_confirmed_screen.dart` (→ `ConsumerWidget`, wire "Message")
- Modify: `lib/features/homestay/host_accepted_screen.dart` (→ `ConsumerWidget`, wire "Message")
- Test: `test/features/message_button_nav_test.dart`

**Interfaces:**
- Consumes: `authRepositoryProvider`, `userRepositoryProvider`, `chatRepositoryProvider`, `Routes`.
- Produces: `Future<void> openChatWith(BuildContext, WidgetRef, {required String otherUid, required String otherName})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/message_button_nav_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Host-accepted "Message" opens a conversation', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
        email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    final booking = HomestayBooking(guestId: auth.currentUser!.uid, hostId: 'host1',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno',
        ratePerNight: 900, checkIn: DateTime(2026, 7, 20), checkOut: DateTime(2026, 7, 23),
        nights: 3, subtotal: 2700, fee: 150, total: 2850);

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    ], initialLocation: Routes.hostAccepted, extra: booking);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Message Meera'));
    await tester.pumpAndSettle();
    expect(find.text('Meera Iyer'), findsOneWidget);   // conversation header
    expect(find.text('Message…'), findsOneWidget);     // composer hint
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/message_button_nav_test.dart`
Expected: FAIL — the button still shows a snackbar (no navigation).

- [ ] **Step 3: Create `lib/features/chat/chat_actions.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../data/repositories/providers.dart';

/// Get-or-create a 1:1 chat with [otherUid] and open the conversation.
Future<void> openChatWith(BuildContext context, WidgetRef ref,
    {required String otherUid, required String otherName}) async {
  final me = ref.read(authRepositoryProvider).currentUser;
  if (me == null) return;
  final profile = await ref.read(userRepositoryProvider).watchUser(me.uid).first;
  final chat = await ref.read(chatRepositoryProvider).openChat(
      myUid: me.uid, myName: profile?.name ?? 'Someone', otherUid: otherUid, otherName: otherName);
  if (context.mounted) context.push(Routes.chat, extra: chat);
}
```

- [ ] **Step 4: Rewire `host_accepted_screen.dart`**

Change `class HostAcceptedScreen extends StatelessWidget` to `extends ConsumerWidget`, and `Widget build(BuildContext context)` to `Widget build(BuildContext context, WidgetRef ref)`. Add imports `import 'package:flutter_riverpod/flutter_riverpod.dart';` and `import '../chat/chat_actions.dart';`. Change the "Message" button's `onTap` from `() => showComingSoon(context, 'Chat')` to:
```dart
              onTap: () => openChatWith(context, ref, otherUid: b.hostId, otherName: b.hostName),
```
If `pg_snackbar` import becomes unused (no other `showComingSoon` in the file), remove it.

- [ ] **Step 5: Rewire `booking_confirmed_screen.dart`**

Change `class BookingConfirmedScreen extends StatelessWidget` to `extends ConsumerWidget`, and `Widget build(BuildContext context)` to `Widget build(BuildContext context, WidgetRef ref)`. Add imports `import 'package:flutter_riverpod/flutter_riverpod.dart';` and `import '../chat/chat_actions.dart';`. Change the "Message $proFirst" button's `onTap` from `() => showComingSoon(context, 'Chat')` to:
```dart
              onTap: () => openChatWith(context, ref, otherUid: b.proId, otherName: b.proName),
```
If `pg_snackbar` import becomes unused, remove it.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/message_button_nav_test.dart`
Expected: PASS.

- [ ] **Step 7: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/chat/chat_actions.dart lib/features/services/booking_confirmed_screen.dart lib/features/homestay/host_accepted_screen.dart test/features/message_button_nav_test.dart
git commit -m "feat: openChatWith helper; wire Booking-confirmed + Host-accepted Message buttons to chat"
```
Expected: whole suite green, analyze clean.

---

### Task 9: Rewire Pro-profile & Woof-match Message buttons

**Files:**
- Modify: `lib/features/services/pro_profile_screen.dart` (→ `ConsumerWidget`, wire the chat button)
- Modify: `lib/features/discovery/woof_match_screen.dart` (→ `ConsumerWidget`, wire "Send a message")
- Test: `test/features/woof_match_message_test.dart`

**Interfaces:**
- Consumes: `openChatWith` (Task 8), `userByIdProvider` (Slice 7a).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/woof_match_message_test.dart
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
  testWidgets('Woof-match "Send a message" opens a conversation with the pet owner', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
        email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    await users.createUser(const UserProfile(uid: 'owner1', name: 'Karan Mehta',
        email: 'k@x.com', area: 'Khar', role: Role.petParent));
    const pet = PetProfile(id: 'p1', ownerId: 'owner1', name: 'Simba', breed: 'Beagle',
        ageLabel: '3 yrs', sex: 'male', area: 'Khar', species: Species.dog,
        vaccinated: true, accentColor: Color(0xFF6B8DE0));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    ], initialLocation: Routes.woofMatch, extra: pet);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send a message 💬'));
    await tester.pumpAndSettle();
    expect(find.text('Karan Mehta'), findsOneWidget); // conversation header (owner name via userByIdProvider)
    expect(find.text('Message…'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/woof_match_message_test.dart`
Expected: FAIL — button still shows a snackbar.

- [ ] **Step 3: Rewire `woof_match_screen.dart`**

Change `class WoofMatchScreen extends StatelessWidget` to `extends ConsumerWidget`, and `Widget build(BuildContext context)` to `Widget build(BuildContext context, WidgetRef ref)`. Add imports `import 'package:flutter_riverpod/flutter_riverpod.dart';`, `import '../../data/repositories/providers.dart';`, and `import '../chat/chat_actions.dart';`. In `build`, after `final name = pet?.name ?? 'your match';`, add:
```dart
    final ownerUid = pet?.ownerId ?? '';
    final ownerName = ref.watch(userByIdProvider(ownerUid)).value?.name ?? 'Pet parent';
```
Change the "Send a message 💬" button (currently `() => showComingSoon(context, 'Chat')`) to:
```dart
                'Send a message 💬', () => ownerUid.isEmpty
                    ? null
                    : openChatWith(context, ref, otherUid: ownerUid, otherName: ownerName))),
```
Remove the now-unused `pg_snackbar` import if `showComingSoon` is no longer referenced in the file.

- [ ] **Step 4: Rewire `pro_profile_screen.dart`**

Change `class ProProfileScreen extends StatelessWidget` to `extends ConsumerWidget`, and `Widget build(BuildContext context)` to `Widget build(BuildContext context, WidgetRef ref)`. Add imports `import 'package:flutter_riverpod/flutter_riverpod.dart';` and `import '../chat/chat_actions.dart';`. Change the chat/💬 button's `onTap` from `() => showComingSoon(context, 'Chat')` to:
```dart
              onTap: () => openChatWith(context, ref, otherUid: p.uid, otherName: p.name),
```
(`p` is the non-null `Pro` in scope.) Keep the `showComingSoon` import — the "Book" button in that file still uses it.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/woof_match_message_test.dart`
Expected: PASS.

- [ ] **Step 6: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/services/pro_profile_screen.dart lib/features/discovery/woof_match_screen.dart test/features/woof_match_message_test.dart
git commit -m "feat: wire Pro-profile + Woof-match Message buttons to chat"
```
Expected: whole suite green, analyze clean.

---

### Task 10: Firestore rules for `chats` + `messages`; deploy

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the `chats` block to `firestore.rules`**

Inside `match /databases/{database}/documents { ... }`, after the `posts` block:
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

- [ ] **Step 2: Deploy the rules**

Run: `firebase deploy --only firestore:rules --project pet-aggregator-app`
Expected: `Deploy complete!`

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "chore: add + deploy Firestore rules for chats + messages (participant-scoped)"
```

---

### Task 11: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a `chats`/`messages` round-trip test)

- [ ] **Step 1: Append a chat test to `integration_test/firebase_repos_test.dart`**

Add `import 'package:pet_aggregator_app/data/models/chat.dart';` and `import 'package:pet_aggregator_app/data/repositories/firebase/firestore_chat_repository.dart';` with the other imports, then add this `testWidgets` inside `main()`:
```dart
  testWidgets('chats + messages open/send/watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final repo = FirestoreChatRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'chat_$stamp@x.com', password: 'secret1');
    final otherUid = 'other_$stamp';

    final chat = await repo.openChat(myUid: me.uid, myName: 'Me', otherUid: otherUid, otherName: 'Aarav');
    expect(chat.id, Chat.chatIdFor(me.uid, otherUid));
    final mine = await repo.watchMyChats(me.uid).firstWhere((l) => l.any((c) => c.id == chat.id));
    expect(mine.any((c) => c.id == chat.id), isTrue);

    await repo.sendMessage(chatId: chat.id, senderId: me.uid, text: 'ring me 9876543210');
    final msgs = await repo.watchMessages(chat.id).firstWhere((l) => l.isNotEmpty);
    expect(msgs.single.text, 'ring me ••••'); // write-time masked
    final afterSend = await repo.watchMyChats(me.uid).firstWhere((l) =>
        l.any((c) => c.id == chat.id && c.lastMessage == 'ring me ••••'));
    expect(afterSend.firstWhere((c) => c.id == chat.id).lastMessage, 'ring me ••••');

    await repo.markRead(chatId: chat.id, uid: me.uid);
    final read = await repo.watchMyChats(me.uid).firstWhere((l) =>
        l.any((c) => c.id == chat.id && (c.lastRead[me.uid] ?? 0) > 0));
    expect((read.firstWhere((c) => c.id == chat.id).lastRead[me.uid] ?? 0) > 0, isTrue);

    await auth.signOut();
  });
```

- [ ] **Step 2: Start emulators + run the integration test**

```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app   # one terminal
flutter test integration_test/firebase_repos_test.dart -d emulator-5554        # another
```
Expected: all integration tests pass. (Reuse a running emulator if one is up on 8080/9099; if the Pixel_10 AVD is offline, kill stale `qemu`/`emulator` processes, delete `~/.android/avd/Pixel_10.avd/*.lock`, and cold-boot.) Stop the emulators after if you started them.

- [ ] **Step 3: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: unit/widget tests pass, analyze clean, APK builds.

- [ ] **Step 4: Manual walkthrough (real cloud)**

Run: `flutter run -d emulator-5554`. From a booking/host-accept/woof-match, tap **Message** → a conversation opens; send a message with a phone number → it stores **masked** and the safety notice appears. From another account, open the same conversation → the message is there; reply → it appears live on the first account. Open the **Messages** list from the Home icon → the conversation shows with the right last message; the unread dot clears after opening.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify chats/messages round-trip + masking against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- `chats` + `messages` model + `maskPhones` → Task 1. ✓
- `ChatRepository` + fake + Firestore + providers → Tasks 2–4. ✓
- Conversation screen (live thread, composer, safety notice, markRead) → Task 5; Messages list (unread dot) → Task 6. ✓
- Home messages icon → Task 7. ✓
- `openChatWith` + rewire all 4 buttons → Tasks 8–9. ✓
- Rules (participant-scoped) + deploy → Task 10; emulator integration → Task 11. ✓
- Deferred (presence, calls, search, attachments) → none implemented; 📞 → coming-soon, search is a stub. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. `chatMessagesProvider` is `autoDispose.family` (no listener leak). Timestamps are client ints. `maskPhones` runs at write time in both repo impls.

**Type consistency:**
- `Chat` fields/`chatIdFor`/`otherName`/`hasUnread` and `Message` identical across Task 1 (model), Task 2 (fake/tests), Task 5 (conversation), Task 6 (list), Task 11 (integration). ✓
- `ChatRepository` methods (`openChat` returns `Chat`, `watchMyChats`, `watchMessages`, `sendMessage`, `markRead`) match between interface (Task 2), fake (Task 2), Firestore (Task 3), providers (Task 4), and callers (Tasks 5–9, 11). ✓
- Providers (`chatRepositoryProvider`, `myChatsProvider`, `chatMessagesProvider`) defined Task 4, consumed Tasks 5–6, 8. ✓
- `Routes.chatList`/`Routes.chat` added Task 5, used Tasks 5 (route + `_protected`), 6 (`/messages` route + row push `chat`), 7 (`push chatList`), 8 (`openChatWith` push `chat`). ✓
- `openChatWith(context, ref, {otherUid, otherName})` defined Task 8, consumed Tasks 8 (booking-confirmed, host-accepted), 9 (pro-profile, woof-match). ✓
- `userByIdProvider` (Slice 7a) reused Task 9 (woof-match owner name). `Post.timeAgo` (Slice P6) reused Task 6. ✓
- `showComingSoon` retained in `pro_profile_screen.dart` (Book button still uses it); removed from the others only if it becomes unused. ✓
