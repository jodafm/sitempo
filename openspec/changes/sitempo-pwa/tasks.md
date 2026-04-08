# Tasks: sitempo-pwa

> **Change**: sitempo-pwa — PWA support alongside macOS native
> **Strategy**: 7 phases, each independently shippable, TDD within each phase
> **Phases**: A (Scaffold) → B (Repositories) → C (AlarmService) → D (NotificationService) → E (StatusBar+Window) → F (Inline fixes) → G (PWA polish)

---

## Task 1: Add web platform scaffold
- Phase: A
- Effort: S
- Depends on: none
- Files: `web/index.html`, `web/manifest.json`, `web/favicon.png` (generated)
- Acceptance: REQ-024
- Description: Run `flutter create --platforms web .` from the project root. This generates the `web/` directory with `index.html`, a default `manifest.json`, `flutter_service_worker.js` bootstrap script, and `favicon.png`. Do NOT modify any generated files yet — that happens in Task 16. Verify `web/` dir exists and `flutter build web --no-tree-shake-icons` exits 0 (even if the app crashes at runtime due to platform code — compile success is enough for this task).

---

## Task 2: Add packages to pubspec.yaml
- Phase: A
- Effort: XS
- Depends on: Task 1
- Files: `pubspec.yaml`
- Acceptance: REQ-025
- Description: Add three packages under `dependencies`:
  - `http: ^1.4.0`
  - `shared_preferences: ^2.5.0`
  - `audioplayers: ^6.4.0`
  Do not remove any existing package. Run `flutter pub get` and confirm it resolves cleanly on macOS.

---

## Task 3: Bundle web sound assets
- Phase: A
- Effort: S
- Depends on: Task 1
- Files: `assets/sounds/glass.mp3`, `assets/sounds/hero.mp3`, `assets/sounds/sosumi.mp3`, `pubspec.yaml`
- Acceptance: REQ-024 AC3
- Description: Source or convert mp3 equivalents of the three macOS system sounds (Glass, Hero, Sosumi). Place them as `assets/sounds/glass.mp3`, `assets/sounds/hero.mp3`, `assets/sounds/sosumi.mp3`. Declare the asset directory in `pubspec.yaml`:
  ```yaml
  flutter:
    assets:
      - assets/sounds/
  ```
  Confirm `flutter pub get` succeeds. Files must exist at these exact paths — `audioplayers` on web resolves `AssetSource('sounds/glass.mp3')` to this directory automatically.

---

## Task 4: Write tests for RoutineRepository web implementation
- Phase: B
- Effort: S
- Depends on: Task 2
- Files: `test/routine_repository_web_test.dart`
- Acceptance: REQ-019 AC1, AC2
- Description: Write unit tests for the web RoutineRepository contract using `shared_preferences` with `SharedPreferences.setMockInitialValues({})`. Tests must cover:
  - `loadRoutines()` returns `Routine.defaults` when `sitempo_routines` key is absent.
  - `saveRoutines([custom])` then `loadRoutines()` returns custom merged with defaults.
  - `loadActivities()` returns `Activity.defaults` when `sitempo_activities` key is absent.
  - `saveActivities([custom])` then `loadActivities()` returns custom merged with defaults.
  Tests should import the future web implementation path directly (or use a shared interface). All tests must FAIL before Task 5.

---

## Task 5: Write tests for ReminderRepository web implementation
- Phase: B
- Effort: S
- Depends on: Task 2
- Files: `test/reminder_repository_web_test.dart`
- Acceptance: REQ-019 AC4
- Description: Write unit tests for the web ReminderRepository contract. Tests must cover:
  - `load()` returns `Reminder.defaults` when `sitempo_reminders` key is absent.
  - `save([reminders])` then `load()` returns saved reminders merged with defaults.
  - Deduplication: if a default reminder id is saved with modified `enabled`, `load()` respects the saved `enabled` value.
  All tests must FAIL before Task 6.

---

## Task 6: Implement RoutineRepository web + barrel
- Phase: B
- Effort: M
- Depends on: Task 4
- Files:
  - `lib/services/platform/routine_repository_native.dart` (new)
  - `lib/services/platform/routine_repository_web.dart` (new)
  - `lib/services/routine_repository.dart` (modified → barrel)
