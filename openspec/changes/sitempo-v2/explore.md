# SDD Explore — sitempo-v2

**Date**: 2026-04-07  
**Change**: sitempo-v2  
**Features investigated**: Step description display, In-app popup notifications, OS notification permission status

---

## Feature 1: Step Description Display

### Current State

**Already implemented — nearly complete.**

`RoutineStep` in `lib/models/routine.dart` has a `description` field (line 8):
```dart
final String description;
```
- Serialized to/from JSON (`toJson`/`fromJson`), defaulting to `''`.
- The `RoutineEditorScreen` already renders a `_buildDescriptionField()` per step and saves the value via `_EditableStep.description`.
- The `_buildTimelineStep()` method in `timer_screen.dart` (lines 576–588) already conditionally shows the description **only for the currently active step in the timeline section**.

**What's missing**: The description is NOT shown in the prominent `_buildActivityLabel()` widget (lines 349–370), which is the large emoji + uppercase label + "Paso X de Y" block at the top of the screen. It appears only in the small timeline at the bottom.

### Key Locations

| File | Lines | Role |
|------|-------|------|
| `lib/models/routine.dart` | 8–11 | `RoutineStep.description` field |
| `lib/screens/timer_screen.dart` | 349–370 | `_buildActivityLabel()` — top of screen, no description here |
| `lib/screens/timer_screen.dart` | 576–588 | Description shown in timeline row (already works) |
| `lib/screens/routine_editor_screen.dart` | 260–277 | Description text field in editor |

### Recommended Approach

Add the description text below "Paso X de Y" in `_buildActivityLabel()`, conditionally shown only when `_currentStep.description.isNotEmpty`:

```dart
if (_currentStep.description.isNotEmpty)
  Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      _currentStep.description,
      style: TextStyle(
        fontSize: 13,
        color: activity.color.withAlpha(180),
        fontStyle: FontStyle.italic,
      ),
      textAlign: TextAlign.center,
    ),
  ),
```

**Risk**: None. The model already has the field, the editor already saves it, and the timeline already reads it. This is a 3-line UI addition.

---

## Feature 2: In-App Popup Notifications

### Current State

Notifications flow exclusively through macOS UNUserNotificationCenter:
- `ReminderService._fire()` (`lib/services/reminder_service.dart` line 33–38) calls `NotificationService.show()`.
- `NotificationService.show()` (`lib/services/notification_service.dart` line 11–19) calls the Swift MethodChannel `com.sitempo/notifications → show`.
- Swift side (`macos/Runner/MainFlutterWindow.swift` lines 93–114) creates a `UNNotificationRequest` and posts it via `UNUserNotificationCenter`.
- `AppDelegate` (line 20–30) already enables foreground banner display via `willPresent`.

There is **no in-app overlay/snackbar/popup mechanism** anywhere in the Flutter layer. The `ReminderService` is a plain Dart class with no reference to `BuildContext`, so it cannot directly show Flutter UI.

### Architecture Gap

`ReminderService` is decoupled from Flutter's widget tree — it only holds `_reminders` and `_elapsedSeconds`. The `_TimerScreenState` owns the service instance and calls `_reminderService.tick()` on every `_tick()`. This is the right chokepoint.

### Recommended Approach

**Option A — Callback in ReminderService (preferred)**

Add an `onFire` callback to `ReminderService`:
```dart
class ReminderService {
  void Function(Reminder)? onFire;

  void _fire(Reminder reminder) {
    NotificationService.show(...); // keep OS notification
    onFire?.call(reminder);         // also call Flutter layer
  }
}
```

In `_TimerScreenState`, after `_reminderService.load(...)`:
```dart
_reminderService.onFire = (reminder) {
  if (!mounted) return;
  _showInAppBanner(reminder);
};
```

`_showInAppBanner` uses `ScaffoldMessenger.of(context).showSnackBar(...)` or a custom overlay. For a richer popup, use `showDialog` or an `OverlayEntry`.

**Option B — Stream-based (more decoupled but heavier)**

Replace callback with a `StreamController<Reminder>`. `_TimerScreenState` listens on `initState` and cancels on `dispose`. More testable, slightly more boilerplate.

**Recommended UI**: A compact banner at the top of the window (not bottom snackbar, which feels misplaced in a macOS app). Use `OverlayEntry` for full control, or `ScaffoldMessenger` SnackBar positioned at `SnackBarBehavior.floating` as a quick win.

