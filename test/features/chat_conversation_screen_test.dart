import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
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
