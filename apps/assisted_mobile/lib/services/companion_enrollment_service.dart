enum CompanionPlatform {
  watchOS('watchos'),
  wearOS('wearos');

  const CompanionPlatform(this.apiValue);

  final String apiValue;
}

class CompanionEnrollment {
  const CompanionEnrollment({
    required this.token,
    required this.expiresAt,
  });

  final String token;
  final DateTime expiresAt;
}

class CompanionEnrollmentMessage {
  const CompanionEnrollmentMessage({
    required this.platform,
    required this.enrollment,
  });

  static const schemaVersion = 1;

  final CompanionPlatform platform;
  final CompanionEnrollment enrollment;

  Map<String, Object> toMap() => {
        'type': 'companionEnrollment',
        'schemaVersion': schemaVersion,
        'platform': platform.apiValue,
        'enrollmentToken': enrollment.token,
        'expiresAt': enrollment.expiresAt.toUtc().toIso8601String(),
      };
}

abstract interface class CompanionEnrollmentBackendGateway {
  Future<CompanionEnrollment> createCompanionEnrollment(
    CompanionPlatform platform,
  );
}

typedef CompanionEnrollmentSender = Future<void> Function(
  CompanionEnrollmentMessage message,
);

/// Owns the short-lived phone → watch enrollment workflow.
///
/// The token stays in memory only: the backend creates it, then this
/// coordinator immediately hands it to the native watch bridge.
class CompanionEnrollmentCoordinator {
  const CompanionEnrollmentCoordinator({
    required CompanionEnrollmentBackendGateway backend,
    required CompanionEnrollmentSender sendToWatch,
  })  : _backend = backend,
        _sendToWatch = sendToWatch;

  final CompanionEnrollmentBackendGateway _backend;
  final CompanionEnrollmentSender _sendToWatch;

  Future<CompanionEnrollment> start(CompanionPlatform platform) async {
    final enrollment = await _backend.createCompanionEnrollment(platform);
    await _sendToWatch(
      CompanionEnrollmentMessage(
        platform: platform,
        enrollment: enrollment,
      ),
    );
    return enrollment;
  }
}
