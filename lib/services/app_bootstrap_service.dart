import '../models/contact.dart';
import '../repositories/contacts_repository.dart';
import 'backend_api_service.dart';
import 'location_service.dart';

/// Best-effort app startup bootstrap for phone-side integrations.
///
/// This keeps startup coordination out of the widget entrypoint while
/// preserving the existing behavior: request location permission, warm up the
/// backend client, and sync locally stored contacts when possible.
class AppBootstrapService {
  AppBootstrapService({
    required LocationService locationService,
    required BackendApiService backendApi,
    required ContactsRepository contactsRepository,
  })  : _locationService = locationService,
        _backendApi = backendApi,
        _contactsRepository = contactsRepository;

  final LocationService _locationService;
  final BackendApiService _backendApi;
  final ContactsRepository _contactsRepository;

  Future<void> bootstrap() async {
    await _locationService.requestPermissionIfNeeded();
    await _backendApi.ensureReady();
    final List<Contact> contacts = await _contactsRepository.getAll();
    await _backendApi.syncContacts(contacts);
  }
}
