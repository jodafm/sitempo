# Delta Spec: sitempo-pwa

> **Base spec**: sitempo v2.0.0 (REQ-001 – REQ-017)
> **This document**: Delta requirements for PWA support (REQ-018 – REQ-025)
> **Approach**: Abstract service interfaces with conditional imports (`dart.library.io` / `dart.library.html`). Zero `kIsWeb` checks in UI code.

---

## REQ-018: AlarmService Abstraction

### Description
Replace the macOS-only `Process.run('afplay', ...)` implementation with an abstract `AlarmService` interface and two conditional implementations: `alarm_service_native.dart` (afplay, existing macOS logic) and `alarm_service_web.dart` (audioplayers package via HTML5 Audio). The abstract layer is selected at compile time via conditional imports — no runtime branching in UI code.

### Requirements

**Interface contract (alarm_service.dart)**:
- MUST expose a static-equivalent abstract API: `playStart()`, `playTransition(String soundPath)`, `playPreview(String sound)`, `startLoopingAlarmWithPath(String path)`, `stopLoopingAlarm()`, `startNotificationAlert({int count, String sound})`, `stopNotificationAlert()`, `resolveSoundPath(String sound) → String`, `loadCustomSounds() → Future<List<String>>`.
- MUST expose `systemSounds` constant list: `['Glass.aiff', 'Hero.aiff', 'Sosumi.aiff']`.

**Native implementation (alarm_service_native.dart)**:
- MUST preserve all existing `Process.run('afplay', ...)` logic verbatim.
- MUST preserve `resolveSoundPath` with `~/.sitempo/sounds/` check and `/System/Library/Sounds/` fallback.
- MUST preserve `importSound()` via osascript (macOS only).
- MUST preserve `loadCustomSounds()` via `dart:io` Directory listing.

**Web implementation (alarm_service_web.dart)**:
- MUST play sounds using the `audioplayers` package (`AudioPlayer`).
- MUST resolve sound URLs as relative asset paths: `assets/sounds/{sound}` for system sounds bundled in `web/assets/sounds/`.
- MUST implement looping via `AudioPlayer` with `setReleaseMode(ReleaseMode.loop)` for `startLoopingAlarmWithPath`.
- MUST stop looping via `player.stop()` in `stopLoopingAlarm()`.
- MUST implement `startNotificationAlert` by playing the sound `count` times sequentially using `await player.play(...)`.
- MUST implement `playPreview` using a one-shot `AudioPlayer`.
- MUST return `[]` from `loadCustomSounds()` on web (custom sound import is out of scope for web).
- MUST return the asset URL from `resolveSoundPath` (no filesystem check).
- SHOULD guard `AudioPlayer` playback behind user-gesture state: if no gesture has occurred yet, MUST NOT attempt to play (log warning, no exception thrown).
- MUST NOT call `Process.run` or import `dart:io`.

**AudioContext user-gesture constraint**:
- MUST track whether a user gesture has been received (flag set on first button press in the UI).
- MUST expose `AlarmService.markUserGesture()` (no-op on native, sets the flag on web).
- Timer start button tap MUST call `AlarmService.markUserGesture()` before `playStart()`.

**Conditional import wiring (lib/services/alarm_service.dart)**:
- MUST use `export 'alarm_service_stub.dart' if (dart.library.io) 'alarm_service_native.dart' if (dart.library.html) 'alarm_service_web.dart'`.

### Acceptance Criteria

#### Scenario 1: macOS — looping alarm plays and stops
```
Given macOS build, autoAdvance=false, step completes
When _startLoopingTransitionSound() is called
Then AlarmService.startLoopingAlarmWithPath(path) delegates to native impl
And afplay loops until stopLoopingAlarm() is called
```

#### Scenario 2: Web — start sound blocked before user gesture
```
Given web build, no user gesture received yet
When AlarmService.playStart() is called
Then no AudioPlayer.play() call is made
And a debug warning is logged
```

