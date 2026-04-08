# Tasks: sitempo-v2

**Status**: ready | **Created**: 2026-04-07 | **Change**: sitempo-v2
**Total tasks**: 20 | **TDD**: enabled

---

## Task 1: Test — step description shown/hidden in timer header (F1)
- Feature: F1
- Effort: S
- Depends on: none
- Files: `test/widget_test.dart` (or new `test/timer_screen_test.dart`)
- Acceptance: AC-010-1, AC-010-2, AC-010-3
- Description: Write unit/widget tests for `_buildActivityLabel()` behavior. Three cases: (a) description non-empty → Text widget present with correct style (italic, fontSize 13, Colors.white54); (b) description empty → no Text widget and no gap in Column children; (c) step advances from non-empty to empty description → Text disappears on rebuild. Tests must fail before Task 2 is implemented.

---

## Task 2: Implement — step description in `_buildActivityLabel()` (F1)
- Feature: F1
- Effort: XS
- Depends on: Task 1
- Files: `lib/screens/timer_screen.dart`
- Acceptance: AC-010-1, AC-010-2, AC-010-3
- Description: In `_buildActivityLabel()`, after the "Paso X de Y" Text widget, add a conditional expression: `if (_currentStep.description.isNotEmpty) Text(...)` styled with `fontSize: 13`, `color: Colors.white54`, `fontStyle: FontStyle.italic`, `textAlign: TextAlign.center`. No new widgets, no layout changes. ~7 lines. Tests from Task 1 must pass after this change.

---

## Task 3: Test — `onFire` callback on ReminderService (F2)
- Feature: F2
- Effort: S
- Depends on: none
- Files: `test/reminder_service_test.dart` (new)
- Acceptance: AC-011-1 (service side), AC-011-2
- Description: Unit tests for `ReminderService.onFire` contract. Two cases: (a) when `onFire` is set and `_fire()` executes, the callback is called with the correct `Reminder` instance; (b) OS notification (`NotificationService.show()`) still fires alongside — both happen in the same `_fire()` invocation. Use a mock/stub for `NotificationService.show()`. Tests must fail before Task 4.

---

## Task 4: Implement — `onFire` callback on ReminderService (F2)
- Feature: F2
- Effort: XS
- Depends on: Task 3
- Files: `lib/services/reminder_service.dart`
- Acceptance: AC-011-1 (service side)
- Description: Add `void Function(Reminder)? onFire;` field to `ReminderService`. In `_fire()`, after (or just before) the existing `NotificationService.show()` call, add `onFire?.call(reminder)`. ~2 lines total. No other changes. Tests from Task 3 must pass.

---

## Task 5: Test — popup overlay widget behavior (F2)
- Feature: F2
- Effort: M
- Depends on: Task 4
- Files: `test/timer_screen_test.dart` (new)
- Acceptance: AC-011-1 through AC-011-6
- Description: Widget tests for the OverlayEntry popup in `TimerScreen`. Cover: (a) popup appears with correct content (emoji, label, description) when `onFire` triggers; (b) second fire replaces first popup — only one visible at a time; (c) popup auto-dismisses after 5 seconds (use `tester.pump(Duration(seconds: 5))`); (d) tap on popup removes it immediately; (e) dispose while popup visible → no error; (f) callback invoked after unmount → returns immediately without crash. Tests must fail before Task 6.

---

## Task 6: Implement — in-app popup overlay in TimerScreen (F2)
- Feature: F2
- Effort: M
- Depends on: Task 4, Task 5
- Files: `lib/screens/timer_screen.dart`
- Acceptance: AC-011-1 through AC-011-6
- Description: In `TimerScreen`:
  1. Add `OverlayEntry? _activePopup` and `Timer? _popupDismissTimer` fields.
  2. Assign `_reminderService.onFire` in `initState()` after `load()`: guard with `if (!mounted) return`, call `_showReminderPopup(reminder)`.
  3. Implement `_showReminderPopup(Reminder reminder)`: dismiss any existing popup first (call `_dismissPopup()`), build `OverlayEntry` containing `_ReminderPopup` widget, insert via `Overlay.of(context).insert(...)`, set `_popupDismissTimer = Timer(Duration(seconds: 5), _dismissPopup)`.
  4. Implement `_dismissPopup()`: if `_activePopup != null`, remove and null it; cancel and null `_popupDismissTimer`.
  5. In `dispose()`: call `_dismissPopup()`, null `_reminderService.onFire`.
  6. Add private `_ReminderPopup` `StatefulWidget` at bottom of file: `AnimationController` (300ms, easeOutCubic) driving `SlideTransition` (Offset(0,-1) → Offset.zero) + `FadeTransition`. Visual: top-centered, 24px margins, `Color(0xDD1A1A2E)` background, `BorderRadius.circular(16)`, 4px left border in `Color(0xFF6C9BFF)`. Shows emoji (28px), label (16px bold white), description if non-empty (13px italic white70). Wrapped in `GestureDetector` calling `onDismiss` callback. ~100 lines total. Tests from Task 5 must pass.

