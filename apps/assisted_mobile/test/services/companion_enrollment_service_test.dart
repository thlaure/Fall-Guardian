import 'package:fall_guardian/services/companion_enrollment_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend implements CompanionEnrollmentBackendGateway {
  _FakeBackend(this.result);

  final CompanionEnrollment result;
  CompanionPlatform? requestedPlatform;

  @override
  Future<CompanionEnrollment> createCompanionEnrollment(
    CompanionPlatform platform,
  ) async {
    requestedPlatform = platform;
    return result;
  }
}

class _FailingBackend implements CompanionEnrollmentBackendGateway {
  @override
  Future<CompanionEnrollment> createCompanionEnrollment(
    CompanionPlatform platform,
  ) {
    throw StateError('backend unavailable');
  }
}

void main() {
  final expiresAt = DateTime.parse('2026-07-25T10:05:00+00:00');
  final enrollment = CompanionEnrollment(
    token: 'a' * 64,
    expiresAt: expiresAt,
  );

  test('builds stable versioned watchOS message', () {
    final message = CompanionEnrollmentMessage(
      platform: CompanionPlatform.watchOS,
      enrollment: enrollment,
    );

    expect(message.toMap(), {
      'type': 'companionEnrollment',
      'schemaVersion': 1,
      'platform': 'watchos',
      'enrollmentToken': 'a' * 64,
      'expiresAt': '2026-07-25T10:05:00.000Z',
    });
  });

  test('creates token then immediately sends it to the selected platform',
      () async {
    final backend = _FakeBackend(enrollment);
    CompanionEnrollmentMessage? sent;
    final coordinator = CompanionEnrollmentCoordinator(
      backend: backend,
      sendToWatch: (message) async => sent = message,
    );

    final result = await coordinator.start(CompanionPlatform.wearOS);

    expect(result, same(enrollment));
    expect(backend.requestedPlatform, CompanionPlatform.wearOS);
    expect(sent?.platform, CompanionPlatform.wearOS);
    expect(sent?.enrollment, same(enrollment));
  });

  test('does not invoke native sender when backend creation fails', () async {
    var sent = false;
    final coordinator = CompanionEnrollmentCoordinator(
      backend: _FailingBackend(),
      sendToWatch: (_) async => sent = true,
    );

    await expectLater(
      coordinator.start(CompanionPlatform.watchOS),
      throwsA(isA<StateError>()),
    );

    expect(sent, isFalse);
  });

  test('propagates native delivery failure', () async {
    final coordinator = CompanionEnrollmentCoordinator(
      backend: _FakeBackend(enrollment),
      sendToWatch: (_) => throw StateError('watch unavailable'),
    );

    await expectLater(
      coordinator.start(CompanionPlatform.watchOS),
      throwsA(isA<StateError>()),
    );
  });
}