#### Scenario 3: Web — start sound plays after gesture
```
Given web build, user tapped "Iniciar" (markUserGesture() called)
When AlarmService.playStart() is called
Then AudioPlayer plays assets/sounds/Hero.aiff
```

#### Scenario 4: Web — looping alarm starts and stops
```
Given web build, confirmation gate triggers
When AlarmService.startLoopingAlarmWithPath('assets/sounds/Glass.aiff') is called
Then AudioPlayer plays with ReleaseMode.loop
When stopLoopingAlarm() is called
Then AudioPlayer.stop() is called
```

#### Scenario 5: Web — loadCustomSounds returns empty list
```
Given web build
When AlarmService.loadCustomSounds() is called
Then an empty list is returned (no exception)
```

---

## REQ-019: Repository Abstraction (RoutineRepository + ReminderRepository)

### Description
Replace the `dart:io`-based JSON file persistence with an abstract repository interface and two implementations: native (existing file I/O) and web (shared_preferences, which maps to localStorage on web). The interface is the same for both; consumers do not know the backing store.

### Requirements

**Shared contract**:
- `RoutineRepository`: MUST expose `loadRoutines() → Future<List<Routine>>`, `saveRoutines(List<Routine>) → Future<void>`, `loadActivities() → Future<List<Activity>>`, `saveActivities(List<Activity>) → Future<void>`.
- `ReminderRepository`: MUST expose `load() → Future<List<Reminder>>`, `save(List<Reminder>) → Future<void>`.
- Both MUST preserve all existing merge logic (defaults vs custom, deduplication by id).
- Both MUST return in-memory defaults when the backing store is empty or missing.

**Native implementations**:
- MUST preserve all existing `dart:io` file logic verbatim (no behavior change).
- Files remain at `~/.sitempo/routines.json`, `~/.sitempo/activities.json`, `~/.sitempo/reminders.json`.

**Web implementations**:
- MUST use `shared_preferences` package (`SharedPreferences.getInstance()`).
- MUST store routines under key `sitempo_routines` as a JSON string.
- MUST store activities under key `sitempo_activities` as a JSON string.
- MUST store reminders under key `sitempo_reminders` as a JSON string.
- MUST return defaults when the key is absent or value is empty/null.
- MUST apply the same merge/deduplication logic as the native implementation.
- MUST NOT import `dart:io` or reference `Platform`.

**Conditional import wiring**:
- `lib/services/routine_repository.dart`: conditional export selecting native vs web.
- `lib/services/reminder_repository.dart`: conditional export selecting native vs web.

### Acceptance Criteria

#### Scenario 1: Web — first run, no data in localStorage
```
Given web build, SharedPreferences has no 'sitempo_routines' key
When RoutineRepository.loadRoutines() is called
Then Routine.defaults is returned
```

#### Scenario 2: Web — save and reload routines
```
Given web build
When saveRoutines([customRoutine]) is called
Then SharedPreferences stores the JSON under 'sitempo_routines'
When loadRoutines() is called again
Then the custom routine is returned merged with defaults
```

#### Scenario 3: macOS — behavior unchanged
```
Given macOS build
When RoutineRepository.loadRoutines() is called and routines.json exists
Then file content is returned (same as before abstraction)
```

#### Scenario 4: Web — reminders persist across reload
```
Given web build, a reminder list is saved
When the page is reloaded (SharedPreferences re-read)
Then ReminderRepository.load() returns the saved reminders
```

---

## REQ-020: NotificationService Abstraction

### Description
Replace the macOS MethodChannel-based notification service with an abstract interface that has a native implementation (MethodChannel, unchanged) and a web implementation (Web Notifications API via `dart:html` or `web` package). On web, permission is requested through the browser's Notification API.

### Requirements

**Interface**:
- MUST expose `requestPermission() → Future<bool>`.
- MUST expose `checkPermission() → Future<String>` returning `'authorized'`, `'denied'`, or `'notDetermined'`.
- MUST expose `show({required String title, String? body}) → Future<void>`.

**Native implementation**: unchanged (MethodChannel `com.sitempo/notifications`).

