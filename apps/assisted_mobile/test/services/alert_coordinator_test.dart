import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/services/alert_coordinator.dart';
import 'package:fall_guardian/services/alert_ports.dart';
import 'package:fall_guardian/services/alert_runtime.dart';

class _FakeContactsRepository implements EmergencyContactsStore {
  _FakeContactsRepository(this.contacts);

  final List<Contact> contacts;

  @override
  Future<List<Contact>> getAll() async => contacts;
}

class _FakeFallEventsRepository implements FallEventRecorder {
  final List<FallEvent> savedEvents = [];

  @override
  Future<void> add(FallEvent event) async {
    savedEvents.add(event);
  }
}

class _FakeLocationService implements AlertLocationProvider {
  @override
  Future<Position?> getCurrentPosition() async => null;
}

class _FakeLocationServiceWithPosition implements AlertLocationProvider {
  @override
  Future<Position?> getCurrentPosition() async => Position(
        latitude: 48.8566,
        longitude: 2.3522,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

class _FakeNotificationService implements AlertNotificationGateway {
  int cancelCount = 0;

  @override
  Future<void> cancelAll() async {
    cancelCount++;
  }
}

class _FakeBackendGateway implements AlertBackendGateway {
  _FakeBackendGateway({
    this.shouldFail = false,
    this.recordCancelledCompleter,
    this.cancelCompleter,
  });

  final bool shouldFail;
  final Completer<void>? recordCancelledCompleter;
  final Completer<void>? cancelCompleter;
  String? lastClientAlertId;
  String? lastLocale;
  List<Contact>? lastContacts;
  int? lastTimestamp;
  double? lastLatitude;
  double? lastLongitude;
  int cancelCount = 0;
  int callCount = 0;
  int cancelledRecordCount = 0;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> syncContacts(List<Contact> contacts) async {}

  @override
  Future<void> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
    required List<Contact> contacts,
  }) async {
    callCount++;
    lastClientAlertId = clientAlertId;
    lastLocale = locale;
    lastTimestamp = fallTimestamp;
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastContacts = contacts;
    if (shouldFail) {
      throw Exception('backend unavailable');
    }
  }

  @override
  Future<void> recordCancelledFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    cancelledRecordCount++;
    lastClientAlertId = clientAlertId;
    lastLocale = locale;
    lastTimestamp = fallTimestamp;
    lastLatitude = latitude;
    lastLongitude = longitude;
    await recordCancelledCompleter?.future;
  }

  @override
  Future<void> cancelFallAlert({required String clientAlertId}) async {
    cancelCount++;
    await cancelCompleter?.future;
  }
}

class _FakeWatchGateway implements WatchCommandGateway {
  int cancelCount = 0;

  @override
  Future<void> sendCancelAlert() async {
    cancelCount++;
  }
}

class _FakeClock implements Clock {
  _FakeClock([DateTime? initialNow]) : _now = initialNow ?? DateTime.now();

  DateTime _now;

  @override
  DateTime now() => _now;

  void setNow(DateTime value) {
    _now = value;
  }
}

class _FakeIdGenerator implements IdGenerator {
  int _next = 0;

  @override
  String newId() => 'id-${_next++}';
}

