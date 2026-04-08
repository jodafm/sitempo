import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitempo/models/reminder.dart';
import 'package:sitempo/services/platform/reminder_repository_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ReminderRepository web', () {
    test('load() returns empty list when key absent', () async {
      final reminders = await ReminderRepository.load();

      expect(reminders, isEmpty);
    });

    test('save → load round-trips correctly', () async {
      final reminders = [
        const Reminder(
          id: 'r1',
          emoji: '💧',
          label: 'Agua',
          intervalMinutes: 60,
        ),
        const Reminder(
          id: 'r2',
          emoji: '👀',
          label: 'Descanso visual',
          intervalMinutes: 20,
        ),
      ];

      await ReminderRepository.save(reminders);
      final loaded = await ReminderRepository.load();

      expect(loaded.length, 2);
      expect(loaded[0].id, 'r1');
      expect(loaded[0].label, 'Agua');
      expect(loaded[1].id, 'r2');
      expect(loaded[1].label, 'Descanso visual');
    });
  });
}
