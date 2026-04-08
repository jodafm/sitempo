# Technical Design: sitempo-pwa

## Overview

Abstract all 6 platform-specific services behind interfaces using Flutter's conditional import pattern. Each service becomes a barrel file that exports the correct implementation based on the target platform. Screens import only the barrel — zero `kIsWeb` checks in UI code.

---

## 1. File Structure

```
lib/
  services/
    # Barrel files (the import points — these replace current files)
    alarm_service.dart          → export conditional
    notification_service.dart   → export conditional
    status_bar_service.dart     → export conditional
    window_service.dart         → export conditional
    reminder_repository.dart    → export conditional
    routine_repository.dart     → export conditional

    # Platform implementations
    platform/
      alarm_service_native.dart
      alarm_service_web.dart
      notification_service_native.dart
      notification_service_web.dart
      status_bar_service_native.dart
      status_bar_service_web.dart
      window_service_native.dart
      window_service_web.dart
      reminder_repository_native.dart
      reminder_repository_web.dart
      routine_repository_native.dart
      routine_repository_web.dart

    # Utility (new)
    http_client.dart            → export conditional
    platform/
      http_client_native.dart
      http_client_web.dart

    # Unchanged
    reminder_service.dart       → platform-agnostic, no changes

  models/                       → unchanged (already platform-agnostic)
  screens/                      → minimal changes (import paths stay the same)

web/                            → new (flutter create --platforms web)
  index.html
  manifest.json
  flutter_service_worker.js     → auto-generated
  icons/                        → PWA icons

assets/
  sounds/
    glass.mp3                   → web-compatible versions of macOS system sounds
    hero.mp3
    sosumi.mp3
```

Total new files: **13** (6 native + 6 web + 1 barrel for http_client) + web scaffold
Modified files: **9** (6 service barrels + timer_screen + reminder_list_screen + pubspec)

---

## 2. Conditional Import Pattern

Every barrel file follows the same structure:

```dart
// lib/services/alarm_service.dart
export 'platform/alarm_service_native.dart'
    if (dart.library.js_interop) 'platform/alarm_service_web.dart';
```

**Decision: `dart.library.js_interop` over `dart.library.html`**

`dart.library.html` is deprecated as of Dart 3.4+ (package:web replaces dart:html). The modern conditional is `dart.library.js_interop` which resolves to web targets. Since sitempo uses Dart SDK ^3.11.4, this is the correct choice.

Each platform file defines a class with the SAME name (e.g., `AlarmService`). No abstract class or interface file is needed — the conditional export guarantees only one implementation is compiled. The class name IS the contract.

**Why no abstract interface file?** Flutter's conditional import pattern works by exporting different files that define the same class name. Adding an abstract class would require either:
- `implements` — which forces boilerplate and a separate file
- Runtime polymorphism — unnecessary overhead

The barrel pattern gives compile-time platform resolution with zero runtime cost. The "interface" is implicit: both platform files must expose the same static API surface. If they diverge, the app won't compile on the platform that's missing a method.

---

## 3. Service Contracts & Implementations

### 3.1 AlarmService

**Static API surface** (both platforms must implement all of these):

```dart
class AlarmService {
  static const systemSounds = <String>[...];

  // Sound management
  static Future<void> ensureSoundsDir();
  static Future<List<String>> loadCustomSounds();
  static String resolveSoundPath(String sound);
  static Future<String?> importSound();

  // Playback
  static Future<void> playPreview(String sound);
  static Future<void> playTransition();
  static Future<void> playStart();

  // Looping
  static Future<void> startLoopingAlarm();
  static Future<void> startLoopingAlarmWithPath(String path);
  static void stopLoopingAlarm();

  // Notification alerts
  static Future<void> startNotificationAlert({int count, String sound});
  static void stopNotificationAlert();
}
```

**Native implementation** (`alarm_service_native.dart`):
- Wraps the current code verbatim. Imports `dart:io`.
- `Process.run('afplay', [...])` for playback.
- `Directory`/`File` for custom sounds in `~/.sitempo/sounds/`.
- `Process.run('osascript', [...])` for file picker on import.
- `systemSounds` remains `['Glass.aiff', 'Hero.aiff', 'Sosumi.aiff']`.

**Web implementation** (`alarm_service_web.dart`):

**Package decision: `audioplayers` over `just_audio`**

