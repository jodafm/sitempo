import 'dart:convert';

import 'activity.dart';

class RoutineStep {
  final String activityId;
  final Duration duration;
  final String description;

  const RoutineStep({
    required this.activityId,
    required this.duration,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
        'activityId': activityId,
        'durationMinutes': duration.inMinutes,
        if (description.isNotEmpty) 'description': description,
      };

  factory RoutineStep.fromJson(Map<String, dynamic> json) => RoutineStep(
        activityId: json['activityId'] as String,
        duration: Duration(minutes: json['durationMinutes'] as int),
        description: json['description'] as String? ?? '',
      );

  Activity resolveActivity(List<Activity> activities) =>
      activities.firstWhere((a) => a.id == activityId,
          orElse: () => Activity.defaults.first);
}

class Routine {
  final String id;
  final String name;
  final List<RoutineStep> cycle;
  final int repeatCount;
  final RoutineStep? breakStep;
  final bool isDefault;
  final bool autoAdvance;
  final String transitionSound;

  const Routine({
    required this.id,
    required this.name,
    required this.cycle,
    this.repeatCount = 1,
    this.breakStep,
    this.isDefault = false,
    this.autoAdvance = false,
    this.transitionSound = 'Glass.aiff',
  });

  List<RoutineStep> get expandedSteps {
    final steps = <RoutineStep>[];
    for (var i = 0; i < repeatCount; i++) {
      steps.addAll(cycle);
    }
    if (breakStep != null) steps.add(breakStep!);
    return steps;
  }

  int get totalMinutes =>
      expandedSteps.fold(0, (sum, s) => sum + s.duration.inMinutes);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cycle': cycle.map((s) => s.toJson()).toList(),
        'repeatCount': repeatCount,
        'breakStep': breakStep?.toJson(),
        'isDefault': isDefault,
        'autoAdvance': autoAdvance,
        'transitionSound': transitionSound,
      };

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
        id: json['id'] as String,
        name: json['name'] as String,
        cycle: (json['cycle'] as List)
            .map((s) => RoutineStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        repeatCount: json['repeatCount'] as int? ?? 1,
        breakStep: json['breakStep'] != null
            ? RoutineStep.fromJson(json['breakStep'] as Map<String, dynamic>)
            : null,
        isDefault: json['isDefault'] as bool? ?? false,
        autoAdvance: json['autoAdvance'] as bool? ?? false,
        transitionSound: json['transitionSound'] as String? ?? 'Glass.aiff',
      );

  Routine copyWith({
    String? name,
    List<RoutineStep>? cycle,
    int? repeatCount,
    RoutineStep? Function()? breakStep,
    bool? autoAdvance,
    String? transitionSound,
  }) =>
      Routine(
        id: id,
        name: name ?? this.name,
        cycle: cycle ?? this.cycle,
        repeatCount: repeatCount ?? this.repeatCount,
        breakStep: breakStep != null ? breakStep() : this.breakStep,
        isDefault: isDefault,
        autoAdvance: autoAdvance ?? this.autoAdvance,
        transitionSound: transitionSound ?? this.transitionSound,
      );

  static String encode(List<Routine> routines) =>
      jsonEncode(routines.map((r) => r.toJson()).toList());

  static List<Routine> decode(String json) => (jsonDecode(json) as List)
      .map((r) => Routine.fromJson(r as Map<String, dynamic>))
      .toList();

  static List<Routine> defaults = [
    Routine(
      id: 'default',
      name: 'Sentado / De pie',
      isDefault: true,
      cycle: [
        RoutineStep(activityId: 'sitting', duration: Duration(minutes: 45)),
        RoutineStep(activityId: 'standing', duration: Duration(minutes: 15)),
      ],
    ),
  ];
}
