import 'dart:convert';
import 'dart:io';

import '../../models/activity.dart';
import '../../models/routine.dart';

class RoutineRepository {
  static final _dir = Directory(
    '${Platform.environment['HOME']}/.sitempo',
  );
  static File get _routinesFile => File('${_dir.path}/routines.json');
  static File get _activitiesFile => File('${_dir.path}/activities.json');

  static Future<void> _ensureDir() async {
    if (!await _dir.exists()) await _dir.create(recursive: true);
  }

  // Activities

  static Future<List<Activity>> loadActivities() async {
    if (!await _activitiesFile.exists()) return Activity.defaults.toList();

    final json = await _activitiesFile.readAsString();
    if (json.isEmpty) return Activity.defaults.toList();

    final custom = (jsonDecode(json) as List)
        .map((a) => Activity.fromJson(a as Map<String, dynamic>))
        .toList();

    final defaultIds = Activity.defaults.map((a) => a.id).toSet();
    final onlyCustom = custom.where((a) => !defaultIds.contains(a.id)).toList();

    return [...Activity.defaults, ...onlyCustom];
  }

  static Future<void> saveActivities(List<Activity> activities) async {
    await _ensureDir();
    final custom = activities.where((a) => !a.isDefault).toList();
    await _activitiesFile
        .writeAsString(jsonEncode(custom.map((a) => a.toJson()).toList()));
  }

  // Routines

  static Future<List<Routine>> loadRoutines() async {
    if (!await _routinesFile.exists()) return Routine.defaults;

    final json = await _routinesFile.readAsString();
    if (json.isEmpty) return Routine.defaults;

    final saved = Routine.decode(json);
    final defaultIds = Routine.defaults.map((r) => r.id).toSet();
    final custom = saved.where((r) => !defaultIds.contains(r.id)).toList();

    return [...Routine.defaults, ...custom];
  }

  static Future<void> saveRoutines(List<Routine> routines) async {
    await _ensureDir();
    final custom = routines.where((r) => !r.isDefault).toList();
    await _routinesFile.writeAsString(Routine.encode(custom));
  }
}