| Criteria | audioplayers | just_audio |
|----------|-------------|------------|
| Web support | Yes (HTML5 Audio) | Yes (HTML5 Audio) |
| Asset playback | `AudioPlayer().play(AssetSource(...))` | `AudioPlayer().setAsset(...)` |
| Looping | Built-in `setReleaseMode(ReleaseMode.loop)` | Built-in `setLoopMode(LoopMode.one)` |
| Package size | Lighter | Heavier (more features) |
| API complexity | Simpler | More complex |
| macOS native | Available but unnecessary (we keep afplay) | Available |

**Decision: `audioplayers`** — simpler API, lighter, built-in loop mode, good web support. We only need play/loop/stop.

Web implementation details:
- `systemSounds` = `['glass.mp3', 'hero.mp3', 'sosumi.mp3']` (bundled assets).
- `resolveSoundPath(sound)` → returns `'assets/sounds/$sound'` (Flutter asset path). For system sounds, maps `.aiff` names to `.mp3` equivalents (e.g., `Glass.aiff` → `glass.mp3`).
- `playPreview(sound)` → `AudioPlayer().play(AssetSource('sounds/${resolveSoundPath(sound)}'))`.
- `startLoopingAlarmWithPath(path)` → creates `AudioPlayer()`, sets `ReleaseMode.loop`, plays.
- `stopLoopingAlarm()` → calls `stop()` + `dispose()` on the cached player.
- `ensureSoundsDir()` → no-op.
- `loadCustomSounds()` → returns empty list (no custom sounds on web).
- `importSound()` → returns `null` (scoped out — no custom sound import on web).
- `startNotificationAlert({count, sound})` → plays sound `count` times with delay between plays using `AudioPlayer.onPlayerComplete` stream.

**AudioContext user gesture requirement (CRITICAL)**:
- Browsers require a user gesture to unlock AudioContext.
- Timer start (`playStart`) happens on button tap → user gesture present → OK.
- Transition sounds happen after timer reaches zero → no direct gesture → MAY be blocked.
- Reminder alerts fire from background timer → no gesture → WILL be blocked on first play.
- **Mitigation**: The reminder modal is already user-triggered (user sees notification, clicks). The `startNotificationAlert` call in `_handleReminderFire` runs synchronously with the modal show — this should satisfy the gesture requirement. For transition sounds, the timer itself was started by a gesture, and most browsers consider the page "user-activated" after that. We need to verify in testing, but this should work in practice because the AudioContext gets unlocked on first `playStart` and stays unlocked for the session.

### 3.2 ReminderRepository

**Static API surface:**

```dart
class ReminderRepository {
  static Future<List<Reminder>> load();
  static Future<void> save(List<Reminder> reminders);
}
```

**Native implementation** (`reminder_repository_native.dart`):
- Current code verbatim. `dart:io` File I/O to `~/.sitempo/reminders.json`.

**Web implementation** (`reminder_repository_web.dart`):
- Uses `shared_preferences` package.
- `load()` → reads `SharedPreferences.getString('reminders')`, decodes JSON, applies same merge logic with `Reminder.defaults`.
- `save(reminders)` → `SharedPreferences.setString('reminders', jsonEncode(...))`.

### 3.3 RoutineRepository

**Static API surface:**

```dart
class RoutineRepository {
  static Future<List<Activity>> loadActivities();
  static Future<void> saveActivities(List<Activity> activities);
  static Future<List<Routine>> loadRoutines();
  static Future<void> saveRoutines(List<Routine> routines);
}
```

**Native implementation** (`routine_repository_native.dart`):
- Current code verbatim.

**Web implementation** (`routine_repository_web.dart`):
- Same pattern as ReminderRepository web: `shared_preferences` with keys `'routines'` and `'activities'`.
- Same merge/default logic preserved.

### 3.4 NotificationService

**Static API surface:**

```dart
class NotificationService {
  static Future<bool> requestPermission();
  static Future<String> checkPermission();
  static Future<void> show({required String title, String? body});
}
```

**Native implementation** (`notification_service_native.dart`):
- Current code verbatim. MethodChannel to Swift.

**Web implementation** (`notification_service_web.dart`):
- Uses `package:web` (the modern dart:html replacement, already bundled with Flutter SDK).
- `requestPermission()` → `Notification.requestPermission()`, returns `true` if result is `'granted'`.
- `checkPermission()` → reads `Notification.permission` property. Maps: `'granted'` → `'authorized'`, `'denied'` → `'denied'`, `'default'` → `'notDetermined'`.
- `show(title, body)` → `Notification(title, NotificationOptions(body: body))`.
- **HTTPS requirement**: Web Notifications API requires secure context (HTTPS or localhost). Development on localhost works. Production PWA must be served over HTTPS. This is a deployment concern, not a code concern.