---

## Task 7: Test — Swift `checkPermission` channel handler (F3)
- Feature: F3
- Effort: S
- Depends on: none
- Files: `macos/RunnerTests/` or inline comment — Swift unit test if test target exists; otherwise document as manual verification criteria
- Acceptance: AC-012-5
- Description: Verify that `checkPermission` case in the Swift MethodChannel handler maps `UNAuthorizationStatus` values correctly: `.authorized` → `"granted"`, `.denied` → `"denied"`, `.notDetermined` → `"notDetermined"`, `.provisional` → `"granted"`, `.ephemeral` → `"granted"`, `@unknown default` → `"denied"`. If no Swift test target exists, write a Dart mock test that stubs the channel return value and verifies `NotificationService.checkPermission()` passes it through correctly. Note: TDD for Swift requires a test target — check `macos/RunnerTests/` existence before deciding approach.

---

## Task 8: Implement — Swift `checkPermission` in MethodChannel handler (F3)
- Feature: F3
- Effort: S
- Depends on: Task 7
- Files: `macos/Runner/MainFlutterWindow.swift`
- Acceptance: AC-012-5
- Description: In the `com.sitempo/notifications` channel handler switch statement, add a `case "checkPermission":` branch. Call `UNUserNotificationCenter.current().getNotificationSettings { settings in }`. Inside the callback, switch on `settings.authorizationStatus`: `.authorized`, `.provisional`, `.ephemeral` → `result("granted")`; `.denied` → `result("denied")`; `.notDetermined`, `@unknown default` → `result("notDetermined")`. Reply must be dispatched on the main thread: `DispatchQueue.main.async { result(...) }`. ~16 lines.

---

## Task 9: Test — `NotificationService.checkPermission()` Dart method (F3)
- Feature: F3
- Effort: XS
- Depends on: Task 8
- Files: `test/notification_service_test.dart` (new)
- Acceptance: AC-012-5 (Dart side)
- Description: Unit tests using `TestDefaultBinaryMessengerBinding` or `setMockMethodCallHandler` to stub the `com.sitempo/notifications` channel. Cases: (a) channel returns `"granted"` → `checkPermission()` returns `"granted"`; (b) channel returns `"denied"` → returns `"denied"`; (c) channel returns `null` → returns `"notDetermined"` (fallback); (d) channel throws → returns `"notDetermined"` (fallback). Tests must fail before Task 10.

---

## Task 10: Implement — `NotificationService.checkPermission()` Dart method (F3)
- Feature: F3
- Effort: XS
- Depends on: Task 8, Task 9
- Files: `lib/services/notification_service.dart`
- Acceptance: AC-012-5 (Dart side)
- Description: Add `static Future<String> checkPermission() async` to `NotificationService`. Invoke `_channel.invokeMethod<String>('checkPermission')` inside a try/catch. Return the raw string if non-null; return `"notDetermined"` if null or if the invocation throws. ~4 lines. Tests from Task 9 must pass.

---

## Task 11: Test — permission warning banner in ReminderListScreen (F3)
- Feature: F3
- Effort: M
- Depends on: Task 10
- Files: `test/reminder_list_screen_test.dart` (new)
- Acceptance: AC-012-1, AC-012-2, AC-012-3, AC-012-4, AC-012-6
- Description: Widget tests for `ReminderListScreen` permission banner. Stub `NotificationService.checkPermission()` via method channel mock. Cases: (a) status `"granted"` → no banner in widget tree; (b) status `"denied"` → banner visible with text "Las notificaciones están desactivadas" and "Activar" button; (c) status `"notDetermined"` → no banner; (d) tap "Activar" → triggers system settings open (verify the `Process.run` or `url_launcher` call was made — use a spy/mock); (e) lifecycle resume with status changed from `"denied"` to `"granted"` → banner disappears without reload. Tests must fail before Task 12.

