import 'package:flutter/material.dart';

enum PostCategory {
  health('health', 'Health', '🩺', Color(0xFFF59E2E)),
  training('training', 'Training', '🎓', Color(0xFF6B8DE0)),
  lostFound('lostFound', 'Lost & Found', '🔎', Color(0xFFF2547B));

  final String storageKey, label, emoji;
  final Color color;
  const PostCategory(this.storageKey, this.label, this.emoji, this.color);

  static PostCategory fromStorage(String key) =>
      PostCategory.values.firstWhere((c) => c.storageKey == key, orElse: () => PostCategory.health);
}

class Post {
  final String id, authorId, authorName, title, body;
  final PostCategory category;
  final int replyCount, createdAt;

  /// Optional photo. Matters most for Lost & Found, where a description alone
  /// is rarely enough to recognise an animal.
  final String photoUrl;

  /// The author's area, captured at post time. Also mainly for Lost & Found —
  /// "seen near Bandra West" is the difference between a useful post and noise.
  final String area;

  const Post({
    this.id = '',
    required this.authorId, required this.authorName, required this.category,
    required this.title, required this.body, required this.createdAt,
    this.replyCount = 0, this.photoUrl = '', this.area = '',
  });

  Map<String, dynamic> toMap() => {
        'authorId': authorId,
        'authorName': authorName,
        'category': category.storageKey,
        'title': title,
        'body': body,
        'replyCount': replyCount,
        'createdAt': createdAt,
        'photoUrl': photoUrl,
        'area': area,
      };

  factory Post.fromMap(String id, Map<String, dynamic> m) => Post(
        id: id,
        authorId: (m['authorId'] ?? '') as String,
        authorName: (m['authorName'] ?? '') as String,
        category: PostCategory.fromStorage((m['category'] ?? 'health') as String),
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        replyCount: (m['replyCount'] ?? 0) as int,
        createdAt: (m['createdAt'] ?? 0) as int,
        photoUrl: (m['photoUrl'] ?? '') as String,
        area: (m['area'] ?? '') as String,
      );

  static String timeAgo(int millis) {
    if (millis <= 0) return 'just now';
    final secs = (DateTime.now().millisecondsSinceEpoch - millis) ~/ 1000;
    if (secs < 60) return 'just now';
    final mins = secs ~/ 60;
    if (mins < 60) return '${mins}m';
    final hours = mins ~/ 60;
    if (hours < 24) return '${hours}h';
    return '${hours ~/ 24}d';
  }
}

class Comment {
  final String id, authorId, authorName, body;
  final int createdAt;

  const Comment({
    this.id = '',
    required this.authorId, required this.authorName, required this.body, required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'authorId': authorId,
        'authorName': authorName,
        'body': body,
        'createdAt': createdAt,
      };

  factory Comment.fromMap(String id, Map<String, dynamic> m) => Comment(
        id: id,
        authorId: (m['authorId'] ?? '') as String,
        authorName: (m['authorName'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        createdAt: (m['createdAt'] ?? 0) as int,
      );
}
