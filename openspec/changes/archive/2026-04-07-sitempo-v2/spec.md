# Specification: sitempo-v2 (Delta)

**Status**: draft | **Created**: 2026-04-07 | **Base**: sitempo-v1  
**Stack**: Flutter 3.41.6 / Dart 3.11.4 / Swift (macOS)

> This document specifies ONLY the delta from v1. All v1 requirements remain in effect unless explicitly superseded here.

---

## REQ-010: Step Description in Timer Header

### Description
The timer header area (the section between the routine selector and the timer ring) MUST display the current step's description text when one is present. This is distinct from the description shown in the timeline — this surfaces the description at a glance, at the top of the screen, without requiring the user to scroll to the timeline.

### Context
`_buildActivityLabel()` in `timer_screen.dart` currently renders: emoji → activity label (UPPERCASE) → "Paso X de Y". The description is not shown in this area. The timeline already shows it for the current step inside `_buildTimelineStep()`.

### Requirements
- MUST display the current step's description below the "Paso X de Y" text inside `_buildActivityLabel()`.
- MUST render the description ONLY when `_currentStep.description.isNotEmpty`.
- MUST NOT render any widget (not even an empty SizedBox) when the description is empty.
- MUST style the description text as: `fontSize: 13`, `color: Colors.white54`, `fontStyle: FontStyle.italic`, centered horizontally.
- MUST NOT alter the layout, size, or position of any existing widget in `_buildActivityLabel()`.
- SHOULD update live as the step changes (no additional state needed — `setState` on step advance already rebuilds).

### Priority
Must

### Acceptance Criteria

#### AC-010-1: Description shown when present
```
Given a RoutineStep with description = "Espalda recta, pies apoyados en el suelo"
And that step is the current step
When _buildActivityLabel() renders
Then a Text widget appears below "Paso X de Y"
And its content is "Espalda recta, pies apoyados en el suelo"
And it is italic, fontSize 13, color Colors.white54
```

#### AC-010-2: Description hidden when empty
```
Given a RoutineStep with description = ""
And that step is the current step
When _buildActivityLabel() renders
Then no description Text widget is present in the Column children
```

#### AC-010-3: Description updates on step advance
```
Given step 1 has description "Sentate con la espalda recta"
And step 2 has description = ""
When the timer advances from step 1 to step 2
Then the description Text widget disappears
And the layout does not show a blank gap
```

---

## REQ-011: In-App Popup Notification on Reminder Fire

### Description
When a reminder fires while the app is in the foreground, an in-app overlay popup MUST appear inside the Flutter window in addition to the existing OS notification. This ensures the user cannot miss the reminder when actively using the app.

### Context
`ReminderService._fire()` currently only calls `NotificationService.show()`. `TimerScreen` has no mechanism to receive fire events from `ReminderService`. The proposal chose a callback over a StreamController for simplicity.

### Requirements

#### ReminderService contract changes
- MUST expose a `void Function(Reminder)? onFire` property on `ReminderService`.
- MUST call `onFire(reminder)` immediately before (or after) the existing `NotificationService.show()` call inside `_fire()`, when `onFire` is not null.
- MUST NOT remove or alter the existing OS notification call — both fire together.

#### TimerScreen overlay behavior
- MUST assign `_reminderService.onFire` in `initState()` after `_reminderService.load()`.
- MUST show an `OverlayEntry` on the top-level navigator when `onFire` is triggered.
- MUST guard the callback with `if (!mounted) return` before inserting the overlay.
- MUST track the active `OverlayEntry` in a `OverlayEntry? _activePopup` field.
- MUST dismiss (remove + null) any existing `_activePopup` before inserting a new one, to prevent stacking.
- MUST insert the overlay using `Overlay.of(context).insert(...)` via the top-level navigator context.
- MUST remove the overlay and null `_activePopup` in `dispose()` if still present.
- MUST auto-dismiss the popup after 5 seconds via a `Timer` started immediately on show.
- MUST allow manual dismissal by tapping anywhere on the popup.