### 3.5 StatusBarService

**Static API surface:**

```dart
class StatusBarService {
  static Future<void> update({required String time, required String emoji});
  static Future<void> clear();
}
```

**Native implementation** (`status_bar_service_native.dart`):
- Current code verbatim. MethodChannel to NSStatusItem.

**Web implementation** (`status_bar_service_web.dart`):
- `update(time, emoji)` → `document.title = '$emoji $time — sitempo'`. This makes the browser tab show the timer state.
- `clear()` → `document.title = 'sitempo'`.
- Uses `package:web` for `document.title` access.

### 3.6 WindowService

**Static API surface:**

```dart
class WindowService {
  static Future<void> bringToFront();
}
```

**Native implementation** (`window_service_native.dart`):
- Current code verbatim. MethodChannel.

**Web implementation** (`window_service_web.dart`):
- `bringToFront()` → `window.focus()` via `package:web`. Limited effectiveness (browsers restrict focus stealing), but it's the best available option. No-op if `window.focus()` is blocked.

### 3.7 HttpClient (new service)

**Static API surface:**

```dart
class WebhookClient {
  static Future<WebhookResult> post(Uri uri, String body);
}

class WebhookResult {
  final int statusCode;
  final String? error;
  WebhookResult({required this.statusCode, this.error});
}
```

**Why a separate abstraction instead of just switching packages?**

The current `HttpClient` code in `timer_screen.dart` uses `dart:io`'s streaming API (postUrl → write → close → read status). The `http` package has a simpler API (`http.post(uri, body: ..., headers: ...)`). Rather than force both platforms to use the `http` package (which would change the native code unnecessarily), we create a thin `WebhookClient` wrapper:

**Native implementation** (`http_client_native.dart`):
- Uses `dart:io` `HttpClient` (current code extracted).

**Web implementation** (`http_client_web.dart`):
- Uses `package:http` which works on web.
- `post(uri, body)` → `http.post(uri, headers: {'Content-Type': 'application/json'}, body: body)`.

**Alternative considered**: Use `package:http` on BOTH platforms. This is simpler (one implementation) but adds an unnecessary dependency for macOS native which already works fine with `dart:io`. The conditional import approach is consistent with all other services and keeps native code unchanged.

**Decision**: Actually, on reflection — `package:http` works on BOTH native and web. Using it everywhere eliminates the need for a conditional import for this one service. The tradeoff is adding a package dependency to native that isn't strictly needed. However, the simplicity gain (one file, no abstraction) outweighs the cost of an extra lightweight dependency. **Final decision: use `package:http` directly in `timer_screen.dart`, no conditional import needed.** Replace the `dart:io HttpClient` code with `http.post(...)`. This is the pragmatic choice.

---

## 4. Screen Changes

### 4.1 timer_screen.dart

Changes:
1. **Remove `import 'dart:io'`** — no longer needed after fixes below.
2. **Line 170-171**: Replace `Process.run('afplay', [path])` with `AlarmService.playPreview(_routine.transitionSound)`. This fixes the existing bug where `_playTransitionSound()` bypasses AlarmService and calls `Process.run` directly.
3. **Lines 1113-1118**: Replace `HttpClient` usage with `http.post(...)`. Add `import 'package:http/http.dart' as http;`. The new code:
   ```dart
   final response = await http.post(
     uri,
     headers: {'Content-Type': 'application/json; charset=utf-8'},
     body: body,
   );
   ```
4. All `AlarmService.*` calls remain unchanged — the barrel import resolves correctly.

### 4.2 reminder_list_screen.dart

Changes:
1. **Remove `import 'dart:io'`**.
2. **Lines 60-63**: Replace `Process.run('open', ['x-apple.systempreferences:...'])` with a platform-conditional approach. Since this is the ONLY inline platform check in screens, use a simple method on `NotificationService`:

   Add to NotificationService contract:
   ```dart
   static Future<void> openSettings();
   ```
   - Native: `Process.run('open', ['x-apple.systempreferences:com.apple.preference.notifications'])`
   - Web: no-op (web notifications permissions are managed via browser UI, not openable programmatically). Show a `SnackBar` with instructions: "Check your browser's notification settings."

   This keeps the screen clean — `_openNotificationSettings()` becomes `NotificationService.openSettings()`.

