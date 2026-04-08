# Technical Design: sitempo-v2

**Status**: draft | **Created**: 2026-04-07

## Architecture Overview

Four features, all additive. No new packages, no new screens. One new service file (`window_service.dart`). Changes stay within the existing StatefulWidget + static services + MethodChannel architecture established in v1.

```
Changes by layer:

Native (Swift):
  MainFlutterWindow.swift — new "checkPermission" case in notification channel
                            new "bringToFront" case in statusbar channel

Services (Dart):
  AlarmService           — new playLoopingAlarm() / stopAlarm() static methods
  NotificationService    — new checkPermission() static method
  ReminderService        — new onFire callback field
  WindowService          — new bringToFront() static method (new file)

Screens (Dart):
  TimerScreen            — F1: description in _buildActivityLabel()
                           F2: overlay popup on reminder fire
                           F4: confirmation gate state + overlay on step transition
  ReminderListScreen     — F3: permission warning banner
```

---

## F1: Step Description in Timer Screen

### Architecture Decision

**Direct widget insertion in `_buildActivityLabel()`**. No new widget class, no extraction. The method already returns a Column with emoji, label, and step counter. Adding a fourth conditional child is the minimal, correct change.

Why NOT extract a separate widget: the method is 20 lines, uses only local state (`_currentStep`, `_currentStepIndex`, `_expandedSteps`, `_currentActivity`), and is called once. Extraction adds indirection with zero reuse benefit.

### Component Changes

**`timer_screen.dart` — `_buildActivityLabel(Activity activity)`** (lines 349-370)

Current structure:
```
Column(
  Text(emoji)           // line 352
  SizedBox(height: 12)
  Text(label)           // line 354-361
  SizedBox(height: 4)
  Text("Paso X de Y")  // line 364-367
)
```

Add after the "Paso X de Y" Text widget:
```dart
if (_currentStep.description.isNotEmpty) ...[
  const SizedBox(height: 6),
  Text(
    _currentStep.description,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 13,
      color: activity.color.withAlpha(150),
      fontStyle: FontStyle.italic,
    ),
  ),
],
```

### Design Rationale

- **Placement**: Below "Paso X de Y", not below the emoji or label. The description contextualizes the step counter, not the activity. "Sentado — Paso 1 de 6 — Revisá tu postura" reads top-down correctly.
- **Styling**: Italic, 13px, activity color at 150/255 alpha. Italic distinguishes it from the step counter (which is plain white38). Activity-colored ties it visually to the label above. Alpha 150 keeps it secondary to the label (full alpha) but more prominent than the step counter (white38).
- **Guard**: `_currentStep.description.isNotEmpty` — RoutineStep.description defaults to `''`, so steps without descriptions show nothing. No layout shift: the SizedBox is inside the conditional.
- **Text alignment**: `textAlign: TextAlign.center` matches the Column's centered children. Long descriptions wrap naturally within the 40px horizontal padding.

### Data Flow

```
RoutineStep.description (already in model)
  → _currentStep getter (already computed from _expandedSteps[_currentStepIndex])
    → _buildActivityLabel() reads it
      → conditional Text widget renders it
```

No new data flow. The description field already exists on RoutineStep, is already persisted in JSON, and is already accessible via `_currentStep`. The timeline section already renders it for the current step (lines 576-587). This just adds a second render point.

### Edge Cases

- **Empty description**: Guarded. Most default routine steps have empty descriptions.
- **Very long description**: Wraps within the Column. The 40px horizontal padding constrains width. No truncation needed — descriptions are user-authored and typically short.
- **Description in timeline vs header**: Both show simultaneously for the current step. This is intentional — the header description is prominent, the timeline one is contextual within the sequence.

---

## F2: In-App Popup Notification on Reminder Fire

### Architecture Decision

**Callback injection + OverlayEntry**. ReminderService gets a `void Function(Reminder)?` callback. TimerScreen assigns it in `initState()` and shows an OverlayEntry when called.

**Why callback over StreamController**: ReminderService is the only non-static service, but it's still simple — a tick engine with a fire method. A Stream adds subscription lifecycle (listen/cancel in initState/dispose), backpressure semantics, and broadcast vs single-subscriber decisions. A callback is a single field assignment. For a 1:1 relationship (one service, one listener), a callback is the correct abstraction.

**Why OverlayEntry over SnackBar**: SnackBar is tied to ScaffoldMessenger, requires a Scaffold ancestor, and renders at the bottom with Material 3 styling that clashes with the dark custom UI. OverlayEntry gives full control over position, animation, styling, and dismissal. It renders above everything in the widget tree without depending on Scaffold.

