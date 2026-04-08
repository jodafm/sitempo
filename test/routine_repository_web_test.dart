import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitempo/models/activity.dart';
import 'package:sitempo/models/routine.dart';
import 'package:sitempo/services/platform/routine_repository_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RoutineRepository web — routines', () {
    test('loadRoutines returns defaults when key absent', () async {
      final routines = await RoutineRepository.loadRoutines();

      expect(routines.length, greaterThanOrEqualTo(Routine.defaults.length));
      final ids = routines.map((r) => r.id).toList();
      for (final d in Routine.defaults) {
        expect(ids, contains(d.id));
      }
    });

    test('saveRoutines → loadRoutines round-trips custom routine', () async {
      final custom = Routine(
        id: 'custom-test',
        name: 'Test Routine',
        cycle: [
          RoutineStep(
            activityId: 'sitting',
            duration: const Duration(minutes: 30),
          ),
        ],
      );
      final all = [...Routine.defaults, custom];

      await RoutineRepository.saveRoutines(all);
      final loaded = await RoutineRepository.loadRoutines();

      final ids = loaded.map((r) => r.id).toList();
      expect(ids, contains('custom-test'));
      expect(ids, contains('default'));
    });
  });

  group('RoutineRepository web — activities', () {
    test('loadActivities returns defaults when key absent', () async {
      final activities = await RoutineRepository.loadActivities();

      expect(
        activities.length,
        greaterThanOrEqualTo(Activity.defaults.length),
      );
      final ids = activities.map((a) => a.id).toList();
      for (final d in Activity.defaults) {
        expect(ids, contains(d.id));
      }
    });

    test('saveActivities → loadActivities round-trips custom activity',
        () async {
      const custom = Activity(
        id: 'custom-activity',
        label: 'My Activity',
        emoji: '🎯',
        colorValue: 0xFF123456,
      );
      final all = [...Activity.defaults, custom];

      await RoutineRepository.saveActivities(all);
      final loaded = await RoutineRepository.loadActivities();

      final ids = loaded.map((a) => a.id).toList();
      expect(ids, contains('custom-activity'));
      expect(ids, contains('sitting'));
    });
  });
}
