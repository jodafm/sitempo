# Exploration: sitempo PWA Support

**Change**: sitempo-pwa
**Date**: 2026-04-07
**Status**: complete

---

## Executive Summary

sitempo is a Flutter macOS-only app. Making it a PWA requires abstracting 6 platform-specific surfaces behind interfaces with conditional implementations. The codebase is well-structured for this: services are stateless static classes with thin APIs, making the abstraction layer straightforward. No third-party pub.dev packages are web-incompatible — only the Dart SDK itself (`dart:io`, `Process`, `Platform`) and two native MethodChannels are the blockers.

---

## 1. Platform-Specific Code Inventory

### alarm_service.dart — CRITICAL (all methods are macOS-only)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `alarm_service.dart:1` | `import 'dart:io'` | dart:io unavailable on web |
| `alarm_service.dart:4-6` | `/System/Library/Sounds/*.aiff` hardcoded paths | Filesystem paths meaningless on web |
| `alarm_service.dart:17-20` | `Platform.environment['HOME']`, `Directory(...)` | dart:io / filesystem |
| `alarm_service.dart:22-25` | `dir.exists()`, `dir.create()` | dart:io filesystem |
| `alarm_service.dart:28-41` | `dir.list()`, `File(...)` | dart:io filesystem |
| `alarm_service.dart:43-49` | `File(customPath).existsSync()` | dart:io filesystem |
| `alarm_service.dart:52-67` | `Process.run('osascript', ...)` | dart:io Process, macOS-only |
| `alarm_service.dart:69-71` | `Process.run('afplay', [...])` | dart:io Process, macOS-only binary |
| `alarm_service.dart:73-95` | `Process.run('afplay', ...)` (multiple) | dart:io Process |
| `alarm_service.dart:111-116` | `Process.run('afplay', ...)` | dart:io Process |

**Web alternative**: HTML5 `<audio>` element via `dart:html` / `web` package. For looping: `AudioElement.loop = true`. For custom sounds: File Picker API (`file_picker` package) to get blob URLs. System sounds must become bundled audio assets.

---

### notification_service.dart — HIGH (MethodChannel, macOS UNUserNotificationCenter)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `notification_service.dart:1` | `import 'package:flutter/services.dart'` | MethodChannel has no web handler |
| `notification_service.dart:4` | `MethodChannel('com.sitempo/notifications')` | Native bridge, no web side |
| `notification_service.dart:6-9` | `requestPermission()` → MethodChannel | Throws MissingPluginException on web |
| `notification_service.dart:11-18` | `checkPermission()` → MethodChannel | Same |
| `notification_service.dart:20-28` | `show(title, body)` → MethodChannel | Same |

**Web alternative**: Web Notifications API — `Notification.permission`, `Notification.requestPermission()`, `Notification(title, body: body)` — via `dart:html` or the `web` Dart package. Permission model maps 1:1: `granted`/`denied`/`default` (≈ `notDetermined`).

---

### status_bar_service.dart — LOW for PWA (feature non-portable)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `status_bar_service.dart:1` | `MethodChannel('com.sitempo/statusbar')` | No web handler |
| `status_bar_service.dart:6-13` | `update(time, emoji)` | Updates macOS NSStatusItem |
| `status_bar_service.dart:15-17` | `clear()` | Same |

**Web alternative**: No equivalent for a system menu bar. Best web substitute: update `document.title` with current timer state (e.g. `"⏱ 12:34 – Sentado | sitempo"`). Also usable as a PWA: favicon manipulation via canvas. These are cosmetic fallbacks, not functional equivalents.

---

### window_service.dart — LOW for PWA (feature non-portable)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `window_service.dart:1` | `MethodChannel('com.sitempo/statusbar')` | No web handler |
| `window_service.dart:6-8` | `bringToFront()` | Calls NSApp.activate |

**Web alternative**: `window.focus()` in browsers — severely restricted by browser security (only works if called from a user gesture). On web this becomes a no-op or shows a notification instead.