#### Popup widget appearance
- MUST display as a top-centered card positioned below the app bar area (top: 24.0 safe area offset).
- MUST show the reminder emoji (fontSize: 28), label (fontSize: 16, bold, white), and description if non-empty (fontSize: 13, italic, white70).
- MUST have a dark semi-transparent background: `Color(0xDD1A1A2E)` or similar.
- MUST have rounded corners: `BorderRadius.circular(16)`.
- MUST have a left border accent in `Color(0xFF6C9BFF)` (app accent color), width 4.
- SHOULD animate in with a fade + slide-down (100–200ms) using `AnimationController` or `AnimatedOpacity`.

### Priority
Must

### Acceptance Criteria

#### AC-011-1: Popup appears on fire
```
Given the timer is running
And reminder "Tomar agua" fires (elapsed >= interval)
When _fire() executes
Then an OverlayEntry is inserted into the navigator overlay
And it displays "💧", "Tomar agua", and the reminder description
And the OS notification also fires (existing behavior preserved)
```

#### AC-011-2: Previous popup dismissed before new one
```
Given an OverlayEntry popup is currently visible for reminder A
When reminder B fires
Then the overlay for A is removed
And a new overlay for B is inserted immediately
And only one popup is visible at a time
```

#### AC-011-3: Popup auto-dismisses after 5 seconds
```
Given a popup is shown for "Tomar agua"
When 5 seconds elapse without user interaction
Then the OverlayEntry is removed
And _activePopup is set to null
```

#### AC-011-4: Manual dismiss on tap
```
Given a popup is visible
When the user taps anywhere on the popup widget
Then the OverlayEntry is removed immediately
And _activePopup is set to null
And the auto-dismiss timer is cancelled
```

#### AC-011-5: No crash after dispose
```
Given the timer screen is disposed while a popup is visible
When dispose() is called
Then the active OverlayEntry is removed before the widget is torn down
And no "setState called after dispose" error occurs
```

#### AC-011-6: No action when widget not mounted
```
Given the onFire callback is still assigned after navigation away
When a reminder fires after the TimerScreen is unmounted
Then the callback returns immediately without inserting any overlay
```

---

## REQ-012: OS Notification Permission Status in Reminders Screen

### Description
The reminders screen MUST detect the current OS notification permission status and display a contextual warning banner when permissions are not granted. The banner provides a direct call-to-action to open System Settings.

### Context
`NotificationService` currently exposes only `requestPermission()` and `show()`. There is no `checkPermission()` method. `ReminderListScreen` has no permission UI. The macOS Swift handler does not implement a `checkPermission` case.

### Requirements

#### Swift MethodChannel additions (`macos/Runner/AppDelegate.swift` or equivalent)
- MUST add a `checkPermission` case to the `com.sitempo/notifications` method channel handler.
- MUST call `UNUserNotificationCenter.current().getNotificationSettings()` asynchronously.
- MUST map `UNAuthorizationStatus` to a String result:
  - `.authorized` → `"granted"`
  - `.denied` → `"denied"`
  - `.notDetermined` → `"notDetermined"`
  - `.provisional`, `.ephemeral`, or any unknown → `"notDetermined"`
- MUST reply on the main thread via `result(statusString)`.

#### NotificationService Dart additions
- MUST add a `static Future<String> checkPermission()` method.
- MUST invoke `'checkPermission'` on the `com.sitempo/notifications` channel.
- MUST return the raw String from the native side (`"granted"`, `"denied"`, `"notDetermined"`).
- MUST return `"notDetermined"` as the fallback if the channel call returns null or throws.

#### ReminderListScreen UI additions
- MUST call `NotificationService.checkPermission()` in `initState()` and store the result in `String? _permissionStatus`.
- MUST rebuild when `_permissionStatus` changes (call `setState`).
- MUST display a warning banner inside the `Scaffold` body when `_permissionStatus == "denied"`:
  - Banner text: "Las notificaciones están desactivadas. Los recordatorios no funcionarán."
  - Banner color: `Colors.orange.withAlpha(30)` background, `Colors.orange` text.
  - Banner includes a "Activar" `TextButton` that opens System Preferences via `url_launcher` or `Process.run('open', ['x-apple.systempreferences:com.apple.preference.notifications'])`.
- MUST NOT display the banner when status is `"granted"` or `"notDetermined"`.
- SHOULD re-check permission when the screen resumes from background (via `WidgetsBindingObserver.didChangeAppLifecycleState` or equivalent) in case the user granted permission in System Settings while the screen was visible.

