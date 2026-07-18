import 'pro.dart';

class Booking {
  final String id, parentId, proId, proName, petId, petName;
  final ServiceType serviceType;
  final int rate, fee, total, createdAt;
  final String dateLabel, timeSlot, status;

  const Booking({
    this.id = '',
    required this.parentId, required this.proId, required this.proName,
    required this.petId, required this.petName, required this.serviceType,
    required this.rate, required this.fee, required this.total,
    required this.dateLabel, required this.timeSlot, this.status = 'confirmed', this.createdAt = 0,
  });

  static int feeFor(int rate) => (rate * 0.1).round();

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
        createdAt: (m['createdAt'] is int) ? m['createdAt'] as int : 0, // stale serverTimestamp -> 0
      );
}
