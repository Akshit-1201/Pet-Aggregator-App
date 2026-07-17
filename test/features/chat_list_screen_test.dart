import 'package:flutter/material.dart';
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
