import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/repositories/contacts_repository.dart';
import 'package:fall_guardian/services/app_bootstrap_service.dart';
import 'package:fall_guardian/services/backend_api_service.dart';
import 'package:fall_guardian/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  test('bootstrap prepares backend before requesting location permission',
      () async {
    final calls = <String>[];
    final contacts = [
      const Contact(id: '1', name: 'Alice', phone: '+33600000001'),
    ];

    final service = AppBootstrapService(
      locationService: _FakeLocationService(calls),
      backendApi: _FakeBackendApiService(calls),
      contactsRepository: _FakeContactsRepository(calls, contacts),
    );

    await service.bootstrap();

    expect(calls, [
      'backend.ensureReady',
      'contacts.getAll',
      'backend.syncContacts:1',
      'location.requestPermissionIfNeeded',
    ]);
  });
}

class _FakeLocationService extends LocationService {
  _FakeLocationService(this.calls);

  final List<String> calls;

  @override
  Future<LocationPermission> requestPermissionIfNeeded() async {
    calls.add('location.requestPermissionIfNeeded');
    return LocationPermission.whileInUse;
  }
}

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService(this.calls);

  final List<String> calls;

  @override
  Future<void> ensureReady() async {
    calls.add('backend.ensureReady');
  }

  @override
  Future<void> syncContacts(List<Contact> contacts) async {
    calls.add('backend.syncContacts:${contacts.length}');
  }
}

class _FakeContactsRepository extends ContactsRepository {
  _FakeContactsRepository(this.calls, this.contacts);

  final List<String> calls;
  final List<Contact> contacts;

  @override
  Future<List<Contact>> getAll() async {
    calls.add('contacts.getAll');
    return contacts;
  }
}
