import 'dart:convert';
import 'dart:io';

import '../../models/reminder.dart';

class ReminderRepository {
  static final _dir = Directory(
    '${Platform.environment['HOME']}/.sitempo',
  );
  static File get _file => File('${_dir.path}/reminders.json');

  static Future<List<Reminder>> load() async {
    if (!await _file.exists()) return Reminder.defaults.toList();

    final json = await _file.readAsString();
    if (json.isEmpty) return Reminder.defaults.toList();

    final saved = Reminder.decode(json);
    final defaultIds = Reminder.defaults.map((r) => r.id).toSet();

    // Merge: defaults (with saved enabled state) + custom
    final defaults = Reminder.defaults.map((d) {
      final saved_ = saved.where((s) => s.id == d.id).firstOrNull;
      return saved_ != null ? d.copyWith(enabled: saved_.enabled) : d;
    }).toList();

    final custom = saved.where((r) => !defaultIds.contains(r.id)).toList();
    return [...defaults, ...custom];
  }

  static Future<void> save(List<Reminder> reminders) async {
    if (!await _dir.exists()) await _dir.create(recursive: true);
    await _file.writeAsString(
      jsonEncode(reminders.map((r) => r.toJson()).toList()),
    );
  }
}
