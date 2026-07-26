import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/notification_record.dart';

void main() {
  test('maps a full document', () {
    final r = NotificationRecord.fromMap('PAY1_pay_123', {
      'scenario': 'PAY1', 'category': 'money',
      'title': 'Payment received · ₹440', 'body': 'Dog walking with Rahul',
      'route': '/payments', 'createdAt': 1753500000000, 'read': false,
    });
    expect(r.id, 'PAY1_pay_123');
    expect(r.scenario, 'PAY1');
    expect(r.category, 'money');
    expect(r.route, '/payments');
    expect(r.createdAt, 1753500000000);
    expect(r.read, isFalse);
  });

  test('survives a document with missing fields', () {
    final r = NotificationRecord.fromMap('x', const {});
    expect(r.title, '');
    expect(r.category, '');
    expect(r.createdAt, 0);
    expect(r.read, isFalse);
  });

  test('read defaults to false when absent', () {
    final r = NotificationRecord.fromMap('x', const {'title': 'Hi'});
    expect(r.read, isFalse);
  });

  test('emoji and accent are derived from the category, not stored', () {
    expect(NotificationRecord.fromMap('a', const {'category': 'messages'}).emoji, '💬');
    expect(NotificationRecord.fromMap('b', const {'category': 'money'}).emoji, '💰');
    expect(NotificationRecord.fromMap('c', const {'category': 'woofs'}).emoji, '🐾');
    // An unknown category must not crash — it falls back to a bell.
    expect(NotificationRecord.fromMap('d', const {'category': 'nonsense'}).emoji, '🔔');
  });

  test('survives fields of the wrong type instead of throwing', () {
    final r = NotificationRecord.fromMap('bad', {
      'scenario': 42,
      'category': null,
      'title': ['not', 'a', 'string'],
      'createdAt': '1753500000000',
      'read': 'yes',
    });
    expect(r.scenario, '');
    expect(r.category, '');
    expect(r.title, '');
    expect(r.createdAt, 0);
    expect(r.read, isFalse);
  });
}
