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