**Web implementation**:
- MUST call `Notification.requestPermission()` in `requestPermission()`, returning `true` if `'granted'`.
- MUST map browser `Notification.permission` to the string format used by native: `'granted'` → `'authorized'`, `'denied'` → `'denied'`, `'default'` → `'notDetermined'`.
- MUST show a browser `Notification(title, body: body)` in `show()` when permission is `'granted'`.
- MUST NOT throw if permission is not granted; MUST silently no-op `show()`.
- MUST require HTTPS context for `Notification` to function (enforced by the browser; no app-level guard needed).
- MUST NOT import `package:flutter/services.dart` or reference MethodChannel.

**Permission banner on web**:
- The task list screen permission banner (REQ-012) MUST still render on web using the web `checkPermission()` result.
- The "Activar" button on web MUST call `NotificationService.requestPermission()` (browser prompt) instead of `Process.run('open', ...)`.

### Acceptance Criteria

#### Scenario 1: Web — request permission, granted
```
Given web build, browser Notification.permission = 'default'
When NotificationService.requestPermission() is called
Then browser prompts the user
When user grants
Then requestPermission() returns true
And checkPermission() returns 'authorized'
```

#### Scenario 2: Web — show notification when authorized
```
Given web build, Notification.permission = 'granted'
When NotificationService.show(title: 'Tomar agua', body: null) is called
Then a browser Notification is created with title 'Tomar agua'
```

#### Scenario 3: Web — show is no-op when denied
```
Given web build, Notification.permission = 'denied'
When NotificationService.show(...) is called
Then no Notification is created and no exception is thrown
```

#### Scenario 4: Web — "Activar" triggers browser prompt
```
Given web build, permission is 'notDetermined'
And the task list screen shows the permission banner
When user taps "Activar"
Then NotificationService.requestPermission() is called
And the browser shows its native permission dialog
```

---

## REQ-021: StatusBarService Abstraction

### Description
Replace the macOS MethodChannel-based status bar update with an abstract interface. The native implementation is unchanged. The web implementation updates `document.title` to show the current timer state.

### Requirements

**Interface**:
- MUST expose `update({required String time, required String emoji}) → Future<void>`.
- MUST expose `clear() → Future<void>`.

**Native implementation**: unchanged (MethodChannel `com.sitempo/statusbar`).

**Web implementation**:
- MUST set `document.title` to `'{emoji} {time} — sitempo'` in `update()`.
- MUST set `document.title` to `'sitempo'` in `clear()`.
- MUST NOT import `package:flutter/services.dart` or reference MethodChannel.
- MUST NOT throw on any condition.

### Acceptance Criteria

#### Scenario 1: Web — title updates on tick
```
Given web build, timer running with emoji=🧍, time=14:30
When StatusBarService.update(time: '14:30', emoji: '🧍') is called
Then document.title becomes '🧍 14:30 — sitempo'
```

#### Scenario 2: Web — title clears on reset
```
Given web build, timer was running
When StatusBarService.clear() is called
Then document.title becomes 'sitempo'
```

#### Scenario 3: macOS — behavior unchanged
```
Given macOS build
When StatusBarService.update(...) is called
Then the MethodChannel 'com.sitempo/statusbar' update method is invoked (unchanged)
```

---

## REQ-022: WindowService Abstraction

### Description
Replace the macOS MethodChannel-based window focus with an abstract interface. The native implementation is unchanged. The web implementation is a no-op (browsers do not allow programmatic window focus without a user gesture; the browser tab will simply not forcibly come to front).

### Requirements

**Interface**:
- MUST expose `bringToFront() → Future<void>`.

**Native implementation**: unchanged (MethodChannel `com.sitempo/statusbar`, `bringToFront` method).

**Web implementation**:
- MUST be a no-op: `Future<void> bringToFront() async {}`.
- SHOULD attempt `window.focus()` as a best-effort call (browser will ignore unless the tab is already focused).
- MUST NOT import `package:flutter/services.dart` or reference MethodChannel.
- MUST NOT throw.

