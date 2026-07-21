class HomestayBooking {
  final String id, guestId, hostId, homeName, hostName, petId, petName, note, status, paymentId, refundId;
  final DateTime checkIn, checkOut;
  final int ratePerNight, nights, subtotal, fee, total, createdAt, updatedAt, refundAmount;

  const HomestayBooking({
    this.id = '',
    required this.guestId, required this.hostId, required this.homeName,
    required this.hostName, required this.petId, required this.petName,
    required this.ratePerNight, required this.checkIn, required this.checkOut,
    required this.nights, required this.subtotal, required this.fee, required this.total,
    this.note = '', this.paymentId = '', this.refundAmount = 0, this.refundId = '', this.status = 'requested', this.createdAt = 0, this.updatedAt = 0,
  });

  static const int serviceFee = 150;

  static int nightsBetween(DateTime checkIn, DateTime checkOut) =>
      checkOut.difference(checkIn).inDays;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months =
      ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String fmtDay(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

  // Date-only when at exact midnight (keeps the short calendar-date format
  // most bookings use); full ISO-8601 otherwise, so a time-of-day (e.g. a
  // check-in a few hours from now) survives a toMap/fromMap round-trip.
  // The 24h refund cutoff (refund_policy.dart) and canCancelPaidStay need
  // that precision — a date-only round-trip would silently floor any
  // same-day check-in to midnight and misclassify it as already past.
  static String _iso(DateTime d) {
    final date = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final atMidnight =
        d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0 && d.microsecond == 0;
    return atMidnight ? date : d.toIso8601String();
  }

  Map<String, dynamic> toMap() => {
        'guestId': guestId,
        'hostId': hostId,
        'homeName': homeName,
        'hostName': hostName,
        'petId': petId,
        'petName': petName,
        'ratePerNight': ratePerNight,
        'checkIn': _iso(checkIn),
        'checkOut': _iso(checkOut),
        'nights': nights,
        'subtotal': subtotal,
        'fee': fee,
        'total': total,
        'note': note,
        'paymentId': paymentId,
        'refundAmount': refundAmount,
        'refundId': refundId,
        'status': status,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory HomestayBooking.fromMap(String id, Map<String, dynamic> m) => HomestayBooking(
        id: id,
        guestId: (m['guestId'] ?? '') as String,
        hostId: (m['hostId'] ?? '') as String,
        homeName: (m['homeName'] ?? '') as String,
        hostName: (m['hostName'] ?? '') as String,
        petId: (m['petId'] ?? '') as String,
        petName: (m['petName'] ?? '') as String,
        ratePerNight: (m['ratePerNight'] ?? 0) as int,
        checkIn: DateTime.parse((m['checkIn'] ?? '1970-01-01') as String),
        checkOut: DateTime.parse((m['checkOut'] ?? '1970-01-01') as String),
        nights: (m['nights'] ?? 0) as int,
        subtotal: (m['subtotal'] ?? 0) as int,
        fee: (m['fee'] ?? 0) as int,
        total: (m['total'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        paymentId: (m['paymentId'] ?? '') as String,
        refundAmount: (m['refundAmount'] ?? 0) as int,
        refundId: (m['refundId'] ?? '') as String,
        status: (m['status'] ?? 'requested') as String,
        createdAt: (m['createdAt'] is int) ? m['createdAt'] as int : 0,
        updatedAt: (m['updatedAt'] is int) ? m['updatedAt'] as int : 0,
      );
}
