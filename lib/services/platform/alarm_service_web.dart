import 'package:audioplayers/audioplayers.dart';
import 'package:web/web.dart' as web;

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

  // Custom sounds stored as blob URLs in memory
  static final Map<String, String> _customSoundUrls = {};

  static AudioPlayer? _loopPlayer;
  static AudioPlayer? _notifPlayer;

  static String resolveSoundPath(String sound) {
    return _soundMap[sound] ?? sound;
  }

  static Future<void> ensureSoundsDir() async {}

  static Future<List<String>> loadCustomSounds() async {
    return _customSoundUrls.keys.toList();
  }

  static Future<String?> importSound() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'audio/*';

    input.click();

    // Wait for file selection
    final completer = _FileCompleter();
    input.onChange.listen((_) {
      final files = input.files;
      if (files != null && files.length > 0) {
        final file = files.item(0)!;
        final url = web.URL.createObjectURL(file);
        final name = file.name;
        _customSoundUrls[name] = url;
        completer.complete(name);
      } else {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  static Source _sourceFor(String sound) {
    // Check custom sounds first (blob URLs)
    final blobUrl = _customSoundUrls[sound];
    if (blobUrl != null) return UrlSource(blobUrl);
    // System sound → bundled asset
    return AssetSource(resolveSoundPath(sound));
  }

  static Future<void> playSoundByName(String sound) async {
    final player = AudioPlayer();
    await player.play(_sourceFor(sound));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playPreview(String sound) async {
    final player = AudioPlayer();
    await player.play(_sourceFor(sound));
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
    await startLoopingAlarmWithPath('Sosumi.aiff');
  }

  static Future<void> startLoopingAlarmWithPath(String path) async {
    await stopLoopingAlarm();
    _loopPlayer = AudioPlayer();
    await _loopPlayer!.setReleaseMode(ReleaseMode.loop);
    await _loopPlayer!.play(_sourceFor(path));
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
    final source = _sourceFor(sound);
    int played = 0;
    await _notifPlayer!.play(source);
    played++;
    _notifPlayer!.onPlayerComplete.listen((_) async {
      if (_notifPlayer != null && played < count) {
        played++;
        await _notifPlayer!.play(source);
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

  static void markUserGesture() {}
}

/// Simple completer wrapper to avoid importing dart:async complexity
class _FileCompleter {
  String? _result;
  bool _done = false;
  final List<void Function()> _callbacks = [];

  void complete(String? value) {
    _result = value;
    _done = true;
    for (final cb in _callbacks) {
      cb();
    }
  }

  Future<String?> get future async {
    if (_done) return _result;
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 100));
      return !_done;
    });
    return _result;
  }
}
