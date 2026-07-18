import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  test('feeFor is 10% rounded; total helper math', () {
    expect(Booking.feeFor(250), 25);
    expect(Booking.feeFor(255), 26); // 25.5 -> 26
  });

  test('toMap omits id, includes createdAt (default 0); fromMap restores', () {
    const b = Booking(parentId: 'u1', proId: 'p1', proName: 'Aarav', petId: 'pet1',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM');
    final m = b.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m.containsKey('createdAt'), isTrue); // createdAt is now included (value 0)
    expect(m['serviceType'], 'walker');
    expect(m['total'], 275);
    expect(m['status'], 'confirmed');
    final back = Booking.fromMap('b1', m);
    expect(back.id, 'b1');
    expect(back.proName, 'Aarav');
    expect(back.timeSlot, '5:00 PM');
    expect(back.serviceType, ServiceType.walker);
  });
}