### Acceptance Criteria

#### Scenario 1: Web — bringToFront is a no-op, no exception
```
Given web build, confirmation gate triggers
When WindowService.bringToFront() is called
Then no exception is thrown
And execution continues normally
```

#### Scenario 2: macOS — behavior unchanged
```
Given macOS build, confirmation gate triggers
When WindowService.bringToFront() is called
Then MethodChannel 'bringToFront' is invoked
And NSApp activates the window
```

---

## REQ-023: Inline Platform Code Removal

### Description
Three locations in the screens bypass the service layer with direct platform calls. These MUST be replaced with service calls to ensure web compatibility.

### Requirements

**S6a — timer_screen.dart:171 (_playTransitionSound)**:
- MUST replace `Process.run('afplay', [path])` with `AlarmService.playTransition(path)`.
- The new `playTransition(String path)` method MUST be added to the `AlarmService` interface.
- Native implementation MUST call `Process.run('afplay', [path])` (fire-and-forget, same as before).
- Web implementation MUST call `AudioPlayer().play(DeviceFileSource(path))` or equivalent asset URL play.

**S6b — timer_screen.dart:~1113 (_fireWebhook / HttpClient)**:
- MUST replace `dart:io HttpClient` with the `http` package (`http.post(...)`).
- MUST preserve all existing behavior: POST to webhookUrl, JSON body `{task, emoji, id, event, timestamp}`, `Content-Type: application/json; charset=utf-8`.
- MUST treat HTTP 2xx as success, anything else or exception as error.
- MUST NOT import `dart:io` in `timer_screen.dart` after this change.
- MUST add `http` package to `pubspec.yaml`.

**S6c — reminder_list_screen.dart:61-64 (_openNotificationSettings)**:
- MUST replace `Process.run('open', ['x-apple.systempreferences:...'])` with a platform-conditional call.
- Native (macOS): MUST delegate to a new `NotificationService.openSystemSettings()` method which calls `Process.run('open', [...])` internally.
- Web: `NotificationService.openSystemSettings()` MUST call `NotificationService.requestPermission()` instead (triggers browser prompt).
- This removes the last `Process.run` call from the screens layer.

### Acceptance Criteria

#### Scenario 1: Transition sound plays via service (macOS)
```
Given macOS build, step transition fires
When _playTransitionSound() is called
Then AlarmService.playTransition(path) is called
And Process.run('afplay', [path]) executes via the native implementation
```

#### Scenario 2: Transition sound plays via service (web)
```
Given web build, step transition fires
When _playTransitionSound() is called
Then AlarmService.playTransition(assetUrl) is called
And AudioPlayer plays the asset URL
```

#### Scenario 3: Webhook POST uses http package
```
Given a task with webhookUrl fires
When _fireWebhook('triggered') is called
Then http.post(uri, headers: {...}, body: jsonBody) is called
And the response status code is checked for 2xx
```

#### Scenario 4: "Activar" on macOS opens System Preferences
```
Given macOS build, notification permission is denied
When user taps "Activar"
Then NotificationService.openSystemSettings() calls Process.run('open', ['x-apple.systempreferences:...'])
```

#### Scenario 5: "Activar" on web triggers browser prompt
```
Given web build, notification permission is 'notDetermined'
When user taps "Activar"
Then NotificationService.openSystemSettings() calls requestPermission()
And the browser shows its permission dialog
```

---

## REQ-024: Web Scaffold, PWA Manifest, and Service Worker

### Description
Add the Flutter web scaffold (`flutter create --platforms web .`) including a PWA manifest and service worker so the app is installable and works offline (for UI — sounds require network or bundled assets).

### Requirements

**Web scaffold**:
- MUST add `web/` directory with `index.html`, `manifest.json`, `flutter_service_worker.js`, and `flutter_bootstrap.js` (generated by `flutter build web`).
- `index.html` MUST reference the manifest: `<link rel="manifest" href="manifest.json">`.
- `index.html` MUST include the Flutter service worker bootstrap snippet.

