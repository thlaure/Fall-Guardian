import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fall_guardian/services/secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fall_guardian/secure_storage');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SecureKeyValueStore', () {
    test('read invokes the native channel with the given key', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return 'stored-value';
      });

      final store = SecureKeyValueStore();
      final value = await store.read('my-key');

      expect(captured?.method, 'read');
      expect(captured?.arguments, {'key': 'my-key'});
      expect(value, 'stored-value');
    });

    test('write invokes the native channel with key and value', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return null;
      });

      final store = SecureKeyValueStore();
      await store.write('my-key', 'my-value');

      expect(captured?.method, 'write');
      expect(captured?.arguments, {'key': 'my-key', 'value': 'my-value'});
    });

    test('delete invokes the native channel with the given key', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return null;
      });

      final store = SecureKeyValueStore();
      await store.delete('my-key');

      expect(captured?.method, 'delete');
      expect(captured?.arguments, {'key': 'my-key'});
    });
  });
}
