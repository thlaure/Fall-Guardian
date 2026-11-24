import 'dart:async';

import 'package:caregiver_app/services/caregiver_backend_service.dart';

/// Scriptable backend for widget tests. No HTTP is performed.
class FakeCaregiverBackend extends CaregiverBackendService {
  FakeCaregiverBackend({
    List<LinkedProtectedPerson>? protectedPersons,
    List<Map<String, dynamic>>? alerts,
  }) : protectedPersons = protectedPersons ?? [],
       alerts = alerts ?? [];

  final List<LinkedProtectedPerson> protectedPersons;
  final List<Map<String, dynamic>> alerts;

  Object? loadPersonsError;
  Object? removeError;
  Object? acceptError;
  Completer<void>? acceptGate;

  final List<String> removedLinkIds = [];
  final List<(String, String, String)> acceptedInvites = [];

  @override
  Future<List<LinkedProtectedPerson>> getLinkedProtectedPersons() async {
    if (loadPersonsError != null) throw loadPersonsError!;
    return List.of(protectedPersons);
  }

  @override
  Future<void> removeProtectedPersonLink(String linkId) async {
    if (removeError != null) throw removeError!;
    removedLinkIds.add(linkId);
    protectedPersons.removeWhere((person) => person.linkId == linkId);
  }

  @override
  Future<void> acceptInvite(
    String code, {
    required String protectedPersonName,
    required String caregiverName,
  }) async {
    acceptedInvites.add((code, protectedPersonName, caregiverName));
    await acceptGate?.future;
    if (acceptError != null) throw acceptError!;
    protectedPersons.add(
      LinkedProtectedPerson(
        linkId: 'link-${protectedPersons.length + 1}',
        protectedDeviceId: 'device-${protectedPersons.length + 1}',
        protectedDevicePlatform: 'android',
        protectedPersonName: protectedPersonName,
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCaregiverAlerts() async =>
      List.of(alerts);
}

const marie = LinkedProtectedPerson(
  linkId: 'link-1',
  protectedDeviceId: 'protected-device-1',
  protectedDevicePlatform: 'ios',
  protectedPersonName: 'Marie',
);