### Priority
Must (banner) / Should (lifecycle re-check)

### Acceptance Criteria

#### AC-012-1: No banner when granted
```
Given UNAuthorizationStatus is .authorized
When ReminderListScreen opens
Then checkPermission() returns "granted"
And no warning banner is shown in the screen body
```

#### AC-012-2: Banner shown when denied
```
Given UNAuthorizationStatus is .denied
When ReminderListScreen opens
Then checkPermission() returns "denied"
And a warning banner appears at the top of the body
And it contains the text "Las notificaciones están desactivadas"
And it contains a "Activar" button
```

#### AC-012-3: Banner not shown when not determined
```
Given UNAuthorizationStatus is .notDetermined
When ReminderListScreen opens
Then checkPermission() returns "notDetermined"
And no warning banner is shown
```

#### AC-012-4: "Activar" button opens System Preferences
```
Given the warning banner is visible
When the user taps "Activar"
Then the macOS System Settings Notifications pane opens
(verified by Process.run call or url_launcher invocation with the notifications preference URL)
```

#### AC-012-5: Swift returns correct status strings
```
Given UNAuthorizationStatus is .authorized
Then getNotificationSettings callback receives .authorized
And result("granted") is called on the Flutter result handler

Given UNAuthorizationStatus is .denied
Then result("denied") is called

Given UNAuthorizationStatus is .notDetermined
Then result("notDetermined") is called

Given UNAuthorizationStatus is .provisional
Then result("notDetermined") is called (mapped to safe default)
```

#### AC-012-6: Lifecycle re-check (Should)
```
Given the banner is visible (status = "denied")
When the user switches to System Settings, grants permission, and returns to the app
Then didChangeAppLifecycleState fires with AppLifecycleState.resumed
And checkPermission() is called again
And if now "granted", the banner disappears without requiring a screen reload
```

---

## REQ-013: Confirmation Gate on Step Transition

### Description
When the timer for a step reaches zero, the timer MUST pause and enter a confirmation state instead of automatically advancing to the next step. A looping alarm sounds and the macOS window is brought to the foreground. The user MUST explicitly confirm the transition by clicking a "Continuar" button before the next step begins.

### Context
`_advanceStep()` in `timer_screen.dart` (line 100-113) advances atomically — it cancels nothing, immediately resets `_remaining` to the next step's duration, and calls `AlarmService.playTransition()` which plays Glass.aiff exactly once via `Process.run('afplay', [...])` (blocking, non-looping). There is no `_awaitingConfirmation` state, no way to pause between steps, and no `Process.start` usage anywhere in the codebase. The user can miss the single-play sound and unknowingly remain in the wrong posture.

### State Model
The feature introduces a three-state model for `_TimerScreenState`:

```
running  ──(timer hits 0)──►  awaitingConfirmation  ──(user taps Continuar)──►  running (next step)
                                                     ──(last step)──►  cycleComplete
```

- `running`: timer ticking, normal UI
- `awaitingConfirmation`: timer paused at 00:00, alarm looping, confirmation overlay visible
- `cycleComplete`: end-of-sequence confirmation with "Ciclo completo" message (still requires confirmation)

### Requirements

#### REQ-013-A: State variables
- MUST add `bool _awaitingConfirmation = false` to `_TimerScreenState`.
- MUST add `int? _pendingStepIndex` to hold the index of the step being transitioned into (null when not awaiting).
- MUST add `bool _isLastStep` computed property (or inline check) to detect when `_currentStepIndex + 1 >= _expandedSteps.length`.

#### REQ-013-B: Timer pause on step end
- MUST modify `_advanceStep()` so that when `_remaining.inSeconds <= 1` (via `_tick()`), it does NOT immediately advance to the next step.
- MUST cancel the periodic `_timer` (set to null) inside the modified `_advanceStep()`.
- MUST set `_awaitingConfirmation = true` and `_pendingStepIndex = nextIndex` (wrapping to 0 at end-of-sequence).
- MUST set `_remaining = Duration.zero` so the ring displays 00:00 frozen.
- MUST call `AlarmService.startLoopingAlarm()` (see REQ-013-D) immediately after entering confirmation state.
- MUST call `NotificationService.show(...)` with a message indicating the current step has ended and next step is ready.
- MUST call the Swift `bringToFront` MethodChannel (see REQ-013-E) to activate the macOS window.
- MUST NOT call `AlarmService.playTransition()` (the old single-play) during confirmation entry — the looping alarm replaces it.

