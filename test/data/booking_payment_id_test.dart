import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  test('Booking.paymentId round-trips and defaults to empty', () {
    final b = Booking(id: 'bk1', parentId: 'g', proId: 'p', proName: 'Aarav', petId: 'x',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue', timeSlot: '5:00 PM', paymentId: 'pay_abc123');
    expect(Booking.fromMap('bk1', b.toMap()).paymentId, 'pay_abc123');
    expect(Booking.fromMap('bk1', const {}).paymentId, ''); // legacy + homestay side
  });
}
