import 'package:flutter_test/flutter_test.dart';

import 'package:sitempo/models/activity.dart';
import 'package:sitempo/models/routine.dart';

void main() {
  test('Default routine has correct structure', () {
    expect(Routine.defaults.length, 1);
    expect(Routine.defaults[0].name, 'Sentado / De pie');
    expect(Routine.defaults[0].cycle[0].activityId, 'sitting');
    expect(Routine.defaults[0].cycle[0].duration.inMinutes, 45);
  });

  test('Expanded steps with repeat and break', () {
    final routine = Routine(
      id: 'test',
      name: 'Test',
      cycle: [
        RoutineStep(activityId: 'sitting', duration: Duration(minutes: 45)),
        RoutineStep(activityId: 'movement', duration: Duration(minutes: 2)),
        RoutineStep(activityId: 'standing', duration: Duration(minutes: 13)),
      ],
      repeatCount: 2,
      breakStep:
          RoutineStep(activityId: 'stretching', duration: Duration(minutes: 5)),
    );

    final expanded = routine.expandedSteps;
    expect(expanded.length, 7); // 3 steps × 2 repeats + 1 break
    expect(expanded[0].activityId, 'sitting');
    expect(expanded[3].activityId, 'sitting'); // second cycle
    expect(expanded[6].activityId, 'stretching'); // break
    expect(routine.totalMinutes, 125); // (45+2+13)*2 + 5
  });

  test('Routine serialization roundtrip', () {
    final routine = Routine(
      id: 'test',
      name: 'Custom',
      cycle: [
        RoutineStep(activityId: 'sitting', duration: Duration(minutes: 30)),
      ],
      repeatCount: 3,
      breakStep:
          RoutineStep(activityId: 'walking', duration: Duration(minutes: 5)),
    );

    final json = Routine.encode([routine]);
    final decoded = Routine.decode(json);

    expect(decoded[0].name, 'Custom');
    expect(decoded[0].repeatCount, 3);
    expect(decoded[0].breakStep?.activityId, 'walking');
  });

  test('Activity serialization roundtrip', () {
    final activity = Activity(
      id: 'custom-yoga',
      label: 'Yoga',
      emoji: '🧘',
      colorValue: 0xFF66BB6A,
    );

    final json = activity.toJson();
    final decoded = Activity.fromJson(json);

    expect(decoded.id, 'custom-yoga');
    expect(decoded.label, 'Yoga');
    expect(decoded.emoji, '🧘');
  });
}