#### REQ-013-C: Confirmation and step advance
- MUST add `_confirmTransition()` method to `_TimerScreenState`.
- `_confirmTransition()` MUST call `AlarmService.stopLoopingAlarm()` first.
- `_confirmTransition()` MUST call `AlarmService.playTransition()` (single Glass.aiff play) to signal the confirmed transition.
- `_confirmTransition()` MUST set `_awaitingConfirmation = false` and clear `_pendingStepIndex`.
- `_confirmTransition()` MUST advance `_currentStepIndex` to `_pendingStepIndex`, reset `_remaining` to the new step's duration, and increment `_completedCycles` if transitioning from the last step.
- `_confirmTransition()` MUST restart the periodic `_timer` (same as `_startPause()` logic) so the next step begins ticking immediately.
- `_confirmTransition()` MUST call `_updateStatusBar()` after advancing.

#### REQ-013-D: AlarmService — looping alarm
- MUST add `static Process? _alarmProcess` field to `AlarmService`.
- MUST add `static Future<void> startLoopingAlarm()` that starts `afplay` with the loop flag:
  ```
  Process.start('afplay', [_transitionSound, '-l', '9999'])
  ```
  and stores the result in `_alarmProcess`.
- MUST add `static void stopLoopingAlarm()` that calls `_alarmProcess?.kill()` and sets `_alarmProcess = null`.
- `startLoopingAlarm()` MUST call `stopLoopingAlarm()` first if `_alarmProcess` is not null (prevents orphaned processes).
- MUST NOT block the Flutter event loop — `Process.start` is async and non-blocking.

#### REQ-013-E: Swift MethodChannel — bringToFront
- MUST add a `bringToFront` case to the existing native MethodChannel handler (same channel used by status bar or notifications).
- MUST call `NSApp.activate(ignoringOtherApps: true)` (or equivalent `NSApplication.shared.activate(...)`) in the Swift handler.
- MUST reply `result(nil)` (no return value needed).
- The Dart side MUST invoke this channel call as fire-and-forget (no await required in the caller).

#### REQ-013-F: Confirmation overlay UI
- MUST render a full-screen overlay (`Stack` with `Positioned.fill`) over the timer screen content when `_awaitingConfirmation == true`.
- MUST NOT use `OverlayEntry` — the confirmation gate is modal within the timer screen, not a global overlay.
- Overlay background MUST be semi-transparent dark: `Color(0xCC000000)` or similar.
- Overlay content MUST be a centered card containing:
  - Title text: "Paso completado" (or equivalent), styled white, fontSize 16, bold.
  - Separator or spacing.
  - Next step section labeled "Siguiente:" with the NEXT step's emoji (fontSize 32), label (fontSize 20, bold, activity color), and description if non-empty (fontSize 13, italic, white70).
  - For the last-step / end-of-cycle case: show "Ciclo completo" instead of next step info (no emoji/label from a future step).
  - "Continuar" `ElevatedButton` that calls `_confirmTransition()`.
- The timer ring MUST show "00:00" frozen (no progress arc movement) during confirmation state.
- The play/pause button MUST be hidden or disabled (opacity 0 or `onPressed: null`) during confirmation state.
- The status bar MUST update to show a paused indicator (e.g., emoji of current step + " | Confirmar") via `StatusBarService.update(...)` when entering confirmation state.

#### REQ-013-G: Dispose safety
- `dispose()` in `_TimerScreenState` MUST call `AlarmService.stopLoopingAlarm()` unconditionally (safe to call even if not looping — `_alarmProcess` will be null).
- This ensures the alarm process is killed if the user closes or navigates away from the screen while confirmation is pending.

### Priority
Must

### Acceptance Criteria

#### AC-013-1: Timer pauses at zero — does not auto-advance
```
Given the timer is running with _remaining = Duration(seconds: 1)
When _tick() fires
Then _remaining reaches Duration.zero
And _advanceStep() does NOT advance _currentStepIndex to the next step
And the periodic _timer is cancelled
And _awaitingConfirmation is set to true
And _pendingStepIndex is set to (_currentStepIndex + 1) % steps.length
```

