import '../models/contact.dart';
import '../repositories/contacts_repository.dart';
import 'backend_api_service.dart';
import 'location_service.dart';

/// Best-effort app startup bootstrap for phone-side integrations.
///
/// This keeps startup coordination out of the widget entrypoint while keeping
/// critical backend readiness independent from optional platform permissions.
class AppBootstrapService {
  AppBootstrapService({
    required this._locationService,
    required this._backendApi,
    required this._contactsRepository,
  });

  final LocationService _locationService;
  final BackendApiService _backendApi;
  final ContactsRepository _contactsRepository;

  Future<void> bootstrap() async {
    // Location permission must be requested before anything network-dependent:
    // a backend failure below must never suppress this prompt, or the first
    // real request ends up happening mid-fall-alert instead of at startup.
    await _locationService.requestPermissionIfNeeded();
    await _backendApi.ensureReady();
    final List<Contact> contacts = await _contactsRepository.getAll();
    await _backendApi.syncContacts(contacts);
  }
}