### 4.3 reminder_editor_dialog.dart

No changes needed. All calls go through `AlarmService.*` which resolves via barrel. On web:
- `loadCustomSounds()` returns empty list → no custom sounds section shown.
- `importSound()` returns null → import option does nothing. **Consider**: hide the import button on web. But this requires a `kIsWeb` check. **Decision**: Let `importSound()` return null and the existing `if (name != null)` guard handles it — the button simply does nothing. Acceptable UX for phase 1.
- `playPreview(sound)` works via audioplayers.
- `systemSounds` shows web sound names.

**Sound name mapping issue**: Native uses `Glass.aiff`, web uses `glass.mp3`. The `systemSounds` list differs per platform. Screens reference `AlarmService.systemSounds` which resolves correctly. Saved routines/reminders store the sound name — a routine created on macOS with `Glass.aiff` won't find that file on web. **Decision**: This is acceptable because localStorage (web) and `~/.sitempo/` (native) are separate storage. Data doesn't cross platforms. If cross-platform sync is added later, a migration layer handles name mapping.

### 4.4 routine_editor_screen.dart

No changes needed. Same as reminder_editor_dialog — all calls go through `AlarmService.*`.

---

## 5. Asset Bundling Strategy (Web Sounds)

### 5.1 Sound Files

Create `assets/sounds/` with web-compatible versions:
- `glass.mp3` — equivalent of macOS Glass.aiff
- `hero.mp3` — equivalent of macOS Hero.aiff  
- `sosumi.mp3` — equivalent of macOS Sosumi.aiff

**Source**: These are well-known macOS system sounds. We need to either:
1. Convert from `.aiff` to `.mp3` using ffmpeg: `ffmpeg -i /System/Library/Sounds/Glass.aiff glass.mp3`
2. Find royalty-free equivalents that sound similar

**Decision**: Option 1 — convert directly. The macOS system sounds are bundled with the OS and their use in a personal PWA is fair use. For a public release, option 2 would be safer from a licensing perspective. Flag this for the user to decide.

### 5.2 pubspec.yaml Assets

```yaml
flutter:
  assets:
    - assets/sounds/
```

### 5.3 Flutter Web Asset Resolution

`audioplayers` on web resolves `AssetSource('sounds/glass.mp3')` to the Flutter asset bundle, which maps to `assets/sounds/glass.mp3` in the project. This works automatically with Flutter's web asset bundling — no extra configuration needed.

---

## 6. Package Additions

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^1.4.0              # Cross-platform HTTP client (replaces dart:io HttpClient in timer_screen)
  shared_preferences: ^2.5.0 # Web: localStorage wrapper for repositories
  audioplayers: ^6.4.0       # Web: HTML5 Audio for alarm sounds
