import 'package:audioplayers/audioplayers.dart';

class AlarmService {
  static const systemSounds = [
    'Glass.aiff',
    'Hero.aiff',
    'Sosumi.aiff',
  ];

  static const _soundMap = {
    'Glass.aiff': 'sounds/glass.m4a',
    'Hero.aiff': 'sounds/hero.m4a',
    'Sosumi.aiff': 'sounds/sosumi.m4a',
  };

  // Separate players for looping alarm vs notification alert
  static AudioPlayer? _loopPlayer;
  static AudioPlayer? _notifPlayer;

  static String resolveSoundPath(String sound) {
    return _soundMap[sound] ?? sound;
  }

  static Future<void> ensureSoundsDir() async {
    // No-op on web — no filesystem access
  }

  static Future<List<String>> loadCustomSounds() async {
    // No filesystem on web
    return [];
  }

  static Future<String?> importSound() async {
    // File picker / copy not supported on web
    return null;
  }

  static Future<void> playSoundByName(String sound) async {
    final player = AudioPlayer();
    await player.play(AssetSource(resolveSoundPath(sound)));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playPreview(String sound) async {
    final player = AudioPlayer();
    await player.play(AssetSource(resolveSoundPath(sound)));
    // Dispose after playback completes
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playTransition() async {
    final player = AudioPlayer();
    await player.play(AssetSource(_soundMap['Glass.aiff']!));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playStart() async {
    final player = AudioPlayer();
    await player.play(AssetSource(_soundMap['Hero.aiff']!));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> startLoopingAlarm() async {
    await startLoopingAlarmWithPath(_soundMap['Sosumi.aiff']!);
  }

  static Future<void> startLoopingAlarmWithPath(String path) async {
    await stopLoopingAlarm();
    _loopPlayer = AudioPlayer();
    await _loopPlayer!.setReleaseMode(ReleaseMode.loop);
    await _loopPlayer!.play(AssetSource(path));
  }

  static Future<void> stopLoopingAlarm() async {
    if (_loopPlayer != null) {
      await _loopPlayer!.stop();
      await _loopPlayer!.dispose();
      _loopPlayer = null;
    }
  }

  static Future<void> startNotificationAlert({
    int count = 3,
    String sound = 'Glass.aiff',
  }) async {
    await stopNotificationAlert();
    if (count <= 0) return;
    _notifPlayer = AudioPlayer();
    final path = resolveSoundPath(sound);
    int played = 0;
    await _notifPlayer!.play(AssetSource(path));
    played++;
    _notifPlayer!.onPlayerComplete.listen((_) async {
      if (_notifPlayer != null && played < count) {
        played++;
        await _notifPlayer!.play(AssetSource(path));
      } else {
        await stopNotificationAlert();
      }
    });
  }

  static Future<void> stopNotificationAlert() async {
    if (_notifPlayer != null) {
      await _notifPlayer!.stop();
      await _notifPlayer!.dispose();
      _notifPlayer = null;
    }
  }

  /// Call this from the first user interaction (button tap, etc.) to unlock
  /// the Web AudioContext — required by browsers before audio can play.
  /// Placeholder: wire to js_interop AudioContext.resume() if needed.
  static void markUserGesture() {
    // No-op placeholder — extend when js_interop AudioContext.resume() is wired
  }
}
