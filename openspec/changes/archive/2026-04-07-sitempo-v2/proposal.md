# SDD Proposal: sitempo-v2

**Status**: draft
**Created**: 2026-04-07
**Stack**: Flutter 3.41.6 / Dart 3.11.4 / Swift (macOS)

---

## 1. Intent

Sitempo's timer screen shows the current step prominently (emoji + label + "Paso X de Y") but omits the step's description, forcing the user to remember what each step involves. Additionally, reminders only fire as OS notifications which are easy to miss when the app is in the foreground. Finally, there is no feedback when the OS has denied or not yet granted notification permissions, so reminders silently fail without explanation.

Beyond those gaps, when the timer reaches zero and transitions to the next step, the advance happens silently and immediately. The user often misses the single transition sound (Glass.aiff) and stays in the wrong posture without realizing the step changed. There is no gate or confirmation — the next step's clock starts ticking the instant the previous one ends.

This proposal addresses all four gaps so the user gets full step context while working, never misses a reminder when the app is visible, understands immediately if notifications are blocked, and must explicitly confirm each step transition before the next step begins.

---

## 2. Scope

### In scope

| # | Feature | Size |
|---|---------|------|
| F1 | Show step description below "Paso X de Y" in timer screen | XS |
| F2 | In-app popup notification when a reminder fires (overlay inside the Flutter window) | S |
| F3 | OS notification permission check + warning banner in the reminders screen | S |
| F4 | Confirmation gate on step transition — pause between steps until user confirms | M |

### Out of scope

- Changing the existing OS notification behavior (it stays as-is alongside the new in-app popup).
- Notification settings/preferences UI beyond the permission banner.
- Redesigning the timer screen layout or step timeline.
- Android/iOS/Windows/Linux targets (macOS only).
- Auto-skip or configurable timeout for the confirmation gate (always requires manual confirmation).

---

## 3. Approach

### F1 — Step Description Display (XS)

**Problem**: `_buildActivityLabel()` in `timer_screen.dart` (lines 349-370) renders the big emoji, step label, and "Paso X de Y" but never reads `_currentStep.description`.

**Solution**: Add a conditional `Text` widget after the "Paso X de Y" row, guarded by `_currentStep.description.isNotEmpty`. Style it as secondary text (smaller font, muted color) to maintain visual hierarchy.

**Files touched**: `timer_screen.dart` (~5 lines added).

### F2 — In-App Popup Notifications (S)

**Problem**: `ReminderService._fire()` calls `NotificationService.show()` which goes straight to Swift/UNUserNotificationCenter. There is no Flutter-side visual feedback. `ReminderService` has no reference to `BuildContext`.

**Solution**:
1. Add a `void Function(Reminder)? onFire` callback property to `ReminderService`.
2. In `_fire()`, invoke the callback (if set) in addition to the existing OS notification call.
3. In `_TimerScreenState`, assign the callback during `initState()`. The callback shows an `OverlayEntry` (or `SnackBar`) with the reminder's message.
4. Guard with `if (!mounted) return` since the reminder fires from a periodic `Timer`.

**Why callback over Stream**: The callback pattern is simpler, requires no subscription lifecycle management, and matches the existing `ReminderService` style. A `StreamController<Reminder>` would be more testable but adds boilerplate disproportionate to the feature size. If testing requirements grow, the callback can be replaced with a stream later without breaking the public API shape.

**Files touched**: `reminder_service.dart` (~10 lines), `timer_screen.dart` (~20 lines for overlay logic).

### F3 — OS Notification Permission Status (S)

**Problem**: The Swift MethodChannel only handles `requestPermission` and `show`. There is no way to check current permission status from Dart. The reminders screen (`ReminderListScreen`) has no permission awareness.

**Solution**:
1. **Swift layer**: Add a `checkPermission` case to the existing MethodChannel handler. Use `UNUserNotificationCenter.current().getNotificationSettings()` and return the authorization status string.
2. **Dart layer**: Add `static Future<String> checkPermission()` to `NotificationService`. Return `"granted"`, `"denied"`, or `"notDetermined"`.
3. **UI layer**: In `_ReminderListScreenState.initState()`, call `checkPermission()`. If not granted, show a warning banner at the top of the list with an "Activar" button that calls `requestPermission()` and re-checks.
4. Handle `notDetermined` by triggering the permission request directly (first-time experience).

**Files touched**: Swift MethodChannel handler (~15 lines), `notification_service.dart` (~10 lines), `reminder_list_screen.dart` (~30 lines).

### F4 — Confirmation Gate on Step Transition (M)

**Problem**: `_advanceStep()` in `timer_screen.dart` (line 100) advances to the next step atomically — no pause, no gate. The timer is never cancelled during transition, so the next step starts ticking immediately. `_isRunning` is a simple boolean with no intermediate "awaiting confirmation" state. The transition sound (`AlarmService.playTransition()`) uses `Process.run('afplay', ...)` which plays once and cannot be looped or cancelled. The user frequently misses this single sound and stays in the wrong posture without knowing the step changed.

