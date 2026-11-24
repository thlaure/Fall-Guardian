import '../utils/api_date_time.dart';

/// Who is currently handling an alert, as reported by the API.
enum AlertHandlingState {
  /// No caregiver has said they are handling it (or the API does not say).
  none,

  /// This caregiver pressed "I'm handling it".
  handledByMe,

  /// At least one other caregiver is handling it.
  handledByOther,
}

/// Typed, tolerant view over a fall alert payload.
///
/// Payloads come from FCM `data` (all values are strings) or from
/// `CaregiverBackendService.toPushAlertData`. They are untrusted input: every
/// field except `alertId` is optional and malformed values are ignored, so an
/// older or newer API never breaks the emergency screen.
class FallAlertDetails {
  const FallAlertDetails({
    required this.alertId,
    this.rawFallTimestamp = '',
    this.fallDetectedAt,
    this.latitude,
    this.longitude,
    this.protectedPersonName,
    this.cancelDeadlineAt,
    this.isReminder = false,
    this.acknowledgedAt,
    this.acknowledgedByMe,
    this.acknowledgementCount,
    this.status,
  });

  factory FallAlertDetails.fromData(Map<String, dynamic> data) {
    final rawTimestamp = _string(data['fallTimestamp']) ?? '';
    final latitude = _double(data['latitude']);
    final longitude = _double(data['longitude']);
    final hasValidLocation =
        latitude != null &&
        longitude != null &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180;

    return FallAlertDetails(
      alertId: _string(data['alertId']) ?? '',
      rawFallTimestamp: rawTimestamp,
      fallDetectedAt: parseApiDateTime(rawTimestamp),
      latitude: hasValidLocation ? latitude : null,
      longitude: hasValidLocation ? longitude : null,
      protectedPersonName: _string(data['protectedPersonName']),
      cancelDeadlineAt: parseApiDateTime(_string(data['cancelDeadlineAt'])),
      isReminder: _string(data['reminder']) == '1',
      acknowledgedAt: parseApiDateTime(_string(data['acknowledgedAt'])),
      acknowledgedByMe: _bool(data['acknowledgedByMe']),
      acknowledgementCount: _int(data['acknowledgementCount']),
      status: _string(data['status']),
    );
  }

  final String alertId;
  final String rawFallTimestamp;
  final DateTime? fallDetectedAt;
  final double? latitude;
  final double? longitude;
  final String? protectedPersonName;
  final DateTime? cancelDeadlineAt;
  final bool isReminder;
  final DateTime? acknowledgedAt;
  final bool? acknowledgedByMe;
  final int? acknowledgementCount;

  /// Backend alert status when known (absent in FCM pushes).
  final String? status;

  bool get hasLocation => latitude != null && longitude != null;

  AlertHandlingState get handlingState {
    if (acknowledgedByMe == true) return AlertHandlingState.handledByMe;
    final count = acknowledgementCount ?? 0;
    // On the current API the only signal that another caregiver responded is
    // the alert status switching to `acknowledged`.
    if (count > 0 ||
        status == 'acknowledged' ||
        (acknowledgedByMe == false && acknowledgedAt != null)) {
      return AlertHandlingState.handledByOther;
    }
    return AlertHandlingState.none;
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(_string(value) ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(_string(value) ?? '');
  }

  static bool? _bool(Object? value) {
    if (value is bool) return value;
    return switch (_string(value)?.toLowerCase()) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };
  }
}
