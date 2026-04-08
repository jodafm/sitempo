import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitempo/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sitempo/notifications');

  void setChannelResponse(dynamic response) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkPermission') return response;
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NotificationService.checkPermission()', () {
    test('returns "granted" when channel returns "granted"', () async {
      setChannelResponse('granted');
      final result = await NotificationService.checkPermission();
      expect(result, 'granted');
    });

    test('returns "denied" when channel returns "denied"', () async {
      setChannelResponse('denied');
      final result = await NotificationService.checkPermission();
      expect(result, 'denied');
    });

    test('returns "notDetermined" when channel returns null', () async {
      setChannelResponse(null);
      final result = await NotificationService.checkPermission();
      expect(result, 'notDetermined');
    });

    test('returns "notDetermined" when channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkPermission') {
          throw PlatformException(code: 'ERROR');
        }
        return null;
      });
      final result = await NotificationService.checkPermission();
      expect(result, 'notDetermined');
    });
  });
}
