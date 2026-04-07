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

class _FakeNotificationService implements AlertNotificationGateway {
  int cancelCount = 0;

  @override
  Future<void> cancelAll() async {
    cancelCount++;
  }
}

class _FakeSmsService implements AlertSmsGateway {
  _FakeSmsService(this.result);

  final List<String> result;
  String? lastMessage;
  List<Contact>? lastContacts;

  @override
  Future<List<String>> sendFallAlert({
    required List<Contact> contacts,
    required String message,
  }) async {
    lastContacts = contacts;
    lastMessage = message;
    return result;
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
  @override
  DateTime now() => DateTime.now();
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
  AlertSmsGateway? smsGateway,
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
    smsGateway: smsGateway ?? _FakeSmsService(const []),
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
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
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
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      watchGateway: watchGateway,
    );

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await coordinator.cancelFromPhone();

    expect(watchGateway.cancelCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(notifications.cancelCount, 1);
    expect(coordinator.currentState, isNull);

    coordinator.dispose();
  });

  test('timeout without contacts records timedOutNoSms', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.timedOutNoSms);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingSms,
      AlertPhase.timedOutNoSms,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('timeout with contacts and successful sms records alertSent', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final sms = _FakeSmsService(const ['Alice', 'Bob']);
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      contactsStore: _FakeContactsRepository(const [
        Contact(id: '1', name: 'Alice', phone: '+33600000001'),
        Contact(id: '2', name: 'Bob', phone: '+33600000002'),
      ]),
      eventRecorder: repo,
      notificationGateway: notifications,
      smsGateway: sms,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(repo.savedEvents.single.notifiedContacts, ['Alice', 'Bob']);
    expect(notifications.cancelCount, 1);
    expect(sms.lastContacts, hasLength(2));
    expect(sms.lastMessage, isNot(contains('Alice')));
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingSms,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('timeout with contacts and failed sms records alertFailed', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      contactsStore: _FakeContactsRepository(const [
        Contact(id: '1', name: 'Alice', phone: '+33600000001'),
      ]),
      eventRecorder: repo,
      notificationGateway: notifications,
      smsGateway: _FakeSmsService(const []),
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
      AlertPhase.sendingSms,
      AlertPhase.alertFailed,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });
}
