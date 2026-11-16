import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/services/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'only HTTPS web addresses without credentials reach the native launcher',
    () async {
      const channel = MethodChannel('com.gpscamera.gps_camera_next/platform');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      for (final url in [
        'javascript:alert(1)',
        'file:///private/file',
        'http://example.com',
        'https://user:password@example.com',
        'https:///policy',
      ]) {
        expect(await Native.openWebPage(url), isFalse);
      }
      expect(calls, isEmpty);
      expect(await Native.openWebPage('https://example.com/privacy'), isTrue);
      expect(calls.single.method, 'openWebPage');
      expect(calls.single.arguments, {'url': 'https://example.com/privacy'});
    },
  );
}
