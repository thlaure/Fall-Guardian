import 'dart:async';

import 'package:caregiver_app/services/foreground_migration_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not migrate during a background launch', () async {
    var runs = 0;
    final gate = ForegroundMigrationGate(
      migrate: () async {
        runs++;
        return true;
      },
      isForeground: () => false,
    );

    await gate.ensure();

    expect(runs, 0);
    expect(gate.completed, isFalse);
  });

  test('migrates once in the foreground', () async {
    var runs = 0;
    final gate = ForegroundMigrationGate(
      migrate: () async {
        runs++;
        return true;
      },
      isForeground: () => true,
    );

    await gate.ensure();
    await gate.ensure();

    expect(runs, 1);
    expect(gate.completed, isTrue);
  });

  test('retries after a deferred or failed run', () async {
    final results = <Future<bool> Function()>[
      () async => false,
      () async => throw StateError('keychain'),
      () async => true,
    ];
    var runs = 0;
    final gate = ForegroundMigrationGate(
      migrate: () => results[runs++](),
      isForeground: () => true,
    );

    await gate.ensure();
    expect(gate.completed, isFalse);
    await gate.ensure();
    expect(gate.completed, isFalse);
    await gate.ensure();
    expect(gate.completed, isTrue);
    expect(runs, 3);
  });

  test('concurrent callers share a single run', () async {
    var runs = 0;
    final release = Completer<bool>();
    final gate = ForegroundMigrationGate(
      migrate: () {
        runs++;
        return release.future;
      },
      isForeground: () => true,
    );

    final first = gate.ensure();
    final second = gate.ensure();
    release.complete(true);
    await Future.wait([first, second]);

    expect(runs, 1);
  });
}