---

### reminder_repository.dart — HIGH (dart:io File I/O)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `reminder_repository.dart:1-2` | `import 'dart:io'` | dart:io unavailable |
| `reminder_repository.dart:7-10` | `Platform.environment['HOME']`, `Directory(...)`, `File(...)` | Filesystem |
| `reminder_repository.dart:13-28` | `_file.exists()`, `_file.readAsString()` | dart:io |
| `reminder_repository.dart:31-36` | `_dir.exists()`, `_dir.create()`, `_file.writeAsString()` | dart:io |

**Web alternative**: `shared_preferences` package (web impl uses `localStorage`) or `idb_sqflite`/`sembast_web` for IndexedDB. Recommended: `shared_preferences` for simplicity — stores JSON string under a key, identical API shape to current load/save pattern.

---

### routine_repository.dart — HIGH (dart:io File I/O)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `routine_repository.dart:1-2` | `import 'dart:io'` | dart:io unavailable |
| `routine_repository.dart:7-11` | `Platform.environment['HOME']`, `Directory(...)`, `File(...)` | Filesystem |
| `routine_repository.dart:14-16` | `_dir.exists()`, `_dir.create()` | dart:io |
| `routine_repository.dart:20-35` | `_activitiesFile.exists()`, `readAsString()` | dart:io |
| `routine_repository.dart:36-41` | `_activitiesFile.writeAsString()` | dart:io |
| `routine_repository.dart:45-57` | `_routinesFile.exists()`, `readAsString()` | dart:io |
| `routine_repository.dart:58-63` | `_routinesFile.writeAsString()` | dart:io |

**Web alternative**: Same as `reminder_repository.dart` — `shared_preferences` with separate keys per entity type.

---

### timer_screen.dart — MEDIUM (two dart:io usages inline in UI layer)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `timer_screen.dart:3` | `import 'dart:io'` | dart:io unavailable |
| `timer_screen.dart:171` | `Process.run('afplay', [path])` | In `_playTransitionSound()` — should call AlarmService |
| `timer_screen.dart:1113` | `HttpClient()` from `dart:io` | Used in `_fireWebhook()` for POST to webhook URL |

**Note on `_playTransitionSound()` (line 171)**: This bypasses `AlarmService` and calls `Process.run('afplay', ...)` directly. This is a bug/inconsistency regardless of web — it should go through `AlarmService.playTransition()`.

**Web alternative for HttpClient**: Use the `http` package (`package:http`) — it works on both web and native. Replace `HttpClient()` + manual request building with `http.post(uri, body: body, headers: {...})`.

---

### reminder_list_screen.dart — MEDIUM (one dart:io usage)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `reminder_list_screen.dart:1` | `import 'dart:io'` | dart:io unavailable |
| `reminder_list_screen.dart:61-64` | `Process.run('open', ['x-apple.systempreferences:...'])` | Opens macOS System Preferences |

**Web alternative**: On web, show a toast/dialog explaining notifications are blocked and link to browser notification settings (no programmatic way to open browser settings). The function `_openNotificationSettings()` becomes a no-op or shows a snackbar.

---

### routine_editor_screen.dart — MEDIUM (AlarmService for sound preview/import)

| Location | API used | Reason it breaks on web |
|---|---|---|
| `routine_editor_screen.dart:634` | `AlarmService.playPreview(sound)` | Calls afplay transitively |
| `routine_editor_screen.dart:687` | `AlarmService.playPreview(sound)` | Same |
| `routine_editor_screen.dart:722` | `AlarmService.playPreview(sound)` | Same |
| `routine_editor_screen.dart:756` | `AlarmService.importSound()` | Uses osascript file picker |

These will be fixed transitively once `AlarmService` is abstracted.

---

## 2. Models — Platform Agnostic (no changes needed)

| File | Status | Notes |
|---|---|---|
| `lib/models/reminder.dart` | SAFE | Pure Dart, `dart:convert` only, `DateTime` logic |
| `lib/models/routine.dart` | SAFE | Pure Dart, `dart:convert` only |
| `lib/models/activity.dart` | SAFE | Pure Dart, `dart:ui` for `Color` only |