---

## Task 12: Implement — permission banner in ReminderListScreen (F3)
- Feature: F3
- Effort: M
- Depends on: Task 10, Task 11
- Files: `lib/screens/reminder_list_screen.dart`
- Acceptance: AC-012-1, AC-012-2, AC-012-3, AC-012-4, AC-012-6
- Description:
  1. Add `String? _permissionStatus` field (default `null`; treat `null` as "still checking" — no banner while null).
  2. Add `_checkPermission()` async method: calls `NotificationService.checkPermission()`, then `setState(() => _permissionStatus = result)`.
  3. Call `_checkPermission()` in `initState()`.
  4. Implement `WidgetsBindingObserver` mixin: in `didChangeAppLifecycleState`, when state is `AppLifecycleState.resumed`, call `_checkPermission()` again.
  5. Add `_buildPermissionBanner()`: returns a `Container` with `Colors.orange.withAlpha(30)` background, orange text "Las notificaciones están desactivadas. Los recordatorios no funcionarán.", and a `TextButton("Activar")` that calls `Process.run('open', ['x-apple.systempreferences:com.apple.preference.notifications'])`.
  6. In the `Scaffold` body (likely a `Column`), insert `if (_permissionStatus == "denied") _buildPermissionBanner()` at the top. ~60 lines. Tests from Task 11 must pass.

---

## Task 13: Test — `AlarmService` looping alarm (F4)
- Feature: F4
- Effort: S
- Depends on: none
- Files: `test/alarm_service_test.dart` (new or extend existing)
- Acceptance: AC-013-2, AC-013-8, AC-013-9
- Description: Unit tests for `AlarmService.startLoopingAlarm()` and `stopLoopingAlarm()`. Cases: (a) `startLoopingAlarm()` starts an `afplay` process with the `-l 9999` flag — verify `_alarmProcess` is not null after the call; (b) `stopLoopingAlarm()` kills the process and sets `_alarmProcess` to null; (c) calling `startLoopingAlarm()` when `_alarmProcess` is already set calls `stopLoopingAlarm()` first — only one process exists at a time (AC-013-8); (d) calling `stopLoopingAlarm()` when `_alarmProcess` is null is a no-op (no exception). Use `Process` fakes or stub via dependency injection if `AlarmService` allows; otherwise accept integration-style tests with actual process spawning. Tests must fail before Task 14.

---

## Task 14: Implement — `AlarmService` looping alarm (F4)
- Feature: F4
- Effort: S
- Depends on: Task 13
- Files: `lib/services/alarm_service.dart`
- Acceptance: AC-013-2, AC-013-8, AC-013-9
- Description:
  1. Add `static Process? _alarmProcess` field to `AlarmService`.
  2. Add `static Future<void> startLoopingAlarm() async`: call `stopLoopingAlarm()` first if `_alarmProcess != null`, then `_alarmProcess = await Process.start('afplay', [_transitionSound, '-l', '9999'])`. Non-blocking — `Process.start` returns immediately after spawning.
  3. Add `static void stopLoopingAlarm()`: call `_alarmProcess?.kill()`, set `_alarmProcess = null`.
  4. `_transitionSound` path must match the existing `playTransition()` usage (same file, `/System/Library/Sounds/Glass.aiff` or equivalent). ~10 lines total. Tests from Task 13 must pass.

---

## Task 15: Test — Swift `bringToFront` channel handler (F4)
- Feature: F4
- Effort: S
- Depends on: none
- Files: `macos/RunnerTests/` (Swift test if target exists) or `test/window_service_test.dart` (Dart channel stub)
- Acceptance: AC-013-3
- Description: Verify that the `bringToFront` case in the Swift MethodChannel handler activates the window. If a Swift test target exists: write a unit test that invokes the channel and asserts `NSApp.activate` was called (using a mock or manual invocation). If no Swift test target: write a Dart test that stubs the `com.sitempo/statusbar` channel for `bringToFront`, calls `WindowService.bringToFront()`, and asserts the method call was received on the channel with method name `"bringToFront"`. Tests must fail before Task 16.

