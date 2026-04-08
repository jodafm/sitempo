import '../models/reminder.dart';
import 'notification_service.dart';

class ReminderService {
  List<Reminder> _reminders = [];
  final Map<String, int> _elapsedSeconds = {};
  final Set<String> _completedIds = {};

  Set<String> get completedIds => _completedIds;

  void Function(Reminder)? onFire;

  void load(List<Reminder> reminders) {
    _reminders = reminders;
    for (final r in reminders) {
      _elapsedSeconds.putIfAbsent(r.id, () => 0);
    }
  }

  void tick() {
    for (final reminder in _reminders) {
      if (!reminder.enabled) continue;
      if (_completedIds.contains(reminder.id)) continue;
      if (!reminder.isInTimeWindow()) continue;

      final elapsed = (_elapsedSeconds[reminder.id] ?? 0) + 1;
      _elapsedSeconds[reminder.id] = elapsed;

      if (elapsed >= reminder.intervalMinutes * 60) {
        _elapsedSeconds[reminder.id] = 0;
        _fire(reminder);
      }
    }
  }

  void complete(String id) {
    _completedIds.add(id);
    _elapsedSeconds[id] = 0;
  }

  void syncCompletedIds(Set<String> ids) {
    _completedIds
      ..clear()
      ..addAll(ids);
  }

  void reset() {
    _elapsedSeconds.updateAll((_, _) => 0);
    _completedIds.clear();
  }

  void _fire(Reminder reminder) {
    NotificationService.show(
      title: '${reminder.emoji} ${reminder.label}',
      body: reminder.description,
    );
    onFire?.call(reminder);
    if (!reminder.repeat) {
      complete(reminder.id);
    }
  }
}