---

## 3. Dependencies Audit (pubspec.yaml)

Current dependencies:
- `flutter` SDK — web-compatible
- `cupertino_icons` — web-compatible (font asset)

No third-party packages currently. **Zero dependency blockers.**

Packages to ADD for web support:
- `http: ^1.2.0` — replaces `dart:io HttpClient` for webhooks (cross-platform)
- `shared_preferences: ^2.3.0` — replaces File I/O for persistence (cross-platform)
- `file_picker: ^8.0.0` — replaces `osascript` file picker for sound import (cross-platform)
- `audioplayers: ^6.0.0` OR `just_audio: ^0.9.0` — replaces `afplay` Process.run (cross-platform, web audio)

---

## 4. Flutter Web Setup

The `web/` directory does NOT exist. Running `flutter create --platforms web .` from the project root will scaffold it without touching existing code. This is safe and reversible.

Required: `flutter config --enable-web` (one-time dev machine setup).

---

## 5. Recommended Abstraction Pattern

Use **abstract class + conditional import** (the standard Flutter pattern for platform services).

### Pattern example — AlarmService

```
lib/services/
  alarm_service.dart          ← abstract interface (current file becomes this)
  alarm_service_native.dart   ← macOS implementation (current logic)
  alarm_service_web.dart      ← web implementation (audioplayers / dart:html Audio)
```

`alarm_service.dart` (the contract):
```dart
abstract class AlarmService {
  static AlarmService get instance => _instance;
  static late AlarmService _instance;
  static void setInstance(AlarmService s) => _instance = s;

  Future<void> playPreview(String sound);
  Future<void> playTransition();
  Future<void> playStart();
  Future<void> startLoopingAlarm();
  Future<void> startLoopingAlarmWithPath(String path);
  void stopLoopingAlarm();
  Future<void> startNotificationAlert({int count, String sound});
  void stopNotificationAlert();
  Future<String?> importSound();
  Future<List<String>> loadCustomSounds();
  List<String> get systemSounds;
}
```

Alternatively, use **conditional imports** at the top of `alarm_service.dart`:
```dart
import 'alarm_service_stub.dart'
  if (dart.library.io) 'alarm_service_native.dart'
  if (dart.library.html) 'alarm_service_web.dart';
```

This is the cleanest approach — zero `kIsWeb` checks in UI code.

Apply same pattern to:
- `NotificationService` → `notification_service_native.dart` + `notification_service_web.dart`
- `StatusBarService` → `status_bar_service_native.dart` + `status_bar_service_web.dart` (noop + document.title)
- `WindowService` → `window_service_native.dart` + `window_service_web.dart` (noop)
- `ReminderRepository` → `reminder_repository_native.dart` + `reminder_repository_web.dart`
- `RoutineRepository` → `routine_repository_native.dart` + `routine_repository_web.dart`

---

## 6. Risk Assessment

| Risk | Severity | Notes |
|---|---|---|
| Sound on web requires user gesture to unlock AudioContext | HIGH | Browser policy: first audio play must be triggered by user interaction. The timer start button is a user gesture — OK. Background alarm on reminder fire is NOT — will be silently blocked. Mitigation: show a visible alert modal (already done) + attempt audio. |
| Web Notifications require HTTPS | MEDIUM | PWA must be served over HTTPS. localhost is exempt for dev. |
| Web Notifications blocked by default in many browsers | MEDIUM | Permission request flow is identical to current macOS flow — already handled. |
| `importSound()` on web returns blob URL, not a file path | MEDIUM | Internal sound reference system uses filenames as keys. Web impl must map blob URLs to display names and store them differently (e.g. IndexedDB for audio blobs, not localStorage). |
| `afplay` loop uses blocking Process.run in a while loop | LOW (native only) | Already exists; web impl uses `AudioElement.loop` which is non-blocking. |
| `_playTransitionSound()` in timer_screen.dart bypasses AlarmService | LOW | Bug exists today regardless of web. Fix during abstraction. |
| Status bar / window focus have no web equivalent | LOW | These are enhancement features. Silent no-ops are acceptable. |
| `shared_preferences` web uses localStorage (5MB limit) | LOW | Routine/reminder JSON is tiny. Not a concern. |