**Why NOT a persistent widget in the tree**: The popup is transient (auto-dismisses). Keeping it in the widget tree means managing visibility state, animation controllers, and rebuild cycles. OverlayEntry is insert-and-forget — it lives outside the widget tree's rebuild cycle.

### Component Changes

#### `reminder_service.dart`

Add callback field and invoke it in `_fire()`:

```dart
class ReminderService {
  List<Reminder> _reminders = [];
  final Map<String, int> _elapsedSeconds = {};
  void Function(Reminder)? onFire;  // NEW

  // ... load(), tick(), reset() unchanged ...

  void _fire(Reminder reminder) {
    NotificationService.show(
      title: '${reminder.emoji} ${reminder.label}',
      body: reminder.description,
    );
    onFire?.call(reminder);  // NEW — fires after OS notification
  }
}
```

Changes: +2 lines (field declaration, callback invocation). No breaking changes — `onFire` is nullable, existing behavior unchanged when null.

#### `timer_screen.dart` — `_TimerScreenState`

New fields:
```dart
OverlayEntry? _activePopup;
Timer? _popupDismissTimer;
```

In `initState()`, after `_load()` completes (inside the `setState` callback or after it):
```dart
_reminderService.onFire = _showReminderPopup;
```

In `dispose()`:
```dart
_dismissPopup();
_reminderService.onFire = null;
```

New methods:
```dart
void _showReminderPopup(Reminder reminder) {
  if (!mounted) return;
  _dismissPopup(); // dismiss previous if any

  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (context) => _ReminderPopup(
      reminder: reminder,
      onDismiss: _dismissPopup,
    ),
  );

  _activePopup = entry;
  overlay.insert(entry);
  _popupDismissTimer = Timer(const Duration(seconds: 5), _dismissPopup);
}

void _dismissPopup() {
  _popupDismissTimer?.cancel();
  _popupDismissTimer = null;
  _activePopup?.remove();
  _activePopup = null;
}
```

New widget (private, in timer_screen.dart):
```dart
class _ReminderPopup extends StatefulWidget {
  final Reminder reminder;
  final VoidCallback onDismiss;

  const _ReminderPopup({required this.reminder, required this.onDismiss});

  @override
  State<_ReminderPopup> createState() => _ReminderPopupState();
}

class _ReminderPopupState extends State<_ReminderPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 24,
      right: 24,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A4E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6C9BFF).withAlpha(60)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(80),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(widget.reminder.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.reminder.label,
                            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                          if (widget.reminder.description.isNotEmpty)
                            Text(widget.reminder.description,
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.close, size: 16, color: Colors.white24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### Data Flow

```
Timer.periodic (1s)
  → _tick()
    → _reminderService.tick()
      → interval reached → _fire(reminder)
        → NotificationService.show()  (OS notification — unchanged)
        → onFire?.call(reminder)      (NEW — callback to TimerScreen)
          → _showReminderPopup(reminder)
            → _dismissPopup()         (dismiss previous)
            → OverlayEntry created + inserted
            → Timer(5s, _dismissPopup) (auto-dismiss)