- Acceptance: REQ-019 AC1, AC2, AC3
- Description:
  1. Create `lib/services/platform/routine_repository_native.dart`: move ALL current `routine_repository.dart` logic here verbatim (same class name `RoutineRepository`, same static methods).
  2. Create `lib/services/platform/routine_repository_web.dart`: implement `RoutineRepository` using `shared_preferences`. Store routines under `sitempo_routines`, activities under `sitempo_activities`. Apply identical merge/deduplication logic as native. Must NOT import `dart:io` or reference `Platform`.
  3. Replace `lib/services/routine_repository.dart` with a barrel:
     ```dart
     export 'platform/routine_repository_native.dart'
         if (dart.library.js_interop) 'platform/routine_repository_web.dart';
     ```
  All existing callers import the barrel — no import changes needed in screens. Run Task 4 tests → must pass.

---

## Task 7: Implement ReminderRepository web + barrel
- Phase: B
- Effort: M
- Depends on: Task 5
- Files:
  - `lib/services/platform/reminder_repository_native.dart` (new)
  - `lib/services/platform/reminder_repository_web.dart` (new)
  - `lib/services/reminder_repository.dart` (modified → barrel)
- Acceptance: REQ-019 AC4
- Description:
  1. Create `lib/services/platform/reminder_repository_native.dart`: move ALL current `reminder_repository.dart` logic verbatim.
  2. Create `lib/services/platform/reminder_repository_web.dart`: `SharedPreferences` backed, key `sitempo_reminders`. Same merge logic (defaults + saved enabled state + custom). Must NOT import `dart:io`.
  3. Replace `lib/services/reminder_repository.dart` with a barrel:
     ```dart
     export 'platform/reminder_repository_native.dart'
         if (dart.library.js_interop) 'platform/reminder_repository_web.dart';
     ```
  Run Task 5 tests → must pass. Verify macOS tests still pass.

---

## Task 8: Write tests for AlarmService web implementation
- Phase: C
- Effort: S
- Depends on: Task 3
- Files: `test/alarm_service_web_test.dart`
- Acceptance: REQ-018 AC2, AC3, AC4, AC5
- Description: Write unit tests for the web AlarmService contract. Mock `AudioPlayer` or use a test double. Tests must cover:
  - `playStart()` before `markUserGesture()` does NOT call `AudioPlayer.play()` (no-op, no exception).
  - `markUserGesture()` then `playStart()` calls `AudioPlayer.play()`.
  - `startLoopingAlarmWithPath(path)` starts looping (ReleaseMode.loop).
  - `stopLoopingAlarm()` calls `player.stop()`.
  - `loadCustomSounds()` returns `[]`.
  - `resolveSoundPath('Glass.aiff')` returns `'assets/sounds/glass.mp3'` (or equivalent asset URL).
  All tests must FAIL before Task 9.

---

## Task 9: Implement AlarmService web + barrel
- Phase: C
- Effort: M
- Depends on: Task 8
- Files:
  - `lib/services/platform/alarm_service_native.dart` (new)
  - `lib/services/platform/alarm_service_web.dart` (new)
  - `lib/services/alarm_service.dart` (modified → barrel)
- Acceptance: REQ-018 AC1–AC5
- Description:
  1. Create `lib/services/platform/alarm_service_native.dart`: move ALL current `alarm_service.dart` logic verbatim. Add `playTransition(String path)` method: `Process.run('afplay', [path])`. Add `markUserGesture()` as a no-op static method.
  2. Create `lib/services/platform/alarm_service_web.dart`:
     - Static `_gestureReceived = false`; `markUserGesture()` sets it to true.
     - All play methods guard on `_gestureReceived`; if false, log warning and return.
     - `resolveSoundPath(String sound)`: maps `'Glass.aiff'` → `'assets/sounds/glass.mp3'`, `'Hero.aiff'` → `'assets/sounds/hero.mp3'`, `'Sosumi.aiff'` → `'assets/sounds/sosumi.mp3'`.
     - `playStart()`: `AudioPlayer().play(AssetSource('sounds/hero.mp3'))`.
     - `playTransition(String path)`: `AudioPlayer().play(AssetSource('sounds/glass.mp3'))` (path ignored on web).
     - `startLoopingAlarmWithPath(String path)`: `_loopPlayer.setReleaseMode(ReleaseMode.loop); _loopPlayer.play(...)`.
     - `stopLoopingAlarm()`: `_loopPlayer.stop()`.
     - `startNotificationAlert({int count, String sound})`: play sound `count` times sequentially.
     - `loadCustomSounds()`: returns `[]`.
     - `importSound()`: returns `null`.
  3. Replace `lib/services/alarm_service.dart` with a barrel:
     ```dart
     export 'platform/alarm_service_native.dart'
         if (dart.library.js_interop) 'platform/alarm_service_web.dart';
     ```
  Run Task 8 tests → must pass. Run existing `alarm_service_test.dart` → must still pass.