**Solution**:
1. **New state**: Add `bool _awaitingConfirmation` and `int _pendingStepIndex` to `_TimerScreenState`. This creates a three-state model: running → awaiting confirmation → running (next step).
2. **Modified `_advanceStep()`**: Instead of advancing directly, cancel the timer, set `_awaitingConfirmation = true`, store the next step index in `_pendingStepIndex`, start looping alarm, bring the macOS window to front, and fire an OS notification.
3. **New `_confirmTransition()` method**: Called when user taps "Continuar". Stops the looping alarm, sets `_awaitingConfirmation = false`, advances to `_pendingStepIndex`, and restarts the timer.
4. **AlarmService changes**: Add `playLoopingAlarm()` using `Process.start('afplay', [path, '-l', '9999'])` which returns a cancellable `Process`. Add `stopAlarm()` that calls `Process.kill()` on the active process. Store the process reference for cleanup.
5. **Swift MethodChannel**: Add a `bringToFront` case that reuses the existing `NSApp.activate(ignoringOtherApps: true)` + `makeKeyAndOrderFront(nil)` logic already present in `statusBarClicked()`.
6. **Confirmation UI**: When `_awaitingConfirmation` is true, show a confirmation overlay replacing the timer display. The overlay shows: next step emoji + label + description, and a prominent "Continuar" button. The timer display is hidden while awaiting confirmation.

**Why looping alarm over repeated timer**: `afplay -l 9999` is a single OS process that loops natively — no Dart timer overhead, no gap between plays, and trivially cancellable via `Process.kill()`. A Dart-side `Timer.periodic` re-triggering `Process.run` would create process-per-play overhead and timing gaps.

**Why bring window to front**: The user may have Sitempo minimized or behind other windows. macOS `NSApp.activate(ignoringOtherApps: true)` forces the window to the foreground, ensuring the confirmation overlay is visible. This logic already exists in the codebase for status bar click handling.

**Files touched**: `timer_screen.dart` (~40 lines for state + UI + confirm method), `alarm_service.dart` (~20 lines for looping/stop), Swift MethodChannel handler (~5 lines for `bringToFront`).

---

## 4. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Overlay shown after widget disposed** (F2) | Crash or visual artifact | Guard with `mounted` check before showing overlay. Dismiss overlay in `dispose()`. |
| **Permission check returns unexpected status** (F3) | Banner shows wrong state | Map all `UNAuthorizationStatus` cases explicitly; default to "check System Preferences" message for unknown values. |
| **OverlayEntry z-order conflicts** (F2) | Popup hidden behind other widgets | Use `Overlay.of(context)` from the top-level navigator context, not a nested one. |
| **Rapid successive reminders** (F2) | Multiple overlays stacking | Track active overlay; dismiss previous before showing new one. |
| **Looping alarm process not killed on dispose** (F4) | Orphaned `afplay` process keeps playing after app closes | Kill process in `AlarmService.stopAlarm()` called from `dispose()`. Also kill in `_confirmTransition()`. |
| **Window focus fails without Accessibility permissions** (F4) | Window doesn't come to front | `NSApp.activate(ignoringOtherApps: true)` works without Accessibility permissions in most cases. Falls back gracefully — alarm still loops and notification still fires. |
| **User AFK — alarm loops indefinitely** (F4) | Battery/CPU usage from `afplay` process | Acceptable trade-off — the entire purpose is persistent alerting. Process is lightweight (~0.1% CPU). |
| **Confirmation gate blocks session completion** (F4) | If on the last step, gate fires but there's no "next step" | Detect last step: on final step completion, skip the gate and show session-complete state directly. |

---

## 5. Effort Estimate

| Feature | Estimate | Confidence |
|---------|----------|------------|
| F1 — Step description display | **XS** (~15 min) | High |
| F2 — In-app popup notifications | **S** (~1-2 hr) | Medium-High |
| F3 — Permission status banner | **S** (~1-2 hr) | Medium |
| F4 — Confirmation gate on step transition | **M** (~2-3 hr) | Medium |
| **Overall** | **M** (~5-7 hr) | Medium |

---

## 6. Recommended Next Steps

1. **Spec phase**: Write delta specs with acceptance criteria per feature.
2. **Design phase**: Detail the overlay widget design (F2), Swift MethodChannel contract (F3), confirmation gate state machine and alarm lifecycle (F4).
3. **Tasks phase**: Break into atomic implementation tasks respecting the dependency order: F1 (independent) | F3-Swift -> F3-Dart -> F3-UI | F2-Service -> F2-UI | F4-Alarm -> F4-Swift -> F4-State -> F4-UI.