---

## Task 16: Implement — Swift `bringToFront` + `WindowService` Dart wrapper (F4)
- Feature: F4
- Effort: S
- Depends on: Task 15
- Files: `macos/Runner/MainFlutterWindow.swift`, `lib/services/window_service.dart` (new)
- Acceptance: AC-013-3
- Description:
  1. **Swift**: In the existing `com.sitempo/statusbar` channel handler switch statement, add `case "bringToFront":` branch. Call `NSApp.activate(ignoringOtherApps: true)` and `NSApp.mainWindow?.makeKeyAndOrderFront(nil)`. Reply `result(nil)`. ~5 lines.
  2. **Dart** (`lib/services/window_service.dart`): Create new file. Add `class WindowService` with `static const _channel = MethodChannel('com.sitempo/statusbar')` and `static Future<void> bringToFront() async => _channel.invokeMethod('bringToFront')`. ~10 lines. Caller uses fire-and-forget (no `await` required at call site). Tests from Task 15 must pass.

---

## Task 17: Test — TimerScreen confirmation state variables and `_advanceStep()` gate (F4)
- Feature: F4
- Effort: M
- Depends on: Task 14, Task 16
- Files: `test/timer_screen_test.dart` (extend)
- Acceptance: AC-013-1, AC-013-2, AC-013-3, AC-013-4, AC-013-10
- Description: Widget/unit tests for `_TimerScreenState` confirmation gate. Cases: (a) when `_remaining` reaches zero and `_tick()` fires, `_awaitingConfirmation` becomes `true` and `_pendingStepIndex` is set to `(_currentStepIndex + 1) % steps.length` — step does NOT advance (AC-013-1); (b) the periodic `_timer` is cancelled (null) after `_advanceStep()` enters confirmation mode; (c) `AlarmService.startLoopingAlarm()` is called on confirmation entry (AC-013-2) — stub the service; (d) `WindowService.bringToFront()` is invoked via channel stub (AC-013-3); (e) `NotificationService.show()` is called with a message referencing the ended step (AC-013-4); (f) `StatusBarService.update()` is called with a paused/confirmar indicator (AC-013-10); (g) last-step case: `_pendingStepIndex` wraps to 0 and `_isLastStep` (or equivalent) is true (AC-013-6 precondition). Tests must fail before Task 18.

---

## Task 18: Implement — TimerScreen confirmation state + modified `_advanceStep()` (F4)
- Feature: F4
- Effort: M
- Depends on: Task 14, Task 16, Task 17
- Files: `lib/screens/timer_screen.dart`
- Acceptance: AC-013-1, AC-013-2, AC-013-3, AC-013-4, AC-013-7, AC-013-8, AC-013-9, AC-013-10
- Description:
  1. Add state fields: `bool _awaitingConfirmation = false`, `int? _pendingStepIndex`.
  2. Modify `_advanceStep()`: instead of advancing immediately, cancel `_timer` (set to null), set `_awaitingConfirmation = true`, set `_pendingStepIndex = (_currentStepIndex + 1) % _expandedSteps.length`, set `_remaining = Duration.zero`. Then call `AlarmService.startLoopingAlarm()`, `NotificationService.show(...)` with end-of-step message, `WindowService.bringToFront()` (fire-and-forget), and `_updateStatusBar()` with a confirmar indicator. Do NOT call `AlarmService.playTransition()` here.
  3. Add `_confirmTransition()`: call `AlarmService.stopLoopingAlarm()`, then `AlarmService.playTransition()`, set `_awaitingConfirmation = false`, advance `_currentStepIndex = _pendingStepIndex!`, clear `_pendingStepIndex = null`, if this was the last step increment `_completedCycles`, reset `_remaining` to the new step's duration, restart the periodic `_timer` (same logic as `_startPause()`), call `_updateStatusBar()`.
  4. In `dispose()`: add `AlarmService.stopLoopingAlarm()` call (unconditional — safe when null). Tests from Task 17 must pass.

---