#### AC-013-2: Looping alarm starts on confirmation entry
```
Given the timer reaches zero and _advanceStep() is called
When confirmation state is entered
Then AlarmService.startLoopingAlarm() is called
And afplay is running with the -l 9999 flag (process is active)
And _alarmProcess is not null in AlarmService
```

#### AC-013-3: Window brought to foreground on confirmation entry
```
Given the macOS app is in the background
When the timer reaches zero
Then the bringToFront MethodChannel is invoked
And the app window comes to the foreground (NSApp.activate called)
```

#### AC-013-4: Notification fires on confirmation entry
```
Given the timer reaches zero on step N
When confirmation state is entered
Then NotificationService.show() is called with a message indicating step N ended
And an OS notification appears
```

#### AC-013-5: Confirmation overlay appears with correct next step
```
Given _awaitingConfirmation = true
And _pendingStepIndex points to a step with emoji "🧘", label "Estirar", description "Levantate y estira"
When the timer screen rebuilds
Then the confirmation overlay is visible
And it shows "🧘", "Estirar", "Levantate y estira"
And the "Continuar" button is present
And the timer ring shows "00:00"
And the play/pause button is disabled or hidden
```

#### AC-013-6: End-of-cycle confirmation shows "Ciclo completo"
```
Given the current step is the last step in the sequence (_currentStepIndex + 1 >= steps.length)
When the timer reaches zero
Then confirmation state is entered with _pendingStepIndex = 0
And the overlay shows "Ciclo completo" instead of the next step's emoji/label
And the "Continuar" button is still present
```

#### AC-013-7: Confirming advances the step and restarts timer
```
Given _awaitingConfirmation = true and _pendingStepIndex = 2
When the user taps "Continuar"
Then _confirmTransition() is called
And AlarmService.stopLoopingAlarm() is called (alarm process killed)
And AlarmService.playTransition() is called (single sound)
And _currentStepIndex is set to 2
And _remaining is set to _expandedSteps[2].duration
And _awaitingConfirmation is false
And the periodic _timer is restarted
And _updateStatusBar() is called
```

#### AC-013-8: No orphaned alarm process on second trigger
```
Given AlarmService._alarmProcess is not null (alarm already running)
When startLoopingAlarm() is called again
Then stopLoopingAlarm() is called first
And the previous afplay process is killed
And a new afplay process is started
And exactly one afplay process exists
```

#### AC-013-9: Alarm killed on dispose
```
Given _awaitingConfirmation = true (alarm is looping)
When the TimerScreen widget is disposed (user navigates away or closes window)
Then dispose() calls AlarmService.stopLoopingAlarm()
And the afplay process is terminated
And no orphaned afplay process remains after dispose
```

#### AC-013-10: Status bar shows confirmation state
```
Given the timer reaches zero on a step with emoji "💪"
When _awaitingConfirmation = true
Then StatusBarService.update() is called with a paused/confirmar indicator
And the macOS status bar item reflects the paused state
```

---

## Non-Requirements (Explicitly Out of Scope for v2)

- Changing existing OS notification behavior (REQ-005 unchanged).
- Notification settings UI beyond the permission banner.
- Redesigning the timer screen layout beyond the description text addition.
- Non-macOS platform targets.
- Notification scheduling or batching.
- Custom sounds for in-app popups.
- Auto-skip or configurable timeout for the confirmation gate (REQ-013).
- Skip button behavior during confirmation state (skip bypasses confirmation — out of scope; skip remains available only when running).

---

## Requirement Cross-Reference

| REQ-ID  | Feature | Files Affected | Priority |
|---------|---------|----------------|----------|
| REQ-010 | F1 — Step description in header | `lib/screens/timer_screen.dart` | Must |
| REQ-011 | F2 — In-app popup on reminder fire | `lib/services/reminder_service.dart`, `lib/screens/timer_screen.dart` | Must |
| REQ-012 | F3 — OS permission status banner | Swift handler, `lib/services/notification_service.dart`, `lib/screens/reminder_list_screen.dart` | Must/Should |
| REQ-013 | F4 — Confirmation gate on step transition | `lib/services/alarm_service.dart`, `lib/screens/timer_screen.dart`, Swift MethodChannel handler | Must |
