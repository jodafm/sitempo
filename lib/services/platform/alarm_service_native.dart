import 'dart:io';

class AlarmService {
  static const _transitionSound = '/System/Library/Sounds/Glass.aiff';
  static const _startSound = '/System/Library/Sounds/Hero.aiff';
  static const _alarmSound = '/System/Library/Sounds/Sosumi.aiff';

  static bool _looping = false;
  static bool _notifLooping = false;

  static const systemSounds = [
    'Glass.aiff',
    'Hero.aiff',
    'Sosumi.aiff',
  ];

  static Directory get _customSoundsDir {
    final home = Platform.environment['HOME']!;
    return Directory('$home/.sitempo/sounds');
  }

  static Future<void> ensureSoundsDir() async {
    final dir = _customSoundsDir;
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  static Future<List<String>> loadCustomSounds() async {
    await ensureSoundsDir();
    final dir = _customSoundsDir;
    final files = await dir.list().toList();
    return files
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.aiff') ||
            f.path.endsWith('.mp3') ||
            f.path.endsWith('.wav') ||
            f.path.endsWith('.m4a'))
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();
  }

  static String resolveSoundPath(String sound) {
    // Check custom dir first
    final customPath = '${_customSoundsDir.path}/$sound';
    if (File(customPath).existsSync()) return customPath;
    // Fall back to system sounds
    return '/System/Library/Sounds/$sound';
  }

  static Future<String?> importSound() async {
    final result = await Process.run('osascript', [
      '-e',
      'set theFile to choose file of type {"public.audio"} with prompt "Elegir sonido"',
      '-e',
      'POSIX path of theFile',
    ]);
    final path = (result.stdout as String).trim();
    if (path.isEmpty) return null;

    await ensureSoundsDir();
    final source = File(path);
    final name = source.uri.pathSegments.last;
    final dest = File('${_customSoundsDir.path}/$name');
    await source.copy(dest.path);
    return name;
  }

  static Future<void> playSoundByName(String sound) async {
    await Process.run('afplay', [resolveSoundPath(sound)]);
  }

  static Future<void> playPreview(String sound) async {
    await Process.run('afplay', [resolveSoundPath(sound)]);
  }

  static Future<void> playTransition() async {
    await Process.run('afplay', [_transitionSound]);
  }

  static Future<void> playStart() async {
    await Process.run('afplay', [_startSound]);
  }

  static Future<void> startLoopingAlarm() async {
    startLoopingAlarmWithPath(_alarmSound);
  }

  static Future<void> startLoopingAlarmWithPath(String path) async {
    stopLoopingAlarm();
    _looping = true;
    _loopPlay(path);
  }

  static Future<void> _loopPlay(String path) async {
    while (_looping) {
      await Process.run('afplay', [path]);
    }
  }

  static void stopLoopingAlarm() {
    _looping = false;
  }

  static Future<void> startNotificationAlert({
    int count = 3,
    String sound = 'Glass.aiff',
  }) async {
    stopNotificationAlert();
    if (count <= 0) return;
    _notifLooping = true;
    _notifLoopPlay(count, resolveSoundPath(sound));
  }

  static Future<void> _notifLoopPlay(int count, String path) async {
    for (var i = 0; i < count && _notifLooping; i++) {
      await Process.run('afplay', [path]);
    }
    _notifLooping = false;
  }

  static void stopNotificationAlert() {
    _notifLooping = false;
  }

  static void markUserGesture() {
    // No-op on native — gesture tracking only needed for web AudioContext
  }
}
