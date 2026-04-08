@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitempo/services/platform/notification_service_web.dart';

void main() {
  group('NotificationService (web)', () {
    test('checkPermission() returns a valid permission string', () async {
      final result = await NotificationService.checkPermission();
      expect(result, anyOf('granted', 'denied', 'notDetermined'));
    });

    test('show() does not throw', () async {
      await expectLater(
        NotificationService.show(title: 'Test', body: 'body'),
        completes,
      );
    });

    test('requestPermission() does not throw', () async {
      await expectLater(
        NotificationService.requestPermission(),
        completes,
      );
    });
  });
}