```

**Notes:**
- `package:web` is part of the Dart SDK — no pubspec entry needed.
- `shared_preferences` is only used in web implementations but must be in pubspec (it's tree-shaken on native).
- `audioplayers` is only used in web AlarmService but must be in pubspec.
- `http` is used directly in `timer_screen.dart` (both platforms).

---

## 7. Web Scaffold & PWA Configuration

### 7.1 Flutter Web Setup

```bash
flutter create --platforms web .
```

This generates `web/` directory with `index.html`, `manifest.json`, and service worker.

### 7.2 PWA Manifest (`web/manifest.json`)

```json
{
  "name": "sitempo",
  "short_name": "sitempo",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#1A1A2E",
  "theme_color": "#1A1A2E",
  "description": "Pomodoro timer with routines and reminders",
  "orientation": "portrait",
  "prefer_related_applications": false,
  "icons": [
    {
      "src": "icons/Icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "icons/Icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    },
    {
      "src": "icons/Icon-maskable-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "icons/Icon-maskable-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ]
}
```

### 7.3 Service Worker

Flutter's default service worker (`flutter_service_worker.js`) provides offline caching out of the box. No custom service worker needed for phase 1. The generated `index.html` registers it automatically.

### 7.4 Meta Tags (`web/index.html`)

Add to `<head>`:
```html
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="sitempo">
<link rel="apple-touch-icon" href="icons/Icon-192.png">
```

---

## 8. Migration Path (Zero-Breakage Strategy)

### Phase order (each phase is independently shippable):

**Phase A: Scaffold & packages** (no behavior change)
1. `flutter create --platforms web .`
2. Add packages to `pubspec.yaml`
3. Create `assets/sounds/` with converted .mp3 files
4. Add `flutter: assets:` to pubspec
5. **Verify**: `flutter build macos` still works.

**Phase B: Repositories** (lowest risk — pure data layer)
1. Create `platform/reminder_repository_native.dart` — copy current code.
2. Create `platform/reminder_repository_web.dart` — shared_preferences impl.
3. Convert `reminder_repository.dart` to barrel export.
4. Repeat for `routine_repository`.
5. **Verify**: `flutter build macos` — repositories work identically.

**Phase C: AlarmService** (highest complexity)
1. Create `platform/alarm_service_native.dart` — copy current code.
2. Create `platform/alarm_service_web.dart` — audioplayers impl.
3. Convert `alarm_service.dart` to barrel export.
4. **Verify**: `flutter build macos` — alarm sounds work.

**Phase D: NotificationService** (medium complexity)
1. Create `platform/notification_service_native.dart` — copy current + add `openSettings()`.
2. Create `platform/notification_service_web.dart` — Web Notifications API.
3. Convert `notification_service.dart` to barrel export.
4. Fix `reminder_list_screen.dart` to use `NotificationService.openSettings()`.
5. **Verify**: `flutter build macos` — notifications work.

**Phase E: StatusBarService + WindowService** (trivial)
1. Create native + web implementations for both.
2. Convert to barrel exports.
3. **Verify**: `flutter build macos`.

**Phase F: Inline fixes** (screen-level changes)
1. Fix `timer_screen.dart` line 170-171: use `AlarmService.playPreview()`.
2. Fix `timer_screen.dart` lines 1113-1118: replace `HttpClient` with `http.post()`.
3. Remove `import 'dart:io'` from both screen files.
4. **Verify**: `flutter build macos` + `flutter build web`.

**Phase G: PWA polish**
1. Configure `manifest.json`.
2. Add PWA meta tags to `index.html`.
3. Generate PWA icons.
4. **Verify**: `flutter build web`, deploy to localhost, test install prompt.

### Why this order?

- Each phase can be committed independently without breaking macOS.
- Phases B-E only ADD files and change barrel exports — existing imports in screens don't change.
- Phase F is the only phase that modifies screen code, and it fixes existing bugs.
- Phase G is pure web-only configuration.

---

## 9. Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| AudioContext blocked without gesture | HIGH | First `playStart()` on user tap unlocks context for session. Verify in testing. Fallback: add invisible "unlock audio" button on first interaction. |
| Web Notifications require HTTPS | MEDIUM | localhost works for dev. Production requires HTTPS hosting (GitHub Pages, Netlify, etc.). Document this. |
| `shared_preferences` data loss on browser clear | LOW | Same as any localStorage app. Not worse than macOS where user could delete `~/.sitempo/`. |
| audioplayers web audio format support | LOW | MP3 is universally supported. |
| Sound names differ across platforms | LOW | Acceptable — data doesn't cross platforms. |
| `package:web` API surface | LOW | Using only `document.title`, `window.focus()`, `Notification` — all stable APIs. |

---

## 10. Decisions Summary

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | `dart.library.js_interop` for conditional import | `dart.library.html` deprecated in Dart 3.4+; project uses SDK ^3.11.4 |
| D2 | No abstract interface files | Barrel + conditional export is the Flutter-recommended pattern; class name IS the contract |
| D3 | `audioplayers` over `just_audio` | Simpler API, lighter, built-in loop, sufficient for our needs |
| D4 | `package:http` directly (no conditional import) | Works cross-platform; simpler than wrapping; only one callsite |
| D5 | `shared_preferences` for web repos | Standard Flutter approach for localStorage; same JSON encode/decode logic |
| D6 | `package:web` for browser APIs | Modern replacement for dart:html; bundled with SDK; no extra dep |
| D7 | Bundled .mp3 for web sounds | Browsers don't support .aiff; .mp3 is universal; 3 small files |
| D8 | No custom sound import on web (phase 1) | Scoped out per proposal; `importSound()` returns null |
| D9 | `NotificationService.openSettings()` method | Moves platform-specific `Process.run('open')` out of screen code |
| D10 | `document.title` for web status bar | Best available equivalent; shows timer in browser tab |
