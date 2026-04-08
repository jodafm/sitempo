import 'package:shared_preferences/shared_preferences.dart';

import '../../models/reminder.dart';

class ReminderRepository {
  static const _remindersKey = 'sitempo_reminders';

  static Future<List<Reminder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_remindersKey);

    if (raw == null || raw.isEmpty) return [];

    return Reminder.decode(raw);
  }

  static Future<void> save(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _remindersKey,
      Reminder.encode(reminders),
    );
  }
}
