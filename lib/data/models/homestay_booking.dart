class HomestayBooking {
  final String id, guestId, hostId, homeName, hostName, petId, petName, note, status;
  final DateTime checkIn, checkOut;
  final int ratePerNight, nights, subtotal, fee, total, createdAt;

  const HomestayBooking({
    this.id = '',
    required this.guestId, required this.hostId, required this.homeName,
    required this.hostName, required this.petId, required this.petName,
    required this.ratePerNight, required this.checkIn, required this.checkOut,
    required this.nights, required this.subtotal, required this.fee, required this.total,
    this.note = '', this.status = 'requested', this.createdAt = 0,
  });

  static const int serviceFee = 150;

  static int nightsBetween(DateTime checkIn, DateTime checkOut) =>
      checkOut.difference(checkIn).inDays;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months =
      ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String fmtDay(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
        'status': status,
        'createdAt': createdAt,
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
        status: (m['status'] ?? 'requested') as String,
        createdAt: (m['createdAt'] is int) ? m['createdAt'] as int : 0,
      );
}