---

## Task 10: Write tests for NotificationService web implementation
- Phase: D
- Effort: S
- Depends on: Task 2
- Files: `test/notification_service_web_test.dart`
- Acceptance: REQ-020 AC1, AC2, AC3, AC4; REQ-023 AC4, AC5
- Description: Write unit tests for the web NotificationService. Mock the `web` package Notification API or test at the contract level. Tests must cover:
  - `checkPermission()` maps `'granted'` → `'authorized'`, `'denied'` → `'denied'`, `'default'` → `'notDetermined'`.
  - `requestPermission()` returns `true` when browser grants.
  - `show(title: 'X')` is a no-op (no exception) when permission is not granted.
  - `openSystemSettings()` calls `requestPermission()` on web (not `Process.run`).
  All tests must FAIL before Task 11.

---

## Task 11: Implement NotificationService web + barrel
- Phase: D
- Effort: M
- Depends on: Task 10
- Files:
  - `lib/services/platform/notification_service_native.dart` (new)
  - `lib/services/platform/notification_service_web.dart` (new)
  - `lib/services/notification_service.dart` (modified → barrel)
- Acceptance: REQ-020 AC1–AC4
- Description:
  1. Create `lib/services/platform/notification_service_native.dart`: move all current `notification_service.dart` MethodChannel logic verbatim. Add `openSystemSettings()`: `Process.run('open', ['x-apple.systempreferences:com.apple.preference.notifications'])`.
  2. Create `lib/services/platform/notification_service_web.dart` using `package:web`:
     - `checkPermission()`: reads `Notification.permission`, maps to the native string format.
     - `requestPermission()`: calls `Notification.requestPermission()`, returns `true` if result is `'granted'`.
     - `show({title, body})`: creates `Notification(title, ...)` only if `Notification.permission == 'granted'`; silently no-ops otherwise.
     - `openSystemSettings()`: calls `requestPermission()` (browser prompt instead of OS settings).
     - Must NOT import `package:flutter/services.dart`.
  3. Replace `lib/services/notification_service.dart` with a barrel:
     ```dart
     export 'platform/notification_service_native.dart'
         if (dart.library.js_interop) 'platform/notification_service_web.dart';
     ```
  Run Task 10 tests → must pass. Run existing `notification_service_test.dart` → must still pass.

---

## Task 12: Write tests for StatusBarService web implementation
- Phase: E
- Effort: XS
- Depends on: Task 2
- Files: `test/status_bar_service_web_test.dart`
- Acceptance: REQ-021 AC1, AC2
- Description: Write unit tests for the web StatusBarService. Since `document.title` is a browser API, test at the contract level by verifying the method doesn't throw and (if mockable) that the title string is formed correctly: `'{emoji} {time} — sitempo'` for `update()` and `'sitempo'` for `clear()`. All tests must FAIL before Task 13.

---

## Task 13: Implement StatusBarService web + barrel
- Phase: E
- Effort: S
- Depends on: Task 12
- Files:
  - `lib/services/platform/status_bar_service_native.dart` (new)
  - `lib/services/platform/status_bar_service_web.dart` (new)
  - `lib/services/status_bar_service.dart` (modified → barrel)