## Task 19: Test — confirmation overlay UI (F4)
- Feature: F4
- Effort: M
- Depends on: Task 18
- Files: `test/timer_screen_test.dart` (extend)
- Acceptance: AC-013-5, AC-013-6, AC-013-7
- Description: Widget tests for the confirmation overlay rendered when `_awaitingConfirmation == true`. Cases: (a) overlay appears when `_awaitingConfirmation` is true: `Positioned.fill` with semi-transparent background is present, "Continuar" button is visible (AC-013-5); (b) overlay shows next step emoji, label, and description when `_pendingStepIndex` points to a step with all fields populated (AC-013-5); (c) last-step / end-of-cycle case: overlay shows "Ciclo completo" text, no next-step emoji/label from a future step (AC-013-6); (d) tapping "Continuar" calls `_confirmTransition()` — overlay disappears, timer restarts, step advances (AC-013-7); (e) the timer ring shows "00:00" while `_awaitingConfirmation` is true; (f) the play/pause button is disabled or hidden (`onPressed: null` or opacity 0) during confirmation state. Tests must fail before Task 20.

---

## Task 20: Implement — confirmation overlay UI in TimerScreen (F4)
- Feature: F4
- Effort: M
- Depends on: Task 18, Task 19
- Files: `lib/screens/timer_screen.dart`
- Acceptance: AC-013-5, AC-013-6, AC-013-7
- Description: In the `build()` method's body `Stack`, add a `Positioned.fill` child conditional on `_awaitingConfirmation`:
  1. Background: `Container(color: Color(0xCC000000))`.
  2. Centered card: `BorderRadius.circular(16)`, dark background, padding 24px. Content: "Paso completado" title (white, 16px, bold); spacing; "Siguiente:" label; if not last step — next step emoji (32px), label (20px, bold, activity color), description if non-empty (13px, italic, white70); if last step — "Ciclo completo" text (white, 18px, bold); spacing; `ElevatedButton("Continuar", onPressed: _confirmTransition)`.
  3. Disable play/pause button: `onPressed: _awaitingConfirmation ? null : _startPause` (or wrap in `IgnorePointer`/opacity 0).
  4. The timer ring already reads `_remaining` which is `Duration.zero` during confirmation — no additional change needed for "00:00" display.
  5. Do NOT use `OverlayEntry` — this overlay is inline in the screen's `Stack`. ~50 lines. Tests from Task 19 must pass.

---

## Dependency Graph

```
Task 1 → Task 2                          (F1: test → impl)

Task 3 → Task 4 → Task 5 → Task 6       (F2: service test → service impl → UI test → UI impl)

Task 7 → Task 8 → Task 9 → Task 10
                         ↘
                    Task 11 → Task 12    (F3: Swift test → Swift impl → Dart test → Dart impl → UI test → UI impl)

Task 13 → Task 14 ──┐
                    ├──► Task 17 → Task 18 → Task 19 → Task 20   (F4: state + _advanceStep → UI)
Task 15 → Task 16 ──┘
```

## Parallel execution opportunities

- F1 (Tasks 1-2), F2 (Tasks 3-6), F3 (Tasks 7-12), and F4 (Tasks 13-20) are fully independent of each other.
- Tasks 1, 3, 7, 13, and 15 can all start simultaneously.
- Within F4: Tasks 13 and 15 are independent and can run in parallel; Task 17 waits for both Task 14 and Task 16.
- Tasks 5 and 9 can run in parallel once their respective upstream tasks complete.

## Summary

| Task | Feature | Effort | Blocked by |
|------|---------|--------|------------|
| 1 | F1 | S | — |
| 2 | F1 | XS | 1 |
| 3 | F2 | S | — |
| 4 | F2 | XS | 3 |
| 5 | F2 | M | 4 |
| 6 | F2 | M | 4, 5 |
| 7 | F3 | S | — |
| 8 | F3 | S | 7 |
| 9 | F3 | XS | 8 |
| 10 | F3 | XS | 8, 9 |
| 11 | F3 | M | 10 |
| 12 | F3 | M | 10, 11 |
| 13 | F4 | S | — |
| 14 | F4 | S | 13 |
| 15 | F4 | S | — |
| 16 | F4 | S | 15 |
| 17 | F4 | M | 14, 16 |
| 18 | F4 | M | 14, 16, 17 |
| 19 | F4 | M | 18 |
| 20 | F4 | M | 18, 19 |
