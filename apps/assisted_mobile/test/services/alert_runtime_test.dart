import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fall_guardian/services/alert_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fall_guardian/watch');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('SystemClock.now returns the current time', () {
    final clock = SystemClock();
    final before = DateTime.now();
    final now = clock.now();
    final after = DateTime.now();

    expect(now.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    expect(now.isBefore(after.add(const Duration(seconds: 1))), isTrue);
  });

  test('UuidGenerator.newId returns a non-empty unique id', () {
    const generator = UuidGenerator();

    final first = generator.newId();
    final second = generator.newId();

    expect(first, isNotEmpty);
    expect(first, isNot(second));
  });

  test('DeviceLocaleResolver.languageCode returns the platform locale code',
      () {
    const resolver = DeviceLocaleResolver();

    expect(resolver.languageCode(), isNotEmpty);
  });

  test('DeviceLocaleResolver.resolve returns supported AppLocalizations', () {
    const resolver = DeviceLocaleResolver();

    expect(resolver.resolve(), isNotNull);
  });

  test(
      'DeviceLocaleResolver.resolve falls back to English for an unsupported '
      'device locale', () {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.localeTestValue = const Locale('xx');
    addTearDown(dispatcher.clearLocaleTestValue);

    const resolver = DeviceLocaleResolver();

    expect(resolver.resolve().appTitle, isNotEmpty);
  });

  test('MethodChannelWatchGateway.sendCancelAlert invokes the watch channel',
      () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    const gateway = MethodChannelWatchGateway();
    await gateway.sendCancelAlert();

    expect(captured?.method, 'sendCancelAlert');
  });
}
