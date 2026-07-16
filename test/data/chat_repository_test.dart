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
