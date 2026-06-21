import 'package:caregiver_app/utils/api_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseApiDateTime treats backend timestamps without offset as UTC', () {
    final parsed = parseApiDateTime('2026-06-21T07:41:00');

    expect(parsed, isNotNull);
    expect(parsed!.isUtc, isTrue);
    expect(parsed.toIso8601String(), '2026-06-21T07:41:00.000Z');
  });

  test('parseApiDateTime preserves explicit timezone offsets', () {
    final parsed = parseApiDateTime('2026-06-21T09:41:00+02:00');

    expect(parsed, isNotNull);
    expect(parsed!.toUtc().toIso8601String(), '2026-06-21T07:41:00.000Z');
  });
}