```

### Overlay Lifecycle

| Event | Behavior |
|-------|----------|
| Popup shown | OverlayEntry inserted, 5s dismiss timer starts |
| User taps popup | `onDismiss` → `_dismissPopup()` → entry removed, timer cancelled |
| 5 seconds pass | Timer fires → `_dismissPopup()` → entry removed |
| New reminder fires while popup visible | `_dismissPopup()` called first (removes old), then new entry inserted. **No stacking** — at most one popup at a time |
| User navigates away (push) | Overlay persists (it's above the Navigator). Popup auto-dismisses after 5s. Not ideal but acceptable — reminders only fire on ~20-30 min intervals |
| Widget disposed (app closing) | `dispose()` calls `_dismissPopup()` + nulls callback. Safe |
| `mounted` is false | Guard at top of `_showReminderPopup`. No-op |

### Design Rationale

- **Stacking policy: replace, don't stack**. Two reminders firing at the exact same second is theoretically possible (two reminders with intervals that are exact multiples). Stacking creates z-order complexity. Replacing is simpler and the "missed" popup was already shown as an OS notification.
- **5-second auto-dismiss**: Long enough to read, short enough to not obstruct the timer. macOS notifications use ~5s for banners.
- **Slide-from-top + fade**: Matches macOS notification banner behavior. `Curves.easeOutCubic` for natural deceleration.
- **Position: top of window, full width with 24px margins**: Above the routine selector, doesn't obstruct the timer ring or controls.
- **Material wrapper**: Required for text rendering inside an OverlayEntry. `color: Colors.transparent` avoids Material's background.

### Edge Cases

- **Rapid successive fires**: Second call to `_showReminderPopup` dismisses the first. Timer cancelled, entry removed. Clean.
- **Fire while on another screen** (e.g., ReminderListScreen): `mounted` is still true (TimerScreen is in the stack, not disposed). `Overlay.of(context)` returns the root overlay. Popup appears above the pushed screen. This is acceptable — it's a notification overlay. The 5s auto-dismiss handles cleanup.
- **Fire after dispose**: `mounted` guard prevents OverlayEntry insertion. Callback nulled in `dispose()`.
- **Timer screen rebuilt during popup**: OverlayEntry is not part of the widget tree — it's in the Overlay. Rebuilds don't affect it.

---

## F3: OS Notification Permission Check + Warning Banner

### Architecture Decision

**Swift `getNotificationSettings()` + Dart static method + UI banner in ReminderListScreen**. The permission check is a read-only query — no new permission request, no new channel. Reuses existing `com.sitempo/notifications` MethodChannel.

**Why check in ReminderListScreen, not TimerScreen**: The reminders screen is where the user manages notification-dependent features. Showing the warning there creates a direct context: "you're configuring reminders, but notifications are off." The timer screen is already dense with information.

**Why a banner, not a dialog**: Dialogs are modal and block interaction. A persistent banner at the top of the list is visible but non-intrusive. The user can still manage reminders even without notification permission. The banner includes an action to resolve the issue.

### Component Changes

#### `MainFlutterWindow.swift` — `setupNotificationChannel()`

Add new case in the switch block (after "show", before "default"):

```swift
case "checkPermission":
  UNUserNotificationCenter.current().getNotificationSettings { settings in
    let status: String
    switch settings.authorizationStatus {
    case .authorized:
      status = "granted"
    case .denied:
      status = "denied"
    case .notDetermined:
      status = "notDetermined"
    case .provisional:
      status = "granted"  // provisional still delivers notifications
    case .ephemeral:
      status = "granted"  // ephemeral still delivers notifications
    @unknown default:
      status = "denied"   // safe fallback — treat unknown as denied
    }
    DispatchQueue.main.async { result(status) }
  }