**Risks**:
- If the user navigates to another screen (ReminderListScreen, RoutineEditorScreen), `mounted` may be false — guard every `setState`/overlay call.
- The reminder fires every N minutes of elapsed timer seconds, not wall clock — this is intentional, but in-app popup should respect the same trigger.
- Don't remove the OS notification — it fires even when the app is not focused.

---

## Feature 3: OS Notification Permission Status

### Current State

**Swift side**:
- `MainFlutterWindow.setupNotificationChannel()` handles `requestPermission` (asks macOS for permission, returns `Bool`) and `show`.
- There is **no `checkPermission` method** exposed via the MethodChannel — only `requestPermission` which both checks AND requests.
- `AppDelegate` sets itself as `UNUserNotificationCenter.delegate` but does not expose permission status.

**Dart side**:
- `NotificationService` (`lib/services/notification_service.dart`) exposes only `requestPermission()` and `show()`. No `checkPermissionStatus()` method exists.
- `TimerScreen._load()` calls `NotificationService.requestPermission()` on app start — it fires the macOS permission dialog on first launch and returns `true`/`false`.
- `ReminderListScreen` (`lib/screens/reminder_list_screen.dart`) shows no permission status anywhere. It has no reference to `NotificationService`.

### Key Locations

| File | Lines | Role |
|------|-------|------|
| `macos/Runner/MainFlutterWindow.swift` | 84–119 | MethodChannel handler — only `requestPermission` + `show` |
| `lib/services/notification_service.dart` | 6–9 | `requestPermission()` only |
| `lib/screens/reminder_list_screen.dart` | full | No permission check |
| `lib/screens/timer_screen.dart` | 62–63 | Calls `requestPermission` on load |

### Recommended Approach

**Step 1 — Add `checkPermission` to Swift**

In `MainFlutterWindow.setupNotificationChannel()`, add a new case:
```swift
case "checkPermission":
  UNUserNotificationCenter.current().getNotificationSettings { settings in
    DispatchQueue.main.async {
      result(settings.authorizationStatus == .authorized)
    }
  }
```

**Step 2 — Expose in Dart**

```dart
static Future<bool> checkPermission() async {
  final result = await _channel.invokeMethod<bool>('checkPermission');
  return result ?? false;
}
```

**Step 3 — Show status in ReminderListScreen**

In `_ReminderListScreenState.initState()`, call `checkPermission()` and store the result. Render a banner/chip at the top of the list:

```dart
// When permission denied:
Container(
  padding: EdgeInsets.all(12),
  color: Colors.orange.withAlpha(20),
  child: Row(children: [
    Icon(Icons.warning_amber, color: Colors.orange),
    SizedBox(width: 8),
    Text('Notificaciones desactivadas en macOS',
         style: TextStyle(color: Colors.orange)),
    Spacer(),
    TextButton(onPressed: _requestPermission, child: Text('Activar')),
  ]),
)
```

**Risks**:
- `getNotificationSettings` returns `.notDetermined` when the user has never been asked — treat this as "not granted" and prompt via `requestPermission`.
- The permission banner should only appear in `ReminderListScreen` (not `TimerScreen`) since that's where the user manages notification-related features.
- `requestPermission` is already called from `TimerScreen._load()` on app start, so by the time the user opens reminders, status is always determined or authorized.

---

## Summary Matrix

| Feature | Model ready? | UI ready? | Service ready? | Native ready? | Effort |
|---------|-------------|-----------|----------------|---------------|--------|
| Step description in timer header | YES | NO (timeline only) | N/A | N/A | XS — 5 lines |
| In-app popup notifications | YES | NO | NO (no callback) | N/A | S — callback + overlay widget |
| Permission status display | N/A | NO | NO | NO (no checkPermission) | S — Swift case + Dart method + UI banner |

---

## Cross-cutting Risks

1. **No state management**: All state is local to `_TimerScreenState`. In-app banners triggered from `ReminderService` must check `mounted` before every widget interaction.
2. **Timer is seconds-based**: `ReminderService.tick()` is called every real second only while the timer is running. If timer is paused, reminders don't fire — this is consistent behavior.
3. **macOS-only**: All native calls assume macOS. No `Platform.isIOS` guards needed but be careful not to introduce any cross-platform abstractions that would complicate the Swift bridge.
