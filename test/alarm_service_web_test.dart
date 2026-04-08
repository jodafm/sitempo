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
    test('resolveSoundPath maps Glass.aiff to sounds/glass.m4a', () {
      expect(AlarmService.resolveSoundPath('Glass.aiff'), 'sounds/glass.m4a');
    });

    test('resolveSoundPath maps Hero.aiff to sounds/hero.m4a', () {
      expect(AlarmService.resolveSoundPath('Hero.aiff'), 'sounds/hero.m4a');
    });

    test('resolveSoundPath maps Sosumi.aiff to sounds/sosumi.m4a', () {
      expect(AlarmService.resolveSoundPath('Sosumi.aiff'), 'sounds/sosumi.m4a');
    });

    // Custom sounds fall back to the sound name itself
    test('resolveSoundPath returns sound name as-is for unknown sounds', () {
      expect(AlarmService.resolveSoundPath('custom.mp3'), 'custom.mp3');
    });
  });
}
