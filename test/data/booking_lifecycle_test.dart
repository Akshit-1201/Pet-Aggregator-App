import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/booking_lifecycle.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

final _now = DateTime(2026, 7, 19, 14, 30); // fixed "today" — time of day must not matter

Booking _svc({String status = 'confirmed', String date = ''}) => Booking(
    id: 'bk1', parentId: 'g', proId: 'p', proName: 'Aarav', petId: 'x', petName: 'Bruno',
    serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
    dateLabel: 'Tue', timeSlot: '5:00 PM', status: status, date: date);

HomestayBooking _stay({String status = 'requested', DateTime? checkIn, DateTime? checkOut}) =>
    HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: 'H', hostName: 'M',
        petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: checkIn ?? DateTime(2026, 7, 21), checkOut: checkOut ?? DateTime(2026, 7, 24),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: status);

void main() {
  group('servicePhase', () {
    test('cancelled wins over any date', () =>
        expect(servicePhase(_svc(status: 'cancelled', date: '2026-07-25'), _now), BookingPhase.cancelled));
    test('legacy (no date) is completed', () =>
        expect(servicePhase(_svc(), _now), BookingPhase.completed));
    test('unparseable date behaves like legacy', () =>
        expect(servicePhase(_svc(date: 'garbage'), _now), BookingPhase.completed));
    test('today and tomorrow are upcoming', () {
      expect(servicePhase(_svc(date: '2026-07-19'), _now), BookingPhase.upcoming);
      expect(servicePhase(_svc(date: '2026-07-20'), _now), BookingPhase.upcoming);
    });
    test('yesterday is completed', () =>
        expect(servicePhase(_svc(date: '2026-07-18'), _now), BookingPhase.completed));
  });

  group('stayPhase', () {
    test('declined / cancelled map directly', () {
      expect(stayPhase(_stay(status: 'declined'), _now), BookingPhase.declined);
      expect(stayPhase(_stay(status: 'cancelled'), _now), BookingPhase.cancelled);
    });
    test('requested is pending up to and including check-in day', () {
      expect(stayPhase(_stay(checkIn: DateTime(2026, 7, 21)), _now), BookingPhase.pending);
      expect(stayPhase(_stay(checkIn: DateTime(2026, 7, 19)), _now), BookingPhase.pending);
    });
    test('requested past check-in is expired', () =>
        expect(stayPhase(_stay(checkIn: DateTime(2026, 7, 18)), _now), BookingPhase.expired));
    test('accepted before check-in is awaitingPayment', () =>
        expect(stayPhase(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 21)), _now),
            BookingPhase.awaitingPayment));
    test('accepted past check-in (never paid) is expired', () =>
        expect(stayPhase(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 18)), _now),
            BookingPhase.expired));
    test('paid is upcoming up to and including checkout day', () =>
        expect(stayPhase(_stay(status: 'paid', checkIn: DateTime(2026, 7, 15), checkOut: DateTime(2026, 7, 19)), _now),
            BookingPhase.upcoming));
    test('paid past checkout is completed', () =>
        expect(stayPhase(_stay(status: 'paid', checkIn: DateTime(2026, 7, 10), checkOut: DateTime(2026, 7, 18)), _now),
            BookingPhase.completed));
  });

  group('permissions', () {
    test('canRate only when completed', () {
      expect(canRate(BookingPhase.completed), isTrue);
      for (final p in BookingPhase.values.where((p) => p != BookingPhase.completed)) {
        expect(canRate(p), isFalse);
      }
    });
    test('canCancelService: strictly before the date; never legacy or cancelled', () {
      expect(canCancelService(_svc(date: '2026-07-20'), _now), isTrue);
      expect(canCancelService(_svc(date: '2026-07-19'), _now), isFalse); // day-of
      expect(canCancelService(_svc(), _now), isFalse);                    // legacy
      expect(canCancelService(_svc(status: 'cancelled', date: '2026-07-25'), _now), isFalse);
    });
    test('canCancelStay: requested until expiry; accepted strictly before check-in', () {
      expect(canCancelStay(_stay(checkIn: DateTime(2026, 7, 19)), _now), isTrue);   // pending, check-in today
      expect(canCancelStay(_stay(checkIn: DateTime(2026, 7, 18)), _now), isFalse);  // expired
      expect(canCancelStay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 20)), _now), isTrue);
      expect(canCancelStay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 19)), _now), isFalse); // starts today
      expect(canCancelStay(_stay(status: 'declined'), _now), isFalse);
    });
    test('canDecide: only live requests', () {
      expect(canDecide(_stay(checkIn: DateTime(2026, 7, 19)), _now), isTrue);
      expect(canDecide(_stay(checkIn: DateTime(2026, 7, 18)), _now), isFalse); // expired
      expect(canDecide(_stay(status: 'accepted'), _now), isFalse);
    });
  });

  group('canPay + paid no-cancel', () {
    test('canPay only for accepted before check-in', () {
      expect(canPay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 20)), _now), isTrue);
      expect(canPay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 19)), _now), isTrue); // check-in today ok
      expect(canPay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 18)), _now), isFalse); // past
      expect(canPay(_stay(status: 'requested', checkIn: DateTime(2026, 7, 20)), _now), isFalse);
      expect(canPay(_stay(status: 'paid', checkIn: DateTime(2026, 7, 20)), _now), isFalse);
    });
    test('a paid stay is not cancellable', () {
      expect(canCancelStay(_stay(status: 'paid', checkIn: DateTime(2026, 7, 25)), _now), isFalse);
    });
  });

  group('canCancelPaidStay', () {
    final now = DateTime(2026, 7, 19, 12, 0);
    HomestayBooking paid(DateTime checkIn) => HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h',
        homeName: 'H', hostName: 'M', petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: checkIn, checkOut: checkIn.add(const Duration(days: 3)), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, status: 'paid');
    test('paid + before check-in is cancellable (any distance before check-in)', () {
      expect(canCancelPaidStay(paid(now.add(const Duration(days: 5))), now), isTrue);
      expect(canCancelPaidStay(paid(now.add(const Duration(hours: 2))), now), isTrue); // still cancellable (0 refund)
    });
    test('paid at/after check-in is not cancellable in-app', () {
      expect(canCancelPaidStay(paid(now), now), isFalse);
      expect(canCancelPaidStay(paid(now.subtract(const Duration(days: 1))), now), isFalse);
    });
    test('non-paid stays are not covered by canCancelPaidStay', () {
      final accepted = HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: 'H',
          hostName: 'M', petId: 'x', petName: 'B', ratePerNight: 900,
          checkIn: now.add(const Duration(days: 5)), checkOut: now.add(const Duration(days: 8)),
          nights: 3, subtotal: 2700, fee: 150, total: 2850, status: 'accepted');
      expect(canCancelPaidStay(accepted, now), isFalse);
    });
  });
}
