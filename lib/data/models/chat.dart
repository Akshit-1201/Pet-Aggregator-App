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
