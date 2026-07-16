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
