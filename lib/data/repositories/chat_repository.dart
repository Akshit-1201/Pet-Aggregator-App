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
