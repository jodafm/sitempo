@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitempo/services/platform/status_bar_service_web.dart';

void main() {
  group('StatusBarService (web)', () {
    // document.title is hard to verify in unit tests — just ensure no throw

    test('update() does not throw', () async {
      await expectLater(
        StatusBarService.update(time: '25:00', emoji: '🍅'),
        completes,
      );
    });

    test('clear() does not throw', () async {
      await expectLater(
        StatusBarService.clear(),
        completes,
      );
    });
  });
}
