enum FallEventStatus { alertSent, alertFailed, cancelled, timedOutNoSms }

class FallEvent {
  final String id;
  final DateTime timestamp;
  final FallEventStatus status;
  final double? latitude;
  final double? longitude;
  final List<String> notifiedContacts; // contact names

  const FallEvent({
    required this.id,
    required this.timestamp,
    required this.status,
    this.latitude,
    this.longitude,
    this.notifiedContacts = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
        'latitude': latitude,
        'longitude': longitude,
        'notifiedContacts': notifiedContacts,
      };

  factory FallEvent.fromJson(Map<String, dynamic> json) => FallEvent(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        status: FallEventStatus.values.byName(json['status'] as String),
        latitude: json['latitude'] as double?,
        longitude: json['longitude'] as double?,
        notifiedContacts: List<String>.from(json['notifiedContacts'] ?? []),
      );
}
