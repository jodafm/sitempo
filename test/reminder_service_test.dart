import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitempo/models/reminder.dart';
import 'package:sitempo/services/reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const reminder = Reminder(
    id: 'test-reminder',
    emoji: '💧',
    label: 'Tomar agua',
    intervalMinutes: 1, // 60 seconds
    description: 'Hidratate',
    enabled: true,
  );

  group('ReminderService.onFire callback', () {
    late List<MethodCall> notificationCalls;

    setUp(() {
      notificationCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.sitempo/notifications'),
        (call) async {
          notificationCalls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.sitempo/notifications'),
        null,
      );
    });

    test('onFire is called with correct Reminder when _fire() runs', () {
      final service = ReminderService();
      service.load([reminder]);

      Reminder? firedReminder;
      service.onFire = (r) => firedReminder = r;

      // Tick 59 times — not fired yet
      for (var i = 0; i < 59; i++) {
        service.tick();
      }
      expect(firedReminder, isNull);

      // Tick 60th time — fires
      service.tick();
      expect(firedReminder, isNotNull);
      expect(firedReminder!.id, 'test-reminder');
      expect(firedReminder!.emoji, '💧');
      expect(firedReminder!.label, 'Tomar agua');
    });

    test('NotificationService.show() also fires alongside onFire', () async {
      final service = ReminderService();
      service.load([reminder]);

      Reminder? firedReminder;
      service.onFire = (r) => firedReminder = r;

      // Tick 60 times to trigger _fire()
      for (var i = 0; i < 60; i++) {
        service.tick();
      }

      expect(firedReminder, isNotNull);
      expect(notificationCalls.length, 1);
      expect(notificationCalls[0].method, 'show');
      expect(
        notificationCalls[0].arguments['title'],
        '💧 Tomar agua',
      );
    });

    test('onFire is not called when not set', () {
      final service = ReminderService();
      service.load([reminder]);

      expect(
        () {
          for (var i = 0; i < 60; i++) {
            service.tick();
          }
        },
        returnsNormally,
      );
    });

    test('onFire is not called for disabled reminders', () {
      const disabledReminder = Reminder(
        id: 'disabled',
        emoji: '👀',
        label: 'Disabled',
        intervalMinutes: 1,
        enabled: false,
      );
      final service = ReminderService();
      service.load([disabledReminder]);

      Reminder? firedReminder;
      service.onFire = (r) => firedReminder = r;

      for (var i = 0; i < 60; i++) {
        service.tick();
      }
      expect(firedReminder, isNull);
    });
  });
}
