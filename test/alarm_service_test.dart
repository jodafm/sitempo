import 'package:flutter_test/flutter_test.dart';
import 'package:sitempo/services/alarm_service.dart';

// We can't mock Process.start directly in Dart unit tests without dependency
// injection, so we test the observable state via the public API.
// The tests verify that:
//   1. stopLoopingAlarm() when no process is running is a no-op (no throw)
//   2. The public API contract is satisfied at the type level

void main() {
  group('AlarmService — looping alarm', () {
    // AC-F4-alarm-1: stopLoopingAlarm when null is a no-op
    test('stopLoopingAlarm() does not throw when no alarm is running', () {
      expect(() => AlarmService.stopLoopingAlarm(), returnsNormally);
    });

    // AC-F4-alarm-2: startLoopingAlarm returns a Future (fire-and-forget safe)
    test('startLoopingAlarm() returns a Future', () {
      final result = AlarmService.startLoopingAlarm();
      expect(result, isA<Future<void>>());
      // We do NOT await here because 'afplay' may not be available in CI.
      // The important contract is that the method returns a Future.
    });

    // AC-F4-alarm-3: stopLoopingAlarm() after startLoopingAlarm() does not throw
    test('stopLoopingAlarm() can be called after startLoopingAlarm() without throwing', () async {
      // Start alarm (will try afplay, may fail on CI — that's OK, we catch below)
      try {
        // Ignoring the future intentionally: we just want to test stop
        AlarmService.startLoopingAlarm();
      } catch (_) {
        // afplay not available is not the concern of this test
      }
      // Immediately stop — should never throw regardless of process state
      expect(() => AlarmService.stopLoopingAlarm(), returnsNormally);
    });
  });
}