AlertCoordinator _coordinator({
  EmergencyContactsStore? contactsStore,
  FallEventRecorder? eventRecorder,
  AlertLocationProvider? locationProvider,
  AlertNotificationGateway? notificationGateway,
  AlertBackendGateway? backendGateway,
  WatchCommandGateway? watchGateway,
  AlertLocaleResolver? localeResolver,
  Clock? clock,
  IdGenerator? idGenerator,
}) {
  return AlertCoordinator(
    contactsStore: contactsStore ?? _FakeContactsRepository(const []),
    eventRecorder: eventRecorder ?? _FakeFallEventsRepository(),
    locationProvider: locationProvider ?? _FakeLocationService(),
    notificationGateway: notificationGateway ?? _FakeNotificationService(),
    backendGateway: backendGateway ?? _FakeBackendGateway(),
    watchGateway: watchGateway ?? _FakeWatchGateway(),
    localeResolver: localeResolver ?? const DeviceLocaleResolver(),
    clock: clock ?? _FakeClock(),
    idGenerator: idGenerator ?? _FakeIdGenerator(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      null,
    );
  });

  test('startAlert enters countdown phase', () async {
    final coordinator = _coordinator();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);

    expect(coordinator.currentState?.fallTimestamp, timestamp);
    expect(coordinator.currentState?.phase, AlertPhase.countdown);
    expect(coordinator.currentState?.isSending, isFalse);

    coordinator.dispose();
  });

  test('cancelFromWatch does not send cancel back to watch', () async {
    final watchCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      (call) async {
        watchCalls.add(call);
        return null;
      },
    );

    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await coordinator.cancelFromWatch();

    expect(
      watchCalls.where((call) => call.method == 'sendCancelAlert'),
      isEmpty,
    );
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(coordinator.currentState, isNull);
    expect(notifications.cancelCount, 1);
    expect(backend.cancelCount, 0);
    expect(backend.cancelledRecordCount, 1);

    coordinator.dispose();
  });

  test('cancelFromWatch emits cancelled phase before dismissal', () async {
    final states = <AlertUiState>[];
    final coordinator = _coordinator();
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await coordinator.cancelFromWatch();

    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.cancelled,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('cancelFromPhone sends cancel to watch and records cancellation',
      () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final watchGateway = _FakeWatchGateway();
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      watchGateway: watchGateway,
      backendGateway: backend,
    );

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await coordinator.cancelFromPhone();

    expect(watchGateway.cancelCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(notifications.cancelCount, 1);
    expect(coordinator.currentState, isNull);
    expect(backend.cancelCount, 0);
    expect(backend.cancelledRecordCount, 1);
    expect(backend.lastClientAlertId, 'id-0');

    coordinator.dispose();
  });

  test('cancelFromPhone waits for backend cancellation record before finishing',
      () async {
    final backendCompleter = Completer<void>();
    final backend = _FakeBackendGateway(
      recordCancelledCompleter: backendCompleter,
    );
    final coordinator = _coordinator(backendGateway: backend);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);

    var completed = false;
    final cancelFuture = coordinator.cancelFromPhone().then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(backend.cancelledRecordCount, 1);
    expect(completed, isFalse);

    backendCompleter.complete();
    await cancelFuture;

    expect(completed, isTrue);

    coordinator.dispose();
  });

  test('cancelFromPhone invalidates alert before backend cancellation finishes',
      () async {
    final backendCompleter = Completer<void>();
    final backend = _FakeBackendGateway(
      recordCancelledCompleter: backendCompleter,
    );
    final clock = _FakeClock(DateTime(2026, 6, 16, 9, 45));
    final coordinator = _coordinator(
      backendGateway: backend,
      clock: clock,
    );

    final timestamp = clock.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);

    final cancelFuture = coordinator.cancelFromPhone();
    await Future<void>.delayed(Duration.zero);

    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();

    expect(backend.callCount, 0);
    expect(backend.cancelledRecordCount, 1);

    backendCompleter.complete();
    await cancelFuture;

    coordinator.dispose();
  });

  test(
      'cancelFromPhone waits for submitted backend cancellation before finishing',
      () async {
    final backendCompleter = Completer<void>();
    final backend = _FakeBackendGateway(cancelCompleter: backendCompleter);
    final coordinator = _coordinator(backendGateway: backend);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    var completed = false;
    final cancelFuture = coordinator.cancelFromPhone().then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(backend.cancelCount, 1);
    expect(completed, isFalse);

    backendCompleter.complete();
    await cancelFuture;

    expect(completed, isTrue);

    coordinator.dispose();
  });

  test(
      'timeout without contacts still submits to backend and records alertSent',
      () async {
    // Even with no emergency contacts the backend is always called so that
    // the fall event is persisted server-side and can be dispatched through
    // the linked caregiver workflow.
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.callCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('reconcileActiveAlert triggers timeout after lifecycle pause', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final clock = _FakeClock(DateTime(2026, 4, 19, 12, 0, 0));
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
      clock: clock,
    );
    final sub = coordinator.stateStream.listen(states.add);

    final timestamp = clock.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);

    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.callCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('timeout with contacts and backend submission records alertSent',
      () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      contactsStore: _FakeContactsRepository(const [
        Contact(id: '1', name: 'Alice', phone: '+33600000001'),
        Contact(id: '2', name: 'Bob', phone: '+33600000002'),
      ]),
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(repo.savedEvents.single.notifiedContacts, isEmpty);
    expect(notifications.cancelCount, 1);
    expect(backend.lastContacts, hasLength(2));
    expect(backend.lastClientAlertId, isNotNull);
    expect(backend.lastLocale, isNotEmpty);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('timeout with contacts and backend failure records alertFailed',
      () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      contactsStore: _FakeContactsRepository(const [
        Contact(id: '1', name: 'Alice', phone: '+33600000001'),
      ]),
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: _FakeBackendGateway(shouldFail: true),
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.alertFailed);
    expect(repo.savedEvents.single.notifiedContacts, isEmpty);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertFailed,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('cancelFromPhone with no active alert clears notifications only',
      () async {
    final notifications = _FakeNotificationService();
    final coordinator = _coordinator(notificationGateway: notifications);
    var dismissed = false;
    final sub = coordinator.dismissStream.listen((_) => dismissed = true);

    await coordinator.cancelFromPhone();
    await Future<void>.delayed(Duration.zero);

    expect(notifications.cancelCount, 1);
    expect(dismissed, isTrue);
    expect(coordinator.currentState, isNull);

    await sub.cancel();
    coordinator.dispose();
  });

  test(
      'timeout with a real position submits lat/lng and dismisses after the '
      'alertSent delay',
      () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      locationProvider: _FakeLocationServiceWithPosition(),
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );
    var dismissed = false;
    final sub = coordinator.dismissStream.listen((_) => dismissed = true);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.lastLatitude, 48.8566);
    expect(backend.lastLongitude, 2.3522);
    expect(repo.savedEvents.single.latitude, 48.8566);
    expect(repo.savedEvents.single.longitude, 2.3522);
    expect(coordinator.currentState?.phase, AlertPhase.alertSent);

    // The alertSent outcome dismisses itself 2 seconds after being shown.
    await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 200));

    expect(dismissed, isTrue);
    expect(coordinator.currentState, isNull);

    await sub.cancel();
    coordinator.dispose();
  });

  test('timeout with a real position and backend failure records lat/lng',
      () async {
    final repo = _FakeFallEventsRepository();
    final coordinator = _coordinator(
      locationProvider: _FakeLocationServiceWithPosition(),
      eventRecorder: repo,
      backendGateway: _FakeBackendGateway(shouldFail: true),
    );

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.alertFailed);
    expect(repo.savedEvents.single.latitude, 48.8566);
    expect(repo.savedEvents.single.longitude, 2.3522);

    coordinator.dispose();
  });
}