- Acceptance: REQ-021 AC1, AC2, AC3
- Description:
  1. Create `lib/services/platform/status_bar_service_native.dart`: move all current MethodChannel logic verbatim.
  2. Create `lib/services/platform/status_bar_service_web.dart` using `package:web`:
     - `update({time, emoji})`: `document.title = '$emoji $time — sitempo'`.
     - `clear()`: `document.title = 'sitempo'`.
     - Must NOT import `package:flutter/services.dart`. Must NOT throw.
  3. Replace `lib/services/status_bar_service.dart` with a barrel:
     ```dart
     export 'platform/status_bar_service_native.dart'
         if (dart.library.js_interop) 'platform/status_bar_service_web.dart';
     ```
  Run Task 12 tests → must pass.

---

## Task 14: Write tests for WindowService web implementation
- Phase: E
- Effort: XS
- Depends on: Task 2
- Files: `test/window_service_web_test.dart`
- Acceptance: REQ-022 AC1
- Description: Write a unit test verifying that `WindowService.bringToFront()` on web does not throw and returns a `Future<void>`. This is primarily a contract test since `window.focus()` cannot be meaningfully tested in unit tests. Test must FAIL before Task 15.

---

## Task 15: Implement WindowService web + barrel
- Phase: E
- Effort: XS
- Depends on: Task 14
- Files:
  - `lib/services/platform/window_service_native.dart` (new)
  - `lib/services/platform/window_service_web.dart` (new)
  - `lib/services/window_service.dart` (modified → barrel)
- Acceptance: REQ-022 AC1, AC2
- Description:
  1. Create `lib/services/platform/window_service_native.dart`: move current MethodChannel logic verbatim.
  2. Create `lib/services/platform/window_service_web.dart`:
     - `bringToFront()`: attempt `window.focus()` via `package:web` as best-effort; must not throw.
  3. Replace `lib/services/window_service.dart` with a barrel:
     ```dart
     export 'platform/window_service_native.dart'
         if (dart.library.js_interop) 'platform/window_service_web.dart';
     ```
  Run Task 14 tests → must pass. Run existing `window_service_test.dart` → must still pass.

---

## Task 16: Write test for timer_screen _playTransitionSound fix
- Phase: F
- Effort: S
- Depends on: Task 9
- Files: `test/timer_screen_test.dart` (modify)
- Acceptance: REQ-023 AC1, AC2
- Description: Add a test (or extend existing) verifying that `_playTransitionSound()` delegates to `AlarmService.playTransition(path)` rather than calling `Process.run` directly. Use a mock or stub for `AlarmService` if the existing test harness supports it. Test must FAIL before Task 17.

---

## Task 17: Fix timer_screen.dart — replace Process.run('afplay') with AlarmService.playTransition
- Phase: F
- Effort: XS
- Depends on: Task 16
- Files: `lib/screens/timer_screen.dart`
- Acceptance: REQ-023 S6a, AC1, AC2
- Description: In `_playTransitionSound()` (line ~171), replace:
  ```dart
  Process.run('afplay', [path]);
  ```
  with:
  ```dart
  AlarmService.playTransition(path);
  ```
  Also add `AlarmService.markUserGesture()` call in the timer start button `onTap` handler, before `AlarmService.playStart()`. Remove any `dart:io` import if it becomes unused after this fix. Run Task 16 test → must pass.

---

## Task 18: Write test for timer_screen _fireWebhook http fix
- Phase: F
- Effort: S
- Depends on: Task 2
- Files: `test/timer_screen_test.dart` (modify)
- Acceptance: REQ-023 S6b, AC3
- Description: Add a test verifying that `_fireWebhook` uses `http.post(...)` (from `package:http`) rather than `dart:io HttpClient`. Mock the `http.Client` to verify the call includes the correct `Content-Type` header and JSON body. Test must FAIL before Task 19.

---

## Task 19: Fix timer_screen.dart — replace HttpClient with http package
- Phase: F
- Effort: S
- Depends on: Task 18
- Files: `lib/screens/timer_screen.dart`
- Acceptance: REQ-023 S6b, AC3; REQ-025
- Description: In `_fireWebhook` (line ~1113), replace the entire `HttpClient` block with:
  ```dart
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json; charset=utf-8'},
    body: body,
  );
  final ok = response.statusCode >= 200 && response.statusCode < 300;
  ```
  Add `import 'package:http/http.dart' as http;` at the top. Remove `import 'dart:io'` if it is no longer used (verify there are no other `dart:io` usages in this file). Preserve all existing status-update logic around the response. Run Task 18 test → must pass.

