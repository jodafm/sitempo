import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/activity.dart';
import '../../models/routine.dart';

class RoutineRepository {
  static const _routinesKey = 'sitempo_routines';
  static const _activitiesKey = 'sitempo_activities';

  // Activities

  static Future<List<Activity>> loadActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activitiesKey);

    if (raw == null || raw.isEmpty) return Activity.defaults.toList();

    final custom = (jsonDecode(raw) as List)
        .map((a) => Activity.fromJson(a as Map<String, dynamic>))
        .toList();

    final defaultIds = Activity.defaults.map((a) => a.id).toSet();
    final onlyCustom = custom.where((a) => !defaultIds.contains(a.id)).toList();

    return [...Activity.defaults, ...onlyCustom];
  }

  static Future<void> saveActivities(List<Activity> activities) async {
    final prefs = await SharedPreferences.getInstance();
    final custom = activities.where((a) => !a.isDefault).toList();
    await prefs.setString(
      _activitiesKey,
      jsonEncode(custom.map((a) => a.toJson()).toList()),
    );
  }

  // Routines

  static Future<List<Routine>> loadRoutines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_routinesKey);

    if (raw == null || raw.isEmpty) return Routine.defaults;

    final saved = Routine.decode(raw);
    final defaultIds = Routine.defaults.map((r) => r.id).toSet();
    final custom = saved.where((r) => !defaultIds.contains(r.id)).toList();

    return [...Routine.defaults, ...custom];
  }

  static Future<void> saveRoutines(List<Routine> routines) async {
    final prefs = await SharedPreferences.getInstance();
    final custom = routines.where((r) => !r.isDefault).toList();
    await prefs.setString(_routinesKey, Routine.encode(custom));
  }
}
