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