---

## Task 20: Write test for reminder_list_screen _openNotificationSettings fix
- Phase: F
- Effort: S
- Depends on: Task 11
- Files: `test/reminder_list_screen_test.dart` (modify)
- Acceptance: REQ-023 S6c, AC4, AC5
- Description: Add a test verifying that `_openNotificationSettings()` delegates to `NotificationService.openSystemSettings()` rather than calling `Process.run('open', ...)` directly. Test must FAIL before Task 21.

---

## Task 21: Fix reminder_list_screen.dart — replace Process.run with NotificationService.openSystemSettings
- Phase: F
- Effort: XS
- Depends on: Task 20
- Files: `lib/screens/reminder_list_screen.dart`
- Acceptance: REQ-023 S6c, AC4, AC5
- Description: In `_openNotificationSettings()` (line ~61), replace:
  ```dart
  await Process.run('open', ['x-apple.systempreferences:com.apple.preference.notifications']);
  ```
  with:
  ```dart
  await NotificationService.openSystemSettings();
  ```
  Remove `dart:io` import if no longer used. Verify `NotificationService` is already imported (it is). Run Task 20 test → must pass.

---

## Task 22: Configure PWA manifest
- Phase: G
- Effort: S
- Depends on: Task 1
- Files: `web/manifest.json`, `web/index.html`
- Acceptance: REQ-024 AC1
- Description: Update `web/manifest.json` with the required PWA fields:
  ```json
  {
    "name": "sitempo",
    "short_name": "sitempo",
    "start_url": "/",
    "display": "standalone",
    "background_color": "#1a1a2e",
    "theme_color": "#1a1a2e",
    "icons": [
      { "src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png" },
      { "src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png" }
    ]
  }
  ```
  Verify `web/index.html` has `<link rel="manifest" href="manifest.json">` (should be generated by scaffold). If icons don't exist, create placeholder PNGs or reuse Flutter's default generated icons.

---

## Task 23: Verify flutter build web succeeds
- Phase: G
- Effort: XS
- Depends on: Tasks 1–22
- Files: none (verification only)
- Acceptance: REQ-024, REQ-025 AC2
- Description: Run `flutter build web --no-tree-shake-icons`. Build must exit 0 with no errors. Fix any remaining compilation errors found. This is the integration checkpoint — all platform abstractions must compile cleanly for the web target.

---

## Task 24: Verify flutter build macos still succeeds (regression check)
- Phase: G
- Effort: XS
- Depends on: Task 23
- Files: none (verification only)
- Acceptance: REQ-025 AC1; REQ-019 AC3
- Description: Run `flutter build macos`. Build must exit 0. Run the full test suite (`flutter test`). All tests must pass. This verifies that no native behavior was broken by the conditional import refactor. If any test fails, trace the failure to the specific barrel or platform file and fix before marking this task complete.

---

## Summary

| Phase | Tasks | Files Changed | Key Risk |
|-------|-------|---------------|----------|
| A — Scaffold | 1, 2, 3 | pubspec.yaml, web/, assets/ | flutter create clobbering existing files |
| B — Repositories | 4, 5, 6, 7 | 4 new + 2 modified | shared_preferences merge logic parity |
| C — AlarmService | 8, 9 | 2 new + 1 modified | AudioContext user-gesture gate |
| D — NotificationService | 10, 11 | 2 new + 1 modified | Web Notification API permissions |
| E — StatusBar+Window | 12, 13, 14, 15 | 4 new + 2 modified | document.title API via package:web |
| F — Inline fixes | 16, 17, 18, 19, 20, 21 | 2 modified screens | dart:io removal completeness |
| G — PWA polish | 22, 23, 24 | manifest.json | build regression |

**Total**: 24 tasks — 13 new files, 9 modified files, 6 test files added/extended.

**TDD coverage**:
- Phase A: no tests (setup only)
- Phases B–E: test-before-implementation for every service
- Phase F: test-before-fix for every inline platform call
- Phase G: build verification (integration-level)
