@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitempo/services/platform/window_service_web.dart';

void main() {
  group('WindowService (web)', () {
    test('bringToFront() does not throw and returns Future<void>', () async {
      await expectLater(
        WindowService.bringToFront(),
        completes,
      );
    });
  });
}
