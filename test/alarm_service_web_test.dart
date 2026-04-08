@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitempo/services/platform/alarm_service_web.dart';

void main() {
  group('AlarmService (web)', () {
    // Same systemSounds list on both platforms
    test('systemSounds matches the canonical list', () {
      expect(AlarmService.systemSounds, ['Glass.aiff', 'Hero.aiff', 'Sosumi.aiff']);
    });

    // No filesystem on web → empty list
    test('loadCustomSounds() returns empty list', () async {
      final sounds = await AlarmService.loadCustomSounds();
      expect(sounds, isEmpty);
    });

    // No file picker on web → null
    test('importSound() returns null', () async {
      final result = await AlarmService.importSound();
      expect(result, isNull);
    });

    // Path resolution for system sounds
    test('resolveSoundPath maps Glass.aiff to assets/sounds/glass.wav', () {
      expect(AlarmService.resolveSoundPath('Glass.aiff'), 'assets/sounds/glass.wav');
    });

    test('resolveSoundPath maps Hero.aiff to assets/sounds/hero.wav', () {
      expect(AlarmService.resolveSoundPath('Hero.aiff'), 'assets/sounds/hero.wav');
    });

    test('resolveSoundPath maps Sosumi.aiff to assets/sounds/sosumi.wav', () {
      expect(AlarmService.resolveSoundPath('Sosumi.aiff'), 'assets/sounds/sosumi.wav');
    });

    // Custom sounds fall back to the sound name itself
    test('resolveSoundPath returns sound name as-is for unknown sounds', () {
      expect(AlarmService.resolveSoundPath('custom.mp3'), 'custom.mp3');
    });
  });
}