---

## 7. Implementation Order

Tasks should proceed in this order to minimize broken intermediate states:

1. **Scaffold web platform** — `flutter create --platforms web .`
2. **Add packages** — `http`, `shared_preferences`, `file_picker`, `audioplayers`
3. **Abstract repositories first** (no UI impact, pure Dart logic)
   - `ReminderRepository` → conditional import, web uses `shared_preferences`
   - `RoutineRepository` → same
4. **Abstract AlarmService** (highest complexity, most callers)
   - Native: moves current `afplay` + `Process.run` logic as-is
   - Web: `audioplayers` for playback, `file_picker` for import
   - Fix the `_playTransitionSound()` bypass in `timer_screen.dart` here
5. **Abstract NotificationService**
   - Native: current MethodChannel logic unchanged
   - Web: Web Notifications API via `dart:html` or `web` package
6. **Abstract StatusBarService + WindowService** (trivial, both become no-ops on web)
7. **Fix reminder_list_screen.dart** — replace `Process.run('open', ...)` with platform-conditional snackbar
8. **Fix timer_screen.dart HttpClient** — replace with `http` package
9. **PWA manifest + service worker** — configure `web/manifest.json` for installability
10. **Test web build** — `flutter run -d chrome`

---

## 8. File Change Map

| File | Action | Effort |
|---|---|---|
| `lib/services/alarm_service.dart` | Refactor → abstract interface | HIGH |
| `lib/services/alarm_service_native.dart` | Create — current logic | LOW |
| `lib/services/alarm_service_web.dart` | Create — audioplayers impl | HIGH |
| `lib/services/notification_service.dart` | Refactor → abstract interface | MEDIUM |
| `lib/services/notification_service_native.dart` | Create — current MethodChannel logic | LOW |
| `lib/services/notification_service_web.dart` | Create — Web Notifications API | MEDIUM |
| `lib/services/status_bar_service.dart` | Refactor → abstract + conditional | LOW |
| `lib/services/status_bar_service_native.dart` | Create — current MethodChannel logic | LOW |
| `lib/services/status_bar_service_web.dart` | Create — document.title update | LOW |
| `lib/services/window_service.dart` | Refactor → abstract + conditional | LOW |
| `lib/services/window_service_native.dart` | Create — current MethodChannel logic | LOW |
| `lib/services/window_service_web.dart` | Create — no-op | LOW |
| `lib/services/reminder_repository.dart` | Refactor → abstract + conditional | MEDIUM |
| `lib/services/reminder_repository_native.dart` | Create — current File I/O logic | LOW |
| `lib/services/reminder_repository_web.dart` | Create — shared_preferences impl | MEDIUM |
| `lib/services/routine_repository.dart` | Refactor → abstract + conditional | MEDIUM |
| `lib/services/routine_repository_native.dart` | Create — current File I/O logic | LOW |
| `lib/services/routine_repository_web.dart` | Create — shared_preferences impl | MEDIUM |
| `lib/screens/timer_screen.dart` | Fix `_playTransitionSound` + replace `HttpClient` with `http` package | MEDIUM |
| `lib/screens/reminder_list_screen.dart` | Replace `Process.run('open', ...)` with platform-conditional UI | LOW |
| `pubspec.yaml` | Add `http`, `shared_preferences`, `file_picker`, `audioplayers` | LOW |
| `web/` | Scaffold via `flutter create --platforms web .` | LOW |
| `web/manifest.json` | Configure PWA name, icons, display mode | LOW |

**Total new files**: 10
**Total modified files**: 9 (+ pubspec.yaml + web scaffold)