```

Design note: `provisional` and `ephemeral` map to "granted" because they both result in delivered notifications (quiet delivery and App Clips respectively). The Dart layer only cares about "will notifications appear?" not "what presentation style?"

#### `notification_service.dart`

Add static method:

```dart
static Future<String> checkPermission() async {
  final result = await _channel.invokeMethod<String>('checkPermission');
  return result ?? 'denied';  // null-safe fallback
}
```

Returns raw string, not an enum. Three features, one new method — an enum adds a file and import for three string values. If permissions grow more complex later, promote to enum then.

#### `reminder_list_screen.dart`

New state fields:
```dart
String _permissionStatus = 'granted'; // optimistic default — no flash of banner
```

New method:
```dart
Future<void> _checkPermission() async {
  final status = await NotificationService.checkPermission();
  if (mounted) setState(() => _permissionStatus = status);
}
```

Call in `initState()`:
```dart
@override
void initState() {
  super.initState();
  _reminders = List.of(widget.reminders);
  _checkPermission();
}
```

New banner widget method:
```dart
Widget _buildPermissionBanner() {
  final isDenied = _permissionStatus == 'denied';
  final isNotDetermined = _permissionStatus == 'notDetermined';

  if (!isDenied && !isNotDetermined) return const SizedBox.shrink();

  return Container(
    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.orange.withAlpha(15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orange.withAlpha(40)),
    ),
    child: Row(
      children: [
        const Icon(Icons.notifications_off, size: 20, color: Colors.orange),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            isDenied
                ? 'Las notificaciones están desactivadas. Activalas en Ajustes del Sistema.'
                : 'Sitempo necesita permiso para enviar notificaciones.',
            style: const TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: isDenied ? _openSystemSettings : _requestAndRecheck,
          child: Text(
            isDenied ? 'Abrir' : 'Activar',
            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
```

Action handlers:
```dart
Future<void> _requestAndRecheck() async {
  await NotificationService.requestPermission();
  await _checkPermission();
}

Future<void> _openSystemSettings() async {
  // NSWorkspace.open for System Settings > Notifications
  // Reuse existing MethodChannel or use url_launcher
  // For now: re-request (which shows the system prompt if notDetermined,
  // or does nothing if denied — macOS doesn't re-prompt after denial)
  await NotificationService.requestPermission();
  await _checkPermission();
}
```

Insert banner in `build()`, between AppBar and the list body:

```dart
body: Column(
  children: [
    _buildPermissionBanner(),
    Expanded(
      child: _reminders.isEmpty
          ? const Center(...)
          : ListView.separated(...),
    ),
  ],
),
```

### Data Flow

```
ReminderListScreen.initState()
  → _checkPermission()
    → NotificationService.checkPermission()
      → MethodChannel('com.sitempo/notifications').invokeMethod('checkPermission')
        → Swift: UNUserNotificationCenter.getNotificationSettings()
          → maps authorizationStatus to "granted"/"denied"/"notDetermined"
            → returns String to Dart
              → setState(_permissionStatus = status)
                → _buildPermissionBanner() renders conditionally
```

### The notDetermined → Prompt Flow

```
State: notDetermined
  → Banner shows: "Sitempo necesita permiso..." [Activar]
    → User taps "Activar"
      → _requestAndRecheck()
        → NotificationService.requestPermission()
          → macOS shows system permission dialog
            → User grants → requestPermission returns true
            → User denies → requestPermission returns false
        → _checkPermission() re-queries actual status
          → "granted" → banner disappears
          → "denied" → banner updates to denied variant

State: denied
  → Banner shows: "Las notificaciones están desactivadas..." [Abrir]
    → User taps "Abrir"
      → requestPermission() called (no-op on macOS after denial — system won't re-prompt)
      → _checkPermission() re-queries → still "denied"
      → Banner persists (correct — user must go to System Settings manually)
```

**Important macOS behavior**: Once the user denies notification permission, `requestAuthorization` becomes a no-op — it doesn't show the system prompt again. The only way to re-enable is System Settings > Notifications > Sitempo. The "Abrir" button text and message reflect this reality. A future enhancement could open System Settings directly via `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)` through a new MethodChannel method, but that's out of scope for v2.

### Edge Cases

- **Permission check fails**: `invokeMethod` throws PlatformException. `checkPermission()` returns `'denied'` (null fallback). Banner shows the denied state — conservative and safe.
- **Permission changes while screen is open**: Not detected. The check runs once in `initState()`. Re-entering the screen re-checks. This is acceptable — permission changes during a single screen visit are rare.
- **Banner + empty list**: Banner appears above "Sin recordatorios" message. Both are visible. No conflict.
- **`provisional` status**: Mapped to "granted" in Swift. No banner shown. Correct — provisional notifications are delivered.
- **`@unknown default`**: Mapped to "denied" in Swift. Future Apple statuses trigger the warning banner. Conservative — better to warn than to silently fail.

---

## F4: Confirmation Gate on Step Transition

### Architecture Decision

**Three-state model via `_awaitingConfirmation` bool + looping alarm via `Process.start`**. When the timer reaches zero, instead of advancing immediately, the system enters a "waiting for confirmation" state: timer stops, alarm loops, window comes to front, and a full-screen overlay with "Continuar" button appears.

**Why a bool (`_awaitingConfirmation`) over an enum**: The existing state model uses `_isRunning` (bool). Adding a second bool keeps the pattern consistent: `_isRunning=true + _awaitingConfirmation=false` = running, `_isRunning=false + _awaitingConfirmation=true` = awaiting confirmation, `_isRunning=false + _awaitingConfirmation=false` = paused/stopped. An enum (`TimerState.running | .paused | .awaitingConfirmation`) would be cleaner in isolation, but it means refactoring every `_isRunning` check across the file (lines 34, 80-82, 85, 605, 615). The bool is additive — zero changes to existing code paths.

**Why `Process.start` over `Process.run` for looping alarm**: `Process.run` blocks until completion — an `afplay -l 9999` call would never return. `Process.start` returns a `Process` handle immediately, and `process.kill()` terminates it. This is the standard pattern for cancellable child processes in Dart.

**Why a new `WindowService` over adding to `StatusBarService`**: Bringing the window to front is not a status bar concern. `StatusBarService` manages the macOS status bar item text. Window focus is a window-level concern. Single responsibility: one service per native concept. The new service is 10 lines — minimal overhead for correct separation.

**Why reuse existing `com.sitempo/statusbar` MethodChannel for `bringToFront`**: The statusbar channel handler already lives in `MainFlutterWindow` (the window instance). Adding `bringToFront` there gives direct access to `self.makeKeyAndOrderFront(nil)` and `NSApp.activate(ignoringOtherApps: true)` — the exact same code as `statusBarClicked()`. Creating a new channel for one method call adds setup boilerplate with no benefit.

**Why NOT auto-skip after timeout**: The proposal explicitly scopes out "auto-skip or configurable timeout." The entire point of the gate is that the user MUST acknowledge. If they're AFK, the alarm keeps playing. `afplay` is ~0.1% CPU — negligible.

**Last step handling**: When the last step completes (cycle wraps), the gate is still shown but the overlay text changes to indicate the next cycle is starting. The user still confirms — otherwise they'd miss that a full cycle completed.

### Component Changes

#### `lib/services/alarm_service.dart` — Looping Alarm

Current state: Two static methods using `Process.run` (blocking, fire-and-forget).

Add looping alarm support:

```dart
import 'dart:io';

class AlarmService {
  static const _transitionSound = '/System/Library/Sounds/Glass.aiff';
  static const _startSound = '/System/Library/Sounds/Hero.aiff';
  static const _alarmSound = '/System/Library/Sounds/Sosumi.aiff';

  static Process? _loopingProcess;

  static Future<void> playTransition() async {
    await Process.run('afplay', [_transitionSound]);
  }

  static Future<void> playStart() async {
    await Process.run('afplay', [_startSound]);
  }

  static Future<void> playLoopingAlarm() async {
    await stopAlarm(); // kill any existing loop first
    _loopingProcess = await Process.start('afplay', [_alarmSound, '-l', '0']);
  }

  static Future<void> stopAlarm() async {
    _loopingProcess?.kill();
    _loopingProcess = null;
  }
}
```

Changes: +1 constant (`_alarmSound`), +1 field (`_loopingProcess`), +2 methods (`playLoopingAlarm`, `stopAlarm`). ~12 lines added.

**Sound choice**: `Sosumi.aiff` — distinctive, attention-grabbing, different from `Glass.aiff` (transition) and `Hero.aiff` (start). The user needs to notice this is NOT a normal transition — it's a gate demanding attention.

**`-l 0` flag**: `afplay -l 0` loops indefinitely (0 = infinite loops). This replaces the proposal's `-l 9999` which would technically stop after 9999 plays (~hours, but still finite). `0` is correct for infinite.

**`stopAlarm()` calls `kill()` first**: `Process.kill()` sends SIGTERM to `afplay`, which terminates cleanly. The null check via `?.` handles the case where no alarm is playing.

**`playLoopingAlarm()` calls `stopAlarm()` first**: Prevents orphaned processes if called twice without stopping.

#### `lib/services/window_service.dart` — New File

```dart
import 'package:flutter/services.dart';

class WindowService {
  static const _channel = MethodChannel('com.sitempo/statusbar');

  static Future<void> bringToFront() async {
    await _channel.invokeMethod('bringToFront');
  }
}
```

Design note: Reuses `com.sitempo/statusbar` channel because the handler is in `MainFlutterWindow` which has direct access to `self` and `NSApp`. The service name (`WindowService`) reflects the Dart-side concern, not the channel name.

#### `macos/Runner/MainFlutterWindow.swift` — `setupStatusBarChannel()`

Add new case in the switch block (after "clear", before "default"):

```swift
case "bringToFront":
  DispatchQueue.main.async {
    NSApp.activate(ignoringOtherApps: true)
    self.makeKeyAndOrderFront(nil)
  }
  result(nil)
```

This is identical to `statusBarClicked()` body. Could extract a shared method, but two call sites (both 2 lines) don't justify extraction. If a third appears, refactor then.

Changes: +6 lines in the existing switch block.

#### `lib/screens/timer_screen.dart` — `_TimerScreenState`

**New import**:
```dart
import '../services/window_service.dart';
```

**New state fields** (after existing `bool _isRunning = false;` on line 34):
```dart
bool _awaitingConfirmation = false;
int _pendingStepIndex = 0;
bool _pendingIsNewCycle = false;
```

- `_awaitingConfirmation`: gates the UI into confirmation mode
- `_pendingStepIndex`: the index to advance to when user confirms
- `_pendingIsNewCycle`: true when the pending transition wraps to step 0 (cycle complete). Used by the overlay to show "Ciclo completado" context.

**Modified `_tick()`** (line 90-98):

No change to `_tick()` itself. It already calls `_advanceStep()` when `_remaining.inSeconds <= 1`. The gate logic lives entirely in `_advanceStep()`.

**Modified `_advanceStep()`** (line 100-113):

```dart
void _advanceStep() {
  final steps = _expandedSteps;
  final nextIndex = _currentStepIndex + 1;
  final isEndOfSequence = nextIndex >= steps.length;

  // Stop the timer — we're gating
  _timer?.cancel();

  setState(() {
    _isRunning = false;
    _awaitingConfirmation = true;
    _pendingStepIndex = isEndOfSequence ? 0 : nextIndex;
    _pendingIsNewCycle = isEndOfSequence;
  });

  AlarmService.playLoopingAlarm();
  WindowService.bringToFront();
  NotificationService.show(
    title: '⏰ Cambio de paso',
    body: 'Confirmá para continuar con: ${steps[_pendingStepIndex].resolveActivity(_activities).label}',
  );
}
```

Key changes from original:
1. Timer cancelled (`_timer?.cancel()`) — no more ticking during confirmation
2. `_isRunning` set to `false` — controls reflect stopped state
3. `_awaitingConfirmation` set to `true` — triggers overlay
4. Step NOT advanced yet — `_currentStepIndex` unchanged until confirmation
5. Three attention mechanisms fire: looping alarm, window focus, OS notification

**New `_confirmTransition()` method**:

```dart
void _confirmTransition() {
  AlarmService.stopAlarm();

  setState(() {
    _currentStepIndex = _pendingStepIndex;
    _remaining = _expandedSteps[_currentStepIndex].duration;
    if (_pendingIsNewCycle) _completedCycles++;
    _awaitingConfirmation = false;
  });

  // Auto-start the next step
  _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  setState(() => _isRunning = true);
  AlarmService.playStart();
  _updateStatusBar();
}
```

Design decisions:
- Alarm stopped BEFORE state change — user hears silence immediately on tap
- Step advanced to `_pendingStepIndex` (computed in `_advanceStep`)
- Timer auto-starts — no need to manually press play after confirming. The user confirmed they're ready; starting automatically is the expected UX.
- `playStart()` gives audio feedback that the new step began (same sound as manual start)
- `_updateStatusBar()` syncs the macOS status bar with the new step

**Modified `dispose()`** (line 74-77):

```dart
@override
void dispose() {
  _timer?.cancel();
  AlarmService.stopAlarm();  // NEW — kill looping alarm if awaiting
  // ... existing F2 cleanup (_dismissPopup, callback null) ...
  super.dispose();
}
```

**Modified `_reset()`** (line 115-124):

```dart
void _reset() {
  _timer?.cancel();
  AlarmService.stopAlarm();  // NEW — kill looping alarm if awaiting
  _reminderService.reset();
  setState(() {
    _isRunning = false;
    _awaitingConfirmation = false;  // NEW — clear confirmation state
    _currentStepIndex = 0;
    _remaining = _expandedSteps[0].duration;
    _completedCycles = 0;
  });
  StatusBarService.clear();
}
```

**Modified `_buildControls()`** — Disable controls during confirmation:

```dart
Widget _buildControls(Color color) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _buildControlButton(
        icon: Icons.refresh,
        label: 'Reiniciar',
        onPressed: _awaitingConfirmation ? null : _reset,  // CHANGED
        color: Colors.white24,
      ),
      const SizedBox(width: 24),
      _buildControlButton(
        icon: _isRunning ? Icons.pause : Icons.play_arrow,
        label: _isRunning ? 'Pausar' : 'Iniciar',
        onPressed: _awaitingConfirmation ? null : _startPause,  // CHANGED
        color: color,
        isPrimary: true,
      ),
      const SizedBox(width: 24),
      _buildControlButton(
        icon: Icons.skip_next,
        label: 'Saltar',
        onPressed: _isRunning ? _advanceStep : null,
        color: Colors.white24,
      ),
    ],
  );
}
```

Controls disabled during confirmation because:
- Start/Pause: meaningless — there's no timer running and the state is "awaiting", not "paused"
- Reset: could be allowed, but creates confusion — user sees confirmation overlay AND resets to step 0. Simpler to force them to either confirm or use the overlay's dismiss. Reset works after confirmation.
- Skip: already disabled (`_isRunning` is false during confirmation)

**New confirmation overlay widget** — built by `_buildConfirmationOverlay()`, rendered conditionally in the `build()` method via a Stack:

```dart
Widget _buildConfirmationOverlay() {
  if (!_awaitingConfirmation) return const SizedBox.shrink();

  final pendingStep = _expandedSteps[_pendingStepIndex];
  final pendingActivity = pendingStep.resolveActivity(_activities);

  return Positioned.fill(
    child: Container(
      color: Colors.black.withAlpha(200),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingIsNewCycle) ...[
              const Text(
                '🔄 Ciclo completado',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Text(
              'Siguiente paso',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              pendingActivity.emoji,
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 12),
            Text(
              pendingActivity.label,
              style: TextStyle(
                color: pendingActivity.color,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (pendingStep.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                pendingStep.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: pendingActivity.color.withAlpha(150),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _formatDuration(pendingStep.duration),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton(
                onPressed: _confirmTransition,
                style: ElevatedButton.styleFrom(
                  backgroundColor: pendingActivity.color.withAlpha(40),
                  foregroundColor: pendingActivity.color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: pendingActivity.color.withAlpha(80)),
                  ),
                ),
                child: const Text(
                  'Continuar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

**Overlay placement in `build()`**: Wrap the existing body content in a Stack, with the confirmation overlay on top:

```dart
// In build(), wrap the body Scaffold content:
body: Stack(
  children: [
    // existing body content (SingleChildScrollView or Column)
    existingBody,
    // F4: confirmation overlay (renders SizedBox.shrink when not awaiting)
    _buildConfirmationOverlay(),
  ],
),
```

The overlay is `Positioned.fill` with a semi-transparent black background (`alpha: 200`), centering the next step info and "Continuar" button. This darkens the timer display underneath, creating clear visual separation.

### Data Flow

```
Timer.periodic (1s)
  → _tick()
    → _remaining.inSeconds <= 1
      → _advanceStep()
        → _timer?.cancel()                    (stop ticking)
        → setState: _isRunning=false, _awaitingConfirmation=true
        → AlarmService.playLoopingAlarm()      (Sosumi.aiff loops via Process.start)
        → WindowService.bringToFront()         (NSApp.activate + makeKeyAndOrderFront)
        → NotificationService.show()           (OS notification as fallback)
        → UI rebuilds: overlay appears, controls disabled

  ... user sees overlay, hears alarm, window is focused ...

  → User taps "Continuar"
    → _confirmTransition()
      → AlarmService.stopAlarm()               (Process.kill on afplay)
      → setState: advance step, _awaitingConfirmation=false
      → Timer.periodic starts                  (auto-resume)
      → setState: _isRunning=true
      → AlarmService.playStart()               (Hero.aiff confirmation sound)
      → _updateStatusBar()                     (sync macOS status bar)
      → UI rebuilds: overlay gone, timer running
```

### State Transition Diagram

```
                    ┌──────────┐
                    │  Paused  │ (_isRunning=false, _awaitingConfirmation=false)
                    └────┬─────┘
                         │ _startPause()
                         ▼
                    ┌──────────┐
                    │ Running  │ (_isRunning=true, _awaitingConfirmation=false)
                    └────┬─────┘
                         │ _remaining <= 1 → _advanceStep()
                         ▼
              ┌─────────────────────┐
              │ Awaiting Confirmation│ (_isRunning=false, _awaitingConfirmation=true)
              └──────────┬──────────┘
                         │ _confirmTransition()
                         ▼
                    ┌──────────┐
                    │ Running  │ (next step, auto-started)
                    └──────────┘

  _reset() from ANY state → Paused (step 0, alarm stopped, confirmation cleared)
```

### Interaction with F2 (In-App Popup)

**Problem**: F2's `_showReminderPopup()` is triggered by `ReminderService.onFire`. If a reminder fires at the exact moment a step transition occurs, both the F2 popup and F4 confirmation overlay would appear simultaneously.

**Resolution**: They coexist without conflict. Here's why:

1. **Z-order**: F4's confirmation overlay is a `Positioned.fill` child in the body Stack. F2's popup is an `OverlayEntry` inserted into the root Overlay. The OverlayEntry renders ABOVE the Stack content. So the F2 popup appears on top of the F4 overlay. This is correct — the reminder notification is transient (5s auto-dismiss), and the confirmation gate persists until tapped.

2. **No suppression needed**: The F2 popup auto-dismisses in 5 seconds. The F4 overlay stays until confirmed. They serve different purposes — F2 is "hey, reminder" and F4 is "confirm to proceed." Suppressing F2 during F4 would mean the user misses a reminder notification just because a step transition happened simultaneously.

3. **Reminder ticking stops during confirmation**: `_tick()` is not called when `_timer` is cancelled (during `_awaitingConfirmation`). This means `_reminderService.tick()` also stops. Reminders won't fire during the confirmation gate. The coincidence only happens if `_tick()` triggers both `_advanceStep()` (line 93) and `_reminderService.tick()` fires in the same tick — which IS possible since `_reminderService.tick()` runs on line 91, before the step check on line 92. So the reminder fires, THEN the gate activates. F2 popup shows first, F4 overlay appears on top. F2 auto-dismisses in 5s while F4 waits. Clean.

### Edge Cases

| Case | Behavior |
|------|----------|
| **Last step (cycle wrap)** | `_pendingIsNewCycle = true`, overlay shows "🔄 Ciclo completado" above next step info. Gate still shown — user confirms to start the new cycle. `_completedCycles` incremented on confirmation, not on gate entry. |
| **Dispose during confirmation** | `dispose()` calls `AlarmService.stopAlarm()` — kills the looping `afplay` process. No orphaned processes. |
| **Rapid double-tap on "Continuar"** | First tap calls `_confirmTransition()`, which sets `_awaitingConfirmation = false`. UI rebuilds, overlay returns `SizedBox.shrink()`. Second tap has no target. `stopAlarm()` called twice is safe (second call: `_loopingProcess` is already null, `?.kill()` is no-op). |
| **Reset during confirmation** | Controls disabled during `_awaitingConfirmation` — reset button is null. User must confirm or close the app. This is intentional: the gate is mandatory. |
| **Skip button during confirmation** | Already disabled — `_isRunning` is false, so `_isRunning ? _advanceStep : null` evaluates to null. |
| **App killed during confirmation** | `afplay` process is a child of the Flutter process. When parent dies, macOS sends SIGHUP to children. `afplay` terminates. No zombie processes. |
| **Multiple `playLoopingAlarm()` calls** | `playLoopingAlarm()` calls `stopAlarm()` first — previous process killed before new one starts. At most one `afplay` process alive at any time. |
| **Window already focused** | `bringToFront()` calls `NSApp.activate` + `makeKeyAndOrderFront`. Both are no-ops when already focused. Safe. |
| **Notification permission denied** | `NotificationService.show()` fires but OS silently drops it. Alarm + window focus are the primary attention mechanisms. Notification is a fallback. |
| **Routine changed during confirmation** | Not possible — routine selector is behind the overlay (Positioned.fill blocks interaction). User must confirm first. |

---

## Cross-Feature Concerns

### No New Dependencies

All four features use existing Flutter widgets (Text, OverlayEntry, Container, ElevatedButton, Stack), existing MethodChannel infrastructure, existing UNUserNotificationCenter APIs, and `dart:io` Process (already imported by AlarmService). Zero new packages.

### State Management

No change to the state management approach. All new state is local:
- F1: No new state (reads existing `_currentStep.description`)
- F2: Two fields (`_activePopup`, `_popupDismissTimer`) in `_TimerScreenState`
- F3: One field (`_permissionStatus`) in `_ReminderListScreenState`
- F4: Three fields (`_awaitingConfirmation`, `_pendingStepIndex`, `_pendingIsNewCycle`) in `_TimerScreenState`

### Testing Impact

No existing tests to break (project has no test files). All changes are additive. Manual test plan:
- F1: Create routine with step descriptions → verify they show below step counter
- F2: Enable a reminder with short interval → verify popup appears + auto-dismisses
- F3: Reset notification permissions → verify banner states for each status
- F4: Let timer reach 0 → verify alarm loops, window focused, overlay shows next step → tap "Continuar" → verify alarm stops, next step starts. Also test: last step cycle wrap, reset during confirmation (blocked), dispose during confirmation (alarm killed)

### File Change Summary

| File | Feature | Change Type | ~Lines |
|------|---------|-------------|--------|
| `lib/screens/timer_screen.dart` | F1 | Add conditional Text in `_buildActivityLabel()` | +7 |
| `lib/services/reminder_service.dart` | F2 | Add `onFire` callback field + invocation | +2 |
| `lib/screens/timer_screen.dart` | F2 | Add overlay fields, lifecycle methods, `_ReminderPopup` widget | +100 |
| `lib/services/notification_service.dart` | F3 | Add `checkPermission()` static method | +4 |
| `macos/Runner/MainFlutterWindow.swift` | F3 | Add "checkPermission" case in notification channel | +16 |
| `lib/screens/reminder_list_screen.dart` | F3 | Add permission state, banner widget, action handlers | +60 |
| `lib/services/alarm_service.dart` | F4 | Add `_alarmSound`, `_loopingProcess`, `playLoopingAlarm()`, `stopAlarm()` | +12 |
| `lib/services/window_service.dart` | F4 | New file — `bringToFront()` via statusbar channel | +10 |
| `macos/Runner/MainFlutterWindow.swift` | F4 | Add "bringToFront" case in statusbar channel | +6 |
| `lib/screens/timer_screen.dart` | F4 | State fields, modified `_advanceStep`, `_confirmTransition`, overlay, controls guard | +120 |

**Total**: ~337 lines added across 5 Dart files + 1 Swift file. 1 new file (`window_service.dart`). Zero files deleted or renamed.
