import 'pro.dart';

class Booking {
  final String id, parentId, proId, proName, petId, petName;
  final ServiceType serviceType;
  final int rate, fee, total, createdAt, updatedAt;
  final String dateLabel, timeSlot, status, date; // date: ISO yyyy-MM-dd ('' = legacy booking)

  const Booking({
    this.id = '',
    required this.parentId, required this.proId, required this.proName,
    required this.petId, required this.petName, required this.serviceType,
    required this.rate, required this.fee, required this.total,
    required this.dateLabel, required this.timeSlot, this.status = 'confirmed',
    this.date = '', this.createdAt = 0, this.updatedAt = 0,
  });

  static int feeFor(int rate) => (rate * 0.1).round();

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'parentId': parentId,
        'proId': proId,
        'proName': proName,
        'petId': petId,
        'petName': petName,
        'serviceType': serviceType.storageKey,
        'rate': rate,
        'fee': fee,
        'total': total,
        'dateLabel': dateLabel,
        'timeSlot': timeSlot,
        'status': status,
        'date': date,
        'updatedAt': updatedAt,
        'createdAt': createdAt,
      };

  factory Booking.fromMap(String id, Map<String, dynamic> m) => Booking(
        id: id,
        parentId: (m['parentId'] ?? '') as String,
        proId: (m['proId'] ?? '') as String,
        proName: (m['proName'] ?? '') as String,
        petId: (m['petId'] ?? '') as String,
        petName: (m['petName'] ?? '') as String,
        serviceType: ServiceType.fromStorage((m['serviceType'] ?? 'walker') as String),
        rate: (m['rate'] ?? 0) as int,
        fee: (m['fee'] ?? 0) as int,
        total: (m['total'] ?? 0) as int,
        dateLabel: (m['dateLabel'] ?? '') as String,
        timeSlot: (m['timeSlot'] ?? '') as String,
        status: (m['status'] ?? 'confirmed') as String,
        date: (m['date'] ?? '') as String,
        updatedAt: (m['updatedAt'] is int) ? m['updatedAt'] as int : 0,
        createdAt: (m['createdAt'] is int) ? m['createdAt'] as int : 0, // stale serverTimestamp -> 0
      );
}