**PWA manifest (web/manifest.json)**:
- MUST set `name` to `"sitempo"`.
- MUST set `short_name` to `"sitempo"`.
- MUST set `start_url` to `"/"`.
- MUST set `display` to `"standalone"`.
- MUST set `background_color` to `"#1a1a2e"` (matches app dark background).
- MUST set `theme_color` to `"#1a1a2e"`.
- MUST include at least two icons: 192×192 and 512×512 PNG.

**Service worker**:
- MUST use Flutter's default `flutter_service_worker.js` generated at build time.
- MUST cache the app shell for offline use.
- Sound assets (`web/assets/sounds/`) MUST be included in the service worker cache manifest.

**Bundled system sounds**:
- MUST copy `Glass.aiff`, `Hero.aiff`, `Sosumi.aiff` into `web/assets/sounds/` (or `assets/sounds/` declared in `pubspec.yaml`) so they are served as static assets.
- MUST declare the sounds directory in `pubspec.yaml` under `flutter.assets`.

### Acceptance Criteria

#### Scenario 1: App is installable as PWA
```
Given the app is served over HTTPS
When the user visits the URL in Chrome/Safari
Then the browser shows an "Install" prompt
When the user installs it
Then it opens in standalone mode (no browser chrome)
```

#### Scenario 2: App loads offline (shell)
```
Given the user has visited the app once (service worker cached)
When network is unavailable
Then the app shell loads from cache
And the timer UI is functional (no network required for core loop)
```

#### Scenario 3: System sounds play on web
```
Given web build running in browser
When AlarmService.playStart() is called
Then AudioPlayer loads 'assets/sounds/Hero.aiff' from the bundled assets
And the sound plays (assuming user gesture has been received)
```

---

## REQ-025: Package Additions

### Description
The following packages MUST be added to `pubspec.yaml` to support web targets. No existing packages are removed.

### Requirements

- MUST add `http: ^1.2.0` (or latest stable) — replaces `dart:io HttpClient` in webhook calls; works on all platforms.
- MUST add `shared_preferences: ^2.3.0` (or latest stable) — provides localStorage-backed persistence on web, file-backed on native.
- MUST add `audioplayers: ^6.0.0` (or latest stable) — provides cross-platform audio; used in web `AlarmService` implementation. NOT used in native implementation (native continues to use afplay).
- MUST NOT remove or replace any existing package.
- MUST run `flutter pub get` after adding packages.
- The `http` package MUST be used only in `timer_screen.dart` (webhook). Other HTTP usage elsewhere MUST also migrate to `http` if any is found.

### Acceptance Criteria

#### Scenario 1: Packages resolve on macOS
```
Given the updated pubspec.yaml
When flutter pub get is run on macOS
Then all packages resolve without conflict
And the macOS build succeeds
```

#### Scenario 2: Packages resolve on web
```
Given the updated pubspec.yaml
When flutter build web is run
Then all packages resolve without conflict
And no dart:io imports appear in web-target code paths
```

#### Scenario 3: http replaces HttpClient
```
Given timer_screen.dart after S6b fix
When grepping for 'HttpClient' or 'dart:io'
Then neither appears in the file
```

---

## Constraints and Non-Goals (Delta)

- **Scope OUT** (not specced in this change): iOS, Android, Windows, Linux support; cloud sync; custom sound import on web; UI redesign; user accounts.
- **macOS behavior**: All 17 existing requirements (REQ-001 – REQ-017) remain fully unchanged. The abstraction is additive only.
- **TDD**: Each new service implementation MUST have unit tests. Web implementations MUST be testable via mock injection (no `dart:html` global calls in production paths that cannot be replaced by a test double).
- **No kIsWeb**: UI code MUST NOT contain `if (kIsWeb)` checks. Platform differences live exclusively in the service implementations.
- **AudioContext**: Web `AlarmService` MUST NOT throw on playback failure; degrade gracefully with a logged warning.
